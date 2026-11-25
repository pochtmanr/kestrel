import Foundation

enum TronAddress {
    /// Every TRON mainnet address payload starts with this byte.
    static let prefix: UInt8 = 0x41

    /// A real TRON mainnet address: Base58Check, 21 bytes, 0x41 prefix.
    /// Stricter than a regex — a typo fails the checksum.
    static func isValid(_ address: String) -> Bool {
        guard address.hasPrefix("T"), let payload = Base58.decodeCheck(address) else { return false }
        return payload.count == 21 && payload[0] == prefix
    }

    /// 21-byte hex (0x41 ‖ 20 bytes) used in TronGrid request bodies.
    static func hex21(_ address: String) -> String? {
        guard isValid(address), let payload = Base58.decodeCheck(address) else { return nil }
        return Hex.encode(payload)
    }

    /// 20-byte hex left-padded to 32 bytes, for ABI-encoded contract params.
    static func abiWord(_ address: String) -> String? {
        guard let hex = hex21(address) else { return nil }
        return String(repeating: "0", count: 24) + hex.dropFirst(2)
    }
}
