import Foundation

/// What the app shares with its widgets through the App Group. Only public
/// data: the wallet address (it's on the blockchain anyway), the last known
/// balances, and the user's "hide balance" choice. Never keys or the phrase.
enum SharedWallet {
    static let appGroup = Brand.appGroup
    static let widgetKind = "KestrelBalance"
    static let hideBalanceKey = "wallet.hideBalance"
    /// Transfers the large widget lists.
    static let recentCount = 4

    nonisolated(unsafe) static let defaults: UserDefaults = UserDefaults(suiteName: appGroup) ?? .standard

    struct Snapshot: Codable, Equatable, Sendable {
        var address: String
        var usdtUnits: UInt64
        var trxSun: Int64
        var updatedAt: Date
        /// The latest few USDT transfers, for the large widget (public chain data).
        /// Optional so snapshots saved by older builds still decode.
        var recent: [TokenTransfer]?
    }

    private static let snapshotKey = "wallet.snapshot"

    static var snapshot: Snapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static var isBalanceHidden: Bool { defaults.bool(forKey: hideBalanceKey) }

    static func clear() {
        defaults.removeObject(forKey: snapshotKey)
        defaults.removeObject(forKey: hideBalanceKey)
    }
}
