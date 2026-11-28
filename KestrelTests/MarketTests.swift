import Foundation
import XCTest
@testable import Kestrel

final class MarketTests: XCTestCase {
    // MARK: Parsing

    func testParsesMarketsRows() throws {
        let json = """
        [{"id":"tether","current_price":1.0002,"price_change_percentage_24h":0.01,
          "price_change_percentage_24h_in_currency":0.012,"price_change_percentage_7d_in_currency":-0.03,
          "market_cap":184000000000,"total_volume":61000000000,"high_24h":1.0006,"low_24h":0.9997,
          "ath":1.32,"ath_date":"2018-07-24T00:00:00.000Z","sparkline_in_7d":{"price":[1.0,1.001,0.999]}},
         {"id":"tron","current_price":0.2431,"price_change_percentage_24h":2.37,"ath":0.4313,
          "ath_date":"2024-12-04T00:00:00Z","sparkline_in_7d":{"price":[]}},
         {"id":"bitcoin","current_price":90000}]
        """
        let quotes = try MarketParser.quotes(from: Data(json.utf8))
        XCTAssertEqual(quotes.count, 2, "unknown ids are ignored")
        let usdt = try XCTUnwrap(quotes[.usdt])
        XCTAssertEqual(usdt.price, 1.0002)
        XCTAssertEqual(usdt.change24h, 0.012, "the in-currency change wins")
        XCTAssertEqual(usdt.change7d, -0.03)
        XCTAssertEqual(usdt.sparkline, [1.0, 1.001, 0.999])
        XCTAssertEqual(usdt.marketCap, 184_000_000_000)
        XCTAssertEqual(usdt.allTimeHighDate, Date(timeIntervalSince1970: 1_532_390_400))
        let trx = try XCTUnwrap(quotes[.trx])
        XCTAssertEqual(trx.change24h, 2.37, "falls back to the plain 24h change")
        XCTAssertNil(trx.marketCap)
        XCTAssertNotNil(trx.allTimeHighDate, "dates without fractions parse too")
    }

    func testParsesChartSortedAndSkipsBadPairs() throws {
        let json = #"{"prices":[[1700000060000,0.25],[1700000000000,0.24],[1700000120000]],"market_caps":[],"total_volumes":[]}"#
        let points = try MarketParser.chart(from: Data(json.utf8))
        XCTAssertEqual(points.map(\.usd), [0.24, 0.25])
        XCTAssertEqual(points.first?.date, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(try XCTUnwrap(points.changePercent), 4.1666, accuracy: 0.001)
    }

    func testParsesExtraMarketStatsAndLeavesMissingOnesNil() throws {
        let json = """
        [{"id":"tether","current_price":1.0002,"market_cap_rank":3,"circulating_supply":184190000000.5,
          "total_supply":187400000000,"max_supply":null,"ath":1.32,"ath_change_percentage":-24.2,
          "atl":0.5725,"atl_date":"2015-03-02T00:00:00.000Z",
          "price_change_percentage_30d_in_currency":0.03,"price_change_percentage_1y_in_currency":-0.05},
         {"id":"tron","current_price":0.2431,"max_supply":100000000000,"atl_date":null}]
        """
        let quotes = try MarketParser.quotes(from: Data(json.utf8))
        let usdt = try XCTUnwrap(quotes[.usdt])
        XCTAssertEqual(usdt.rank, 3)
        XCTAssertEqual(usdt.circulatingSupply, 184_190_000_000.5)
        XCTAssertEqual(usdt.totalSupply, 187_400_000_000)
        XCTAssertNil(usdt.maxSupply, "null means no supply cap")
        XCTAssertEqual(usdt.allTimeLow, 0.5725)
        XCTAssertEqual(usdt.allTimeLowDate, Date(timeIntervalSince1970: 1_425_254_400))
        XCTAssertEqual(usdt.athChangePercent, -24.2)
        XCTAssertEqual(usdt.change30d, 0.03)
        XCTAssertEqual(usdt.change1y, -0.05)
        let trx = try XCTUnwrap(quotes[.trx])
        XCTAssertEqual(trx.maxSupply, 100_000_000_000)
        XCTAssertNil(trx.rank)
        XCTAssertNil(trx.circulatingSupply)
        XCTAssertNil(trx.totalSupply)
        XCTAssertNil(trx.allTimeLow)
        XCTAssertNil(trx.allTimeLowDate)
        XCTAssertNil(trx.athChangePercent)
        XCTAssertNil(trx.change30d)
        XCTAssertNil(trx.change1y)
    }

    func testChartPairsVolumesByIndex() throws {
        let json = #"{"prices":[[1700000060000,0.25],[1700000000000,0.24]],"total_volumes":[[1700000060000,500],[1700000000000,400]]}"#
        let points = try MarketParser.chart(from: Data(json.utf8))
        XCTAssertEqual(points.map(\.usd), [0.24, 0.25])
        XCTAssertEqual(points.map(\.volume), [400, 500], "each price keeps its own row's volume through the sort")
    }

    func testChartPairsVolumesByNearestTimeWhenCountsDiffer() throws {
        let json = #"{"prices":[[1700000000000,0.24],[1700000060000,0.25]],"total_volumes":[[1699999990000,100],[1700000055000,200],[1700003000000,300]]}"#
        let points = try MarketParser.chart(from: Data(json.utf8))
        XCTAssertEqual(points.map(\.volume), [100, 200])
    }

    func testChartWithoutVolumesHasNone() throws {
        let missing = try MarketParser.chart(from: Data(#"{"prices":[[1700000000000,0.24]]}"#.utf8))
        XCTAssertEqual(missing.map(\.usd), [0.24])
        XCTAssertEqual(missing.map(\.volume), [nil])
        let broken = try MarketParser.chart(from: Data(#"{"prices":[[1700000000000,0.24]],"total_volumes":"n/a"}"#.utf8))
        XCTAssertEqual(broken.map(\.volume), [nil], "a broken volume array doesn't cost the prices")
    }

    func testKrakenWeeklyCandles() throws {
        // Kraken names the result after its own pair id, and sends prices as strings.
        let json = """
        {"error":[],"result":{"USDTZUSD":[
          [1700697600,"1.0001","1.0005","0.9990","1.0002","1.0000","1000.5",321],
          [1700092800,"0.9999","1.0003","0.9991","1.0001","1.0001","2000.0",400],
          [1600000000,"1.0000","1.0000","1.0000","1.0010","1.0000","5.0",3],
          ["bad"],
          [1701302400,"x","1","1","oops","1","1",1]
        ],"last":1700697600}}
        """
        let points = try MarketParser.krakenChart(from: Data(json.utf8), since: Date(timeIntervalSince1970: 1_650_000_000))
        XCTAssertEqual(points.map(\.date), [Date(timeIntervalSince1970: 1_700_092_800), Date(timeIntervalSince1970: 1_700_697_600)],
                       "oldest first, without the candle before `since` or the malformed rows")
        XCTAssertEqual(points.map(\.usd), [1.0001, 1.0002], "the price is the close")
        XCTAssertEqual(try XCTUnwrap(points[0].volume), 2000.0 * 1.0001, accuracy: 1e-9, "coin volume times the average price")
        XCTAssertEqual(try XCTUnwrap(points[1].volume), 1000.5, accuracy: 1e-9)

        let all = try MarketParser.krakenChart(from: Data(json.utf8), since: .distantPast)
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.first?.usd, 1.0010)
    }

    func testKrakenErrorBodyThrows() {
        let json = #"{"error":["EQuery:Unknown asset pair"]}"#
        XCTAssertThrowsError(try MarketParser.krakenChart(from: Data(json.utf8), since: .distantPast)) { error in
            XCTAssertEqual(error as? MarketParser.Failure, .api(["EQuery:Unknown asset pair"]))
        }
        XCTAssertThrowsError(try MarketParser.krakenChart(from: Data(#"{"error":[],"result":{"last":1}}"#.utf8), since: .distantPast)) { error in
            XCTAssertEqual(error as? MarketParser.Failure, .malformed)
        }
    }

    // MARK: Ranges and cache

    func testFiveYearRange() {
        XCTAssertEqual(PriceRange.allCases.last, .fiveYears)
        XCTAssertEqual(PriceRange.fiveYears.days, 1825)
        XCTAssertEqual(PriceRange.fiveYears.cacheLifetime, 86_400)
        XCTAssertEqual(PriceRange.year.cacheLifetime, 300)
        XCTAssertEqual(TokenKind.usdt.krakenPair, "USDTUSD")
        XCTAssertEqual(TokenKind.trx.krakenPair, "TRXUSD")
    }

    func testChartCacheRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "chart-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertNil(ChartCache.load(token: .trx, range: .fiveYears, in: directory), "nothing saved yet")

        let points = [
            PricePoint(date: Date(timeIntervalSince1970: 1_700_092_800), usd: 0.1012, volume: 21_500_000.25),
            PricePoint(date: Date(timeIntervalSince1970: 1_700_697_600), usd: 0.1034),
        ]
        let fetched = Date(timeIntervalSince1970: 1_700_700_000)
        ChartCache.save(points, token: .trx, range: .fiveYears, in: directory, fetched: fetched)

        let loaded = try XCTUnwrap(ChartCache.load(token: .trx, range: .fiveYears, in: directory))
        XCTAssertEqual(loaded.points, points)
        XCTAssertEqual(loaded.fetched, fetched)
        XCTAssertNil(ChartCache.load(token: .trx, range: .year, in: directory), "one file per range")
        XCTAssertNil(ChartCache.load(token: .usdt, range: .fiveYears, in: directory), "and per coin")

        ChartCache.save([], token: .trx, range: .fiveYears, in: directory)
        XCTAssertEqual(ChartCache.load(token: .trx, range: .fiveYears, in: directory)?.points, points, "an empty chart never replaces a real one")
    }

    #if DEBUG
    func testDemoFiveYearChartIsWeeklyWithVolume() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for token in TokenKind.allCases {
            let points = MarketDemo.chart(for: token, range: .fiveYears, now: now)
            XCTAssertEqual(points.count, 261)
            XCTAssertEqual(points.last?.date, now)
            XCTAssertEqual(try XCTUnwrap(points.first).date.timeIntervalSince(now), -1825 * 86_400, accuracy: 1)
            XCTAssertEqual(try XCTUnwrap(points.last).usd, try XCTUnwrap(MarketDemo.quotes[token]).price, accuracy: 1e-9)
            XCTAssertTrue(points.allSatisfy { $0.usd > 0 && ($0.volume ?? 0) > 0 })
        }
        XCTAssertTrue(MarketDemo.chart(for: .trx, range: .week, now: now).allSatisfy { $0.volume != nil })
    }
    #endif

    // MARK: Portfolio

    private func holding(_ token: TokenKind, _ quantity: Double) -> Holding {
        Holding(token: token, amount: "\(quantity)", quantity: quantity)
    }

    func testPortfolioTotalChangeAndShares() throws {
        let portfolio = Portfolio(holdings: [holding(.usdt, 100), holding(.trx, 100)],
                                  prices: [.usdt: TokenPrice(usd: 1, change24h: 0), .trx: TokenPrice(usd: 1, change24h: 25)])
        XCTAssertEqual(portfolio.total, 200, accuracy: 1e-9)
        // TRX was worth 80 yesterday: 180 → 200.
        XCTAssertEqual(try XCTUnwrap(portfolio.change), 20, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(portfolio.changePercent), 20.0 / 180 * 100, accuracy: 1e-9)
        XCTAssertEqual(portfolio.slices.map(\.share), [0.5, 0.5])
    }

    func testPortfolioWithoutPricesCountsUSDTAtOneDollar() {
        let portfolio = Portfolio(holdings: [holding(.usdt, 50), holding(.trx, 10)], prices: [:])
        XCTAssertEqual(portfolio.total, 50)
        XCTAssertNil(portfolio.change)
        XCTAssertEqual(portfolio.slices.map(\.token), [.usdt], "TRX has no value without a price")
        XCTAssertEqual(portfolio.slices.first?.share, 1)
    }

    func testEmptyPortfolio() {
        let portfolio = Portfolio(holdings: [holding(.usdt, 0), holding(.trx, 0)],
                                  prices: [.usdt: TokenPrice(usd: 1, change24h: 0.1), .trx: TokenPrice(usd: 0.24, change24h: 2)])
        XCTAssertEqual(portfolio.total, 0)
        XCTAssertEqual(portfolio.change, 0)
        XCTAssertNil(portfolio.changePercent, "no percentage of nothing")
        XCTAssertTrue(portfolio.slices.isEmpty)
    }

    // MARK: Sort

    func testSortOrders() {
        let values: [TokenKind: Double] = [.usdt: 10, .trx: 20]
        let changes: [TokenKind: Double] = [.usdt: 0.01]
        let all = TokenKind.allCases
        XCTAssertEqual(CoinSort.value.sorted(all, value: { values[$0] }, change: { changes[$0] }), [.trx, .usdt])
        XCTAssertEqual(CoinSort.name.sorted(all, value: { values[$0] }, change: { changes[$0] }), [.trx, .usdt])
        XCTAssertEqual(CoinSort.change.sorted(all, value: { values[$0] }, change: { changes[$0] }), [.usdt, .trx],
                       "a coin without a change goes last")
        XCTAssertEqual(CoinSort.value.sorted(all, value: { _ in nil }, change: { _ in nil }), all, "ties keep registry order")
    }

    // MARK: Formatting

    func testCompactDollars() {
        XCTAssertEqual(USDPrice.compact(184_230_000_000), "$184.2B")
        XCTAssertEqual(USDPrice.compact(20_950_000_000), "$20.95B")
        XCTAssertEqual(USDPrice.compact(612_000_000), "$612.0M")
        XCTAssertEqual(USDPrice.compact(950), "$950.00")
    }

    func testSearchMatching() {
        XCTAssertTrue(TokenKind.usdt.matches("tether"))
        XCTAssertTrue(TokenKind.trx.matches("FEE"))
        XCTAssertFalse(TokenKind.trx.matches("dollar"))
        XCTAssertTrue(TokenKind.trx.matches("  "))
    }
}
