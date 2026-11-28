import CryptoKit
import XCTest
@testable import Kestrel

/// The vault against the real Keychain. Under XCTest `Keychain` uses a service
/// of its own, so a wallet saved by the app on this simulator is never touched.
final class WalletVaultTests: XCTestCase {
    private let phrase = "legal winner thank year wave sausage worth useful legal winner thank yellow"

    override func setUp() { WalletVault.erase() }
    override func tearDown() { WalletVault.erase() }

    func testKeychainSetReplacesInPlace() throws {
        try Keychain.set("one", for: "test.item")
        try Keychain.set("two", for: "test.item")
        XCTAssertEqual(Keychain.get("test.item"), "two")
        XCTAssertTrue(Keychain.exists("test.item"))
        Keychain.delete("test.item")
        XCTAssertFalse(Keychain.exists("test.item"))
        XCTAssertNil(Keychain.get("test.item"))
    }

    func testNewWalletThenPIN() throws {
        XCTAssertNil(WalletVault.address)
        XCTAssertFalse(WalletVault.hasPIN)

        try WalletVault.save("  Legal winner thank year wave sausage worth useful legal winner thank yellow ")
        let address = try TronKeys(mnemonic: phrase).address
        XCTAssertEqual(WalletVault.address, address)
        XCTAssertFalse(WalletVault.hasPIN, "the app asks for a PIN next")

        XCTAssertEqual(try WalletVault.createPIN("135790"), phrase)
        XCTAssertTrue(WalletVault.hasPIN)
        XCTAssertNil(Keychain.get("wallet.mnemonic"), "no unencrypted copy once the PIN exists")
        XCTAssertEqual(WalletVault.address, address, "the address needs no PIN")
        XCTAssertFalse(try XCTUnwrap(Keychain.get("wallet.phrase.sealed")).contains("winner"))

        XCTAssertEqual(WalletVault.open(pin: "135790"), phrase)
        XCTAssertNil(WalletVault.open(pin: "135791"))
        XCTAssertThrowsError(try WalletVault.createPIN("246802"), "there is no pending phrase to seal twice")
    }

    func testChangingThePIN() throws {
        try WalletVault.save(phrase)
        _ = try WalletVault.createPIN("135790")
        try WalletVault.changePIN(phrase: phrase, to: "246802")
        XCTAssertNil(WalletVault.open(pin: "135790"))
        XCTAssertEqual(WalletVault.open(pin: "246802"), phrase)
    }

    func testWalletFromBeforePINEncryptionMovesBehindThePIN() throws {
        // What earlier versions stored: the phrase in the clear and a salted SHA-256 of the PIN.
        let salt: [UInt8] = Array(0 ..< 16)
        let hash = Hex.encode(Array(SHA256.hash(data: Data(salt + Array("135790".utf8)))))
        try Keychain.set(phrase, for: "wallet.mnemonic")
        try Keychain.set(Hex.encode(salt) + ":" + hash, for: "security.pin.v2")

        XCTAssertEqual(WalletVault.address, try TronKeys(mnemonic: phrase).address)
        XCTAssertTrue(WalletVault.hasPIN)
        XCTAssertNil(WalletVault.open(pin: "000000"))
        XCTAssertNotNil(Keychain.get("wallet.mnemonic"), "a wrong PIN migrates nothing")

        XCTAssertEqual(WalletVault.open(pin: "135790"), phrase)
        XCTAssertNil(Keychain.get("wallet.mnemonic"))
        XCTAssertNil(Keychain.get("security.pin.v2"))
        XCTAssertTrue(WalletVault.hasPIN)
        XCTAssertEqual(WalletVault.open(pin: "135790"), phrase)
        XCTAssertNil(WalletVault.open(pin: "000000"))
    }

    func testBiometricCopyIsSeparateFromThePIN() throws {
        try WalletVault.save(phrase)
        _ = try WalletVault.createPIN("135790")
        XCTAssertFalse(WalletVault.biometricsEnabled)
        do {
            try WalletVault.enableBiometrics(phrase: phrase)
        } catch {
            throw XCTSkip("this simulator can't store a biometry-bound item: \(error)")
        }
        XCTAssertTrue(WalletVault.biometricsEnabled)
        // A new PIN leaves it alone; turning it off removes only it.
        try WalletVault.changePIN(phrase: phrase, to: "246802")
        XCTAssertTrue(WalletVault.biometricsEnabled)
        WalletVault.disableBiometrics()
        XCTAssertFalse(WalletVault.biometricsEnabled)
        XCTAssertEqual(WalletVault.open(pin: "246802"), phrase)
    }

    func testSavingANewWalletDropsTheOldOnesPIN() throws {
        try WalletVault.save(phrase)
        _ = try WalletVault.createPIN("135790")
        try WalletVault.save("letter advice cage absurd amount doctor acoustic avoid letter advice cage above")
        XCTAssertFalse(WalletVault.hasPIN)
        XCTAssertNil(WalletVault.open(pin: "135790"))
    }

    func testEraseLeavesNothing() throws {
        try WalletVault.save(phrase)
        _ = try WalletVault.createPIN("135790")
        _ = SupportIdentity.id
        PinThrottle.recordFailure()
        WalletVault.erase()
        XCTAssertNil(WalletVault.address)
        XCTAssertFalse(WalletVault.hasPIN)
        XCTAssertNil(WalletVault.open(pin: "135790"))
        XCTAssertNil(Keychain.get("support.contact.id"))
        XCTAssertNil(Keychain.get("security.pin.attempts"))
    }

    func testWrongPINsLockEveryPromptAndTheRightOneClearsTheCount() async throws {
        try WalletVault.save(phrase)
        _ = try WalletVault.createPIN("135790")

        for attempt in 1 ... 4 {
            guard case .wrong(lockedUntil: nil) = await PinGate.submit("000000") else {
                return XCTFail("attempt \(attempt) should be wrong, with no wait yet")
            }
        }
        guard case .phrase(phrase) = await PinGate.submit("135790") else { return XCTFail("the right PIN opens") }
        XCTAssertNil(Keychain.get("security.pin.attempts"))

        for _ in 1 ... 4 { _ = await PinGate.submit("000000") }
        guard case .wrong(lockedUntil: let until?) = await PinGate.submit("000000") else {
            return XCTFail("the fifth wrong PIN starts a wait")
        }
        XCTAssertEqual(until.timeIntervalSinceNow, 60, accuracy: 5)
        // Even the right PIN waits, and the count is in the Keychain, not in a view.
        guard case .locked = await PinGate.submit("135790") else { return XCTFail("locked out") }
        XCTAssertNotNil(PinThrottle.lockedUntil())
    }
}
