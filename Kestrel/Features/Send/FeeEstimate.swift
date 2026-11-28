import Foundation

// What a USDT transfer will cost, worked out from a simulation of the
// transfer, the sender's free resources and the chain's current prices.
// Pure arithmetic: the network calls live in `TronClient+Fees.swift`, so
// `FeeEstimateTests` can pin every case down.

/// The two prices TRON charges with, in sun. Both are chain parameters the
/// network can change by vote, so they're read from the node, not assumed.
struct ChainFeeParameters: Codable, Equatable, Sendable {
    /// Sun burnt per unit of energy the sender has none staked for (`getEnergyFee`).
    var energyPriceSun: Int64
    /// Sun burnt per byte when the transaction doesn't fit in free bandwidth (`getTransactionFee`).
    var bandwidthPriceSun: Int64

    /// The prices at the time of writing: used until the node has answered once.
    static let builtIn = ChainFeeParameters(energyPriceSun: 100, bandwidthPriceSun: 1000)
}

/// What the sender can spend before any TRX is burnt.
struct AccountResources: Equatable, Sendable {
    /// Staked (or delegated) energy left.
    var energyAvailable: Int64
    /// The daily free bandwidth every activated account gets.
    var freeNetAvailable: Int64
    /// Bandwidth from staked TRX.
    var stakedNetAvailable: Int64

    /// An account with nothing staked and its free bandwidth used up, or one that isn't activated.
    static let none = AccountResources(energyAvailable: 0, freeNetAvailable: 0, stakedNetAvailable: 0)
}

struct FeeEstimate: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        /// From a simulation of this very transfer.
        case simulated
        /// The network didn't answer: the conservative constant.
        case fallback
    }

    /// Energy the transfer uses (0 for the fallback).
    let energy: Int64
    /// What will most likely be burnt: the figure to show.
    let burnSun: Int64
    /// What the wallet must hold before sending: the figure to gate on.
    let requiredSun: Int64
    let source: Source

    /// A TRC20 transfer is 345–346 bytes on every receipt. Rounded up a little,
    /// because a transaction one byte over the free allowance pays for all of it.
    static let bandwidthBytes: Int64 = 350

    /// Flat headroom on top of the estimate, 0.25 TRX. USDT's energy use moves
    /// by a few hundred units between the simulation and the block (its dynamic
    /// energy penalty is re-rated every few hours). A flat amount covers that; a
    /// percentage would grow with the fee and turn away wallets that can pay.
    static let safetyMarginSun: Int64 = 250_000

    /// Energy of a transfer to an address that already holds USDT (measured on mainnet).
    static let holderEnergy: Int64 = 64_285
    /// Energy of a transfer to an address that holds none: the contract writes a
    /// new balance slot, which costs about twice as much.
    static let newRecipientEnergy: Int64 = 130_285

    static func make(energyUsed: Int64, resources: AccountResources, parameters: ChainFeeParameters) -> FeeEstimate {
        let energyFee = max(0, energyUsed - resources.energyAvailable) * parameters.energyPriceSun
        let fullBandwidthFee = bandwidthBytes * parameters.bandwidthPriceSun
        // All or nothing: TRON never part-pays bandwidth. If neither allowance
        // covers the whole transaction, every byte is paid in TRX.
        let bandwidthIsFree = resources.freeNetAvailable >= bandwidthBytes || resources.stakedNetAvailable >= bandwidthBytes
        return FeeEstimate(
            energy: energyUsed,
            burnSun: energyFee + (bandwidthIsFree ? 0 : fullBandwidthFee),
            // Nothing the wallet might not have at send time is counted here.
            // Bandwidth: the free allowance can be used up (by an incoming
            // activation, another app) first. Energy: delegated or rented energy
            // can be taken back, and a send that then runs dry fails and still
            // burns TRX. So the gate is the full burn; `burnSun` shows the saving.
            requiredSun: energyUsed * parameters.energyPriceSun + fullBandwidthFee + safetyMarginSun,
            source: .simulated
        )
    }

    /// No estimate could be made: the constant that covers any USDT transfer.
    static let fallback = FeeEstimate(energy: 0, burnSun: TRX.minimumForTransferSun,
                                      requiredSun: TRX.minimumForTransferSun, source: .fallback)

    /// The simulation says the recipient holds no USDT yet, so this transfer
    /// is in the dearer class. Judged at the midpoint between the two classes.
    var isFirstTransferToRecipient: Bool {
        source == .simulated && energy > (Self.holderEnergy + Self.newRecipientEnergy) / 2
    }

    /// What a transfer burns for a wallet with no resources: to a USDT holder
    /// at the low end, to a new address at the high end. For copy that has no
    /// recipient to simulate against.
    static func typicalRange(parameters: ChainFeeParameters) -> ClosedRange<Int64> {
        let low = make(energyUsed: holderEnergy, resources: .none, parameters: parameters).burnSun
        let high = make(energyUsed: newRecipientEnergy, resources: .none, parameters: parameters).burnSun
        return min(low, high) ... max(low, high)
    }

    /// The amount to simulate with. A zero amount or one above the balance
    /// makes the contract revert, and a revert says nothing about the fee:
    /// so one unit until an amount is known, and never more than the balance.
    static func simulationUnits(requested: UInt64?, balance: UInt64) -> UInt64 {
        guard let requested else { return 1 }
        return max(1, min(requested, balance))
    }

    // MARK: Text

    /// Sun as TRX with two decimals, rounded up: a fee is never shown lower
    /// than it is. A whole number drops its ".00" ("14", not "14.00").
    static func trxText(sun: Int64) -> String {
        let step: Int64 = 10_000
        let (padded, overflow) = max(sun, 0).addingReportingOverflow(step - 1)
        let text = TRX.format(sun: overflow ? sun : padded / step * step)
        return text.hasSuffix(".00") ? String(text.dropLast(3)) : text
    }

    /// "7–14": a range in whole TRX, each end rounded up.
    static func rangeText(_ range: ClosedRange<Int64>) -> String {
        let low = wholeTRX(range.lowerBound), high = wholeTRX(range.upperBound)
        return low == high ? "\(low)" : "\(low)–\(high)"
    }

    private static func wholeTRX(_ sun: Int64) -> Int64 {
        let sun = max(sun, 0)
        return sun / 1_000_000 + (sun % 1_000_000 == 0 ? 0 : 1)
    }
}
