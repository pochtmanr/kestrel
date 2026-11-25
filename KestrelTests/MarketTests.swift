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
