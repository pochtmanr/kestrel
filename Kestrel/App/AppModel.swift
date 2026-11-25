import Observation
import SwiftUI
import WidgetKit

/// App-wide state: which stage of setup/unlock the user is in, and the
/// wallet's on-chain data.
@MainActor
@Observable
final class AppModel {
    enum Stage { case setup, createPIN, locked, unlocked }

    private(set) var stage: Stage = .setup
    private(set) var address: String?

    // On-chain data for the home screen.
    private(set) var usdtUnits: UInt64 = 0
    private(set) var trxSun: Int64 = 0
    private(set) var history: [TokenTransfer] = []
    private(set) var lastRefresh: Date?
    private(set) var refreshError: String?
    /// After a 429, no TronGrid reads until this time; the wait doubles on each
    /// repeat (30 s → 4 min) and resets on the next success.
    private var backoffUntil: Date?
    private var backoff: TimeInterval = 0

    /// Market prices (USD). Empty until loaded or when the price source is down.
    private(set) var prices: [TokenKind: TokenPrice] = [:]
    /// The full market picture behind `prices`: sparklines and stats for the Currencies screen.
    private(set) var markets: [TokenKind: MarketQuote] = [:]
    /// When `markets` last arrived (nil = never).
    private(set) var marketsUpdatedAt: Date?
    private var pricesFetchedAt: Date?
    /// Coin screen charts, kept a few minutes per coin and range.
    private var charts: [ChartKey: (points: [PricePoint], fetched: Date)] = [:]
    private struct ChartKey: Hashable { let token: TokenKind; let range: PriceRange }

    enum Tab: Hashable { case wallet, activity }
    var selectedTab: Tab = .wallet

    /// A send to present over whichever tab is showing (nil = none).
    var sendRequest: SendRequest?
    struct SendRequest: Identifiable {
        let id = UUID()
        var recipient = ""
    }

    let tron = TronClient()
    /// Full, cached history for the Activity screen (`history` stays the home screen's 25).
    let activity = ActivityStore()
    private let priceClient = PriceClient()

    init() {
        reload()
    }

    var hasGasForTransfer: Bool { trxSun >= TRX.minimumForTransferSun }

    /// Re-derive the stage from the Keychain (after setup, PIN or wipe).
    /// Sample data instead of the network (App Store screenshots, debug only).
    private(set) var isDemo = false

    #if DEBUG
    /// Shows onboarding without touching the Keychain (screenshots, UI checks).
    func showOnboardingPreview() { stage = .setup }

    func loadDemo() {
        isDemo = true
        address = "TV2QjYfd8Js2JhDfqKzZMLBscYtBkxU9ek"
        usdtUnits = 2_481_350_000
        trxSun = 48_200_000
        let me = address!
        let now = Date.now
        history = [
            TokenTransfer(id: "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2", date: now.addingTimeInterval(-1_800), from: "TMuA6YqfCeX8EhbfYEg5y7S4DqzSJireY9", to: me, units: 500_000_000),
            TokenTransfer(id: "b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3", date: now.addingTimeInterval(-26_000), from: me, to: "TDAeAFiB38L4mCAE8AhGRN7QUbG7DUv8tV", units: 120_000_000),
            TokenTransfer(id: "c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4", date: now.addingTimeInterval(-90_000), from: "TLa2f6VPqDgRE67v1736s7bJ8Ray5wYjU7", to: me, units: 1_250_000_000),
            TokenTransfer(id: "d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5", date: now.addingTimeInterval(-190_000), from: me, to: "TXJgMdjVX5dKiQaUi9QobwNxtSQaFqccvd", units: 75_500_000),
        ]
        activity.loadDemo(address: me, now: now)
        lastRefresh = now
        markets = MarketDemo.quotes
        prices = markets.mapValues(\.tokenPrice)
        marketsUpdatedAt = now
        stage = .unlocked
        // `-activity` with `-demo`: open on the Activity tab (screenshots, UI checks).
        if CommandLine.arguments.contains("-activity") { selectedTab = .activity }
    }
    #endif

    func reload() {
        address = (try? WalletVault.keys())?.address
        activity.configure(address: address)
        if address == nil {
            stage = .setup
        } else if !PinStore.isSet {
            stage = .createPIN
        } else if stage != .unlocked {
            stage = .locked
        }
    }

    func walletCreated() {
        selectedTab = .wallet
        reload()
    }

    func pinCreated() {
        stage = .unlocked
    }

    func unlock() {
        guard stage == .locked else { return }
        stage = .unlocked
    }

    func lock() {
        guard stage == .unlocked else { return }
        stage = .locked
    }

    func resetPIN() {
        PinStore.erase()
        Biometrics.isEnabled = false
        stage = .createPIN
    }

    func eraseWallet() {
        activity.clear()
        SharedWallet.clear()
        WidgetCenter.shared.reloadTimelines(ofKind: SharedWallet.widgetKind)
        WalletVault.erase()
        PinStore.erase()
        Biometrics.isEnabled = false
        usdtUnits = 0
        trxSun = 0
        history = []
        stage = .setup
        reload()
    }

    func refresh() async {
        guard let address, !isDemo else { return }
        if let backoffUntil, Date.now < backoffUntil { return }
        async let usdt = tron.usdtBalance(of: address)
        async let trx = tron.trxBalance(of: address)
        async let transfers = tron.usdtHistory(of: address, limit: 25)
        do {
            let (u, t, h) = try await (usdt, trx, transfers)
            usdtUnits = u
            trxSun = t
            history = h
            lastRefresh = .now
            refreshError = nil
            backoff = 0
            backoffUntil = nil
            shareWithWidgets(address: address)
            // Its own errors stay in `activity.error`: the balance is fine.
            await activity.sync()
        } catch TronClient.Failure.rateLimited {
            backoff = min(max(backoff * 2, 30), 240)
            backoffUntil = .now.addingTimeInterval(backoff)
            refreshError = TronClient.Failure.rateLimited.errorDescription
        } catch {
            refreshError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Prices at most once a minute (the free endpoint is rate-limited).
    /// A failure keeps the last prices, or none: they're never required.
    func refreshPrices() async {
        guard !isDemo else { return }
        if let pricesFetchedAt, Date.now.timeIntervalSince(pricesFetchedAt) < 60 { return }
        pricesFetchedAt = .now
        guard let fresh = try? await priceClient.markets(), !fresh.isEmpty else { return }
        markets = fresh
        prices = fresh.mapValues(\.tokenPrice)
        marketsUpdatedAt = .now
    }

    /// A cached chart, if any (stale or not), for drawing straight away.
    func cachedChart(for token: TokenKind, range: PriceRange) -> [PricePoint]? {
        charts[ChartKey(token: token, range: range)]?.points
    }

    /// Price history for the coin screen. Served from cache for 5 minutes;
    /// on a failure the stale copy is returned when there is one.
    func chart(for token: TokenKind, range: PriceRange) async throws -> [PricePoint] {
        let key = ChartKey(token: token, range: range)
        #if DEBUG
        if isDemo { return MarketDemo.chart(for: token, range: range) }
        #endif
        if let cached = charts[key], Date.now.timeIntervalSince(cached.fetched) < 300 { return cached.points }
        do {
            let points = try await priceClient.chart(for: token, range: range)
            charts[key] = (points, .now)
            return points
        } catch {
            if let stale = charts[key] { return stale.points }
            throw error
        }
    }

    /// Hand the fresh balance to the home/lock screen widgets, reloading them
    /// only when something they display actually changed.
    private func shareWithWidgets(address: String) {
        let previous = SharedWallet.snapshot
        let changed = previous?.address != address || previous?.usdtUnits != usdtUnits || previous?.trxSun != trxSun
        SharedWallet.save(.init(address: address, usdtUnits: usdtUnits, trxSun: trxSun, updatedAt: .now))
        if changed { WidgetCenter.shared.reloadTimelines(ofKind: SharedWallet.widgetKind) }
    }
}
