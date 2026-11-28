import Foundation
import Observation

/// The wallet's full USDT history for the Activity screen, cached on disk so
/// charts and totals don't re-download months of transfers on every launch.
///
/// Only public chain data is stored (transfers and fees anyone can read from
/// TronGrid), never keys or the phrase. The home screen keeps using
/// `AppModel.history`; this store is the long tail behind it.
@MainActor
@Observable
final class ActivityStore {
    /// Newest first, unique by transaction id.
    private(set) var transfers: [TokenTransfer] = []
    /// Network fee in sun by txID, for transactions this wallet paid for.
    private(set) var fees: [String: Int64] = [:]
    /// History is complete from this date up to now; `.distantPast` once the
    /// very first transfer is in. nil until anything has been fetched.
    private(set) var coveredSince: Date?
    private(set) var reachedStart = false
    private(set) var isLoading = false
    private(set) var error: String?

    /// Codable on-disk form of one address's history.
    struct Snapshot: Codable, Equatable, Sendable {
        var version = 1
        var address: String
        var transfers: [TokenTransfer]
        var fees: [String: Int64]
        var coveredSince: Date?
        var reachedStart: Bool
    }

    static let pageSize = 200
    /// Pages per call, so one Activity visit can't drain the TronGrid quota.
    static let maxPages = 10

    private let client: TronClient
    private let directory: URL?
    private var address: String?
    private var isDemo = false
    /// Bumped whenever the wallet changes (configure, clear, demo). A fetch
    /// started for an older generation stops at its next await and never
    /// writes, so one wallet's history can't land in another's cache.
    private var generation = 0
    /// A `sync` that arrived while a backfill was running; it runs right after.
    private var syncPending = false
    /// Cache writes and deletes run off the main actor, one after another.
    private var diskQueue: Task<Void, Never>?
    /// Same 429 policy as `AppModel.refresh`: 30 s doubling to 4 min.
    private var backoffUntil: Date?
    private var backoff: TimeInterval = 0

    /// Fee pages per window. A window holds at most `maxPages` transfer pages,
    /// and the wallet pays for little besides those, so this cap is generous
    /// on purpose: running out would leave fees silently missing.
    static let maxFeePages = 30

    /// `directory` nil = Application Support (tests pass a temp folder).
    init(client: TronClient = TronClient(), directory: URL? = nil) {
        self.client = client
        self.directory = directory ?? (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ))
    }

    /// Whether every transfer since `since` is loaded (nil = all history).
    func isComplete(since: Date?) -> Bool {
        if reachedStart { return true }
        guard let since, let coveredSince else { return false }
        return coveredSince <= since
    }

    // MARK: Address and cache

    func configure(address: String?) {
        guard address != self.address || isDemo else { return }
        isDemo = false
        self.address = address
        reset()
        guard let address, let snapshot = Self.load(address: address, in: directory) else { return }
        apply(snapshot)
    }

    /// Forget this address's history, in memory and on disk (wallet erased).
    func clear() {
        if let address, !isDemo, let url = Self.cacheURL(address: address, in: directory) {
            enqueueDisk { try? FileManager.default.removeItem(at: url) }
        }
        reset()
        address = nil
        isDemo = false
    }

    private func reset() {
        generation += 1
        transfers = []
        fees = [:]
        coveredSince = nil
        reachedStart = false
        isLoading = false
        syncPending = false
        error = nil
        backoff = 0
        backoffUntil = nil
    }

    private func apply(_ snapshot: Snapshot) {
        transfers = Self.merge(snapshot.transfers, into: [])
        fees = snapshot.fees
        coveredSince = snapshot.coveredSince
        reachedStart = snapshot.reachedStart
    }

    private func save() {
        guard let address, !isDemo else { return }
        let snapshot = Snapshot(
            address: address, transfers: transfers, fees: fees, coveredSince: coveredSince, reachedStart: reachedStart
        )
        let directory = directory
        enqueueDisk { Self.save(snapshot, in: directory) }
    }

    /// Chains disk work so a delete can't be overtaken by an older write.
    private func enqueueDisk(_ work: @escaping @Sendable () -> Void) {
        let previous = diskQueue
        diskQueue = Task.detached(priority: .utility) {
            await previous?.value
            work()
        }
    }

    /// Waits for pending cache writes (tests).
    func flush() async {
        await diskQueue?.value
    }

    nonisolated static func cacheURL(address: String, in directory: URL?) -> URL? {
        // Addresses are base58, so they're already safe as a file name; the
        // filter only guards against a malformed value reaching the path.
        let safe = address.filter { $0.isLetter || $0.isNumber }
        guard let directory, !safe.isEmpty else { return nil }
        return directory.appending(path: "activity-\(safe).json")
    }

    nonisolated static func load(address: String, in directory: URL?) -> Snapshot? {
        guard let url = cacheURL(address: address, in: directory), let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.version == 1, snapshot.address == address
        else { return nil }
        return snapshot
    }

    nonisolated static func save(_ snapshot: Snapshot, in directory: URL?) {
        guard let directory, let url = cacheURL(address: snapshot.address, in: directory) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        // Public chain data, but it ties this device to the address: unreadable
        // while the device is locked, and kept out of iCloud and computer backups.
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var file = url
        try? file.setResourceValues(values)
    }

    /// Union by id (incoming rows win), newest first. Ties on the same block
    /// time are broken by id so the order is stable across launches.
    nonisolated static func merge(_ new: [TokenTransfer], into existing: [TokenTransfer]) -> [TokenTransfer] {
        var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for transfer in new { byID[transfer.id] = transfer }
        // Zero-value rows cached before they were filtered out (see `parseTransfers`).
        return byID.values.filter { $0.units > 0 }.sorted { $0.date != $1.date ? $0.date > $1.date : $0.id > $1.id }
    }

    // MARK: Network

    /// Pull transfers newer than the newest cached one (or the latest page on
    /// a first run), plus their fees. If a backfill is running, it runs as
    /// soon as that finishes instead of being dropped: the balance chart is
    /// rebuilt from the live balance, so a missing new transfer would shift it.
    func sync() async {
        guard let address, !isDemo, !inBackoff else { return }
        guard !isLoading else { syncPending = true; return }
        let gen = generation
        isLoading = true
        do {
            if let newest = transfers.first?.date {
                try await fetchNewer(than: newest, address: address, gen: gen)
            } else {
                try await fetchFirstPage(address: address, gen: gen)
            }
            succeeded()
        } catch {
            guard gen == generation else { return }
            failed(error)
        }
        finishLoad(gen)
    }

    /// Page backwards until history reaches `since` (nil = the very start),
    /// at most `maxPages` pages per call. Returns at once if a load is running.
    func ensureCoverage(since: Date?) async {
        guard let address, !isDemo, !isLoading, !inBackoff, !isComplete(since: since) else { return }
        let gen = generation
        isLoading = true
        do {
            if transfers.isEmpty, coveredSince == nil { try await fetchFirstPage(address: address, gen: gen) }
            try await fetchOlder(until: since, address: address, gen: gen)
            succeeded()
        } catch {
            guard gen == generation else { return }
            failed(error)
        }
        finishLoad(gen)
        if syncPending, gen == generation {
            syncPending = false
            await sync()
        }
    }

    private func finishLoad(_ gen: Int) {
        guard gen == generation else { return }
        isLoading = false
    }

    private func ensureCurrent(_ gen: Int) throws {
        if gen != generation { throw CancellationError() }
    }

    /// Transfers and their fees land together, so a failed fee fetch can't
    /// leave a stretch of history that later syncs would never revisit.
    private func commit(transfers new: [TokenTransfer], fees newFees: [String: Int64], replacing: Bool = false) {
        if replacing {
            transfers = Self.merge(new, into: [])
            fees = newFees
        } else {
            if !new.isEmpty { transfers = Self.merge(new, into: transfers) }
            fees.merge(newFees) { _, latest in latest }
        }
    }

    private func fetchFirstPage(address: String, gen: Int) async throws {
        let page = try await client.usdtHistoryPage(of: address, limit: Self.pageSize)
        try ensureCurrent(gen)
        let complete = page.next == nil
        let since = complete ? nil : page.transfers.last?.date
        let newFees = try await fetchFees(address: address, from: since, to: nil, gen: gen)
        commit(transfers: page.transfers, fees: newFees)
        reachedStart = complete
        coveredSince = complete ? .distantPast : (since ?? .distantPast)
        save()
    }

    private func fetchNewer(than newest: Date, address: String, gen: Int) async throws {
        var fetched: [TokenTransfer] = []
        var fingerprint: String?
        var pages = 0
        repeat {
            // Inclusive lower bound: another transfer in the newest cached
            // block may not have been indexed yet; the merge drops repeats.
            let page = try await client.usdtHistoryPage(
                of: address, minTimestamp: newest, fingerprint: fingerprint, limit: Self.pageSize
            )
            try ensureCurrent(gen)
            fetched += page.transfers
            fingerprint = page.next
            pages += 1
        } while fingerprint != nil && pages < Self.maxPages
        // Nothing new: no fee call, no merge, no disk write.
        // The inclusive bound re-returns the newest cached block, so only the
        // head of the cache needs checking.
        if fingerprint == nil,
           Set(fetched.map(\.id)).isSubset(of: Set(transfers.prefix(fetched.count + 5).map(\.id))) {
            return
        }
        if fingerprint != nil {
            // Too far behind to close the gap in one go: keep only the fresh
            // contiguous run so the cache never has a silent hole in it.
            let since = fetched.map(\.date).min()
            let newFees = try await fetchFees(address: address, from: since, to: nil, gen: gen)
            commit(transfers: fetched, fees: newFees, replacing: true)
            reachedStart = false
            coveredSince = since
            save()
        } else {
            let newFees = try await fetchFees(address: address, from: newest, to: nil, gen: gen)
            commit(transfers: fetched, fees: newFees)
            save()
        }
    }

    private func fetchOlder(until since: Date?, address: String, gen: Int) async throws {
        guard let oldest = transfers.last?.date, !reachedStart else { return }
        // Inclusive upper bound for the same reason as in `fetchNewer`.
        let windowTop = oldest
        var fetched: [TokenTransfer] = []
        var fingerprint: String?
        var pages = 0
        var windowBottom: Date?
        repeat {
            let page = try await client.usdtHistoryPage(
                of: address, maxTimestamp: windowTop, fingerprint: fingerprint, limit: Self.pageSize
            )
            try ensureCurrent(gen)
            fetched += page.transfers
            fingerprint = page.next
            pages += 1
            if let pageOldest = page.transfers.last?.date { windowBottom = min(windowBottom ?? pageOldest, pageOldest) }
            let reached = fingerprint == nil || (since.map { (windowBottom ?? .distantFuture) <= $0 } ?? false)
            if reached { break }
        } while pages < Self.maxPages
        let complete = fingerprint == nil
        let newFees = try await fetchFees(address: address, from: complete ? nil : windowBottom, to: windowTop, gen: gen)
        commit(transfers: fetched, fees: newFees)
        if complete {
            reachedStart = true
            coveredSince = .distantPast
        } else if let windowBottom {
            coveredSince = min(coveredSince ?? windowBottom, windowBottom)
        }
        save()
    }

    private func fetchFees(address: String, from: Date?, to: Date?, gen: Int) async throws -> [String: Int64] {
        var result: [String: Int64] = [:]
        var fingerprint: String?
        var pages = 0
        repeat {
            let page = try await client.transactionFees(
                of: address, minTimestamp: from, maxTimestamp: to, fingerprint: fingerprint, limit: Self.pageSize
            )
            try ensureCurrent(gen)
            result.merge(page.fees) { _, new in new }
            fingerprint = page.next
            pages += 1
        } while fingerprint != nil && pages < Self.maxFeePages
        return result
    }

    private var inBackoff: Bool {
        if let backoffUntil, Date.now < backoffUntil { return true }
        return false
    }

    private func succeeded() {
        error = nil
        backoff = 0
        backoffUntil = nil
    }

    /// Keeps whatever was committed before the failure; it's all still valid.
    private func failed(_ failure: Error) {
        if case TronClient.Failure.rateLimited = failure {
            backoff = min(max(backoff * 2, 30), 240)
            backoffUntil = .now.addingTimeInterval(backoff)
        }
        error = (failure as? LocalizedError)?.errorDescription ?? failure.localizedDescription
    }

    // MARK: Demo

    #if DEBUG
    /// Fixed sample history for screenshots: the same every run, never saved.
    func loadDemo(address: String, now: Date = .now) {
        reset() // also bumps the generation, cancelling any real fetch
        self.address = address
        isDemo = true
        let demo = Self.demoHistory(address: address, now: now)
        transfers = Self.merge(demo.transfers, into: [])
        fees = demo.fees
        coveredSince = .distantPast
        reachedStart = true
    }

    /// Matches `AppModel.loadDemo`: its four latest transfers come last here
    /// and the running balance ends at its 2,481.35 USDT without ever dipping
    /// below zero.
    static func demoHistory(address me: String, now: Date) -> (transfers: [TokenTransfer], fees: [String: Int64]) {
        let employer = "TLa2f6VPqDgRE67v1736s7bJ8Ray5wYjU7"
        let landlord = "TDAeAFiB38L4mCAE8AhGRN7QUbG7DUv8tV"
        let friend = "TMuA6YqfCeX8EhbfYEg5y7S4DqzSJireY9"
        let shop = "TXJgMdjVX5dKiQaUi9QobwNxtSQaFqccvd"
        let client = "TEPSrSYPDSQ7yXpMFPq91Fb1QEWpMkRGfn"
        let exchange = "TYNZzWMwpRjspHhbEikfKaXhsam8NMPMmm"
        let target: Int64 = 2_481_350_000
        // AppModel's demo history, newest first.
        let latest: [(id: String, ago: TimeInterval, incoming: Bool, other: String, units: Int64)] = [
            ("a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2", 1_800, true, friend, 500_000_000),
            ("b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3", 26_000, false, landlord, 120_000_000),
            ("c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4", 90_000, true, employer, 1_250_000_000),
            ("d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5", 190_000, false, shop, 75_500_000),
        ]
        let latestNet = latest.reduce(Int64(0)) { $0 + ($1.incoming ? $1.units : -$1.units) }
        let targetBeforeLatest = target - latestNet

        var rng = SplitMix64(seed: 0x4B45_5354_5245_4C)
        var events: [(date: Date, incoming: Bool, other: String, units: Int64)] = []
        let day: TimeInterval = 86_400
        let months = 14
        var balance: Int64 = 0

        func add(_ ago: TimeInterval, _ incoming: Bool, _ other: String, _ units: Int64) {
            var incoming = incoming
            var units = units
            // Never spend more than is there: shrink, or turn it into a top-up.
            if !incoming, units > balance {
                if balance >= 10_000_000 { units = balance / 2 } else { incoming = true }
            }
            balance += incoming ? units : -units
            events.append((now.addingTimeInterval(-ago), incoming, other, units))
        }
        func usdt(_ low: Int64, _ high: Int64) -> Int64 {
            // Whole cents, so the amounts look like real payments.
            (low * 100 + Int64(rng.next() % UInt64((high - low) * 100 + 1))) * 10_000
        }

        // Oldest month first, so the balance check above sees real order.
        for month in stride(from: months - 1, through: 0, by: -1) {
            let monthStart = Double(month) * 30 * day + 5 * day
            let jitter = { Double(rng.next() % 36_000) }
            add(monthStart + 26 * day + jitter(), true, employer, usdt(1_700, 2_300))
            add(monthStart + 23 * day + jitter(), false, landlord, usdt(850, 950))
            let extras = 3 + Int(rng.next() % 2)
            for extra in 0 ..< extras {
                let ago = monthStart + Double(20 - extra * 6) * day + jitter()
                switch rng.next() % 6 {
                case 0: add(ago, true, client, usdt(150, 900))
                case 1: add(ago, true, friend, usdt(5, 120))
                case 2: add(ago, false, friend, usdt(5, 80))
                case 3: add(ago, false, shop, usdt(20, 350))
                default: add(ago, false, exchange, usdt(200, 900))
                }
            }
            // Salary outpaces spending, so savings go to the exchange at month
            // end; otherwise the balance would drift far above the demo's.
            let keep = usdt(600, 1_600)
            if month > 0, balance > keep + 5_000_000 {
                add(monthStart + 0.5 * day, false, exchange, min(balance - keep, 3_000_000_000))
            }
        }
        // One move to or from the exchange lands the balance exactly where the
        // home screen's demo expects it before its four latest transfers.
        let gap = targetBeforeLatest - balance
        if gap != 0 { add(4 * day, gap > 0, exchange, abs(gap)) }

        var transfers: [TokenTransfer] = []
        var fees: [String: Int64] = [:]
        for event in events {
            let id = (0 ..< 4).map { _ in String(format: "%016llx", rng.next()) }.joined()
            transfers.append(TokenTransfer(
                id: id, date: event.date,
                from: event.incoming ? event.other : me, to: event.incoming ? me : event.other,
                units: UInt64(event.units)
            ))
            if !event.incoming { fees[id] = 13_000_000 + Int64(rng.next() % 15_000_001) }
        }
        for item in latest {
            transfers.append(TokenTransfer(
                id: item.id, date: now.addingTimeInterval(-item.ago),
                from: item.incoming ? item.other : me, to: item.incoming ? me : item.other,
                units: UInt64(item.units)
            ))
            if !item.incoming { fees[item.id] = 13_000_000 + Int64(rng.next() % 15_000_001) }
        }
        return (transfers, fees)
    }

    /// Tiny deterministic generator: the demo must look identical every run.
    private struct SplitMix64 {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
    #endif
}
