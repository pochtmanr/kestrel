import Foundation
import SwiftUI

// Pure, view-free analytics over the fetched USDT history: the balance line,
// in/out flow per period, summary insights and the transfer filter. Everything
// takes `now` and `calendar` explicitly so it is deterministic under test, and
// amounts stay in integer base units (6 decimals) until a chart needs a Double.
//
// Direction rule, used everywhere here: a transfer is outgoing iff `from == me`.
// A send to yourself therefore counts as outgoing, matching the transfer rows.

// MARK: - Timeframe

enum Timeframe: String, CaseIterable, Identifiable, Sendable {
    case week, month, quarter, year, all

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .week: "7D"
        case .month: "1M"
        case .quarter: "3M"
        case .year: "1Y"
        case .all: "All"
        }
    }

    /// The calendar unit one chart bucket spans.
    var bucket: Calendar.Component {
        switch self {
        case .week, .month: .day
        case .quarter: .weekOfYear
        case .year, .all: .month
        }
    }

    /// Where the timeframe begins. Always aligned to a bucket start so the first
    /// bucket is a whole day, week or month. `.all` is nil without any transfers.
    func start(now: Date, calendar: Calendar, earliest: Date?) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .week:
            return calendar.date(byAdding: .day, value: -6, to: today)
        case .month:
            return calendar.date(byAdding: .day, value: -29, to: today)
        case .quarter:
            // 13 weeks including the current one.
            guard let back = calendar.date(byAdding: .weekOfYear, value: -12, to: now) else { return nil }
            return calendar.dateInterval(of: .weekOfYear, for: back)?.start
        case .year:
            // 12 months including the current one.
            guard let back = calendar.date(byAdding: .month, value: -11, to: now) else { return nil }
            return calendar.dateInterval(of: .month, for: back)?.start
        case .all:
            guard let earliest else { return nil }
            return calendar.dateInterval(of: .month, for: min(earliest, now))?.start
        }
    }

    /// Start of every bucket from `start(...)` up to the one containing `now`.
    /// Steps are calendar additions from the aligned start, so a DST change makes
    /// one day 23 or 25 hours long rather than shifting every later boundary.
    func bucketStarts(now: Date, calendar: Calendar, earliest: Date?) -> [Date] {
        guard let start = start(now: now, calendar: calendar, earliest: earliest) else { return [] }
        var result: [Date] = []
        var index = 0
        // The cap only guards against a pathological calendar; "All" over a
        // decade of months is ~120 buckets.
        while index < 5_000, let date = calendar.date(byAdding: bucket, value: index, to: start), date <= now {
            result.append(date)
            index += 1
        }
        return result
    }
}

// MARK: - Balance

struct BalancePoint: Identifiable, Hashable, Sendable {
    let date: Date
    /// Balance at `date`, clamped at 0. A negative rebuilt value only means the
    /// fetched history is incomplete, and a chart below zero would be a lie.
    let units: UInt64

    var id: Date { date }
    var usdt: Double { Double(units) / 1_000_000 }
}

struct BalanceSeries: Sendable {
    /// Oldest first: the opening balance at the timeframe start, the balance at
    /// each later bucket boundary, then the current balance at `now`.
    let points: [BalancePoint]
    let startUnits: UInt64
    let endUnits: UInt64
    let changeUnits: Int64
    /// Change as a fraction of the start (0.25 = +25%), for `.percent` formatting.
    /// nil when the start balance is 0, where a percentage means nothing.
    let changePercent: Double?

    var changeUSDT: Double { Double(changeUnits) / 1_000_000 }
}

// MARK: - Flow

struct FlowBucket: Identifiable, Hashable, Sendable {
    let start: Date
    let end: Date
    let inflow: UInt64
    let outflow: UInt64
    let net: Int64
    let count: Int

    var id: Date { start }
    var inflowUSDT: Double { Double(inflow) / 1_000_000 }
    var outflowUSDT: Double { Double(outflow) / 1_000_000 }
    var netUSDT: Double { Double(net) / 1_000_000 }
}

// MARK: - Insights

struct Counterparty: Identifiable, Hashable, Sendable {
    let address: String
    let count: Int
    let inflow: UInt64
    let outflow: UInt64
    let net: Int64

    var id: String { address }
    var volume: UInt64 { inflow + outflow }
}

struct ActivityInsights: Sendable {
    let inflow: UInt64
    let outflow: UInt64
    let net: Int64
    let count: Int
    /// Mean transfer size across both directions; 0 with no transfers.
    let averageUnits: UInt64
    let largestIn: TokenTransfer?
    let largestOut: TokenTransfer?
    /// TRX (sun) burned by outgoing transfers in range whose fee is known.
    let feesSun: Int64
    /// Up to three, by in + out volume.
    let topCounterparties: [Counterparty]
}

// MARK: - Query

struct TransferQuery: Equatable, Sendable {
    enum Direction: String, CaseIterable, Identifiable, Sendable {
        case all, incoming, outgoing

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .all: "All"
            case .incoming: "In"
            case .outgoing: "Out"
            }
        }
    }

    var text = ""
    var direction: Direction = .all
    /// Inclusive bounds in base units.
    var minUnits: UInt64?
    var maxUnits: UInt64?
    /// Day bounds: `from` from the start of its day, `to` through the end of its day.
    var from: Date?
    var to: Date?
    /// Exact address of the other side.
    var counterparty: String?

    var isActive: Bool {
        !trimmedText.isEmpty || direction != .all || minUnits != nil || maxUnits != nil
            || from != nil || to != nil || counterparty != nil
    }

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    func matches(_ transfer: TokenTransfer, me: String, calendar: Calendar = .current) -> Bool {
        let outgoing = transfer.from == me
        switch direction {
        case .all: break
        case .incoming: if outgoing { return false }
        case .outgoing: if !outgoing { return false }
        }
        let other = outgoing ? transfer.to : transfer.from
        if let counterparty, other != counterparty { return false }
        if let minUnits, transfer.units < minUnits { return false }
        if let maxUnits, transfer.units > maxUnits { return false }
        if let from, transfer.date < calendar.startOfDay(for: from) { return false }
        if let to {
            let dayStart = calendar.startOfDay(for: to)
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart), transfer.date >= nextDay { return false }
        }

        let query = trimmedText.lowercased()
        guard !query.isEmpty else { return true }
        if other.lowercased().contains(query) { return true }
        if transfer.id.lowercased().hasPrefix(query) { return true }
        // Compare against the full 6-decimal amount without grouping, so "1500",
        // "1,500" and "500.5" all find 1,500.50 the way the user typed them.
        let amountQuery = query.replacingOccurrences(of: ",", with: "")
        guard !amountQuery.isEmpty else { return false }
        let amount = USDT.format(units: transfer.units, fractionDigits: USDT.decimals).replacingOccurrences(of: ",", with: "")
        return amount.contains(amountQuery)
    }
}

// MARK: - Analytics

enum ActivityAnalytics {
    /// The transfer's effect on my balance: + received, - sent.
    static func signedUnits(_ transfer: TokenTransfer, me: String) -> Int64 {
        let amount = Int64(clamping: transfer.units)
        return transfer.from == me ? -amount : amount
    }

    /// Balance just before each instant (transfers at or after it undone),
    /// rebuilt backwards from `current`. Unclamped, so callers can tell an
    /// incomplete history apart. Results follow the order of `instants`.
    static func balances(before instants: [Date], current: UInt64, transfers: [TokenTransfer], me: String) -> [Int64] {
        // Newest first, so undoing each transfer steps the balance back in time.
        let sorted = transfers.sorted { $0.date > $1.date }
        let order = instants.indices.sorted { instants[$0] > instants[$1] }
        var result = [Int64](repeating: 0, count: instants.count)
        var running = Int64(clamping: current)
        var cursor = 0
        for index in order {
            while cursor < sorted.count, sorted[cursor].date >= instants[index] {
                running -= signedUnits(sorted[cursor], me: me)
                cursor += 1
            }
            result[index] = running
        }
        return result
    }

    static func balance(before instant: Date, current: UInt64, transfers: [TokenTransfer], me: String) -> Int64 {
        balances(before: [instant], current: current, transfers: transfers, me: me)[0]
    }

    /// Closing balance of each of the last `days` days, oldest first, each dated
    /// at the start of its day. Today closes at `current` (nothing undone).
    static func dailyBalances(current: UInt64, transfers: [TokenTransfer], me: String,
                              days: Int, now: Date, calendar: Calendar) -> [BalancePoint] {
        let today = calendar.startOfDay(for: now)
        let dayStarts = (0 ..< max(days, 0)).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        // A day closes where the next one starts; today's close is "now", taken
        // as the distant future so a transfer stamped slightly ahead of the
        // device clock still counts in today's balance.
        let closes = dayStarts.map { day in
            day == today ? .distantFuture : calendar.date(byAdding: .day, value: 1, to: day) ?? .distantFuture
        }
        let values = balances(before: closes, current: current, transfers: transfers, me: me)
        return zip(dayStarts, values).map { BalancePoint(date: $0, units: UInt64(max($1, 0))) }
    }

    static func balanceSeries(current: UInt64, transfers: [TokenTransfer], me: String,
                              timeframe: Timeframe, now: Date, calendar: Calendar) -> BalanceSeries {
        let starts = timeframe.bucketStarts(now: now, calendar: calendar, earliest: transfers.map(\.date).min())
        let instants = starts + [.distantFuture]
        let values = balances(before: instants, current: current, transfers: transfers, me: me)
        let dates = starts + [now]
        let points = zip(dates, values).map { BalancePoint(date: $0, units: UInt64(max($1, 0))) }
        let startUnits = points.first?.units ?? current
        let endUnits = points.last?.units ?? current
        let change = Int64(clamping: endUnits) - Int64(clamping: startUnits)
        return BalanceSeries(points: points, startUnits: startUnits, endUnits: endUnits, changeUnits: change,
                             changePercent: startUnits == 0 ? nil : Double(change) / Double(startUnits))
    }

    /// One bucket per timeframe period, empty periods included, oldest first.
    static func flowBuckets(transfers: [TokenTransfer], me: String,
                            timeframe: Timeframe, now: Date, calendar: Calendar) -> [FlowBucket] {
        let starts = timeframe.bucketStarts(now: now, calendar: calendar, earliest: transfers.map(\.date).min())
        guard let last = starts.last else { return [] }
        let ends = Array(starts.dropFirst()) + [calendar.date(byAdding: timeframe.bucket, value: 1, to: last) ?? .distantFuture]
        var inflow = [UInt64](repeating: 0, count: starts.count)
        var outflow = [UInt64](repeating: 0, count: starts.count)
        var counts = [Int](repeating: 0, count: starts.count)
        for transfer in transfers {
            // Last bucket whose start is at or before the transfer (starts ascend).
            var low = 0, high = starts.count - 1, found = -1
            while low <= high {
                let mid = (low + high) / 2
                if starts[mid] <= transfer.date { found = mid; low = mid + 1 } else { high = mid - 1 }
            }
            guard found >= 0, transfer.date < ends[found] else { continue }
            if transfer.from == me { outflow[found] += transfer.units } else { inflow[found] += transfer.units }
            counts[found] += 1
        }
        return starts.indices.map { i in
            FlowBucket(start: starts[i], end: ends[i], inflow: inflow[i], outflow: outflow[i],
                       net: Int64(clamping: inflow[i]) - Int64(clamping: outflow[i]), count: counts[i])
        }
    }

    /// Totals over transfers dated at or after `since` (all of them when nil).
    static func insights(transfers: [TokenTransfer], fees: [String: Int64], me: String, since: Date?) -> ActivityInsights {
        let inRange = transfers.filter { transfer in since.map { transfer.date >= $0 } ?? true }
        var inflow: UInt64 = 0, outflow: UInt64 = 0, feesSun: Int64 = 0
        var largestIn: TokenTransfer?, largestOut: TokenTransfer?
        var parties: [String: (count: Int, inflow: UInt64, outflow: UInt64)] = [:]
        for transfer in inRange {
            if transfer.from == me {
                outflow += transfer.units
                feesSun += fees[transfer.id] ?? 0
                if largestOut.map({ transfer.units > $0.units }) ?? true { largestOut = transfer }
                parties[transfer.to, default: (0, 0, 0)].count += 1
                parties[transfer.to, default: (0, 0, 0)].outflow += transfer.units
            } else {
                inflow += transfer.units
                if largestIn.map({ transfer.units > $0.units }) ?? true { largestIn = transfer }
                parties[transfer.from, default: (0, 0, 0)].count += 1
                parties[transfer.from, default: (0, 0, 0)].inflow += transfer.units
            }
        }
        let top = parties
            .map { Counterparty(address: $0.key, count: $0.value.count, inflow: $0.value.inflow, outflow: $0.value.outflow,
                                net: Int64(clamping: $0.value.inflow) - Int64(clamping: $0.value.outflow)) }
            // Ties broken by count then address, so the list never reshuffles between renders.
            .sorted { ($0.volume, $0.count, $1.address) > ($1.volume, $1.count, $0.address) }
            .prefix(3)
        return ActivityInsights(
            inflow: inflow, outflow: outflow,
            net: Int64(clamping: inflow) - Int64(clamping: outflow),
            count: inRange.count,
            averageUnits: inRange.isEmpty ? 0 : (inflow + outflow) / UInt64(inRange.count),
            largestIn: largestIn, largestOut: largestOut,
            feesSun: feesSun,
            topCounterparties: Array(top)
        )
    }
}
