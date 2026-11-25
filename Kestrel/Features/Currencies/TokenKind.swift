import SwiftUI

/// Every coin the wallet knows. This is the registry the Currencies tab, the
/// coin screen and the market client iterate: a new coin is a new case here,
/// its metadata below, and a balance source in `AppModel.holding(of:)`.
enum TokenKind: String, CaseIterable, Hashable, Sendable {
    case usdt, trx

    var symbol: String {
        switch self {
        case .usdt: "USDT"
        case .trx: "TRX"
        }
    }

    var name: String {
        switch self {
        case .usdt: "Tether USD"
        case .trx: "TRON"
        }
    }

    /// The coin's id on CoinGecko (prices, charts, market data).
    var coingeckoID: String {
        switch self {
        case .usdt: "tether"
        case .trx: "tron"
        }
    }

    var network: LocalizedStringKey {
        switch self {
        case .usdt: "TRON · TRC-20"
        case .trx: "TRON"
        }
    }

    var usedFor: LocalizedStringKey {
        switch self {
        case .usdt: "Payments and savings"
        case .trx: "Network fees"
        }
    }

    var color: Color {
        switch self {
        case .usdt: Theme.Palette.usdt
        case .trx: Theme.Palette.trx
        }
    }

    /// Extra words people search by.
    var searchTerms: [String] {
        switch self {
        case .usdt: ["tether", "dollar", "stablecoin", "trc20", "trc-20"]
        case .trx: ["tron", "fee", "fees", "energy", "gas", "fuel"]
        }
    }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return true }
        return ([symbol, name] + searchTerms).contains { $0.lowercased().contains(needle) }
    }
}

struct TokenIcon: View {
    let token: TokenKind
    var size: CGFloat = 42

    var body: some View {
        Circle()
            .fill(token.color)
            .overlay {
                switch token {
                case .usdt:
                    Text(verbatim: "₮").font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(.white)
                case .trx:
                    Image(systemName: "triangle.fill")
                        .font(.system(size: size * 0.36, weight: .bold))
                        .rotationEffect(.degrees(180))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// How much of a coin the wallet holds, ready to display.
struct Holding {
    let token: TokenKind
    let amount: String
    /// The holding as a plain number, for multiplying by a price.
    let quantity: Double

    /// USDT counts at $1 before a price arrives; other coins have no value without one.
    func usdValue(_ price: TokenPrice?) -> Double? {
        guard let price else { return token == .usdt ? quantity : nil }
        return quantity * price.usd
    }
}

extension AppModel {
    func holding(of token: TokenKind) -> Holding {
        switch token {
        case .usdt: Holding(token: token, amount: USDT.format(units: usdtUnits), quantity: Double(usdtUnits) / 1_000_000)
        case .trx: Holding(token: token, amount: TRX.format(sun: trxSun), quantity: Double(trxSun) / 1_000_000)
        }
    }

    /// Transfers the TRX balance can pay for, at the no-energy worst case.
    var transfersLeft: Int64 { max(0, trxSun / TRX.minimumForTransferSun) }

    var fuelLevel: FuelLevel {
        switch transfersLeft {
        case 0: .empty
        case 1...2: .low
        default: .good
        }
    }
}

/// How much sending the TRX balance still pays for.
enum FuelLevel {
    case good, low, empty

    var color: Color {
        switch self {
        case .good: Theme.Palette.textTertiary
        case .low: Theme.Palette.warning
        case .empty: Theme.Palette.danger
        }
    }

    func note(transfersLeft: Int64) -> String {
        switch self {
        case .empty: String(localized: "Add TRX to send USDT")
        case .low: String(localized: "Low: about \(transfersLeft) transfers left")
        case .good: String(localized: "Pays network fees")
        }
    }
}

/// Dollar values in the same fixed "1,234.56" style as `USDT.format`, whatever
/// the device region, so a balance and its value never disagree on separators.
enum USDPrice {
    static let locale = Locale(identifier: "en_US")

    static func format(_ value: Double, digits: Int = 2) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(digits)).locale(locale))
    }

    /// A price: four decimals under $10 (so a stablecoin's $1.0002 shows), two above.
    static func price(_ usd: Double) -> String {
        format(usd, digits: usd < 10 ? 4 : 2)
    }

    /// "$184.2B", for market cap and volume.
    static func compact(_ value: Double) -> String {
        // Currency `.notation(.compactName)` is iOS 18+, so the suffix is ours.
        let scales: [(Double, String)] = [(1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")]
        guard let (scale, suffix) = scales.first(where: { abs(value) >= $0.0 }) else { return format(value) }
        return format(value / scale, digits: abs(value / scale) < 100 ? 2 : 1) + suffix
    }

    /// "+2.37%".
    static func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always()).locale(locale))
    }

    /// "+$5.18" / "−$5.18".
    static func signed(_ value: Double) -> String {
        (value < 0 ? "−" : "+") + format(abs(value))
    }
}

/// "+2.37%" in green, "−1.20%" in red.
struct PriceChange: View {
    let percent: Double

    var body: some View {
        Text(verbatim: USDPrice.percent(percent))
            .foregroundStyle(percent >= 0 ? Theme.Palette.positive : Theme.Palette.danger)
    }
}
