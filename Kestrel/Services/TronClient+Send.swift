import Foundation

/// Signing and broadcasting — app only (the widget only reads balances).
extension TronClient {
    /// fee_limit for a TRC20 transfer: 100 TRX, comfortably above the real burn.
    static let feeLimitSun = 100_000_000

    /// Builds the TRC20 transfer on TronGrid, signs its id on the device,
    /// and broadcasts it. The private key never leaves this function.
    func sendUSDT(from keys: TronKeys, to recipient: String, units: UInt64) async throws -> String {
        guard let owner = TronAddress.hex21(keys.address), let contract = TronAddress.hex21(USDT.contract),
              let recipientWord = TronAddress.abiWord(recipient) else { throw Failure.rejected("Invalid address.") }
        let amountHex = String(units, radix: 16)
        let amountWord = String(repeating: "0", count: 64 - amountHex.count) + amountHex
        let built = try await post("wallet/triggersmartcontract", [
            "owner_address": owner,
            "contract_address": contract,
            "function_selector": "transfer(address,uint256)",
            "parameter": recipientWord + amountWord,
            "fee_limit": Self.feeLimitSun,
            "call_value": 0,
            "visible": false,
        ])
        guard let result = built["result"] as? [String: Any], result["result"] as? Bool == true else {
            throw Failure.rejected(Self.decodeMessage(built) ?? "The network couldn't build this transfer.")
        }
        guard var transaction = built["transaction"] as? [String: Any],
              let txID = transaction["txID"] as? String, transaction["raw_data_hex"] is String
        else { throw Failure.badResponse }

        transaction["signature"] = [try keys.sign(transactionID: txID)]
        let broadcast = try await post("wallet/broadcasttransaction", transaction)
        guard broadcast["result"] as? Bool == true else {
            throw Failure.rejected(Self.decodeMessage(broadcast) ?? "The network rejected this transfer.")
        }
        return txID
    }
}
