import Foundation

/// A token's market price in US dollars.
struct TokenPrice: Equatable, Sendable {
    let usd: Double
    /// Percent change over the last 24 hours, e.g. -1.8.
    let change24h: Double?
}

/// Market prices from CoinGecko's free public endpoint (no key).
/// The request names only the coins, never the wallet's address: the price
/// source learns nothing about the user. Prices are decoration: when this
/// fails the app simply hides them and the wallet keeps working.
struct PriceClient: Sendable {
    let session: URLSession = .shared

    private static let endpoint = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=tether,tron&vs_currencies=usd&include_24hr_change=true")!

    func prices() async throws -> [TokenKind: TokenPrice] {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode([String: Quote].self, from: data)
        var result: [TokenKind: TokenPrice] = [:]
        if let usdt = decoded["tether"] { result[.usdt] = TokenPrice(usd: usdt.usd, change24h: usdt.usd_24h_change) }
        if let trx = decoded["tron"] { result[.trx] = TokenPrice(usd: trx.usd, change24h: trx.usd_24h_change) }
        return result
    }

    private struct Quote: Decodable {
        let usd: Double
        let usd_24h_change: Double?
    }
}
