import CryptoKit
import XCTest
@testable import Kestrel

/// The check that stands between a node-built transaction and the signature.
final class TransferVerifierTests: XCTestCase {
    private let owner = "TV2QjYfd8Js2JhDfqKzZMLBscYtBkxU9ek"
    private let recipient = "TXJgMdjVX5dKiQaUi9QobwNxtSQaFqccvd"
    private let units: UInt64 = 12_500_000
    private let feeLimit: UInt64 = 100_000_000

    /// A real answer from TronGrid's `wallet/triggersmartcontract` for the
    /// transfer above (mainnet, unsigned, never broadcast).
    private let realRaw = "0a02c1ef2208f5d46263e21aa9924098f4ba88a2345aae01081f12a9010a31747970652e676f6f676c65617069732e636f6d2f70726f746f636f6c2e54726967676572536d617274436f6e747261637412740a1541d1056e7e5166365e87ff45de619facd944f0fb4b121541a614f803b6fd780986a42c78ec9c7f77e6ded13c2244a9059cbb000000000000000000000000ea09611b57e89d67fbb33a516eb90508ca95a3e50000000000000000000000000000000000000000000000000000000000bebc2070edb3b788a234900180c2d72f"
    private let realTxID = "d387015cf172a394ff4a95eab445319474625df56f9dd372c8a28e2b969b0878"
    /// Just before that transaction's own timestamp (its expiry is a minute later).
    private let then = Date(timeIntervalSince1970: 1_795_850_885)

    private func verify(
        _ raw: String, txID: String? = nil, recipient: String? = nil, units: UInt64? = nil, now: Date? = nil
    ) throws -> [UInt8] {
        try TransferVerifier.digest(
            rawDataHex: raw, txID: txID ?? Self.id(of: raw), owner: owner, recipient: recipient ?? self.recipient,
            units: units ?? self.units, feeLimitSun: feeLimit, now: now ?? then
        )
    }

    private static func id(of raw: String) -> String {
        Hex.encode(Array(SHA256.hash(data: Data(Hex.decode(raw) ?? []))))
    }

    private func assertRejects(_ raw: String, _ message: String = "", line: UInt = #line) {
        XCTAssertThrowsError(try verify(raw), message, line: line)
    }

    // MARK: The real transaction

    func testAcceptsTheTransferTronGridBuilt() throws {
        XCTAssertEqual(Hex.encode(try verify(realRaw, txID: realTxID)), realTxID)
        XCTAssertEqual(Hex.encode(try verify(realRaw, txID: realTxID.uppercased())), realTxID)
    }

    func testBuilderReproducesTheRealBytes() {
        XCTAssertEqual(build(), realRaw, "the tampering tests below rely on this encoder")
    }

    func testRejectsATransactionIDThatIsNotTheHash() {
        let other = String(repeating: "ab", count: 32)
        XCTAssertThrowsError(try verify(realRaw, txID: other)) {
            XCTAssertEqual($0 as? TransferVerifier.Failure, .hashMismatch)
        }
        XCTAssertThrowsError(try verify(realRaw, txID: "zz"))
    }

    func testRejectsWhenTheUserConfirmedSomethingElse() {
        XCTAssertThrowsError(try verify(realRaw, recipient: owner))
        XCTAssertThrowsError(try verify(realRaw, units: units + 1))
        XCTAssertThrowsError(try verify(realRaw, units: 0))
    }

    // MARK: What a hostile node could swap in

    func testRejectsAnotherRecipientOrAmount() {
        assertRejects(build(to: owner))
        assertRejects(build(units: 999_000_000))
    }

    func testRejectsAnApproveCall() {
        // approve(address,uint256) with the same arguments.
        assertRejects(build(selector: "095ea7b3"))
    }

    func testRejectsAnotherContractOrOwner() {
        assertRejects(build(contract: recipient))
        assertRejects(build(from: recipient))
    }

    func testRejectsAnotherContractType() {
        // 1 = TransferContract (plain TRX).
        assertRejects(build(type: 1))
        assertRejects(build(typeURL: "type.googleapis.com/protocol.TransferContract"))
    }

    func testRejectsTRXSentAlongWithTheCall() {
        assertRejects(build(callExtra: Proto.varint(3, 5_000_000)), "call_value")
        assertRejects(build(callExtra: Proto.varint(5, 1)), "call_token_value")
    }

    func testRejectsAnotherFeeLimit() {
        assertRejects(build(feeLimit: 5_000_000_000))
        assertRejects(build(feeLimit: nil))
    }

    func testRejectsAFarExpiry() {
        let tomorrow = UInt64((then.timeIntervalSince1970 + 86_400) * 1000)
        assertRejects(build(expiration: tomorrow))
        assertRejects(build(expiration: nil))
    }

    func testRejectsASecondContract() {
        assertRejects(build(rawExtra: Proto.bytes(11, Hex.decode(contract(to: owner))!)))
    }

    func testRejectsFieldsItDoesNotKnow() {
        assertRejects(build(rawExtra: Proto.bytes(10, Array("memo".utf8))), "data")
        assertRejects(build(rawExtra: Proto.bytes(9, [1])), "auths")
        assertRejects(build(rawExtra: Proto.varint(99, 1)))
        assertRejects(build(contractExtra: Proto.varint(5, 2)), "Permission_id")
        // A repeated field: a second `data` that a laxer decoder would let win.
        assertRejects(build(callExtra: Proto.bytes(4, [0xA9])))
    }

    func testRejectsTruncatedOrEmptyBytes() {
        assertRejects("")
        assertRejects("zz")
        assertRejects(String(realRaw.dropLast(2)))
        assertRejects(String(realRaw.dropLast(40)))
        assertRejects(realRaw + "ff")
        // A varint that never ends.
        assertRejects("08" + String(repeating: "ff", count: 11))
    }

    // MARK: A small protobuf encoder for the cases above

    private enum Proto {
        static func varint(_ value: UInt64) -> [UInt8] {
            var value = value, out = [UInt8]()
            repeat {
                let byte = UInt8(value & 0x7F)
                value >>= 7
                out.append(value == 0 ? byte : byte | 0x80)
            } while value != 0
            return out
        }

        static func varint(_ field: UInt64, _ value: UInt64) -> [UInt8] { varint(field << 3) + varint(value) }
        static func bytes(_ field: UInt64, _ value: [UInt8]) -> [UInt8] {
            varint(field << 3 | 2) + varint(UInt64(value.count)) + value
        }
    }

    private func contract(
        from: String? = nil, to: String? = nil, contract: String = USDT.contract, units: UInt64? = nil,
        selector: String = "a9059cbb", type: UInt64 = 31,
        typeURL: String = "type.googleapis.com/protocol.TriggerSmartContract",
        callExtra: [UInt8] = [], contractExtra: [UInt8] = []
    ) -> String {
        let amount = String(units ?? self.units, radix: 16)
        let data = selector + TronAddress.abiWord(to ?? recipient)! + String(repeating: "0", count: 64 - amount.count) + amount
        let call = Proto.bytes(1, Hex.decode(TronAddress.hex21(from ?? owner)!)!)
            + Proto.bytes(2, Hex.decode(TronAddress.hex21(contract)!)!)
            + Proto.bytes(4, Hex.decode(data)!) + callExtra
        let any = Proto.bytes(1, Array(typeURL.utf8)) + Proto.bytes(2, call)
        return Hex.encode(Proto.varint(1, type) + Proto.bytes(2, any) + contractExtra)
    }

    private func build(
        from: String? = nil, to: String? = nil, contract: String = USDT.contract, units: UInt64? = nil,
        selector: String = "a9059cbb", type: UInt64 = 31,
        typeURL: String = "type.googleapis.com/protocol.TriggerSmartContract",
        feeLimit: UInt64? = 100_000_000, expiration: UInt64? = 1_795_850_943_000,
        callExtra: [UInt8] = [], contractExtra: [UInt8] = [], rawExtra: [UInt8] = []
    ) -> String {
        let inner = self.contract(
            from: from, to: to, contract: contract, units: units, selector: selector, type: type,
            typeURL: typeURL, callExtra: callExtra, contractExtra: contractExtra
        )
        var raw = Proto.bytes(1, [0xC1, 0xEF]) + Proto.bytes(4, Hex.decode("f5d46263e21aa992")!)
        if let expiration { raw += Proto.varint(8, expiration) }
        raw += Proto.bytes(11, Hex.decode(inner)!) + Proto.varint(14, 1_795_850_885_613)
        if let feeLimit { raw += Proto.varint(18, feeLimit) }
        return Hex.encode(raw + rawExtra)
    }
}
