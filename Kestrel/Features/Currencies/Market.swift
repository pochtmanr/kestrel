import Foundation
import SwiftUI

/// A token's market price in US dollars.
struct TokenPrice: Equatable, Sendable {
    let usd: Double
    /// Percent change over the last 24 hours, e.g. -1.8.
    let change24h: Double?
}

/// Everything CoinGecko's markets endpoint says about one coin.
struct MarketQuote: Equatable, Sendable {
    let price: Double
    let change24h: Double?
    let change7d: Double?
    /// About 168 hourly prices over the last 7 days, oldest first.
    let sparkline: [Double]
    let marketCap: Double?
    let volume24h: Double?
    let high24h: Double?
    let low24h: Double?
    let allTimeHigh: Double?
    let allTimeHighDate: Date?

    var tokenPrice: TokenPrice { TokenPrice(usd: price, change24h: change24h) }
}

struct PricePoint: Equatable, Sendable, Identifiable {
    let date: Date
    let usd: Double
    var id: Date { date }
}

/// The coin screen's chart ranges. The free CoinGecko API serves at most a
/// year of history (`days=max` answers 401), so there's no "All".
enum PriceRange: String, CaseIterable, Identifiable, Sendable {
    case day, week, month, quarter, year

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .day: "1D"
        case .week: "7D"
        case .month: "1M"
        case .quarter: "3M"
        case .year: "1Y"
        }
    }

    /// What the change next to the price is measured over.
    var caption: LocalizedStringKey {
        switch self {
        case .day: "Today"
        case .week: "Past week"
        case .month: "Past month"
        case .quarter: "Past 3 months"
        case .year: "Past year"
        }
    }

    var days: Int {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .year: 365
        }
    }
}

// MARK: - Parsing

enum MarketParser {
    /// Rows of `coins/markets`, keyed by our tokens. Unknown ids are ignored.
    static func quotes(from data: Data) throws -> [TokenKind: MarketQuote] {
        let rows = try decoder.decode([MarketRow].self, from: data)
        var result: [TokenKind: MarketQuote] = [:]
        for row in rows {
            guard let token = TokenKind.allCases.first(where: { $0.coingeckoID == row.id }), let price = row.current_price else { continue }
            result[token] = MarketQuote(
                price: price,
                change24h: row.price_change_percentage_24h_in_currency ?? row.price_change_percentage_24h,
                change7d: row.price_change_percentage_7d_in_currency,
                sparkline: row.sparkline_in_7d?.price ?? [],
                marketCap: row.market_cap,
                volume24h: row.total_volume,
                high24h: row.high_24h,
                low24h: row.low_24h,
                allTimeHigh: row.ath,
                allTimeHighDate: row.ath_date
            )
        }
        return result
    }

    /// `coins/{id}/market_chart`: `prices` is `[[epochMillis, usd], …]`.
    static func chart(from data: Data) throws -> [PricePoint] {
        let body = try decoder.decode(ChartBody.self, from: data)
        return body.prices.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return PricePoint(date: Date(timeIntervalSince1970: pair[0] / 1000), usd: pair[1])
        }
        .sorted { $0.date < $1.date }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(text)"))
        }
        return decoder
    }()

    private struct MarketRow: Decodable {
        let id: String
        let current_price: Double?
        let price_change_percentage_24h: Double?
        let price_change_percentage_24h_in_currency: Double?
        let price_change_percentage_7d_in_currency: Double?
        let market_cap: Double?
        let total_volume: Double?
        let high_24h: Double?
        let low_24h: Double?
        let ath: Double?
        let ath_date: Date?
        let sparkline_in_7d: Sparkline?

        struct Sparkline: Decodable { let price: [Double] }
    }

    private struct ChartBody: Decodable {
        let prices: [[Double]]
    }
}

// MARK: - Portfolio maths

/// The Currencies header: total value, its 24h change, and each coin's share.
struct Portfolio: Equatable {
    struct Slice: Equatable {
        let token: TokenKind
        let value: Double
        let share: Double
    }

    let total: Double
    /// Dollar change over 24h, nil when no held coin has a 24h change.
    let change: Double?
    /// The change relative to yesterday's total, in percent.
    let changePercent: Double?
    /// Coins with a value, biggest first.
    let slices: [Slice]

    init(holdings: [Holding], prices: [TokenKind: TokenPrice]) {
        var total = 0.0
        var yesterday = 0.0
        var anyChange = false
        var values: [(TokenKind, Double)] = []
        for holding in holdings {
            guard let value = holding.usdValue(prices[holding.token]) else { continue }
            total += value
            values.append((holding.token, value))
            if let change = prices[holding.token]?.change24h, change > -100 {
                yesterday += value / (1 + change / 100)
                anyChange = true
            } else {
                yesterday += value
            }
        }
        self.total = total
        if anyChange {
            change = total - yesterday
            changePercent = yesterday > 0 ? (total - yesterday) / yesterday * 100 : nil
        } else {
            change = nil
            changePercent = nil
        }
        var slices: [Slice] = []
        for (token, value) in values where value > 0 {
            slices.append(Slice(token: token, value: value, share: total > 0 ? value / total : 0))
        }
        self.slices = slices.sorted { $0.value > $1.value }
    }
}

/// How the Currencies list is ordered.
enum CoinSort: String, CaseIterable, Identifiable {
    case value, name, change

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .value: "Value"
        case .name: "Name"
        case .change: "24h change"
        }
    }

    /// Ties (and coins without the measure) fall back to the registry order.
    func sorted(_ tokens: [TokenKind], value: (TokenKind) -> Double?, change: (TokenKind) -> Double?) -> [TokenKind] {
        let order = Dictionary(uniqueKeysWithValues: TokenKind.allCases.enumerated().map { ($1, $0) })
        return tokens.sorted { a, b in
            switch self {
            case .name:
                return a.symbol.localizedStandardCompare(b.symbol) == .orderedAscending
            case .value, .change:
                let x = self == .value ? value(a) : change(a)
                let y = self == .value ? value(b) : change(b)
                if x != y { return (x ?? -.infinity) > (y ?? -.infinity) }
                return order[a, default: 0] < order[b, default: 0]
            }
        }
    }
}

extension Array where Element == PricePoint {
    /// Percent change from the first point to the last.
    var changePercent: Double? {
        guard let first, let last, first.usd > 0 else { return nil }
        return (last.usd - first.usd) / first.usd * 100
    }

    func nearest(to date: Date) -> PricePoint? {
        self.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

// MARK: - Demo data

#if DEBUG
enum MarketDemo {
    static let quotes: [TokenKind: MarketQuote] = [
        .usdt: MarketQuote(price: 1.0002, change24h: 0.01, change7d: -0.02, sparkline: series(base: 1.0, swing: 0.0012, count: 168, seed: 3).map(\.usd),
                           marketCap: 184_230_000_000, volume24h: 61_400_000_000, high24h: 1.0006, low24h: 0.9997,
                           allTimeHigh: 1.32, allTimeHighDate: Date(timeIntervalSince1970: 1_532_563_200)),
        .trx: MarketQuote(price: 0.2431, change24h: 2.37, change7d: 5.8, sparkline: series(base: 0.232, swing: 0.012, count: 168, seed: 7, trend: 0.011).map(\.usd),
                          marketCap: 20_950_000_000, volume24h: 612_000_000, high24h: 0.2449, low24h: 0.2368,
                          allTimeHigh: 0.4313, allTimeHighDate: Date(timeIntervalSince1970: 1_733_097_600)),
    ]

    static func chart(for token: TokenKind, range: PriceRange, now: Date = .now) -> [PricePoint] {
        let count = range == .day ? 288 : range == .week ? 168 : range.days
        let points: [PricePoint]
        switch token {
        case .usdt: points = series(base: 1.0, swing: 0.0015, count: count, seed: UInt64(range.days) + 11)
        case .trx: points = series(base: 0.2431 / (1 + 0.04 * Double(range.days) / 90), swing: 0.003 * sqrt(Double(range.days)) / 3,
                                   count: count, seed: UInt64(range.days) + 23, trend: 0.2431 - 0.2431 / (1 + 0.04 * Double(range.days) / 90))
        }
        // End exactly on the quote, as live data does.
        let shift = (quotes[token]?.price ?? 0) - (points.last?.usd ?? 0)
        let step = Double(range.days) * 86_400 / Double(count - 1)
        return points.enumerated().map { PricePoint(date: now.addingTimeInterval(-step * Double(count - 1 - $0)), usd: $1.usd + shift) }
    }

    /// A deterministic wobbly walk ending near `base + trend`.
    private static func series(base: Double, swing: Double, count: Int, seed: UInt64, trend: Double = 0) -> [PricePoint] {
        var state = seed &* 0x9E37_79B9_7F4A_7C15
        var walk = 0.0
        return (0..<count).map { i in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let noise = Double(state >> 33) / Double(1 << 31) - 0.5
            walk = walk * 0.92 + noise * swing
            let t = Double(i) / Double(max(1, count - 1))
            return PricePoint(date: .distantPast, usd: base + trend * t + walk)
        }
    }
}
#endif
