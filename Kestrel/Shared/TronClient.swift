import Foundation

/// USDT (TRC20) amounts: 6 decimals, held as integer base units.
enum USDT {
    static let contract = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"
    static let decimals = 6

    /// "1.5" → 1_500_000. nil for malformed input or more than 6 decimals.
    static func units(from text: String) -> UInt64? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard (1 ... 2).contains(parts.count), parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
        let whole = parts[0].isEmpty ? "0" : String(parts[0])
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard fraction.count <= decimals, let w = UInt64(whole),
              let f = UInt64(fraction.padding(toLength: decimals, withPad: "0", startingAt: 0))
        else { return nil }
        let (scaled, overflow) = w.multipliedReportingOverflow(by: 1_000_000)
        let (total, carried) = scaled.addingReportingOverflow(f)
        return overflow || carried ? nil : total
    }

    /// 1_234_567_890 → "1,234.56" (truncated, never rounded up).
    static func format(units: UInt64, fractionDigits: Int = 2) -> String {
        let whole = units / 1_000_000
        let fraction = String(format: "%06llu", units % 1_000_000).prefix(fractionDigits)
        let digits = Array(String(whole))
        var grouped = ""
        for (i, digit) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { grouped.append(",") }
            grouped.append(digit)
        }
        return fractionDigits > 0 ? "\(grouped).\(fraction)" : grouped
    }
}

/// TRX amounts in sun (1 TRX = 1_000_000 sun).
enum TRX {
    /// The most a USDT transfer burns when the wallet has no staked energy: about 7 TRX to an
    /// address that already holds USDT, 13–14 to one that doesn't (energy at 100 sun). Used where
    /// there's no recipient to estimate for; Send asks the network (`FeeEstimate`).
    static let minimumForTransferSun: Int64 = 14_000_000

    static func format(sun: Int64) -> String {
        USDT.format(units: UInt64(max(sun, 0)))
    }
}

struct TokenTransfer: Identifiable, Hashable, Sendable, Codable {
    let id: String // transaction id
    let date: Date
    let from: String
    let to: String
    let units: UInt64
}

/// Reads and writes the TRON network directly through TronGrid's public
/// HTTP API. No app server is involved: the wallet is fully self-custody.
struct TronClient: Sendable {
    enum Failure: LocalizedError {
        case http(Int)
        /// HTTP 429: TronGrid's request quota for this key or IP is used up for now.
        case rateLimited
        case badResponse
        case rejected(String)

        var errorDescription: String? {
            switch self {
            case .http(let code): tr("The TRON network didn't respond (HTTP \(code)). Try again.")
            case .rateLimited: tr("The TRON network is busy. Retrying shortly.")
            case .badResponse: tr("Unexpected response from the TRON network.")
            case .rejected(let message): message
            }
        }
    }

    static let base = URL(string: "https://api.trongrid.io")!

    /// TronGrid project key: lifts the low keyless rate limit (HTTP 429).
    /// A client key by design, like the Supabase anon key: it ships inside the
    /// app and only identifies the project for quota, it grants no access.
    static let apiKey = "4a694370-15a4-41e6-94d4-5f976b5e33ae"

    let session: URLSession = .shared

    // MARK: Reads

    /// TRC20 balance via the contract's balanceOf view call. Works for
    /// unactivated addresses too (TRC20 balances live in contract storage).
    func usdtBalance(of address: String) async throws -> UInt64 {
        guard let owner = TronAddress.hex21(address), let param = TronAddress.abiWord(address),
              let contract = TronAddress.hex21(USDT.contract) else { throw Failure.badResponse }
        let body = try await post("wallet/triggerconstantcontract", [
            "owner_address": owner,
            "contract_address": contract,
            "function_selector": "balanceOf(address)",
            "parameter": param,
            "visible": false,
        ])
        guard let results = body["constant_result"] as? [String], let word = results.first else { return 0 }
        // uint256 → UInt64: a real USDT balance never needs more than 64 bits.
        let trimmed = word.drop { $0 == "0" }
        guard trimmed.count <= 16 else { throw Failure.badResponse }
        return trimmed.isEmpty ? 0 : UInt64(trimmed, radix: 16) ?? 0
    }

    func trxBalance(of address: String) async throws -> Int64 {
        let body = try await get("v1/accounts/\(address)")
        let account = (body["data"] as? [[String: Any]])?.first
        return (account?["balance"] as? NSNumber)?.int64Value ?? 0
    }

    func usdtHistory(of address: String, limit: Int = 20) async throws -> [TokenTransfer] {
        let body = try await get(
            "v1/accounts/\(address)/transactions/trc20",
            query: ["contract_address": USDT.contract, "limit": String(limit), "only_confirmed": "true"]
        )
        return Self.parseTransfers(body).transfers
    }

    /// One page of USDT transfers, newest first. Pass the returned `next` back
    /// as `fingerprint` to continue; it is nil on the last page.
    func usdtHistoryPage(
        of address: String, minTimestamp: Date? = nil, maxTimestamp: Date? = nil,
        fingerprint: String? = nil, limit: Int = 200
    ) async throws -> (transfers: [TokenTransfer], next: String?) {
        var query = [
            "contract_address": USDT.contract, "limit": String(limit), "only_confirmed": "true",
            "order_by": "block_timestamp,desc",
        ]
        Self.addWindow(to: &query, min: minTimestamp, max: maxTimestamp, fingerprint: fingerprint)
        return Self.parseTransfers(try await get("v1/accounts/\(address)/transactions/trc20", query: query))
    }

    /// Network fees (sun, keyed by txID) for transactions this address paid
    /// for. `only_from` makes TronGrid return just those, so incoming transfers
    /// (paid by the sender) never show up as our cost.
    func transactionFees(
        of address: String, minTimestamp: Date? = nil, maxTimestamp: Date? = nil,
        fingerprint: String? = nil, limit: Int = 200
    ) async throws -> (fees: [String: Int64], next: String?) {
        var query = [
            "limit": String(limit), "only_confirmed": "true", "only_from": "true",
            "order_by": "block_timestamp,desc",
        ]
        Self.addWindow(to: &query, min: minTimestamp, max: maxTimestamp, fingerprint: fingerprint)
        return Self.parseFees(try await get("v1/accounts/\(address)/transactions", query: query))
    }

    private static func addWindow(to query: inout [String: String], min: Date?, max: Date?, fingerprint: String?) {
        if let min { query["min_timestamp"] = String(Int64((min.timeIntervalSince1970 * 1000).rounded())) }
        if let max { query["max_timestamp"] = String(Int64((max.timeIntervalSince1970 * 1000).rounded())) }
        if let fingerprint { query["fingerprint"] = fingerprint }
    }

    /// TronGrid's next-page token; absent (or empty) on the last page.
    private static func nextFingerprint(_ body: [String: Any]) -> String? {
        guard let token = (body["meta"] as? [String: Any])?["fingerprint"] as? String, !token.isEmpty else { return nil }
        return token
    }

    /// Rows of `v1/accounts/{a}/transactions/trc20`. Malformed and zero-value
    /// rows are skipped rather than failing the page.
    static func parseTransfers(_ body: [String: Any]) -> (transfers: [TokenTransfer], next: String?) {
        let rows = body["data"] as? [[String: Any]] ?? []
        let transfers: [TokenTransfer] = rows.compactMap { row in
            guard let id = row["transaction_id"] as? String,
                  let ts = (row["block_timestamp"] as? NSNumber)?.doubleValue,
                  let from = row["from"] as? String, let to = row["to"] as? String,
                  let value = row["value"] as? String, let units = UInt64(value),
                  // A zero-value transfer moves nothing. Anyone can post one "from"
                  // any address, and scammers do, to plant a lookalike address in
                  // the history (address poisoning). It never belongs in a list.
                  units > 0
            else { return nil }
            return TokenTransfer(id: id, date: Date(timeIntervalSince1970: ts / 1000), from: from, to: to, units: units)
        }
        return (transfers, nextFingerprint(body))
    }

    /// Rows of `v1/accounts/{a}/transactions`. `ret[0].fee` is the total burnt;
    /// older or odd rows lack it, and then energy + bandwidth fees add up to it.
    static func parseFees(_ body: [String: Any]) -> (fees: [String: Int64], next: String?) {
        let rows = body["data"] as? [[String: Any]] ?? []
        var fees: [String: Int64] = [:]
        for row in rows {
            guard let id = row["txID"] as? String else { continue }
            if let fee = ((row["ret"] as? [[String: Any]])?.first?["fee"] as? NSNumber)?.int64Value {
                fees[id] = fee
            } else {
                let energy = (row["energy_fee"] as? NSNumber)?.int64Value ?? 0
                let net = (row["net_fee"] as? NSNumber)?.int64Value ?? 0
                fees[id] = energy + net
            }
        }
        return (fees, nextFingerprint(body))
    }

    // MARK: HTTP

    private func get(_ path: String, query: [String: String] = [:]) async throws -> [String: Any] {
        var components = URLComponents(url: Self.base.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request)
    }

    func post(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: Self.base.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> [String: Any] {
        var request = request
        request.timeoutInterval = 20
        request.setValue(Self.apiKey, forHTTPHeaderField: Self.apiKeyHeader)
        var (data, status) = try await perform(request)
        // The key ships in the app, so its quota can be used up by anyone, and
        // TronGrid can suspend it. Neither may stop the wallet: a request the
        // key was refused for goes again without it, on the keyless per-IP
        // allowance. A refused request was never processed, so this can't send twice.
        if Self.keyWasRefused(status) {
            request.setValue(nil, forHTTPHeaderField: Self.apiKeyHeader)
            (data, status) = try await perform(request)
        }
        if status == 429 { throw Failure.rateLimited }
        guard (200 ..< 300).contains(status) else { throw Failure.http(status) }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.badResponse }
        return object
    }

    private static let apiKeyHeader = "TRON-PRO-API-KEY"

    /// 401 / 403: the key is unknown, suspended or not allowed this call. 429: its quota is spent.
    static func keyWasRefused(_ status: Int) -> Bool {
        status == 401 || status == 403 || status == 429
    }

    private func perform(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// TronGrid returns error messages hex-encoded.
    static func decodeMessage(_ body: [String: Any]) -> String? {
        let raw = ((body["result"] as? [String: Any])?["message"] as? String) ?? body["message"] as? String
        guard let raw else { return nil }
        if let bytes = Hex.decode(raw), let text = String(bytes: bytes, encoding: .utf8), !text.isEmpty { return text }
        return raw
    }
}
