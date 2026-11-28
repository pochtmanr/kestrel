import UserNotifications
import XCTest
@testable import Kestrel

/// Offline checks for price alerts: the crossing rules, validation, the
/// on-device store and the check that posts notifications.
@MainActor
final class PriceAlertTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "PriceAlertTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    private func alert(_ direction: PriceAlert.Direction, _ target: Double, firedAt: Date? = nil) -> PriceAlert {
        alert(.trx, direction, target, firedAt: firedAt)
    }

    private func alert(_ token: TokenKind, _ direction: PriceAlert.Direction, _ target: Double, firedAt: Date? = nil) -> PriceAlert {
        PriceAlert(token: token, direction: direction, targetUSD: target,
                   createdAt: Date(timeIntervalSince1970: 1_795_000_000), firedAt: firedAt)
    }

    /// Records what would have been posted instead of touching the system.
    @MainActor
    private final class FakeNotifier: PriceAlertNotifying {
        private(set) var posted: [(alert: PriceAlert, price: Double)] = []

        func authorizationStatus() async -> AlertAuthorization { .authorized }
        func requestAuthorization() async -> Bool { true }
        func post(_ alert: PriceAlert, price: Double) async { posted.append((alert, price)) }
    }

    // MARK: Crossing

    func testAboveIsDueAtOrOverTheTarget() {
        let above = alert(.above, 0.35)
        XCTAssertFalse(PriceAlertRules.isDue(above, price: 0.3499))
        XCTAssertTrue(PriceAlertRules.isDue(above, price: 0.35), "exactly equal counts")
        XCTAssertTrue(PriceAlertRules.isDue(above, price: 0.36))
    }

    func testBelowIsDueAtOrUnderTheTarget() {
        let below = alert(.below, 0.20)
        XCTAssertFalse(PriceAlertRules.isDue(below, price: 0.2001))
        XCTAssertTrue(PriceAlertRules.isDue(below, price: 0.20), "exactly equal counts")
        XCTAssertTrue(PriceAlertRules.isDue(below, price: 0.19))
    }

    func testDuePicksOnlyArmedAlertsWithAPrice() {
        let reached = alert(.above, 0.30)
        let waiting = alert(.above, 0.40)
        let alreadyFired = alert(.above, 0.30, firedAt: .now)
        let noPrice = alert(.usdt, .below, 2)
        let due = PriceAlertRules.due([reached, waiting, alreadyFired, noPrice], prices: [.trx: 0.33])
        XCTAssertEqual(due.map(\.id), [reached.id])
        XCTAssertTrue(PriceAlertRules.due([reached], prices: [:]).isEmpty)
        // A broken quote is no reason to fire a "below" alert.
        XCTAssertTrue(PriceAlertRules.due([alert(.below, 0.2)], prices: [.trx: 0]).isEmpty)
        XCTAssertTrue(PriceAlertRules.due([alert(.above, 0.2)], prices: [.trx: .nan]).isEmpty)
    }

    func testSuggestedDirection() {
        XCTAssertEqual(PriceAlertRules.suggestedDirection(target: 0.30, current: 0.24), .above)
        XCTAssertEqual(PriceAlertRules.suggestedDirection(target: 0.20, current: 0.24), .below)
    }

    func testDistancePercent() throws {
        XCTAssertEqual(try XCTUnwrap(PriceAlertRules.distancePercent(target: 0.30, current: 0.24)), 25, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(PriceAlertRules.distancePercent(target: 0.18, current: 0.24)), -25, accuracy: 1e-9)
        XCTAssertNil(PriceAlertRules.distancePercent(target: 1, current: 0))
    }

    // MARK: Validation

    func testValidateRejectsNonPositiveTargets() {
        XCTAssertEqual(PriceAlertRules.validate(target: 0, current: 0.24, direction: .above), .notPositive)
        XCTAssertEqual(PriceAlertRules.validate(target: -1, current: nil, direction: .below), .notPositive)
        XCTAssertEqual(PriceAlertRules.validate(target: .nan, current: 0.24, direction: .above), .notPositive)
        XCTAssertEqual(PriceAlertRules.validate(target: .infinity, current: 0.24, direction: .above), .notPositive)
    }

    func testValidateRejectsAlreadyCrossedTargets() {
        XCTAssertEqual(PriceAlertRules.validate(target: 0.20, current: 0.24, direction: .above), .alreadyAbove)
        XCTAssertEqual(PriceAlertRules.validate(target: 0.24, current: 0.24, direction: .above), .alreadyAbove)
        XCTAssertEqual(PriceAlertRules.validate(target: 0.30, current: 0.24, direction: .below), .alreadyBelow)
        XCTAssertEqual(PriceAlertRules.validate(target: 0.24, current: 0.24, direction: .below), .alreadyBelow)
    }

    func testValidateAcceptsTargetsStillAhead() {
        XCTAssertNil(PriceAlertRules.validate(target: 0.30, current: 0.24, direction: .above))
        XCTAssertNil(PriceAlertRules.validate(target: 0.20, current: 0.24, direction: .below))
        // No price yet: only the target itself can be judged.
        XCTAssertNil(PriceAlertRules.validate(target: 0.20, current: nil, direction: .above))
    }

    func testEveryProblemHasAMessage() {
        for problem in [PriceAlertRules.Problem.notPositive, .alreadyAbove, .alreadyBelow] {
            XCTAssertFalse(problem.message.isEmpty)
        }
    }

    // MARK: Typing

    func testParse() {
        XCTAssertEqual(PriceAlertRules.parse("0.35"), 0.35)
        XCTAssertEqual(PriceAlertRules.parse(" 0,35 "), 0.35)
        XCTAssertEqual(PriceAlertRules.parse(".5"), 0.5)
        XCTAssertEqual(PriceAlertRules.parse("12"), 12)
        XCTAssertEqual(PriceAlertRules.parse("0"), 0)
        XCTAssertNil(PriceAlertRules.parse(""))
        XCTAssertNil(PriceAlertRules.parse("."))
        XCTAssertNil(PriceAlertRules.parse("1.2.3"))
        XCTAssertNil(PriceAlertRules.parse("-1"))
        XCTAssertNil(PriceAlertRules.parse("1e5"))
        XCTAssertNil(PriceAlertRules.parse("abc"))
        XCTAssertNil(PriceAlertRules.parse("99999999999"))
    }

    func testFieldTextAndStepTargets() {
        XCTAssertEqual(PriceAlertRules.fieldText(0.35), "0.35")
        XCTAssertEqual(PriceAlertRules.fieldText(64_250), "64250")
        XCTAssertEqual(PriceAlertRules.fieldText(0.123456), "0.123456")
        XCTAssertEqual(PriceAlertRules.fieldText(PriceAlertRules.target(from: 0.2431, percent: 5)), "0.2553")
        XCTAssertEqual(PriceAlertRules.fieldText(PriceAlertRules.target(from: 0.2431, percent: -10)), "0.2188")
        XCTAssertEqual(PriceAlertRules.fieldText(PriceAlertRules.target(from: 64_250, percent: 10)), "70675")
        // Every chip gives a target that can be saved as is.
        for step in [-10.0, -5, 5, 10] {
            let target = PriceAlertRules.target(from: 0.2431, percent: step)
            XCTAssertNil(PriceAlertRules.validate(target: target, current: 0.2431, direction: step > 0 ? .above : .below))
        }
    }

    // MARK: Store

    func testStoreRoundTrip() throws {
        let store = PriceAlertStore(defaults: defaults)
        XCTAssertTrue(store.alerts.isEmpty)
        XCTAssertFalse(store.hasArmedAlerts)

        let up = try XCTUnwrap(store.add(token: .trx, direction: .above, targetUSD: 0.35))
        let down = try XCTUnwrap(store.add(token: .usdt, direction: .below, targetUSD: 0.99))
        store.markFired(down.id, at: Date(timeIntervalSince1970: 1_795_000_123))

        let reopened = PriceAlertStore(defaults: defaults)
        XCTAssertEqual(reopened.alerts, store.alerts)
        XCTAssertEqual(reopened.alerts.map(\.id), [up.id, down.id])
        XCTAssertEqual(reopened.alerts[1].firedAt, Date(timeIntervalSince1970: 1_795_000_123))
        XCTAssertEqual(reopened.alerts(for: .trx).map(\.id), [up.id])
        XCTAssertTrue(reopened.hasArmedAlerts)
    }

    func testStoresAreIsolatedByDefaults() throws {
        PriceAlertStore(defaults: defaults).add(token: .trx, direction: .above, targetUSD: 0.35)
        let otherName = suiteName + ".other"
        let other = try XCTUnwrap(UserDefaults(suiteName: otherName))
        defer { other.removePersistentDomain(forName: otherName) }
        XCTAssertTrue(PriceAlertStore(defaults: other).alerts.isEmpty)
    }

    func testAddRejectsBadTargets() {
        let store = PriceAlertStore(defaults: defaults)
        XCTAssertNil(store.add(token: .trx, direction: .above, targetUSD: 0))
        XCTAssertNil(store.add(token: .trx, direction: .above, targetUSD: -3))
        XCTAssertNil(store.add(token: .trx, direction: .above, targetUSD: .nan))
        XCTAssertTrue(store.alerts.isEmpty)
    }

    func testCap() {
        let store = PriceAlertStore(defaults: defaults)
        for index in 0 ..< PriceAlertStore.limit {
            XCTAssertFalse(store.isFull)
            XCTAssertNotNil(store.add(token: .trx, direction: .above, targetUSD: 1 + Double(index)))
        }
        XCTAssertTrue(store.isFull)
        XCTAssertNil(store.add(token: .trx, direction: .above, targetUSD: 99))
        XCTAssertEqual(store.alerts.count, PriceAlertStore.limit)
        XCTAssertEqual(PriceAlertStore(defaults: defaults).alerts.count, PriceAlertStore.limit)

        store.delete(store.alerts[0].id)
        XCTAssertFalse(store.isFull)
        XCTAssertNotNil(store.add(token: .trx, direction: .above, targetUSD: 99))
    }

    func testUpdateAndDelete() throws {
        let store = PriceAlertStore(defaults: defaults)
        var alert = try XCTUnwrap(store.add(token: .trx, direction: .above, targetUSD: 0.35))
        alert.targetUSD = 0.15
        alert.direction = .below
        store.update(alert)
        XCTAssertEqual(PriceAlertStore(defaults: defaults).alerts, [alert])

        // An alert the store doesn't have is not added by an update.
        store.update(self.alert(.above, 5))
        XCTAssertEqual(store.alerts, [alert])

        store.delete(alert.id)
        XCTAssertTrue(store.alerts.isEmpty)
        XCTAssertTrue(PriceAlertStore(defaults: defaults).alerts.isEmpty)
    }

    func testOneShotAndRearm() throws {
        let store = PriceAlertStore(defaults: defaults)
        let alert = try XCTUnwrap(store.add(token: .trx, direction: .above, targetUSD: 0.35))
        let moment = Date(timeIntervalSince1970: 1_795_000_500)

        XCTAssertTrue(store.evaluate(prices: [.trx: 0.30], now: moment).isEmpty)
        XCTAssertTrue(store.hasArmedAlerts)

        let fired = store.evaluate(prices: [.trx: 0.36], now: moment)
        XCTAssertEqual(fired.map(\.id), [alert.id])
        XCTAssertEqual(fired.first?.firedAt, moment)
        XCTAssertFalse(store.hasArmedAlerts)
        XCTAssertEqual(PriceAlertStore(defaults: defaults).alerts.first?.firedAt, moment, "firing is saved")

        // Still over the target, and again after a dip: it stays quiet.
        XCTAssertTrue(store.evaluate(prices: [.trx: 0.37]).isEmpty)
        XCTAssertTrue(store.evaluate(prices: [.trx: 0.30]).isEmpty)
        XCTAssertTrue(store.evaluate(prices: [.trx: 0.40]).isEmpty)

        store.rearm(alert.id)
        XCTAssertTrue(store.hasArmedAlerts)
        XCTAssertNil(PriceAlertStore(defaults: defaults).alerts.first?.firedAt, "re-arming is saved")
        XCTAssertTrue(store.evaluate(prices: [.trx: 0.30]).isEmpty)
        XCTAssertEqual(store.evaluate(prices: [.trx: 0.35]).map(\.id), [alert.id])
    }

    func testMarkFiredKeepsTheFirstDate() throws {
        let store = PriceAlertStore(defaults: defaults)
        let alert = try XCTUnwrap(store.add(token: .trx, direction: .above, targetUSD: 0.35))
        let first = Date(timeIntervalSince1970: 1_795_000_000)
        store.markFired(alert.id, at: first)
        store.markFired(alert.id, at: first.addingTimeInterval(60))
        XCTAssertEqual(store.alerts.first?.firedAt, first)
    }

    func testEvaluateReturnsEachDueAlertOnce() throws {
        let store = PriceAlertStore(defaults: defaults)
        let trxUp = try XCTUnwrap(store.add(token: .trx, direction: .above, targetUSD: 0.30))
        let trxDown = try XCTUnwrap(store.add(token: .trx, direction: .below, targetUSD: 0.10))
        let trxSame = try XCTUnwrap(store.add(token: .trx, direction: .above, targetUSD: 0.30))
        let usdtDown = try XCTUnwrap(store.add(token: .usdt, direction: .below, targetUSD: 0.99))

        let fired = store.evaluate(prices: [.trx: 0.31, .usdt: 0.98])
        XCTAssertEqual(fired.map(\.id), [trxUp.id, trxSame.id, usdtDown.id])
        XCTAssertEqual(Set(fired.map(\.id)).count, fired.count)
        XCTAssertTrue(fired.allSatisfy { !$0.isArmed })

        XCTAssertTrue(store.evaluate(prices: [.trx: 0.31, .usdt: 0.98]).isEmpty)
        XCTAssertEqual(store.alerts.filter(\.isArmed).map(\.id), [trxDown.id])
    }

    func testClear() {
        let store = PriceAlertStore(defaults: defaults)
        store.add(token: .trx, direction: .above, targetUSD: 0.35)
        store.clear()
        XCTAssertTrue(store.alerts.isEmpty)
        XCTAssertNil(defaults.data(forKey: PriceAlertStore.storageKey))
        XCTAssertTrue(PriceAlertStore(defaults: defaults).alerts.isEmpty)
    }

    func testUnreadableRowsAreDroppedNotTheWholeList() throws {
        let good = alert(.above, 0.35)
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode([good, alert(.below, 0.1)])) as? [[String: Any]])
        rows[1]["token"] = "dogecoin"
        defaults.set(try JSONSerialization.data(withJSONObject: rows), forKey: PriceAlertStore.storageKey)
        XCTAssertEqual(PriceAlertStore(defaults: defaults).alerts, [good])

        defaults.set(Data("not json".utf8), forKey: PriceAlertStore.storageKey)
        XCTAssertTrue(PriceAlertStore(defaults: defaults).alerts.isEmpty)
    }

    func testAlertCodableRoundTrip() throws {
        let original = alert(.usdt, .below, 0.9975, firedAt: Date(timeIntervalSince1970: 1_795_000_777))
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(PriceAlert.self, from: data), original)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["token"] as? String, "usdt")
        XCTAssertEqual(json["direction"] as? String, "below")
    }

    // MARK: The check

    func testCheckPostsEachFiredAlertOnceWithTheCurrentPrice() async throws {
        let store = PriceAlertStore(defaults: defaults)
        let notifier = FakeNotifier()
        let up = try XCTUnwrap(store.add(token: .trx, direction: .above, targetUSD: 0.30))
        store.add(token: .trx, direction: .below, targetUSD: 0.10)

        let quiet = await checkPriceAlerts(store: store, prices: [.trx: 0.25], notifier: notifier)
        XCTAssertTrue(quiet.isEmpty)
        XCTAssertTrue(notifier.posted.isEmpty)

        let fired = await checkPriceAlerts(store: store, prices: [.trx: 0.31], notifier: notifier)
        XCTAssertEqual(fired.map(\.id), [up.id])
        XCTAssertEqual(notifier.posted.map(\.alert.id), [up.id])
        XCTAssertEqual(notifier.posted.first?.price, 0.31)

        await checkPriceAlerts(store: store, prices: [.trx: 0.32], notifier: notifier)
        XCTAssertEqual(notifier.posted.count, 1, "one-shot: no second notification")
    }

    func testNotificationShowsOnlyTheCoinAndPrice() {
        let above = AlertNotifier.content(for: alert(.above, 0.35), price: 0.3512)
        XCTAssertTrue(above.title.contains("TRX"))
        XCTAssertTrue(above.title.contains(USDPrice.price(0.35)))
        XCTAssertTrue(above.body.contains(USDPrice.price(0.3512)))
        XCTAssertEqual(above.threadIdentifier, "price-alert.trx")
        XCTAssertEqual(above.categoryIdentifier, AlertNotifier.category)
        XCTAssertTrue(above.userInfo.isEmpty)

        let below = AlertNotifier.content(for: alert(.usdt, .below, 0.99), price: 0.98)
        XCTAssertTrue(below.title.contains("USDT"))
        XCTAssertNotEqual(below.threadIdentifier, above.threadIdentifier)
    }
}
