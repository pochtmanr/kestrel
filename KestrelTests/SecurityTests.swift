import XCTest
@testable import Kestrel

/// PIN encryption of the recovery phrase, the wrong-PIN wait, and the
/// address-poisoning checks. None of these touch the Keychain: the tests run
/// inside the app, whose Keychain may hold a real wallet.
final class SecurityTests: XCTestCase {
    private let phrase = "legal winner thank year wave sausage worth useful legal winner thank yellow"
    private let me = "TV2QjYfd8Js2JhDfqKzZMLBscYtBkxU9ek"
    private let friend = "TXJgMdjVX5dKiQaUi9QobwNxtSQaFqccvd"

    // MARK: Sealed phrase

    func testSealedPhraseOpensOnlyWithItsPIN() throws {
        // Few rounds: the cost is what's configurable, not what's under test.
        let sealed = try SealedPhrase.seal(phrase, pin: "135790", iterations: 1000)
        XCTAssertEqual(sealed.open(pin: "135790"), phrase)
        XCTAssertNil(sealed.open(pin: "135791"))
        XCTAssertNil(sealed.open(pin: ""))
        XCTAssertFalse(sealed.box.contains("legal"))
    }

    func testSealingTwiceGivesDifferentRecords() throws {
        let a = try SealedPhrase.seal(phrase, pin: "135790", iterations: 1000)
        let b = try SealedPhrase.seal(phrase, pin: "135790", iterations: 1000)
        XCTAssertNotEqual(a.salt, b.salt)
        XCTAssertNotEqual(a.box, b.box)
    }

    func testSealedPhraseSurvivesStorageAndRejectsTampering() throws {
        let sealed = try SealedPhrase.seal(phrase, pin: "135790", iterations: 1000)
        var stored = try JSONDecoder().decode(SealedPhrase.self, from: JSONEncoder().encode(sealed))
        XCTAssertEqual(stored.open(pin: "135790"), phrase)

        // A lower round count must not open it: the rounds are part of the key.
        stored.iterations = 1
        XCTAssertNil(stored.open(pin: "135790"))
        stored = sealed
        var box = try XCTUnwrap(Data(base64Encoded: stored.box))
        box[box.count - 1] ^= 1
        stored.box = box.base64EncodedString()
        XCTAssertNil(stored.open(pin: "135790"))
        stored = sealed
        stored.version = 2
        XCTAssertNil(stored.open(pin: "135790"))
    }

    func testStandardKeyDerivationCost() throws {
        XCTAssertGreaterThanOrEqual(SealedPhrase.standardIterations, 600_000)
        let sealed = try SealedPhrase.seal(phrase, pin: "000000")
        XCTAssertEqual(sealed.iterations, SealedPhrase.standardIterations)
        XCTAssertEqual(sealed.open(pin: "000000"), phrase)
    }

    // MARK: Wrong-PIN wait

    func testWaitGrowsWithEachFailure() {
        XCTAssertEqual((0 ... 9).map { PinThrottle.delay(afterFailures: $0) }, [0, 0, 0, 0, 0, 60, 300, 900, 3600, 3600])
    }

    func testLockedUntil() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNil(PinThrottle.lockedUntil(.init(failures: 4, lastFailure: now), now: now))
        XCTAssertEqual(PinThrottle.lockedUntil(.init(failures: 5, lastFailure: now), now: now), now.addingTimeInterval(60))
        XCTAssertNil(PinThrottle.lockedUntil(.init(failures: 5, lastFailure: now.addingTimeInterval(-61)), now: now))
        XCTAssertEqual(
            PinThrottle.lockedUntil(.init(failures: 7, lastFailure: now.addingTimeInterval(-100)), now: now),
            now.addingTimeInterval(800)
        )
    }

    func testSettingTheClockBackDoesNotShortenTheWait() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let later = now.addingTimeInterval(86_400)
        XCTAssertEqual(PinThrottle.lockedUntil(.init(failures: 6, lastFailure: later), now: now), now.addingTimeInterval(300))
    }

    // MARK: Address poisoning

    private func transfer(_ id: String, from: String, to: String, units: UInt64) -> TokenTransfer {
        TokenTransfer(id: id, date: Date(timeIntervalSince1970: 1_700_000_000), from: from, to: to, units: units)
    }

    func testZeroValueTransfersNeverReachTheHistory() throws {
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Data("""
        {"data":[
          {"transaction_id":"real","block_timestamp":2,"from":"\(me)","to":"\(friend)","value":"5000000"},
          {"transaction_id":"poison","block_timestamp":1,"from":"\(me)","to":"TXJgMdjVX5dKiQaUi9QobwNxtSQaFqccvx","value":"0"}
        ]}
        """.utf8)) as? [String: Any])
        XCTAssertEqual(TronClient.parseTransfers(body).transfers.map(\.id), ["real"])

        // One cached before the filter existed goes at the next merge.
        let merged = ActivityStore.merge([], into: [transfer("old", from: me, to: friend, units: 0), transfer("kept", from: me, to: friend, units: 1)])
        XCTAssertEqual(merged.map(\.id), ["kept"])
    }

    func testTinyTransfersAreSuspicious() {
        XCTAssertTrue(AddressSafety.isSuspicious(transfer("a", from: friend, to: me, units: 1)))
        XCTAssertTrue(AddressSafety.isSuspicious(transfer("a", from: friend, to: me, units: 999_999)))
        XCTAssertFalse(AddressSafety.isSuspicious(transfer("a", from: friend, to: me, units: 1_000_000)))
    }

    func testRecipientYouPaidBeforeIsKnown() {
        let history = [transfer("a", from: me, to: friend, units: 20_000_000)]
        XCTAssertEqual(AddressSafety.assess(recipient: friend, ownAddress: me, transfers: history), .known)
        XCTAssertEqual(AddressSafety.assess(recipient: USDT.contract, ownAddress: me, transfers: history), .firstTime)
        XCTAssertEqual(AddressSafety.assess(recipient: friend, ownAddress: me, transfers: []), .firstTime)
    }

    func testLookalikeOfAnAddressFromTheHistory() {
        let history = [transfer("a", from: me, to: friend, units: 20_000_000)]
        // Same ending, different middle: what a poisoner generates.
        let sameEnd = "TQ5xk2mFh7Zp1Wc8Yd3Rb6Nv9Ls4Gt0Jccvd"
        let sameStart = "TXJgM" + String(repeating: "z", count: 29)
        XCTAssertEqual(AddressSafety.assess(recipient: sameEnd, ownAddress: me, transfers: history), .lookalike(of: friend))
        XCTAssertEqual(AddressSafety.assess(recipient: sameStart, ownAddress: me, transfers: history), .lookalike(of: friend))
        // Someone who really paid you is worth imitating too.
        let incoming = [transfer("b", from: friend, to: me, units: 20_000_000)]
        XCTAssertEqual(AddressSafety.assess(recipient: sameEnd, ownAddress: me, transfers: incoming), .lookalike(of: friend))
    }

    func testDustDoesNotMakeAnAddressKnown() {
        let poisoner = "TQ5xk2mFh7Zp1Wc8Yd3Rb6Nv9Ls4Gt0Jccvd"
        let history = [
            transfer("a", from: me, to: friend, units: 20_000_000),
            transfer("dust-in", from: poisoner, to: me, units: 1),
            transfer("dust-out", from: me, to: poisoner, units: 10),
        ]
        XCTAssertEqual(AddressSafety.assess(recipient: poisoner, ownAddress: me, transfers: history), .lookalike(of: friend))
    }

    // MARK: Amounts

    func testAmountAtTheTopOfTheRangeDoesNotOverflow() {
        XCTAssertNil(USDT.units(from: "18446744073709.999999"), "the fraction pushes it past UInt64")
        XCTAssertEqual(USDT.units(from: "18446744073709.551615"), UInt64.max)
        XCTAssertNil(USDT.units(from: "18446744073710"))
    }
}
