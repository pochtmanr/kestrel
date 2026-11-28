import Foundation
import Observation

/// Fee estimates — app only. Read-only node calls: nothing here signs,
/// broadcasts or touches the Keychain.
extension TronClient {
    /// Simulates the transfer and prices it for this sender. Throws when the
    /// node can't be reached, rate-limits, or the simulation reverts; callers
    /// then fall back to `FeeEstimate.fallback`.
    func estimateUSDTTransferFee(from: String, to: String, units: UInt64) async throws -> FeeEstimate {
        async let energy = simulatedTransferEnergy(from: from, to: to, units: units)
        async let resources = accountResources(of: from)
        async let parameters = chainFeeParameters()
        return FeeEstimate.make(energyUsed: try await energy, resources: try await resources,
                                parameters: await parameters)
    }

    /// Energy the transfer would use, from a dry run on the node. TronGrid has
    /// `wallet/estimateenergy` switched off, so this is a constant-contract call:
    /// it executes the transfer against current state and discards the result.
    private func simulatedTransferEnergy(from: String, to: String, units: UInt64) async throws -> Int64 {
        guard let owner = TronAddress.hex21(from), let contract = TronAddress.hex21(USDT.contract),
              let recipientWord = TronAddress.abiWord(to) else { throw Failure.badResponse }
        // Same ABI words as `sendUSDT` builds, so the dry run is the real call.
        let amountHex = String(units, radix: 16)
        let amountWord = String(repeating: "0", count: 64 - amountHex.count) + amountHex
        let body = try await post("wallet/triggerconstantcontract", [
            "owner_address": owner,
            "contract_address": contract,
            "function_selector": "transfer(address,uint256)",
            "parameter": recipientWord + amountWord,
            "visible": false,
        ])
        guard let energy = Self.parseSimulation(body) else { throw Failure.badResponse }
        return energy
    }

    private func accountResources(of address: String) async throws -> AccountResources {
        guard let hex = TronAddress.hex21(address) else { throw Failure.badResponse }
        return Self.parseResources(try await post("wallet/getaccountresource", ["address": hex, "visible": false]))
    }

    /// The chain's fee prices: the saved copy while it's fresh, else the node's,
    /// else the last saved copy however old, else the built-in ones. Never throws.
    func chainFeeParameters() async -> ChainFeeParameters {
        let saved = ChainFeeParameterCache.load()
        if let saved, saved.isFresh { return saved.parameters }
        if let body = try? await post("wallet/getchainparameters", [:]),
           let parameters = Self.parseChainParameters(body) {
            ChainFeeParameterCache.save(parameters)
            return parameters
        }
        return saved?.parameters ?? .builtIn
    }

    /// What's on hand without asking the network: for the first frame.
    static var savedChainFeeParameters: ChainFeeParameters {
        ChainFeeParameterCache.load()?.parameters ?? .builtIn
    }

    // MARK: Parsers

    /// `energy_used` of a `triggerconstantcontract` reply, or nil when the
    /// simulation can't be trusted.
    ///
    /// A reverting call looks like a cheap success: `result.result` is true and
    /// `energy_used` is small. What gives it away is `result.message` (the
    /// revert reason) and an empty `constant_result`. USDT's `transfer` returns
    /// all zeros on success, so the returned word itself is not a test.
    static func parseSimulation(_ body: [String: Any]) -> Int64? {
        guard let result = body["result"] as? [String: Any], result["result"] as? Bool == true,
              result["message"] == nil,
              let word = (body["constant_result"] as? [String])?.first, !word.isEmpty,
              let energy = (body["energy_used"] as? NSNumber)?.int64Value, energy > 0
        else { return nil }
        return energy
    }

    /// A `getaccountresource` reply. The node leaves out every key whose value
    /// is zero, and answers `{}` for an address that isn't activated.
    static func parseResources(_ body: [String: Any]) -> AccountResources {
        func value(_ key: String) -> Int64 { (body[key] as? NSNumber)?.int64Value ?? 0 }
        return AccountResources(
            energyAvailable: max(0, value("EnergyLimit") - value("EnergyUsed")),
            freeNetAvailable: max(0, value("freeNetLimit") - value("freeNetUsed")),
            stakedNetAvailable: max(0, value("NetLimit") - value("NetUsed"))
        )
    }

    /// A `getchainparameters` reply: a list of `{key, value}`. nil unless both
    /// prices are there and positive.
    static func parseChainParameters(_ body: [String: Any]) -> ChainFeeParameters? {
        let list = body["chainParameter"] as? [[String: Any]] ?? []
        func value(_ key: String) -> Int64? {
            (list.first { $0["key"] as? String == key }?["value"] as? NSNumber)?.int64Value
        }
        guard let energy = value("getEnergyFee"), energy > 0,
              let bandwidth = value("getTransactionFee"), bandwidth > 0 else { return nil }
        return ChainFeeParameters(energyPriceSun: energy, bandwidthPriceSun: bandwidth)
    }
}

/// The chain's prices change by vote, a few times a year: asking once every
/// six hours is plenty, and saves a request on every estimate.
private enum ChainFeeParameterCache {
    struct Saved: Codable {
        var parameters: ChainFeeParameters
        var savedAt: Date

        var isFresh: Bool {
            let age = Date.now.timeIntervalSince(savedAt)
            return age >= 0 && age < ChainFeeParameterCache.lifetime
        }
    }

    static let key = "fees.chainParameters"
    static let lifetime: TimeInterval = 6 * 60 * 60

    static func load() -> Saved? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Saved.self, from: data)
    }

    static func save(_ parameters: ChainFeeParameters) {
        guard let data = try? JSONEncoder().encode(Saved(parameters: parameters, savedAt: .now)) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// Keeps the Send screens' fee estimate current as the recipient changes.
/// Owned by `SendView`; it holds nothing that outlives a send.
@MainActor @Observable
final class FeeEstimator {
    /// The estimate for `recipient`: nil until the first answer.
    private(set) var estimate: FeeEstimate?
    private(set) var isLoading = false
    /// Whose transfer `estimate` prices.
    private(set) var recipient: String?

    private struct Entry {
        let estimate: FeeEstimate
        let units: UInt64
        let at: Date
    }

    /// The fee depends on the recipient (whether it holds USDT), hardly on the
    /// amount, so one answer per recipient serves for a minute.
    private static let cacheLifetime: TimeInterval = 60
    /// Typing an address fires a change per character; wait for it to settle.
    private static let debounce: Duration = .milliseconds(400)

    @ObservationIgnored private let client: TronClient
    @ObservationIgnored private var cache: [String: Entry] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var sender: String?

    init(client: TronClient = TronClient()) {
        self.client = client
    }

    /// The estimate, if it's for this recipient (never one left from the last).
    func estimate(for recipient: String) -> FeeEstimate? {
        self.recipient == recipient ? estimate : nil
    }

    /// Estimates a transfer to `to`. `units` is nil until an amount is entered;
    /// `balance` is the sender's USDT, which caps the simulated amount.
    /// `immediately` skips the typing delay (the review sheet).
    ///
    /// One attempt per call: a failure or a rate limit settles on
    /// `FeeEstimate.fallback` and is kept for a minute like any other answer.
    func update(from: String, to: String, units: UInt64? = nil, balance: UInt64 = 0, immediately: Bool = false) {
        let simulated = FeeEstimate.simulationUnits(requested: units, balance: balance)
        task?.cancel()
        if sender != from {
            cache.removeAll()
            sender = from
        }
        if recipient != to {
            recipient = to
            estimate = nil
        }
        let cached = cache[to].flatMap { Date.now.timeIntervalSince($0.at) < Self.cacheLifetime ? $0 : nil }
        if let cached {
            estimate = cached.estimate
            // Good as it is, unless a real amount has since replaced the placeholder.
            if units == nil || cached.units == simulated {
                isLoading = false
                return
            }
        }
        isLoading = true
        task = Task { [client] in
            if !immediately {
                try? await Task.sleep(for: Self.debounce)
                if Task.isCancelled { return }
            }
            let fresh = try? await client.estimateUSDTTransferFee(from: from, to: to, units: simulated)
            // A newer call has taken over: its result is the one to show.
            if Task.isCancelled { return }
            if let fresh {
                self.cache[to] = Entry(estimate: fresh, units: simulated, at: .now)
                self.estimate = fresh
            } else if cached?.estimate.source != .simulated {
                // A simulated answer from a moment ago beats the fallback.
                self.cache[to] = Entry(estimate: .fallback, units: simulated, at: .now)
                self.estimate = .fallback
            }
            self.isLoading = false
        }
    }

    /// Shows a given estimate without the network (the demo wallet).
    func show(_ estimate: FeeEstimate, for recipient: String) {
        task?.cancel()
        self.recipient = recipient
        self.estimate = estimate
        isLoading = false
    }

    /// No recipient to estimate for.
    func clear() {
        task?.cancel()
        recipient = nil
        estimate = nil
        isLoading = false
    }
}
