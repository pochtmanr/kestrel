import CryptoKit
import Foundation

/// BIP-32 derivation at TRON's path m/44'/195'/0'/0/0, plus TRON address
/// encoding. Same derivation as the previous app, so existing recovery
/// phrases restore to the same address.
struct TronKeys {
    let privateKey: [UInt8]
    let address: String

    static let derivationPath: [UInt32] = [44 | hardened, 195 | hardened, 0 | hardened, 0, 0]
    private static let hardened: UInt32 = 0x8000_0000

    init(mnemonic: String) throws {
        var seed = try Mnemonic.seed(from: mnemonic)
        defer { seed.resetBytes() }

        let master = Array(HMAC<SHA512>.authenticationCode(for: Data(seed), using: SymmetricKey(data: Data("Bitcoin seed".utf8))))
        var key = Array(master[0 ..< 32])
        var chainCode = Array(master[32 ..< 64])
        guard Secp256k1.isValidPrivateKey(key) else { throw Secp256k1.Failure.invalidKey }

        for index in Self.derivationPath {
            var data: [UInt8]
            if index & Self.hardened != 0 {
                data = [0] + key
            } else {
                data = try Secp256k1.publicKey(of: key, compressed: true)
            }
            data += withUnsafeBytes(of: index.bigEndian, Array.init)
            let digest = Array(HMAC<SHA512>.authenticationCode(for: Data(data), using: SymmetricKey(data: Data(chainCode))))
            key = try Secp256k1.addTweak(Array(digest[0 ..< 32]), to: key)
            chainCode = Array(digest[32 ..< 64])
        }

        privateKey = key
        address = try Self.address(forPrivateKey: key)
    }

    static func address(forPrivateKey key: [UInt8]) throws -> String {
        let publicKey = try Secp256k1.publicKey(of: key, compressed: false) // 0x04 ‖ X ‖ Y
        let hash = Keccak256.hash(Array(publicKey.dropFirst()))
        return Base58.encodeCheck([TronAddress.prefix] + hash.suffix(20))
    }

    func sign(transactionID: String) throws -> String {
        guard let digest = Hex.decode(transactionID), digest.count == 32 else { throw Secp256k1.Failure.signingFailed }
        return Hex.encode(try Secp256k1.signRecoverable(digest: digest, privateKey: privateKey))
    }
}
