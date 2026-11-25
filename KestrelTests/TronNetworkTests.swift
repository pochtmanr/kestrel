import XCTest
@testable import Kestrel

/// Live read-only checks against TronGrid (skipped when offline).
final class TronNetworkTests: XCTestCase {
    // A busy public exchange wallet with constant USDT traffic.
    private let busyAddress = "TV6MuMXfmLbBqPZvBHdwFsDnQeVfnmiuSi"

    func testReadsBalancesAndHistory() async throws {
        let client = TronClient()
        let usdt: UInt64
        do { usdt = try await client.usdtBalance(of: busyAddress) } catch { throw XCTSkip("TronGrid unreachable: \(error)") }
        let trx = try await client.trxBalance(of: busyAddress)
        let history = try await client.usdtHistory(of: busyAddress, limit: 5)
        print("USDT \(USDT.format(units: usdt)) TRX \(TRX.format(sun: trx)) history \(history.count)")
        XCTAssertGreaterThan(usdt, 0)
        XCTAssertGreaterThan(trx, 0)
        XCTAssertFalse(history.isEmpty)
        XCTAssertTrue(history.allSatisfy { TronAddress.isValid($0.from) && TronAddress.isValid($0.to) && $0.id.count == 64 })
    }
}
