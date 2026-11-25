import CryptoKit
import Foundation

enum Hex {
    static func encode(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func decode(_ string: String) -> [UInt8]? {
        var hex = string
        if hex.hasPrefix("0x") { hex.removeFirst(2) }
        guard hex.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index ..< next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}

enum Base58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)
    private static let indexes: [UInt8: Int] = {
        var map = [UInt8: Int]()
        for (i, c) in alphabet.enumerated() { map[c] = i }
        return map
    }()

    static func encode(_ bytes: [UInt8]) -> String {
        let zeros = bytes.prefix { $0 == 0 }.count
        var digits = [UInt8]() // base58 digits, little-endian
        for byte in bytes {
            var carry = Int(byte)
            for i in 0 ..< digits.count {
                carry += Int(digits[i]) << 8
                digits[i] = UInt8(carry % 58)
                carry /= 58
            }
            while carry > 0 {
                digits.append(UInt8(carry % 58))
                carry /= 58
            }
        }
        let leading = [UInt8](repeating: alphabet[0], count: zeros)
        return String(decoding: leading + digits.reversed().map { alphabet[Int($0)] }, as: UTF8.self)
    }

    static func decode(_ string: String) -> [UInt8]? {
        let chars = Array(string.utf8)
        let zeros = chars.prefix { $0 == alphabet[0] }.count
        var bytes = [UInt8]() // little-endian
        for c in chars {
            guard let value = indexes[c] else { return nil }
            var carry = value
            for i in 0 ..< bytes.count {
                carry += Int(bytes[i]) * 58
                bytes[i] = UInt8(carry & 0xFF)
                carry >>= 8
            }
            while carry > 0 {
                bytes.append(UInt8(carry & 0xFF))
                carry >>= 8
            }
        }
        return [UInt8](repeating: 0, count: zeros) + bytes.reversed()
    }

    /// Base58 with a 4-byte double-SHA256 checksum appended (TRON addresses).
    static func encodeCheck(_ payload: [UInt8]) -> String {
        encode(payload + checksum(payload))
    }

    static func decodeCheck(_ string: String) -> [UInt8]? {
        guard let full = decode(string), full.count > 4 else { return nil }
        let payload = Array(full.dropLast(4))
        guard Array(full.suffix(4)) == checksum(payload) else { return nil }
        return payload
    }

    private static func checksum(_ payload: [UInt8]) -> [UInt8] {
        Array(SHA256.hash(data: Data(SHA256.hash(data: Data(payload)))).prefix(4))
    }
}
