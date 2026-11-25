import Foundation
import XCTest
@testable import Kestrel

final class ActivityAnalyticsTests: XCTestCase {
    private let me = "TMyWalletAddress000000000000000000"
    private let alice = "TAliceQwErTy111111111111111111111"
    private let bob = "TBobZxCvB222222222222222222222222"
    private let carol = "TCarol33333333333333333333333333"
    private let dave = "TDave444444444444444444444444444"

    private func calendar(_ zone: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.locale = Locale(identifier: "en_GB")
        calendar.firstWeekday = 2 // Monday
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func usdt(_ value: UInt64) -> UInt64 { value * 1_000_000 }

    private func incoming(_ id: String, _ date: Date, _ units: UInt64, from: String? = nil) -> TokenTransfer {
        TokenTransfer(id: id, date: date, from: from ?? alice, to: me, units: units)
    }

    private func outgoing(_ id: String, _ date: Date, _ units: UInt64, to: String? = nil) -> TokenTransfer {
        TokenTransfer(id: id, date: date, from: me, to: to ?? bob, units: units)
    }

    // MARK: Timeframes

    func testBucketCountsAndBoundaries() {
        let cal = calendar()
        let now = date(2026, 11, 25, 15, in: cal) // a Wednesday

        let week = Timeframe.week.bucketStarts(now: now, calendar: cal, earliest: nil)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.first, date(2026, 11, 19, in: cal))
        XCTAssertEqual(week.last, date(2026, 11, 25, in: cal))

        let month = Timeframe.month.bucketStarts(now: now, calendar: cal, earliest: nil)
        XCTAssertEqual(month.count, 30)
        XCTAssertEqual(month.first, date(2026, 10, 27, in: cal))
        XCTAssertEqual(month.last, date(2026, 11, 25, in: cal))

        let quarter = Timeframe.quarter.bucketStarts(now: now, calendar: cal, earliest: nil)
        XCTAssertEqual(quarter.count, 13)
        XCTAssertEqual(quarter.first, date(2026, 8, 31, in: cal)) // Monday
        XCTAssertEqual(quarter.last, date(2026, 11, 23, in: cal)) // this week's Monday
        XCTAssertTrue(quarter.allSatisfy { cal.component(.weekday, from: $0) == 2 })

        let year = Timeframe.year.bucketStarts(now: now, calendar: cal, earliest: nil)
        XCTAssertEqual(year.count, 12)
        XCTAssertEqual(year.first, date(2025, 12, 1, in: cal))
        XCTAssertEqual(year.last, date(2026, 11, 1, in: cal))

        let all = Timeframe.all.bucketStarts(now: now, calendar: cal, earliest: date(2024, 3, 15, 9, in: cal))
        XCTAssertEqual(all.count, 33) // Mar 2024 ... Nov 2026
        XCTAssertEqual(all.first, date(2024, 3, 1, in: cal))

        XCTAssertNil(Timeframe.all.start(now: now, calendar: cal, earliest: nil))
        XCTAssertTrue(Timeframe.all.bucketStarts(now: now, calendar: cal, earliest: nil).isEmpty)
    }

    func testBucketComponents() {
        XCTAssertEqual(Timeframe.week.bucket, .day)
        XCTAssertEqual(Timeframe.month.bucket, .day)
        XCTAssertEqual(Timeframe.quarter.bucket, .weekOfYear)
        XCTAssertEqual(Timeframe.year.bucket, .month)
        XCTAssertEqual(Timeframe.all.bucket, .month)
    }

    func testDaylightSavingCrossingKeepsMidnightBoundaries() {
        // UK clocks go forward on Sunday 29 March 2026.
        let cal = calendar("Europe/London")
        let now = date(2026, 3, 31, 12, in: cal)

        let week = Timeframe.week.bucketStarts(now: now, calendar: cal, earliest: nil)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.first, date(2026, 3, 25, in: cal))
        for start in week {
            XCTAssertEqual(cal.component(.hour, from: start), 0)
            XCTAssertEqual(cal.component(.minute, from: start), 0)
        }
        let sunday = date(2026, 3, 29, in: cal)
        let monday = date(2026, 3, 30, in: cal)
        XCTAssertTrue(week.contains(sunday))
        XCTAssertEqual(monday.timeIntervalSince(sunday), 23 * 3600)

        XCTAssertEqual(Timeframe.month.bucketStarts(now: now, calendar: cal, earliest: nil).count, 30)

        // A late-evening transfer on the short day lands in that day's bucket.
        let late = incoming("late", date(2026, 3, 29, 23, 30, in: cal), usdt(5))
        let flow = ActivityAnalytics.flowBuckets(transfers: [late], me: me, timeframe: .week, now: now, calendar: cal)
        XCTAssertEqual(flow.count, 7)
        let bucket = flow.first { $0.start == sunday }
        XCTAssertEqual(bucket?.inflow, usdt(5))
        XCTAssertEqual(bucket?.end, monday)
        XCTAssertEqual(flow.map(\.count).reduce(0, +), 1)
    }

    // MARK: Balance

    func testBalanceRebuild() {
        let cal = calendar()
        let now = date(2026, 11, 25, 15, in: cal)
        let transfers = [
            incoming("a", date(2026, 11, 24, 10, in: cal), usdt(30)),
            outgoing("b", date(2026, 11, 22, 10, in: cal), usdt(50)),
            incoming("c", date(2026, 11, 10, 10, in: cal), usdt(200)), // before the week
        ]
        let series = ActivityAnalytics.balanceSeries(current: usdt(100), transfers: transfers, me: me,
                                                     timeframe: .week, now: now, calendar: cal)
        XCTAssertEqual(series.points.count, 8) // 7 bucket starts + now
        XCTAssertEqual(series.points.first?.date, date(2026, 11, 19, in: cal))
        XCTAssertEqual(series.points.last?.date, now)
        XCTAssertEqual(series.points.map(\.units), [120, 120, 120, 120, 70, 70, 100, 100].map(usdt))
        XCTAssertEqual(series.startUnits, usdt(120))
        XCTAssertEqual(series.endUnits, usdt(100))
        XCTAssertEqual(series.changeUnits, -20_000_000)
        XCTAssertEqual(series.changePercent!, -20.0 / 120.0, accuracy: 1e-9)

        XCTAssertEqual(ActivityAnalytics.balance(before: date(2026, 11, 1, in: cal), current: usdt(100),
                                                 transfers: transfers, me: me), -80_000_000)
    }

    func testBalanceClampsAtZeroForIncompleteHistory() {
        let cal = calendar()
        let now = date(2026, 11, 25, 15, in: cal)
        // Received 50 but only 10 left and the matching send isn't in the fetched page.
        let transfers = [incoming("a", date(2026, 11, 23, 10, in: cal), usdt(50))]
        let series = ActivityAnalytics.balanceSeries(current: usdt(10), transfers: transfers, me: me,
                                                     timeframe: .week, now: now, calendar: cal)
        XCTAssertEqual(series.startUnits, 0)
        XCTAssertTrue(series.points.allSatisfy { $0.units <= usdt(10) })
        XCTAssertEqual(series.changeUnits, 10_000_000)
        XCTAssertNil(series.changePercent)
    }

    func testDailyBalancesMatchLegacyChartLoop() {
        let cal = calendar("Europe/London")
        let now = date(2026, 3, 31, 12, in: cal)
        var transfers: [TokenTransfer] = []
        for i in 0 ..< 40 {
            let when = now.addingTimeInterval(-Double(i) * 17 * 3600)
            let units = UInt64(1 + (i * 37) % 23) * 1_000_000 + UInt64(i) * 1_234
            transfers.append(i % 3 == 0 ? outgoing("o\(i)", when, units) : incoming("i\(i)", when, units))
        }
        let current = usdt(150)
        let days = 30

        // The loop BalanceLineChart used before it moved here, kept as the oracle.
        let today = cal.startOfDay(for: now)
        var running = Double(current) / 1_000_000
        var legacy: [(Date, Double)] = []
        let sorted = transfers.sorted { $0.date > $1.date }
        var index = 0
        for offset in 0 ..< days {
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            legacy.append((day, max(running, 0)))
            while index < sorted.count, sorted[index].date >= day {
                let amount = Double(sorted[index].units) / 1_000_000
                running += sorted[index].from == me ? amount : -amount
                index += 1
            }
        }
        legacy.reverse()

        let points = ActivityAnalytics.dailyBalances(current: current, transfers: transfers, me: me,
                                                     days: days, now: now, calendar: cal)
        XCTAssertEqual(points.count, legacy.count)
        for (point, old) in zip(points, legacy) {
            XCTAssertEqual(point.date, old.0)
            XCTAssertEqual(point.usdt, old.1, accuracy: 1e-6)
        }
    }

    // MARK: Empty history

    func testEmptyHistory() {
        let cal = calendar()
        let now = date(2026, 11, 25, 15, in: cal)

        let all = ActivityAnalytics.balanceSeries(current: usdt(7), transfers: [], me: me, timeframe: .all, now: now, calendar: cal)
        XCTAssertEqual(all.points.map(\.units), [usdt(7)])
        XCTAssertEqual(all.startUnits, usdt(7))
        XCTAssertEqual(all.changeUnits, 0)
        XCTAssertEqual(all.changePercent, 0)

        let week = ActivityAnalytics.balanceSeries(current: 0, transfers: [], me: me, timeframe: .week, now: now, calendar: cal)
        XCTAssertEqual(week.points.count, 8)
        XCTAssertNil(week.changePercent)

        XCTAssertTrue(ActivityAnalytics.flowBuckets(transfers: [], me: me, timeframe: .all, now: now, calendar: cal).isEmpty)
        let flow = ActivityAnalytics.flowBuckets(transfers: [], me: me, timeframe: .week, now: now, calendar: cal)
        XCTAssertEqual(flow.count, 7)
        XCTAssertTrue(flow.allSatisfy { $0.inflow == 0 && $0.outflow == 0 && $0.count == 0 })

        let insights = ActivityAnalytics.insights(transfers: [], fees: [:], me: me, since: nil)
        XCTAssertEqual(insights.count, 0)
        XCTAssertEqual(insights.averageUnits, 0)
        XCTAssertNil(insights.largestIn)
        XCTAssertNil(insights.largestOut)
        XCTAssertTrue(insights.topCounterparties.isEmpty)

        XCTAssertEqual(ActivityAnalytics.dailyBalances(current: usdt(3), transfers: [], me: me, days: 7, now: now, calendar: cal)
            .map(\.units), Array(repeating: usdt(3), count: 7))
    }

    // MARK: Flow and insights

    func testFlowTotalsEqualInsightsTotals() {
        let cal = calendar()
        let now = date(2026, 11, 25, 15, in: cal)
        let transfers = [
            incoming("a", date(2026, 11, 25, 9, in: cal), usdt(10)),
            outgoing("b", date(2026, 11, 3, 9, in: cal), usdt(4)),
            incoming("c", date(2026, 10, 1, 9, in: cal), usdt(25)),
            outgoing("d", date(2026, 6, 1, 9, in: cal), usdt(8)),
            incoming("e", date(2025, 1, 1, 9, in: cal), usdt(100)),
        ]
        for timeframe in Timeframe.allCases {
            let flow = ActivityAnalytics.flowBuckets(transfers: transfers, me: me, timeframe: timeframe, now: now, calendar: cal)
            let since = timeframe.start(now: now, calendar: cal, earliest: transfers.map(\.date).min())
            let insights = ActivityAnalytics.insights(transfers: transfers, fees: [:], me: me, since: since)
            XCTAssertEqual(flow.map(\.inflow).reduce(0, +), insights.inflow, "\(timeframe)")
            XCTAssertEqual(flow.map(\.outflow).reduce(0, +), insights.outflow, "\(timeframe)")
            XCTAssertEqual(flow.map(\.net).reduce(0, +), insights.net, "\(timeframe)")
            XCTAssertEqual(flow.map(\.count).reduce(0, +), insights.count, "\(timeframe)")

            // The balance line's change agrees with the flow's net.
            let series = ActivityAnalytics.balanceSeries(current: usdt(500), transfers: transfers, me: me,
                                                         timeframe: timeframe, now: now, calendar: cal)
            XCTAssertEqual(series.changeUnits, insights.net, "\(timeframe)")
        }
        let all = ActivityAnalytics.insights(transfers: transfers, fees: [:], me: me, since: nil)
        XCTAssertEqual(all.inflow, usdt(135))
        XCTAssertEqual(all.outflow, usdt(12))
        XCTAssertEqual(all.averageUnits, usdt(147) / 5)
        XCTAssertEqual(all.largestIn?.id, "e")
        XCTAssertEqual(all.largestOut?.id, "d")
    }

    func testTopCounterpartiesOrdering() {
        let cal = calendar()
        let t = date(2026, 11, 20, in: cal)
        let transfers = [
            incoming("1", t, usdt(200), from: alice),
            outgoing("2", t, usdt(100), to: alice),
            incoming("3", t, usdt(300), from: bob),
            outgoing("4", t, usdt(100), to: carol),
            incoming("5", t, usdt(50), from: dave),
        ]
        let insights = ActivityAnalytics.insights(transfers: transfers, fees: [:], me: me, since: nil)
        // Alice and Bob tie on volume; Alice has more transfers.
        XCTAssertEqual(insights.topCounterparties.map(\.address), [alice, bob, carol])
        let a = insights.topCounterparties[0]
        XCTAssertEqual(a.count, 2)
        XCTAssertEqual(a.inflow, usdt(200))
        XCTAssertEqual(a.outflow, usdt(100))
        XCTAssertEqual(a.net, 100_000_000)
        XCTAssertEqual(insights.topCounterparties[2].net, -100_000_000)
    }

    func testFeesOnlyFromOutgoingInRange() {
        let cal = calendar()
        let since = date(2026, 11, 1, in: cal)
        let transfers = [
            outgoing("out-in-range", date(2026, 11, 5, in: cal), usdt(1)),
            outgoing("out-no-fee", date(2026, 11, 6, in: cal), usdt(1)),
            incoming("in-in-range", date(2026, 11, 7, in: cal), usdt(1)),
            outgoing("out-old", date(2026, 10, 5, in: cal), usdt(1)),
        ]
        let fees: [String: Int64] = ["out-in-range": 13_500_000, "in-in-range": 9_000_000, "out-old": 14_000_000]
        XCTAssertEqual(ActivityAnalytics.insights(transfers: transfers, fees: fees, me: me, since: since).feesSun, 13_500_000)
        XCTAssertEqual(ActivityAnalytics.insights(transfers: transfers, fees: fees, me: me, since: nil).feesSun, 27_500_000)
    }

    // MARK: Query

    func testQueryMatching() {
        let cal = calendar()
        let sent = TokenTransfer(id: "abcdef0123", date: date(2026, 11, 20, 23, 59, in: cal), from: me, to: bob, units: 1_500_500_000)
        let received = TokenTransfer(id: "99ff00", date: date(2026, 11, 18, 8, in: cal), from: alice, to: me, units: usdt(500))
        func match(_ q: TransferQuery, _ t: TokenTransfer) -> Bool { q.matches(t, me: me, calendar: cal) }

        var q = TransferQuery()
        XCTAssertFalse(q.isActive)
        XCTAssertTrue(match(q, sent) && match(q, received))

        // Address substring, case-insensitive; my own address never matches.
        q.text = "zxcvb"
        XCTAssertTrue(q.isActive)
        XCTAssertTrue(match(q, sent))
        XCTAssertFalse(match(q, received))
        q.text = "MyWallet"
        XCTAssertFalse(match(q, sent) || match(q, received))

        // Transaction id prefix, not substring.
        q.text = "ABCD"
        XCTAssertTrue(match(q, sent))
        q.text = "cdef"
        XCTAssertFalse(match(q, sent))

        // Amount text, with or without grouping commas.
        q.text = "500"
        XCTAssertTrue(match(q, sent)) // 1,500.50
        XCTAssertTrue(match(q, received)) // 500.00
        q.text = "500.5"
        XCTAssertTrue(match(q, sent))
        XCTAssertFalse(match(q, received))
        q.text = "1,500.50"
        XCTAssertTrue(match(q, sent))
        q.text = "   "
        XCTAssertFalse(q.isActive)

        // Direction.
        q = TransferQuery(direction: .incoming)
        XCTAssertTrue(q.isActive)
        XCTAssertFalse(match(q, sent))
        XCTAssertTrue(match(q, received))
        q.direction = .outgoing
        XCTAssertTrue(match(q, sent))
        XCTAssertFalse(match(q, received))

        // Amount range, inclusive.
        q = TransferQuery(minUnits: usdt(500), maxUnits: usdt(500))
        XCTAssertTrue(match(q, received))
        XCTAssertFalse(match(q, sent))

        // Counterparty, exact.
        q = TransferQuery(counterparty: alice)
        XCTAssertTrue(match(q, received))
        XCTAssertFalse(match(q, sent))

        // Dates: `to` covers its whole day, `from` starts at midnight.
        q = TransferQuery(from: date(2026, 11, 20, 18, in: cal), to: date(2026, 11, 20, 0, in: cal))
        XCTAssertTrue(match(q, sent)) // 23:59 on the 20th
        XCTAssertFalse(match(q, received))
        q = TransferQuery(to: date(2026, 11, 19, 12, in: cal))
        XCTAssertFalse(match(q, sent))
        XCTAssertTrue(match(q, received))
    }

    func testTitles() {
        XCTAssertEqual(Timeframe.allCases.count, 5)
        XCTAssertEqual(TransferQuery.Direction.allCases.count, 3)
        XCTAssertEqual(Timeframe.week.title, "7D")
        XCTAssertEqual(TransferQuery.Direction.outgoing.title, "Out")
    }
}
