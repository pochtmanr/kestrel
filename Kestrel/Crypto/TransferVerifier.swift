import CryptoKit
import Foundation

/// Checks an unsigned transaction a node built for us before the device signs it.
///
/// TronGrid assembles the transfer, so without this the wallet would sign whatever
/// came back: a hostile or compromised node could swap in a different recipient, a
/// larger amount or an `approve`. The signature covers only `SHA256(raw_data)`, so
/// this decodes those exact bytes and accepts one shape only: a single
/// `transfer(address,uint256)` call on the USDT contract, from our address, to the
/// recipient and for the amount the user confirmed.
///
/// The decoder is deliberately strict: an unknown field, a repeated field or a wrong
/// wire type fails the check, so nothing we don't understand is ever signed.
enum TransferVerifier {
    enum Failure: Error, Equatable {
        case malformed
        case hashMismatch
        case unexpected(String)
    }

    /// `transfer(address,uint256)`.
    static let transferSelector = "a9059cbb"
    private static let triggerSmartContractType: UInt64 = 31
    private static let triggerSmartContractURL = "type.googleapis.com/protocol.TriggerSmartContract"
    /// TronGrid sets about a minute. A far-off expiry would let a node hold the
    /// signed transfer back and send it long after the user gave up on it.
    static let longestValidity: TimeInterval = 3600

    /// Returns the 32-byte digest to sign. Throws unless `rawDataHex` is exactly
    /// the transfer described by the other arguments.
    static func digest(
        rawDataHex: String, txID: String, owner: String, recipient: String, units: UInt64,
        feeLimitSun: UInt64, now: Date = .now
    ) throws -> [UInt8] {
        guard let raw = Hex.decode(rawDataHex), !raw.isEmpty else { throw Failure.malformed }
        let digest = Array(SHA256.hash(data: Data(raw)))
        guard let claimed = Hex.decode(txID), claimed == digest else { throw Failure.hashMismatch }

        guard let ownerBytes = TronAddress.hex21(owner).flatMap(Hex.decode),
              let contractBytes = TronAddress.hex21(USDT.contract).flatMap(Hex.decode),
              let recipientWord = TronAddress.abiWord(recipient).flatMap(Hex.decode),
              let selector = Hex.decode(transferSelector)
        else { throw Failure.malformed }

        // Transaction.raw: 1 ref_block_bytes, 3 ref_block_num, 4 ref_block_hash,
        // 8 expiration, 11 contract, 14 timestamp, 18 fee_limit. Anything else
        // (auths, a memo, scripts) is not part of a transfer we build.
        let transaction = try Message(raw, bytes: [1, 4, 11], varints: [3, 8, 14, 18])
        guard let wrapper = transaction.bytes[11] else { throw Failure.unexpected("contract") }
        guard transaction.varints[18] == feeLimitSun else { throw Failure.unexpected("fee_limit") }
        guard let expiration = transaction.varints[8] else { throw Failure.unexpected("expiration") }
        let latest = (now.timeIntervalSince1970 + longestValidity) * 1000
        guard Double(expiration) <= latest else { throw Failure.unexpected("expiration") }

        // Contract: 1 type, 2 parameter (Any), 5 Permission_id.
        let contract = try Message(wrapper, bytes: [2], varints: [1, 5])
        guard contract.varints[1] == triggerSmartContractType else { throw Failure.unexpected("type") }
        guard (contract.varints[5] ?? 0) == 0 else { throw Failure.unexpected("permission") }
        guard let anyBytes = contract.bytes[2] else { throw Failure.unexpected("parameter") }

        // google.protobuf.Any: 1 type_url, 2 value.
        let any = try Message(anyBytes, bytes: [1, 2], varints: [])
        guard any.bytes[1] == Array(triggerSmartContractURL.utf8) else { throw Failure.unexpected("type_url") }
        guard let callBytes = any.bytes[2] else { throw Failure.unexpected("value") }

        // TriggerSmartContract: 1 owner_address, 2 contract_address, 3 call_value,
        // 4 data, 5 call_token_value, 6 token_id.
        let call = try Message(callBytes, bytes: [1, 2, 4], varints: [3, 5, 6])
        guard call.bytes[1] == ownerBytes else { throw Failure.unexpected("owner_address") }
        guard call.bytes[2] == contractBytes else { throw Failure.unexpected("contract_address") }
        guard (call.varints[3] ?? 0) == 0, (call.varints[5] ?? 0) == 0, (call.varints[6] ?? 0) == 0 else {
            throw Failure.unexpected("call_value")
        }
        let amountWord = [UInt8](repeating: 0, count: 24) + withUnsafeBytes(of: units.bigEndian, Array.init)
        guard call.bytes[4] == selector + recipientWord + amountWord else { throw Failure.unexpected("data") }

        return digest
    }

    /// One decoded protobuf message whose every field is expected and appears once.
    private struct Message {
        private(set) var bytes: [UInt64: [UInt8]] = [:]
        private(set) var varints: [UInt64: UInt64] = [:]

        init(_ data: [UInt8], bytes bytesFields: Set<UInt64>, varints varintFields: Set<UInt64>) throws {
            var reader = Reader(data)
            while !reader.isAtEnd {
                let key = try reader.varint()
                let field = key >> 3
                switch key & 7 {
                case 0:
                    guard varintFields.contains(field), varints[field] == nil else { throw Failure.malformed }
                    varints[field] = try reader.varint()
                case 2:
                    guard bytesFields.contains(field), bytes[field] == nil else { throw Failure.malformed }
                    bytes[field] = try reader.lengthDelimited()
                default:
                    throw Failure.malformed
                }
            }
        }
    }

    private struct Reader {
        private let data: [UInt8]
        private var offset = 0

        init(_ data: [UInt8]) { self.data = data }

        var isAtEnd: Bool { offset == data.count }

        mutating func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for shift in stride(from: 0, to: 70, by: 7) {
                guard offset < data.count else { throw Failure.malformed }
                let byte = data[offset]
                offset += 1
                // The tenth byte can only carry the top bit of a 64-bit value.
                if shift == 63, byte > 1 { throw Failure.malformed }
                value |= UInt64(byte & 0x7F) << UInt64(shift)
                if byte & 0x80 == 0 { return value }
            }
            throw Failure.malformed
        }

        mutating func lengthDelimited() throws -> [UInt8] {
            let length = try varint()
            guard length <= UInt64(data.count - offset) else { throw Failure.malformed }
            defer { offset += Int(length) }
            return Array(data[offset ..< offset + Int(length)])
        }
    }
}
