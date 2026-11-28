import Foundation
import XCTest
@testable import Kestrel

/// The fee estimate's parsing and arithmetic, against replies captured from TronGrid.
final class FeeEstimateTests: XCTestCase {
    private func json(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    // MARK: Fixtures

    /// `triggerconstantcontract` for a transfer to an address that holds USDT.
    private let holderSimulation = """
    {"result":{"result":true},"energy_used":64285,"energy_penalty":49635,
     "constant_result":["0000000000000000000000000000000000000000000000000000000000000000"],
     "transaction":{"ret":[{}],"visible":false,"txID":"5c2b","raw_data_hex":"0a02"}}
    """

    /// The same call for an address that holds none: a new balance slot is written.
    private let newRecipientSimulation = """
    {"result":{"result":true},"energy_used":130285,"energy_penalty":100593,
     "constant_result":["0000000000000000000000000000000000000000000000000000000000000000"]}
    """

    /// A revert (amount above the balance): `result.result` is still true.
    private let revertedSimulation = """
    {"result":{"result":true,"message":"524556455254206f70636f6465206578656375746564"},
     "energy_used":8624,"constant_result":[""]}
    """

    private let chainParameters = """
    {"chainParameter":[
      {"key":"getMaintenanceTimeInterval","value":21600000},
      {"key":"getTransactionFee","value":1000},
      {"key":"getEnergyFee","value":100},
      {"key":"getAllowTvmTransferTrc10"},
      {"key":"getFreeNetLimit","value":600}
    ]}
    """

    private let none = AccountResources.none

    // MARK: Simulation

    func testReadsEnergyOfATransferToAHolder() throws {
        XCTAssertEqual(TronClient.parseSimulation(try json(holderSimulation)), 64_285)
    }

    func testReadsEnergyOfATransferToANewRecipient() throws {
        XCTAssertEqual(TronClient.parseSimulation(try json(newRecipientSimulation)), 130_285)
    }

    func testRejectsARevertThatLooksLikeACheapSuccess() throws {
        XCTAssertNil(TronClient.parseSimulation(try json(revertedSimulation)))
    }

    func testRejectsIncompleteSimulations() throws {
        XCTAssertNil(TronClient.parseSimulation([:]))
        XCTAssertNil(TronClient.parseSimulation(try json(#"{"result":{"result":true},"energy_used":64285,"constant_result":[""]}"#)),
                     "an empty return word is a revert, message or not")
        XCTAssertNil(TronClient.parseSimulation(try json(#"{"result":{"result":true},"energy_used":64285}"#)))
        XCTAssertNil(TronClient.parseSimulation(try json(#"{"result":{"result":true,"message":"00"},"energy_used":64285,"constant_result":["00"]}"#)),
                     "any message means the call didn't run clean")
        XCTAssertNil(TronClient.parseSimulation(try json(#"{"result":{"result":false},"energy_used":64285,"constant_result":["00"]}"#)))
        XCTAssertNil(TronClient.parseSimulation(try json(#"{"result":{"result":true},"constant_result":["00"]}"#)), "no energy figure")
        XCTAssertNil(TronClient.parseSimulation(try json(#"{"Error":"class java.lang.NullPointerException"}"#)))
    }

    // MARK: Resources

    func testAnUnactivatedAccountHasNoResources() throws {
        XCTAssertEqual(TronClient.parseResources(try json("{}")), none)
    }

    func testOmittedKeysCountAsZero() throws {
        // Nothing used yet today, nothing staked: only the limits are sent.
        let fresh = TronClient.parseResources(try json(#"{"freeNetLimit":600,"TotalNetLimit":43200000000,"TotalEnergyLimit":180000000000}"#))
        XCTAssertEqual(fresh, AccountResources(energyAvailable: 0, freeNetAvailable: 600, stakedNetAvailable: 0))

        let used = TronClient.parseResources(try json(#"{"freeNetLimit":600,"freeNetUsed":346}"#))
        XCTAssertEqual(used.freeNetAvailable, 254)

        let staked = TronClient.parseResources(try json(
            #"{"freeNetLimit":600,"freeNetUsed":600,"NetLimit":5000,"NetUsed":692,"EnergyLimit":100000,"EnergyUsed":61672}"#))
        XCTAssertEqual(staked, AccountResources(energyAvailable: 38_328, freeNetAvailable: 0, stakedNetAvailable: 4_308))
    }

    func testResourcesNeverGoNegative() throws {
        // Usage can exceed a limit right after an unstake.
        let over = TronClient.parseResources(try json(#"{"freeNetLimit":600,"freeNetUsed":700,"EnergyLimit":10,"EnergyUsed":50,"NetUsed":3}"#))
        XCTAssertEqual(over, none)
    }

    // MARK: Chain parameters

    func testReadsChainParameters() throws {
        XCTAssertEqual(TronClient.parseChainParameters(try json(chainParameters)),
                       ChainFeeParameters(energyPriceSun: 100, bandwidthPriceSun: 1000))
        XCTAssertEqual(TronClient.parseChainParameters(try json(chainParameters)), .builtIn)
    }

    func testRejectsChainParametersWithoutBothPrices() throws {
        XCTAssertNil(TronClient.parseChainParameters([:]))
        XCTAssertNil(TronClient.parseChainParameters(try json(#"{"chainParameter":[{"key":"getEnergyFee","value":100}]}"#)))
        XCTAssertNil(TronClient.parseChainParameters(try json(
            #"{"chainParameter":[{"key":"getEnergyFee","value":0},{"key":"getTransactionFee","value":1000}]}"#)))
    }

    func testChainParametersSurviveSaving() throws {
        let parameters = ChainFeeParameters(energyPriceSun: 210, bandwidthPriceSun: 1000)
        let data = try JSONEncoder().encode(parameters)
        XCTAssertEqual(try JSONDecoder().decode(ChainFeeParameters.self, from: data), parameters)
    }

    // MARK: The estimate

    func testTransferToAHolderWithNoResources() {
        let estimate = FeeEstimate.make(energyUsed: 64_285, resources: none, parameters: .builtIn)
        XCTAssertEqual(estimate.energy, 64_285)
        XCTAssertEqual(estimate.burnSun, 6_778_500, "6.4285 TRX of energy + 0.35 TRX of bandwidth")
        XCTAssertEqual(estimate.requiredSun, 7_028_500, "≈ 7.03 TRX")
        XCTAssertEqual(estimate.source, .simulated)
        XCTAssertFalse(estimate.isFirstTransferToRecipient)
    }

    func testTransferToANewRecipientWithNoResources() {
        let estimate = FeeEstimate.make(energyUsed: 130_285, resources: none, parameters: .builtIn)
        XCTAssertEqual(estimate.burnSun, 13_378_500)
        XCTAssertEqual(estimate.requiredSun, 13_628_500, "≈ 13.63 TRX")
        XCTAssertTrue(estimate.isFirstTransferToRecipient)
        XCTAssertLessThanOrEqual(estimate.requiredSun, TRX.minimumForTransferSun, "the constant still covers the dearest case")
    }

    func testStakedEnergyPaysFirst() {
        let partial = AccountResources(energyAvailable: 38_328, freeNetAvailable: 600, stakedNetAvailable: 0)
        let estimate = FeeEstimate.make(energyUsed: 130_285, resources: partial, parameters: .builtIn)
        XCTAssertEqual(estimate.burnSun, 9_195_700, "(130,285 − 38,328) × 100 sun, bandwidth free")
        XCTAssertEqual(estimate.requiredSun, 13_028_500 + 350_000 + 250_000, "the gate doesn't count on staked energy")

        let plenty = AccountResources(energyAvailable: 500_000, freeNetAvailable: 600, stakedNetAvailable: 0)
        let free = FeeEstimate.make(energyUsed: 64_285, resources: plenty, parameters: .builtIn)
        XCTAssertEqual(free.burnSun, 0)
        XCTAssertEqual(free.requiredSun, 6_428_500 + 600_000, "energy can be taken back, so the full burn is held back")
    }

    func testBandwidthIsAllOrNothing() {
        func burn(free: Int64, staked: Int64) -> Int64 {
            let resources = AccountResources(energyAvailable: 1_000_000, freeNetAvailable: free, stakedNetAvailable: staked)
            return FeeEstimate.make(energyUsed: 64_285, resources: resources, parameters: .builtIn).burnSun
        }
        XCTAssertEqual(burn(free: 600, staked: 0), 0)
        XCTAssertEqual(burn(free: 350, staked: 0), 0)
        XCTAssertEqual(burn(free: 349, staked: 0), 350_000, "one byte short pays for every byte")
        XCTAssertEqual(burn(free: 0, staked: 350), 0)
        XCTAssertEqual(burn(free: 200, staked: 200), 350_000, "the two allowances don't add up")
        XCTAssertEqual(burn(free: 0, staked: 0), 350_000)
    }

    func testRequiredAlwaysCountsBandwidthAndAFlatMargin() {
        let free = AccountResources(energyAvailable: 0, freeNetAvailable: 600, stakedNetAvailable: 5_000)
        let estimate = FeeEstimate.make(energyUsed: 64_285, resources: free, parameters: .builtIn)
        XCTAssertEqual(estimate.burnSun, 6_428_500)
        XCTAssertEqual(estimate.requiredSun, 7_028_500, "the same as with no free bandwidth")
        XCTAssertEqual(estimate.requiredSun - estimate.burnSun,
                       FeeEstimate.bandwidthBytes * 1000 + FeeEstimate.safetyMarginSun)
    }

    func testFollowsChainPrices() {
        let dearer = ChainFeeParameters(energyPriceSun: 210, bandwidthPriceSun: 2000)
        let estimate = FeeEstimate.make(energyUsed: 64_285, resources: none, parameters: dearer)
        XCTAssertEqual(estimate.burnSun, 64_285 * 210 + 350 * 2000)
        XCTAssertEqual(estimate.requiredSun, 64_285 * 210 + 350 * 2000 + 250_000)
    }

    func testFallbackIsTheConstant() {
        XCTAssertEqual(FeeEstimate.fallback.burnSun, 14_000_000)
        XCTAssertEqual(FeeEstimate.fallback.requiredSun, TRX.minimumForTransferSun)
        XCTAssertEqual(FeeEstimate.fallback.source, .fallback)
        XCTAssertFalse(FeeEstimate.fallback.isFirstTransferToRecipient)
    }

    func testTypicalRange() {
        let range = FeeEstimate.typicalRange(parameters: .builtIn)
        XCTAssertEqual(range, 6_778_500 ... 13_378_500)
        XCTAssertEqual(FeeEstimate.rangeText(range), "7–14")
        XCTAssertEqual(FeeEstimate.rangeText(7_000_000 ... 7_000_000), "7")
    }

    func testSimulatesWithAnAmountThatCannotRevert() {
        XCTAssertEqual(FeeEstimate.simulationUnits(requested: nil, balance: 50_000_000), 1, "no amount yet")
        XCTAssertEqual(FeeEstimate.simulationUnits(requested: 5_000_000, balance: 50_000_000), 5_000_000)
        XCTAssertEqual(FeeEstimate.simulationUnits(requested: 90_000_000, balance: 50_000_000), 50_000_000, "capped at the balance")
        XCTAssertEqual(FeeEstimate.simulationUnits(requested: 0, balance: 50_000_000), 1, "never zero")
    }

    func testFeeTextRoundsUp() {
        XCTAssertEqual(FeeEstimate.trxText(sun: 6_778_500), "6.78")
        XCTAssertEqual(FeeEstimate.trxText(sun: 7_028_500), "7.03")
        XCTAssertEqual(FeeEstimate.trxText(sun: 13_628_500), "13.63")
        XCTAssertEqual(FeeEstimate.trxText(sun: 14_000_000), "14")
        XCTAssertEqual(FeeEstimate.trxText(sun: 0), "0")
    }
}
