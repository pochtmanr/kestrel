import Foundation
import Observation

/// The user's price alerts, kept on this device only (UserDefaults, one JSON
/// value). Nothing here is secret and nothing leaves the phone: an alert is a
/// coin, a direction and a price.
@MainActor
@Observable
final class PriceAlertStore {
    static let storageKey = "priceAlerts.v1"
    /// Across all coins. Each check is one price lookup whatever the count;
    /// the cap keeps the list (and a burst of notifications) manageable.
    static let limit = 20

    /// Oldest first.
    private(set) var alerts: [PriceAlert] = []

    @ObservationIgnored private let defaults: UserDefaults

    /// Tests pass their own `UserDefaults(suiteName:)`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        alerts = Self.load(from: defaults)
    }

    var isFull: Bool { alerts.count >= Self.limit }
    var hasArmedAlerts: Bool { alerts.contains(where: \.isArmed) }

    func alerts(for token: TokenKind) -> [PriceAlert] {
        alerts.filter { $0.token == token }
    }

    /// nil when the list is full or the target isn't a positive number.
    @discardableResult
    func add(token: TokenKind, direction: PriceAlert.Direction, targetUSD: Double, now: Date = .now) -> PriceAlert? {
        guard !isFull, targetUSD.isFinite, targetUSD > 0 else { return nil }
        let alert = PriceAlert(token: token, direction: direction, targetUSD: targetUSD, createdAt: now)
        alerts.append(alert)
        save()
        return alert
    }

    /// Replaces the alert with the same id, exactly as given.
    func update(_ alert: PriceAlert) {
        guard let index = alerts.firstIndex(where: { $0.id == alert.id }), alerts[index] != alert else { return }
        alerts[index] = alert
        save()
    }

    func delete(_ id: PriceAlert.ID) {
        guard alerts.contains(where: { $0.id == id }) else { return }
        alerts.removeAll { $0.id == id }
        save()
    }

    /// A fired alert waits for its price again.
    func rearm(_ id: PriceAlert.ID) {
        guard let index = alerts.firstIndex(where: { $0.id == id }), !alerts[index].isArmed else { return }
        alerts[index].firedAt = nil
        save()
    }

    func markFired(_ id: PriceAlert.ID, at date: Date = .now) {
        guard let index = alerts.firstIndex(where: { $0.id == id }), alerts[index].isArmed else { return }
        alerts[index].firedAt = date
        save()
    }

    /// Marks every alert the prices have reached as fired and returns them, as
    /// they are now (with `firedAt` set). An alert is returned once: the next
    /// call skips it until it's re-armed.
    func evaluate(prices: [TokenKind: Double], now: Date = .now) -> [PriceAlert] {
        let due = Set(PriceAlertRules.due(alerts, prices: prices).map(\.id))
        guard !due.isEmpty else { return [] }
        var fired: [PriceAlert] = []
        for index in alerts.indices where due.contains(alerts[index].id) {
            alerts[index].firedAt = now
            fired.append(alerts[index])
        }
        save()
        return fired
    }

    /// Wallet erase: the next wallet starts with no alerts.
    func clear() {
        alerts = []
        defaults.removeObject(forKey: Self.storageKey)
    }

    // MARK: Storage

    private func save() {
        guard let data = try? JSONEncoder().encode(alerts) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func load(from defaults: UserDefaults) -> [PriceAlert] {
        guard let data = defaults.data(forKey: storageKey),
              let rows = try? JSONDecoder().decode([Lossy].self, from: data) else { return [] }
        return Array(rows.compactMap(\.alert).prefix(limit))
    }

    /// One unreadable row (a coin this version doesn't know) is dropped
    /// instead of taking the whole list with it.
    private struct Lossy: Decodable {
        let alert: PriceAlert?
        init(from decoder: Decoder) throws { alert = try? PriceAlert(from: decoder) }
    }
}
