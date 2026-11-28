import Foundation

/// Market data from CoinGecko's free public API (no key), plus Kraken's
/// public candles for the five-year chart, which CoinGecko's free tier
/// doesn't reach. Requests name only the coins, never the wallet's address:
/// the price sources learn nothing about the user. Prices are decoration: when this
/// fails the app simply hides them and the wallet keeps working.
struct PriceClient: Sendable {
    let session: URLSession = .shared

    private static let coingecko = URL(string: "https://api.coingecko.com/api/v3/")!
    private static let kraken = URL(string: "https://api.kraken.com/0/public/")!

    enum Failure: Error { case rateLimited, badResponse }

    /// Price, changes, 7-day sparkline and market stats for every known coin.
    func markets() async throws -> [TokenKind: MarketQuote] {
        let ids = TokenKind.allCases.map(\.coingeckoID).joined(separator: ",")
        let data = try await get(Self.coingecko, "coins/markets", [
            "vs_currency": "usd", "ids": ids, "sparkline": "true", "price_change_percentage": "24h,7d,30d,1y",
        ])
        return try MarketParser.quotes(from: data)
    }

    /// Price history for the coin screen's chart.
    func chart(for token: TokenKind, range: PriceRange) async throws -> [PricePoint] {
        if range == .fiveYears { return try await weeklyCandles(for: token, days: range.days) }
        let data = try await get(Self.coingecko, "coins/\(token.coingeckoID)/market_chart", [
            "vs_currency": "usd", "days": String(range.days),
        ])
        return try MarketParser.chart(from: data)
    }

    /// Kraken answers with its whole weekly history (a few hundred candles)
    /// in one response; the parser keeps the last `days` of it.
    private func weeklyCandles(for token: TokenKind, days: Int) async throws -> [PricePoint] {
        let data = try await get(Self.kraken, "OHLC", ["pair": token.krakenPair, "interval": "10080"])
        let since = Date.now.addingTimeInterval(-Double(days) * 86_400)
        do {
            return try MarketParser.krakenChart(from: data, since: since)
        } catch MarketParser.Failure.api(let messages) {
            // Kraken reports throttling in the body of a 200, not as a 429.
            let throttled = messages.contains { $0.localizedCaseInsensitiveContains("rate limit") || $0.localizedCaseInsensitiveContains("too many requests") }
            throw throttled ? Failure.rateLimited : Failure.badResponse
        }
    }

    private func get(_ base: URL, _ path: String, _ query: [String: String]) async throws -> Data {
        var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
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
