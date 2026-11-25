import Foundation

/// Market data from CoinGecko's free public API (no key).
/// Requests name only the coins, never the wallet's address: the price
/// source learns nothing about the user. Prices are decoration: when this
/// fails the app simply hides them and the wallet keeps working.
struct PriceClient: Sendable {
    let session: URLSession = .shared

    private static let base = URL(string: "https://api.coingecko.com/api/v3/")!

    enum Failure: Error { case rateLimited, badResponse }

    /// Price, changes, 7-day sparkline and market stats for every known coin.
    func markets() async throws -> [TokenKind: MarketQuote] {
        let ids = TokenKind.allCases.map(\.coingeckoID).joined(separator: ",")
        let data = try await get("coins/markets", [
            "vs_currency": "usd", "ids": ids, "sparkline": "true", "price_change_percentage": "24h,7d",
        ])
        return try MarketParser.quotes(from: data)
    }

    /// Price history for the coin screen's chart.
    func chart(for token: TokenKind, range: PriceRange) async throws -> [PricePoint] {
        let data = try await get("coins/\(token.coingeckoID)/market_chart", [
            "vs_currency": "usd", "days": String(range.days),
        ])
        return try MarketParser.chart(from: data)
    }

    private func get(_ path: String, _ query: [String: String]) async throws -> Data {
        var components = URLComponents(url: Self.base.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: return data
        case 429: throw Failure.rateLimited
        default: throw Failure.badResponse
        }
    }
}
