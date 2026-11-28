import Foundation

/// "Tell me when TRX goes above $0.35." One-shot: it fires once, then waits
/// until the user re-arms it, so a price hovering at the target can't spam.
struct PriceAlert: Codable, Identifiable, Equatable, Sendable {
    enum Direction: String, Codable, CaseIterable, Sendable {
        case above, below
    }

    let id: UUID
    var token: TokenKind
    var direction: Direction
    var targetUSD: Double
    let createdAt: Date
    /// When it went off; nil while it's still waiting.
    var firedAt: Date?

    var isArmed: Bool { firedAt == nil }

    init(id: UUID = UUID(), token: TokenKind, direction: Direction, targetUSD: Double,
         createdAt: Date = .now, firedAt: Date? = nil) {
        self.id = id
        self.token = token
        self.direction = direction
        self.targetUSD = targetUSD
        self.createdAt = createdAt
        self.firedAt = firedAt
    }

    // The coin is stored by its raw value, so the registry (`TokenKind`)
    // doesn't have to be Codable for alerts to be saved.
    private enum CodingKeys: String, CodingKey {
        case id, token, direction, targetUSD, createdAt, firedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let raw = try container.decode(String.self, forKey: .token)
        guard let token = TokenKind(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .token, in: container, debugDescription: "Unknown coin \(raw)")
        }
        self.token = token
        direction = try container.decode(Direction.self, forKey: .direction)
        targetUSD = try container.decode(Double.self, forKey: .targetUSD)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        firedAt = try container.decodeIfPresent(Date.self, forKey: .firedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(token.rawValue, forKey: .token)
        try container.encode(direction, forKey: .direction)
        try container.encode(targetUSD, forKey: .targetUSD)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(firedAt, forKey: .firedAt)
    }
}

/// The alert maths, free of storage and UI so it can be tested on its own.
enum PriceAlertRules {
    /// Beyond any real coin price; keeps a slipped finger from saving nonsense.
    static let maxTargetUSD: Double = 10_000_000

    enum Problem: Equatable, Sendable {
        case notPositive
        /// An "above" alert whose target the price has already reached.
        case alreadyAbove
        /// A "below" alert whose target the price has already reached.
        case alreadyBelow

        var message: String {
            switch self {
            case .notPositive: tr("Enter a price above zero.")
            case .alreadyAbove: tr("The price is already at or above this target.")
            case .alreadyBelow: tr("The price is already at or below this target.")
            }
        }
    }

    /// Reaching the target exactly counts as crossing it.
    static func isDue(_ alert: PriceAlert, price: Double) -> Bool {
        guard alert.isArmed, price.isFinite, price > 0 else { return false }
        switch alert.direction {
        case .above: return price >= alert.targetUSD
        case .below: return price <= alert.targetUSD
        }
    }

    /// Armed alerts whose target the given prices have reached. A coin
    /// without a price is skipped: no price is not a price of zero.
    static func due(_ alerts: [PriceAlert], prices: [TokenKind: Double]) -> [PriceAlert] {
        alerts.filter { alert in
            guard let price = prices[alert.token] else { return false }
            return isDue(alert, price: price)
        }
    }

    /// A target over the current price is something to rise to; under it, to fall to.
    static func suggestedDirection(target: Double, current: Double) -> PriceAlert.Direction {
        target >= current ? .above : .below
    }

    /// nil = fine to save. Without a current price only the target itself is checked.
    static func validate(target: Double, current: Double?, direction: PriceAlert.Direction) -> Problem? {
        guard target.isFinite, target > 0 else { return .notPositive }
        guard let current, current.isFinite, current > 0 else { return nil }
        switch direction {
        case .above: return current >= target ? .alreadyAbove : nil
        case .below: return current <= target ? .alreadyBelow : nil
        }
    }

    /// Distance from the current price to the target, in percent (+ = target is higher).
    static func distancePercent(target: Double, current: Double) -> Double? {
        guard current.isFinite, current > 0 else { return nil }
        return (target - current) / current * 100
    }

    // MARK: Typing a price

    /// What the user typed as a number: digits with one optional "." or ",".
    /// nil for anything else (zero and negatives are `validate`'s business).
    static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard (1 ... 2).contains(parts.count),
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              parts.contains(where: { !$0.isEmpty }),
              let value = Double(cleaned), value.isFinite, value <= maxTargetUSD else { return nil }
        return value
    }

    /// A price as plain text for the field: "0.2553", "64250", no grouping.
    static func fieldText(_ value: Double) -> String {
        var text = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// The current price moved by `percent`, rounded the way prices are shown
    /// (four decimals under $10, two above).
    static func target(from current: Double, percent: Double) -> Double {
        let raw = current * (1 + percent / 100)
        let scale: Double = raw < 10 ? 10_000 : 100
        return (raw * scale).rounded() / scale
    }
}
