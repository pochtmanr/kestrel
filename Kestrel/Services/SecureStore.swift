import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Keychain storage, device-only and readable only while unlocked: never in
/// backups, never synced to iCloud.
enum Keychain {
    private static let service = "com.simnetiq.kestrel"

    static func set(_ value: String, for account: String) throws {
        delete(account)
        let status = SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData: Data(value.utf8),
        ] as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    static func get(_ account: String, service: String = service) -> String? {
        var result: AnyObject?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String, service: String = service) {
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary)
    }
}

/// The recovery phrase: the only thing that controls the funds.
enum WalletVault {
    private static let account = "wallet.mnemonic"

    static var hasWallet: Bool { mnemonic() != nil }

    static func save(_ mnemonic: String) throws {
        try Keychain.set(Mnemonic.normalize(mnemonic), for: account)
    }

    static func mnemonic() -> String? { Keychain.get(account) }

    static func keys() throws -> TronKeys? {
        guard let phrase = mnemonic() else { return nil }
        return try TronKeys(mnemonic: phrase)
    }

    static func erase() { Keychain.delete(account) }
}

/// 6-digit app PIN, stored as a salted SHA-256 hash.
enum PinStore {
    private static let account = "security.pin.v2"
    static let length = 6

    static var isSet: Bool { Keychain.get(account) != nil }

    static func set(_ pin: String) throws {
        var salt = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt)
        try Keychain.set(Hex.encode(salt) + ":" + hash(pin, salt: salt), for: account)
    }

    static func verify(_ pin: String) -> Bool {
        guard let stored = Keychain.get(account) else { return false }
        let parts = stored.split(separator: ":").map(String.init)
        guard parts.count == 2, let salt = Hex.decode(parts[0]) else { return false }
        return hash(pin, salt: salt) == parts[1]
    }

    static func erase() { Keychain.delete(account) }

    private static func hash(_ pin: String, salt: [UInt8]) -> String {
        Hex.encode(Array(SHA256.hash(data: Data(salt + Array(pin.utf8)))))
    }
}

enum Biometrics {
    enum Kind { case faceID, touchID, opticID, none }

    private static let enabledAccount = "security.biometric.enabled"

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
        case .none: String(localized: "Biometrics")
        }
    }

    static var symbol: String {
        switch kind {
        case .touchID: "touchid"
        case .opticID: "opticid"
        default: "faceid"
        }
    }

    static var isEnabled: Bool {
        get { kind != .none && Keychain.get(enabledAccount) == "1" }
        set {
            if newValue { try? Keychain.set("1", for: enabledAccount) } else { Keychain.delete(enabledAccount) }
        }
    }

    /// Biometrics only (the app PIN is the fallback, shown by our own UI).
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use PIN"
        return (try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)) ?? false
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
