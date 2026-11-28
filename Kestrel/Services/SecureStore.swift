import CommonCrypto
import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Keychain storage, device-only and readable only while unlocked: never in
/// backups, never synced to iCloud.
enum Keychain {
    /// Unit tests run inside the app, on a simulator that may hold a real
    /// wallet: they get a Keychain of their own.
    private static let service = NSClassFromString("XCTestCase") == nil ? "com.simnetiq.kestrel" : "com.simnetiq.kestrel.tests"

    struct Failure: Error { let status: OSStatus }

    private static func query(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
    }

    /// An existing item is updated in place: deleting it first would lose the
    /// value (it may be the recovery phrase) if the add then failed. An item
    /// behind `access` can't be updated without the user present, so it is replaced.
    static func set(_ value: String, for account: String, access: SecAccessControl? = nil) throws {
        let data = Data(value.utf8)
        if access == nil {
            let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData: data] as CFDictionary)
            if status == errSecSuccess { return }
            guard status == errSecItemNotFound else { throw Failure(status: status) }
        } else {
            delete(account)
        }
        var attributes = query(account)
        attributes[kSecValueData] = data
        if let access {
            attributes[kSecAttrAccessControl] = access
        } else {
            attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    /// `context`: an authenticated `LAContext`, for an item behind access control.
    static func get(_ account: String, context: LAContext? = nil) -> String? {
        var query = query(account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        if let context { query[kSecUseAuthenticationContext] = context }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Whether the item is there, without reading it and without ever showing
    /// Face ID. An item whose biometric set has changed no longer counts.
    static func exists(_ account: String) -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        var query = query(account)
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext] = context
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }

    /// Everything this app keeps in the Keychain.
    static func deleteAll() {
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service] as CFDictionary)
    }
}

/// The recovery phrase encrypted under a key derived from the app PIN. The PIN
/// is not stored anywhere: the right one is the one that opens this.
struct SealedPhrase: Codable, Equatable {
    enum Failure: Error { case derivation, random, encoding }

    var version = 1
    var iterations: Int
    /// Hex.
    var salt: String
    /// AES-GCM nonce ‖ ciphertext ‖ tag, base64.
    var box: String

    /// PBKDF2-HMAC-SHA256 rounds (OWASP's 2023 figure). A 6-digit PIN has only
    /// a million values, so the cost per guess is what protects a copied item.
    static let standardIterations = 600_000
    private static let context = Data("kestrel.phrase.v1".utf8)

    static func seal(_ phrase: String, pin: String, iterations: Int = standardIterations) throws -> SealedPhrase {
        var salt = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt) == errSecSuccess else { throw Failure.random }
        let key = try key(pin: pin, salt: salt, iterations: iterations)
        guard let combined = try AES.GCM.seal(Data(phrase.utf8), using: key, authenticating: context).combined else {
            throw Failure.encoding
        }
        return SealedPhrase(iterations: iterations, salt: Hex.encode(salt), box: combined.base64EncodedString())
    }

    /// nil for a wrong PIN (the authentication tag fails) or a damaged record.
    func open(pin: String) -> String? {
        guard version == 1, iterations > 0, let salt = Hex.decode(salt), let combined = Data(base64Encoded: box),
              let key = try? Self.key(pin: pin, salt: salt, iterations: iterations),
              let sealed = try? AES.GCM.SealedBox(combined: combined),
              let plain = try? AES.GCM.open(sealed, using: key, authenticating: Self.context)
        else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    private static func key(pin: String, salt: [UInt8], iterations: Int) throws -> SymmetricKey {
        let password = Array(pin.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = password.withUnsafeBufferPointer { pw in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                UnsafeRawPointer(pw.baseAddress!).assumingMemoryBound(to: CChar.self), pw.count,
                salt, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                &derived, derived.count
            )
        }
        guard status == kCCSuccess, !password.isEmpty else { throw Failure.derivation }
        return SymmetricKey(data: derived)
    }
}

/// The recovery phrase: the only thing that controls the funds.
///
/// It is kept two ways, and neither can be read by simply opening the app:
/// - encrypted under the app PIN (`SealedPhrase`), always;
/// - behind the current Face ID / Touch ID enrolment, when biometrics are on.
///   iOS itself releases that copy, and drops it if a face or finger is added.
///
/// The address is kept beside them in the clear, so launching needs neither.
enum WalletVault {
    enum Failure: Error { case missing, notSaved }

    /// A new wallet's phrase waits here, unencrypted, until its PIN is created.
    /// It is also where versions before PIN encryption kept the phrase for good.
    private static let pendingAccount = "wallet.mnemonic"
    private static let sealedAccount = "wallet.phrase.sealed"
    private static let biometricAccount = "wallet.phrase.biometric"
    private static let addressAccount = "wallet.address"
    /// Before PIN encryption: `hex(salt) : hex(SHA256(salt ‖ pin))` and a "1" flag.
    private static let legacyPinAccount = "security.pin.v2"
    private static let legacyBiometricFlag = "security.biometric.enabled"

    static var address: String? {
        if let address = Keychain.get(addressAccount) { return address }
        // A wallet from before the address was stored on its own.
        guard let phrase = Keychain.get(pendingAccount), let keys = try? TronKeys(mnemonic: phrase) else { return nil }
        try? Keychain.set(keys.address, for: addressAccount)
        return keys.address
    }

    static var hasPIN: Bool { Keychain.exists(sealedAccount) || Keychain.exists(legacyPinAccount) }

    /// A new or restored wallet. Only reachable with no wallet on the device.
    static func save(_ mnemonic: String) throws {
        let phrase = Mnemonic.normalize(mnemonic)
        let keys = try TronKeys(mnemonic: phrase)
        for stale in [sealedAccount, biometricAccount, legacyPinAccount, legacyBiometricFlag] { Keychain.delete(stale) }
        PinThrottle.reset()
        try Keychain.set(phrase, for: pendingAccount)
        try Keychain.set(keys.address, for: addressAccount)
    }

    /// The first PIN of a new wallet. Returns the phrase, for turning biometrics on.
    static func createPIN(_ pin: String) throws -> String {
        guard let phrase = Keychain.get(pendingAccount) else { throw Failure.missing }
        try seal(phrase, pin: pin)
        Keychain.delete(pendingAccount)
        return phrase
    }

    /// A new PIN for a phrase the old PIN just opened. The old record stays
    /// until the new one is written, so an interruption never leaves the wallet without a PIN.
    static func changePIN(phrase: String, to pin: String) throws {
        try seal(phrase, pin: pin)
    }

    /// The phrase, if the PIN is right. Slow by design (key derivation): call off the main thread.
    static func open(pin: String) -> String? {
        if let stored = Keychain.get(sealedAccount) {
            guard let sealed = try? JSONDecoder().decode(SealedPhrase.self, from: Data(stored.utf8)) else { return nil }
            return sealed.open(pin: pin)
        }
        return migrate(pin: pin)
    }

    /// A wallet saved before PIN encryption: check the PIN the old way, then
    /// move the phrase behind it. The plain copy goes only once the sealed one is verified.
    private static func migrate(pin: String) -> String? {
        guard verifyLegacy(pin), let phrase = Keychain.get(pendingAccount) else { return nil }
        if (try? seal(phrase, pin: pin)) != nil {
            Keychain.delete(pendingAccount)
            Keychain.delete(legacyPinAccount)
            if Keychain.get(legacyBiometricFlag) == "1" { try? enableBiometrics(phrase: phrase) }
            Keychain.delete(legacyBiometricFlag)
        }
        return phrase
    }

    private static func verifyLegacy(_ pin: String) -> Bool {
        guard let stored = Keychain.get(legacyPinAccount) else { return false }
        let parts = stored.split(separator: ":").map(String.init)
        guard parts.count == 2, let salt = Hex.decode(parts[0]), let expected = Hex.decode(parts[1]) else { return false }
        let digest = Array(SHA256.hash(data: Data(salt + Array(pin.utf8))))
        guard digest.count == expected.count else { return false }
        // Constant time: no early exit on the first differing byte.
        var difference: UInt8 = 0
        for (a, b) in zip(digest, expected) { difference |= a ^ b }
        return difference == 0
    }

    private static func seal(_ phrase: String, pin: String) throws {
        if Keychain.get(addressAccount) == nil {
            try Keychain.set(try TronKeys(mnemonic: phrase).address, for: addressAccount)
        }
        let sealed = try SealedPhrase.seal(phrase, pin: pin)
        // Never replace a working record with one that doesn't open.
        guard sealed.open(pin: pin) == phrase, let json = String(data: try JSONEncoder().encode(sealed), encoding: .utf8) else {
            throw Failure.notSaved
        }
        try Keychain.set(json, for: sealedAccount)
        guard Keychain.get(sealedAccount) == json else { throw Failure.notSaved }
    }

    // MARK: Biometrics

    static var biometricsEnabled: Bool { Keychain.exists(biometricAccount) }

    /// Stores a copy that only the faces or fingers enrolled right now can
    /// release. Enrolling another one invalidates it, and the PIN is needed again.
    static func enableBiometrics(phrase: String) throws {
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, nil
        ) else { throw Failure.notSaved }
        try Keychain.set(phrase, for: biometricAccount, access: access)
    }

    static func disableBiometrics() { Keychain.delete(biometricAccount) }

    /// `context` must have just passed a biometric check.
    static func open(with context: LAContext) -> String? {
        Keychain.get(biometricAccount, context: context)
    }

    static func erase() {
        Keychain.deleteAll()
    }
}

enum PinStore {
    static let length = 6
}

/// Wrong-PIN counting that survives a relaunch, shared by every PIN prompt.
enum PinThrottle {
    struct State: Codable, Equatable {
        var failures = 0
        var lastFailure = Date.distantPast
    }

    private static let account = "security.pin.attempts"
    static let freeAttempts = 4

    /// The wait after the nth wrong PIN in a row: none for the first four,
    /// then 1, 5 and 15 minutes, then an hour each time.
    static func delay(afterFailures failures: Int) -> TimeInterval {
        switch failures {
        case ...freeAttempts: 0
        case 5: 60
        case 6: 300
        case 7: 900
        default: 3600
        }
    }

    static func lockedUntil(_ state: State, now: Date) -> Date? {
        let wait = delay(afterFailures: state.failures)
        guard wait > 0 else { return nil }
        // A clock set back to before the last failure doesn't shorten the wait.
        let until = min(state.lastFailure, now).addingTimeInterval(wait)
        return until > now ? until : nil
    }

    private static var state: State {
        get {
            guard let stored = Keychain.get(account) else { return State() }
            return (try? JSONDecoder().decode(State.self, from: Data(stored.utf8))) ?? State()
        }
        set {
            guard let json = try? JSONEncoder().encode(newValue) else { return }
            try? Keychain.set(String(decoding: json, as: UTF8.self), for: account)
        }
    }

    static func lockedUntil(now: Date = .now) -> Date? {
        let current = state
        if current.lastFailure > now, current.failures > freeAttempts {
            state = State(failures: current.failures, lastFailure: now)
        }
        return lockedUntil(current, now: now)
    }

    static func recordFailure(now: Date = .now) {
        state = State(failures: state.failures + 1, lastFailure: now)
    }

    static func reset() { Keychain.delete(account) }
}

/// One PIN attempt, counted before it is checked: killing the app mid-check
/// doesn't win a free guess.
enum PinGate {
    enum Outcome {
        case phrase(String)
        case wrong(lockedUntil: Date?)
        case locked(until: Date)
    }

    static func submit(_ pin: String) async -> Outcome {
        if let until = PinThrottle.lockedUntil() { return .locked(until: until) }
        PinThrottle.recordFailure()
        let phrase = await Task.detached(priority: .userInitiated) { WalletVault.open(pin: pin) }.value
        guard let phrase else { return .wrong(lockedUntil: PinThrottle.lockedUntil()) }
        PinThrottle.reset()
        return .phrase(phrase)
    }
}

enum Biometrics {
    enum Kind { case faceID, touchID, opticID, none }

    static var kind: Kind {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return .none }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .none
        }
    }

    static var label: String {
        switch kind {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        case .none: tr("Biometrics")
        }
    }

    static var symbol: String {
        switch kind {
        case .touchID: "touchid"
        case .opticID: "opticid"
        default: "faceid"
        }
    }

    /// On when the phrase's biometric copy exists and can still be released.
    static var isEnabled: Bool { kind != .none && WalletVault.biometricsEnabled }

    /// Biometrics only (the app PIN is the fallback, shown by our own UI).
    static func authenticate(reason: String) async -> Bool {
        await evaluated(reason: reason) != nil
    }

    /// Face ID, then the phrase from the Keychain item that the check releases.
    /// nil when the check fails or is cancelled, or the enrolment has changed.
    static func unlockPhrase(reason: String) async -> String? {
        guard let context = await evaluated(reason: reason) else { return nil }
        return WalletVault.open(with: context)
    }

    private static func evaluated(reason: String) async -> LAContext? {
        let context = LAContext()
        context.localizedFallbackTitle = tr("Use PIN")
        let passed = (try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)) ?? false
        return passed ? context : nil
    }
}

/// Stable anonymous id for support chat, so the conversation history survives
/// relaunches without linking it to the wallet address.
enum SupportIdentity {
    private static let account = "support.contact.id"

    static var id: String {
        if let existing = Keychain.get(account) { return existing }
        let id = "kestrel-\(UUID().uuidString.lowercased())"
        try? Keychain.set(id, for: account)
        return id
    }
}
