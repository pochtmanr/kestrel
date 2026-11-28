import CommonCrypto
import CryptoKit
import Foundation

/// BIP-39 recovery phrases (English wordlist).
enum Mnemonic {
    enum Failure: Error { case randomnessUnavailable, wordlistMissing, derivation }

    static let wordlist: [String] = {
        guard let url = Bundle.main.url(forResource: "bip39-english", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return text.split(whereSeparator: \.isNewline).map(String.init)
    }()

    private static let wordIndex: [String: Int] = {
        var map = [String: Int]()
        for (i, word) in wordlist.enumerated() { map[word] = i }
        return map
    }()

    /// 128 bits of entropy → 12 words.
    static func generate() throws -> String {
        guard wordlist.count == 2048 else { throw Failure.wordlistMissing }
        var entropy = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, entropy.count, &entropy) == errSecSuccess else {
            throw Failure.randomnessUnavailable
        }
        defer { entropy.resetBytes() }
        return words(for: entropy).joined(separator: " ")
    }

    static func normalize(_ phrase: String) -> String {
        phrase.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func isValid(_ phrase: String) -> Bool {
        let words = normalize(phrase).split(separator: " ").map(String.init)
        guard [12, 15, 18, 21, 24].contains(words.count) else { return false }
        var bits = [Bool]()
        for word in words {
            guard let index = wordIndex[word] else { return false }
            for shift in (0 ..< 11).reversed() { bits.append((index >> shift) & 1 == 1) }
        }
        let checksumLength = bits.count / 33
        let entropyBits = bits.prefix(bits.count - checksumLength)
        var entropy = [UInt8]()
        for start in stride(from: 0, to: entropyBits.count, by: 8) {
            var byte: UInt8 = 0
            for bit in entropyBits[start ..< start + 8] { byte = (byte << 1) | (bit ? 1 : 0) }
            entropy.append(byte)
        }
        return words == Self.words(for: entropy)
    }

    /// PBKDF2-HMAC-SHA512, 2048 rounds, salt "mnemonic" (no passphrase).
    /// Throws rather than hand back a zeroed seed, which would be a wallet anyone can derive.
    static func seed(from phrase: String) throws -> [UInt8] {
        let password = Array(normalize(phrase).decomposedStringWithCompatibilityMapping.utf8)
        let salt = Array("mnemonic".utf8)
        var seed = [UInt8](repeating: 0, count: 64)
        let status = password.withUnsafeBufferPointer { pw in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                UnsafeRawPointer(pw.baseAddress!).assumingMemoryBound(to: CChar.self), pw.count,
                salt, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512), 2048,
                &seed, seed.count
            )
        }
        guard status == kCCSuccess, !password.isEmpty else { throw Failure.derivation }
        return seed
    }

    private static func words(for entropy: [UInt8]) -> [String] {
        let hash = Array(SHA256.hash(data: Data(entropy)))
        let checksumLength = entropy.count * 8 / 32
        var bits = [Bool]()
        for byte in entropy { for shift in (0 ..< 8).reversed() { bits.append((byte >> shift) & 1 == 1) } }
        for i in 0 ..< checksumLength { bits.append((hash[i / 8] >> (7 - UInt8(i % 8))) & 1 == 1) }
        return stride(from: 0, to: bits.count, by: 11).map { start in
            let index = bits[start ..< start + 11].reduce(0) { ($0 << 1) | ($1 ? 1 : 0) }
            return wordlist[index]
        }
    }
}

extension Array where Element == UInt8 {
    /// Best-effort wipe of secret material held in a local buffer.
    mutating func resetBytes() {
        for i in indices { self[i] = 0 }
    }
}
