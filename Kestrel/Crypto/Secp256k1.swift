import Foundation
import libsecp256k1

/// Thin wrapper over libsecp256k1 (the Bitcoin Core library). Only the calls
/// the wallet needs: key checks, public keys, BIP32 tweaks, recoverable signing.
enum Secp256k1 {
    enum Failure: Error { case invalidKey, signingFailed }

    // SECP256K1_CONTEXT_NONE / SECP256K1_EC_* flag values from secp256k1.h.
    private static let contextNone: UInt32 = 1
    private static let compressedFlag: UInt32 = (1 << 1) | (1 << 8)
    private static let uncompressedFlag: UInt32 = 1 << 1

    nonisolated(unsafe) private static let context: OpaquePointer = {
        let ctx = secp256k1_context_create(contextNone)!
        var seed = [UInt8](repeating: 0, count: 32)
        // Side-channel hardening. Without randomness the context is still correct,
        // so it is used as it is rather than "randomised" with zeros.
        if SecRandomCopyBytes(kSecRandomDefault, seed.count, &seed) == errSecSuccess {
            _ = secp256k1_context_randomize(ctx, seed)
        }
        return ctx
    }()

    static func isValidPrivateKey(_ key: [UInt8]) -> Bool {
        key.count == 32 && secp256k1_ec_seckey_verify(context, key) == 1
    }

    static func publicKey(of privateKey: [UInt8], compressed: Bool) throws -> [UInt8] {
        guard isValidPrivateKey(privateKey) else { throw Failure.invalidKey }
        var pubkey = secp256k1_pubkey()
        guard secp256k1_ec_pubkey_create(context, &pubkey, privateKey) == 1 else { throw Failure.invalidKey }
        var output = [UInt8](repeating: 0, count: compressed ? 33 : 65)
        var length = output.count
        secp256k1_ec_pubkey_serialize(context, &output, &length, &pubkey, compressed ? compressedFlag : uncompressedFlag)
        return Array(output.prefix(length))
    }

    /// (key + tweak) mod n — the BIP32 child private key step.
    static func addTweak(_ tweak: [UInt8], to privateKey: [UInt8]) throws -> [UInt8] {
        var key = privateKey
        guard tweak.count == 32, secp256k1_ec_seckey_tweak_add(context, &key, tweak) == 1 else {
            throw Failure.invalidKey
        }
        return key
    }

    /// Recoverable ECDSA over a 32-byte digest (no extra hashing), RFC 6979
    /// nonce, low-S. Returns r ‖ s ‖ v — the 65-byte layout TRON expects.
    static func signRecoverable(digest: [UInt8], privateKey: [UInt8]) throws -> [UInt8] {
        guard digest.count == 32, isValidPrivateKey(privateKey) else { throw Failure.invalidKey }
        var signature = secp256k1_ecdsa_recoverable_signature()
        guard secp256k1_ecdsa_sign_recoverable(context, &signature, digest, privateKey, nil, nil) == 1 else {
            throw Failure.signingFailed
        }
        var compact = [UInt8](repeating: 0, count: 64)
        var recoveryId: Int32 = 0
        secp256k1_ecdsa_recoverable_signature_serialize_compact(context, &compact, &recoveryId, &signature)
        return compact + [UInt8(recoveryId)]
    }
}
