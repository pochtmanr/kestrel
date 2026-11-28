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
    // The rest come from the same `coins/markets` row. They default to nil so
    // a quote can still be built from the fields above alone.
    /// Place by market cap, 1 = biggest.
    var rank: Int? = nil
    var circulatingSupply: Double? = nil
    var totalSupply: Double? = nil
    /// nil when the coin has no cap on supply (both of ours).
    var maxSupply: Double? = nil
    var allTimeLow: Double? = nil
    var allTimeLowDate: Date? = nil
    /// Percent below the all-time high, e.g. -43.6.
    var athChangePercent: Double? = nil
    var change30d: Double? = nil
    var change1y: Double? = nil

    var tokenPrice: TokenPrice { TokenPrice(usd: price, change24h: change24h) }
}

struct PricePoint: Equatable, Sendable, Identifiable, Codable {
    let date: Date
    let usd: Double
    /// Dollars traded, when the source reports it. The meaning follows the
    /// source: CoinGecko gives the trailing 24 hours across all markets at
    /// that moment, Kraken gives that one weekly candle on Kraken alone.
    var volume: Double? = nil
    var id: Date { date }
}

/// The coin screen's chart ranges. The free CoinGecko API serves at most a
/// year of history (`days=max` answers 401), so everything up to a year comes
/// from there and the five-year range from Kraken's weekly candles. There's
/// no "All": neither source goes back to the start for every coin.
enum PriceRange: String, CaseIterable, Identifiable, Sendable {
    case day, week, month, quarter, year, fiveYears

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .day: "1D"
        case .week: "7D"
        case .month: "1M"
        case .quarter: "3M"
        case .year: "1Y"
        case .fiveYears: "5Y"
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
        case .fiveYears: "Past 5 years"
        }
    }

    var days: Int {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .year: 365
        case .fiveYears: 1825
        }
    }

    /// How long a fetched chart counts as fresh. Weekly candles gain a point
    /// once a week, so a day is plenty for them.
    var cacheLifetime: TimeInterval {
        self == .fiveYears ? 86_400 : 300
    }

    /// The date under the finger while scrubbing the chart, as detailed as the
    /// range's points are apart, in the app's chosen language.
    func scrubLabel(for date: Date) -> String {
        let locale = AppLanguage.current.locale ?? .current
        switch self {
        case .day:
            return date.formatted(.dateTime.hour().minute().locale(locale))
        case .week:
            return date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale))
        case .month, .quarter, .year:
            return date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
        case .fiveYears:
            let day = date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
            return tr("Week of \(day)")
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
                allTimeHighDate: row.ath_date,
                rank: row.market_cap_rank,
                circulatingSupply: row.circulating_supply,
                totalSupply: row.total_supply,
                maxSupply: row.max_supply,
                allTimeLow: row.atl,
                allTimeLowDate: row.atl_date,
                athChangePercent: row.ath_change_percentage,
                change30d: row.price_change_percentage_30d_in_currency,
                change1y: row.price_change_percentage_1y_in_currency
            )
        }
        return result
    }

    enum Failure: Error, Equatable {
        case malformed
        /// The source answered with its own error messages instead of data.
        case api([String])
    }

    /// `coins/{id}/market_chart`: `prices` is `[[epochMillis, usd], …]`, and
    /// `total_volumes` has the same shape with the trailing 24h volume.
    static func chart(from data: Data) throws -> [PricePoint] {
        let body = try decoder.decode(ChartBody.self, from: data)
        let volumes = body.total_volumes ?? []
        // The two arrays normally line up row for row. When they don't, each
        // price takes the volume closest to it in time.
        let aligned = volumes.count == body.prices.count
        let byTime = aligned ? [] : volumes.filter { $0.count >= 2 }.sorted { $0[0] < $1[0] }
        return body.prices.enumerated().compactMap { index, pair -> PricePoint? in
            guard pair.count >= 2 else { return nil }
            let volume: Double?
            if aligned {
                volume = volumes[index].count >= 2 ? volumes[index][1] : nil
            } else {
                volume = nearestValue(in: byTime, to: pair[0])
            }
            return PricePoint(date: Date(timeIntervalSince1970: pair[0] / 1000), usd: pair[1], volume: volume)
        }
        .sorted { $0.date < $1.date }
    }

    /// The value of the `[time, value]` row closest to `time`; rows are sorted by time.
    private static func nearestValue(in rows: [[Double]], to time: Double) -> Double? {
        guard !rows.isEmpty else { return nil }
        var low = 0
        var high = rows.count - 1
        while low < high {
            let middle = (low + high) / 2
            if rows[middle][0] < time { low = middle + 1 } else { high = middle }
        }
        // `low` is the first row at or after `time`; the one before may be closer.
        if low > 0, abs(rows[low - 1][0] - time) <= abs(rows[low][0] - time) { return rows[low - 1][1] }
        return rows[low][1]
    }

    /// Kraken's `OHLC`: `result` holds one array of candles, under a key that
    /// isn't always the pair asked for (USDTUSD answers as `USDTZUSD`), next
    /// to `last`. A candle is `[time, open, high, low, close, vwap, volume,
    /// count]` with the prices and volume as strings. Errors come back as
    /// HTTP 200 with a filled `error` array.
    ///
    /// The price is the close; the volume is in the coin, so it's multiplied
    /// by the candle's average price to get dollars. Candles before `since`
    /// are dropped.
    static func krakenChart(from data: Data, since: Date) throws -> [PricePoint] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.malformed }
        if let errors = root["error"] as? [Any], !errors.isEmpty { throw Failure.api(errors.map { "\($0)" }) }
        guard let result = root["result"] as? [String: Any],
              let rows = result.first(where: { $0.key != "last" && $0.value is [Any] })?.value as? [Any]
        else { throw Failure.malformed }
        return rows.compactMap { row -> PricePoint? in
            guard let row = row as? [Any], row.count >= 5,
                  let time = number(row[0]), let close = number(row[4]), close.isFinite, close > 0
            else { return nil }
            let date = Date(timeIntervalSince1970: time)
            guard date >= since else { return nil }
            var volume: Double?
            if row.count >= 7, let vwap = number(row[5]), let amount = number(row[6]) { volume = amount * vwap }
            return PricePoint(date: date, usd: close, volume: volume)
        }
        .sorted { $0.date < $1.date }
    }

    /// A JSON number, or a number written as a string.
    private static func number(_ value: Any) -> Double? {
        if let text = value as? String { return Double(text) }
        return value as? Double
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
        let ath_change_percentage: Double?
        let atl: Double?
        let atl_date: Date?
        let market_cap_rank: Int?
        let circulating_supply: Double?
        let total_supply: Double?
        let max_supply: Double?
        let price_change_percentage_30d_in_currency: Double?
        let price_change_percentage_1y_in_currency: Double?
        let sparkline_in_7d: Sparkline?

        struct Sparkline: Decodable { let price: [Double] }
    }

    private struct ChartBody: Decodable {
        let prices: [[Double]]
        let total_volumes: [[Double]]?

        enum CodingKeys: String, CodingKey { case prices, total_volumes }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            prices = try container.decode([[Double]].self, forKey: .prices)
            // Volume is a nice-to-have: a broken array must not cost the chart.
            total_volumes = try? container.decodeIfPresent([[Double]].self, forKey: .total_volumes)
        }
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
                           allTimeHigh: 1.32, allTimeHighDate: Date(timeIntervalSince1970: 1_532_563_200),
                           rank: 3, circulatingSupply: 184_190_000_000, totalSupply: 187_400_000_000, maxSupply: nil,
                           allTimeLow: 0.5725, allTimeLowDate: Date(timeIntervalSince1970: 1_425_254_400),
                           athChangePercent: -24.2, change30d: 0.03, change1y: 0.05),
        .trx: MarketQuote(price: 0.2431, change24h: 2.37, change7d: 5.8, sparkline: series(base: 0.232, swing: 0.012, count: 168, seed: 7, trend: 0.011).map(\.usd),
                          marketCap: 20_950_000_000, volume24h: 612_000_000, high24h: 0.2449, low24h: 0.2368,
                          allTimeHigh: 0.4313, allTimeHighDate: Date(timeIntervalSince1970: 1_733_097_600),
                          rank: 10, circulatingSupply: 86_180_000_000, totalSupply: 86_180_000_000, maxSupply: nil,
                          allTimeLow: 0.00180434, allTimeLowDate: Date(timeIntervalSince1970: 1_510_444_800),
                          athChangePercent: -43.6, change30d: 8.4, change1y: 21.7),
    ]

    static func chart(for token: TokenKind, range: PriceRange, now: Date = .now) -> [PricePoint] {
        let count: Int
        switch range {
        case .day: count = 288
        case .week: count = 168
        case .fiveYears: count = 261 // weekly candles
        default: count = range.days
        }
        let points: [PricePoint]
        switch (token, range) {
        case (.usdt, _):
            points = series(base: 1.0, swing: 0.0015, count: count, seed: UInt64(range.days) + 11)
        case (.trx, .fiveYears):
            points = series(base: 0.09, swing: 0.018, count: count, seed: UInt64(range.days) + 23, trend: 0.2431 - 0.09)
        case (.trx, _):
            points = series(base: 0.2431 / (1 + 0.04 * Double(range.days) / 90), swing: 0.003 * sqrt(Double(range.days)) / 3,
                            count: count, seed: UInt64(range.days) + 23, trend: 0.2431 - 0.2431 / (1 + 0.04 * Double(range.days) / 90))
        }
        // End exactly on the quote, as live data does.
        let shift = (quotes[token]?.price ?? 0) - (points.last?.usd ?? 0)
        let step = Double(range.days) * 86_400 / Double(count - 1)
        // Live volume is the whole market's trailing 24 hours, except on the
        // five-year range, where it's one exchange's week: far smaller.
        let typicalVolume: Double
        switch (token, range) {
        case (.usdt, .fiveYears): typicalVolume = 940_000_000
        case (.trx, .fiveYears): typicalVolume = 21_000_000
        default: typicalVolume = quotes[token]?.volume24h ?? 0
        }
        let wobble = series(base: 1, swing: 0.35, count: count, seed: UInt64(range.days) + 41)
        return points.enumerated().map { index, point in
            PricePoint(date: now.addingTimeInterval(-step * Double(count - 1 - index)), usd: point.usd + shift,
                       volume: typicalVolume * max(0.25, wobble[index].usd))
        }
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
