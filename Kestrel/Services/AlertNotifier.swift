import BackgroundTasks
import Foundation
@preconcurrency import UserNotifications

/// Whether the system will show our notifications.
enum AlertAuthorization: Equatable, Sendable {
    case notDetermined, denied, authorized
}

/// What price alerts need from the notification centre. A protocol so the
/// check can be tested without the system (and without a permission prompt).
protocol PriceAlertNotifying: Sendable {
    func authorizationStatus() async -> AlertAuthorization
    /// Shows the system prompt the first time. True when notifications are allowed.
    @discardableResult func requestAuthorization() async -> Bool
    func post(_ alert: PriceAlert, price: Double) async
}

/// Local notifications for price alerts. Everything stays on the device, and
/// a notification says only the coin and its price: never a balance, an
/// address or what the holding is worth.
final class AlertNotifier: NSObject, PriceAlertNotifying, UNUserNotificationCenterDelegate, Sendable {
    static let shared = AlertNotifier()

    /// Marks our notifications, so the foreground banner applies to them alone.
    static let category = "price-alert"

    /// Call once at launch. Only sets the delegate (so an alert that fires
    /// while the app is open still shows a banner); it never asks for permission.
    static func install() {
        UNUserNotificationCenter.current().delegate = shared
    }

    func authorizationStatus() async -> AlertAuthorization {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .authorized
        @unknown default: .denied
        }
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func post(_ alert: PriceAlert, price: Double) async {
        let request = UNNotificationRequest(identifier: alert.id.uuidString, content: Self.content(for: alert, price: price), trigger: nil)
        // Not allowed, or the system refused: the alert still shows as reached in the app.
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// "TRX is above $0.3500" / "Now $0.3512". Built with `tr` so it speaks
    /// the language chosen in Settings.
    static func content(for alert: PriceAlert, price: Double) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let target = USDPrice.price(alert.targetUSD)
        switch alert.direction {
        case .above: content.title = tr("\(alert.token.symbol) is above \(target)")
        case .below: content.title = tr("\(alert.token.symbol) is below \(target)")
        }
        content.body = tr("Now \(USDPrice.price(price))")
        content.sound = .default
        content.threadIdentifier = "price-alert.\(alert.token.rawValue)"
        content.categoryIdentifier = category
        return content
    }

    // The system calls this off the main actor; the class holds no state.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Only price alerts get a banner over the open app; anything else keeps the system default.
        let ours = notification.request.content.categoryIdentifier == Self.category
        completionHandler(ours ? [.banner, .list, .sound] : [])
    }
}

/// Where the app checks alerts: after each price refresh, and from the
/// background refresh task.
enum PriceAlerts {
    /// Must also be listed under `BGTaskSchedulerPermittedIdentifiers` in the Info.plist.
    static let backgroundTaskID = "com.simnetiq.kestrel.price-alerts"
    /// iOS decides the real moment; this is only the earliest it may be.
    static let backgroundInterval: TimeInterval = 15 * 60

    /// Fires every alert the prices have reached, once each, and posts its notification.
    @MainActor
    @discardableResult
    static func check(store: PriceAlertStore, prices: [TokenKind: Double],
                      notifier: any PriceAlertNotifying = AlertNotifier.shared, now: Date = .now) async -> [PriceAlert] {
        let fired = store.evaluate(prices: prices, now: now)
        for alert in fired {
            guard let price = prices[alert.token] else { continue }
            await notifier.post(alert, price: price)
        }
        return fired
    }

    /// Asks iOS for a background refresh, but only while an alert is waiting;
    /// with none, any pending request is withdrawn. Call when the app goes to
    /// the background and at the end of each background run.
    @MainActor
    static func scheduleBackgroundRefresh(store: PriceAlertStore) {
        // Without the Info.plist entry the scheduler refuses the identifier.
        let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        guard permitted.contains(backgroundTaskID) else { return }
        guard store.hasArmedAlerts else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundTaskID)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: backgroundInterval)
        // Fails on the simulator and when Background App Refresh is off: alerts
        // are then checked only while the app is open, as the screen says.
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// The one call to make wherever prices have just refreshed.
@MainActor
@discardableResult
func checkPriceAlerts(store: PriceAlertStore, prices: [TokenKind: Double],
                      notifier: any PriceAlertNotifying = AlertNotifier.shared) async -> [PriceAlert] {
    await PriceAlerts.check(store: store, prices: prices, notifier: notifier)
}
