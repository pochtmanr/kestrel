import Charts
import SwiftUI
import WidgetKit

/// Screens the home (and the coin screens) push.
enum HomeRoute: Hashable {
    case receive, fees, settings, currencies
    case coin(TokenKind)
    /// Receive opened for a specific coin (TRX from "Add TRX"); `.receive` is USDT.
    case receiveToken(TokenKind)
}

/// Where a `HomeRoute` leads. Pushed screens are full pages: the tab bar
/// steps aside so their own bottom buttons (Copy, Share…) sit where thumbs are.
struct RouteDestination: View {
    let route: HomeRoute

    var body: some View {
        Group {
            switch route {
            case .receive: DepositView()
            case .fees: NetworkFeeInfoView()
            case .settings: SettingsView()
            case .currencies: CurrenciesView()
            case .coin(let token): CoinDetailView(token: token)
            case .receiveToken(let token): DepositView(token: token)
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }
}

/// The Wallet tab: who you are, what you have, and big cards that open
/// everything else. Cards zoom into their screens (iOS 18+).
struct WalletView: View {
    /// Shared with the tab root, which presents Send over every tab.
    let zoom: Namespace.ID

    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage(SharedWallet.hideBalanceKey, store: SharedWallet.defaults) private var hideBalance = false
    @State private var copied = false
    @State private var showSupport = false
    @State private var detail: TokenTransfer?
    @State private var path: [HomeRoute] = []
    #if DEBUG
    /// `onAppear` fires again on every pop back to home; the launch route must apply once.
    @State private var debugRouteApplied = false
    #endif
    static let sendZoomID = "send"

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    balance
                    primaryCards
                    activityCard
                    currenciesCard
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.bottom, 24)
                .readableWidth()
            }
            .scrollIndicators(.hidden)
            .background(Theme.Palette.background)
            .background(alignment: .top) { accentGlow }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HomeRoute.self) { route in
                RouteDestination(route: route).zoomDestination(id: route, in: zoom)
            }
            .refreshable { await app.refresh() }
            .onChange(of: hideBalance) { WidgetCenter.shared.reloadTimelines(ofKind: SharedWallet.widgetKind) }
            #if DEBUG
            .onAppear(perform: openDebugRoute)
            #endif
            .task {
                // Live balance while the home is open.
                while !Task.isCancelled {
                    async let prices: Void = app.refreshPrices()
                    await app.refresh()
                    await prices
                    try? await Task.sleep(for: .seconds(15))
                }
            }
            .sheet(item: $detail) { transfer in
                TransferDetailView(transfer: transfer, myAddress: app.address ?? "") { to in
                    detail = nil
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        app.sendRequest = .init(recipient: to)
                    }
                }
            }
        }
    }

    /// A faint light falling on the slate from above.
    private var accentGlow: some View {
        RadialGradient(colors: [Theme.Palette.accent.opacity(0.22), Theme.Palette.accent.opacity(0.05), .clear],
                       center: .top, startRadius: 0, endRadius: 420)
            .frame(height: 440)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }

    // MARK: Header and balance

    /// One control for "who am I" and "where are my settings": the wallet's
    /// disc in a glass pill, opening a menu. The address text left the header
    /// so the balance owns the top of the screen; the menu keeps it one tap away.
    private var header: some View {
        HStack(spacing: 12) {
            walletMenu
            Spacer(minLength: 8)
            SupportButton { showSupport = true }
        }
        .padding(.top, 8)
        .sheet(isPresented: $showSupport) { SupportChatSheet() }
    }

    private var walletMenu: some View {
        let address = app.address ?? ""
        return Menu {
            Section("Main wallet") {
                Button(action: copyAddress) {
                    Text("Copy address")
                    Text(verbatim: address.shortAddress)
                    Image(systemName: "doc.on.doc")
                }
                .disabled(app.address == nil)
            }
            Button {
                Haptics.tap()
                path.append(.settings)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        } label: {
            HStack(spacing: 6) {
                WalletBadge(address: address, size: 36)
                // Swaps to a tick for a moment after a copy: the menu is gone
                // by then, so the pill is where the confirmation can live.
                Image(systemName: copied ? "checkmark" : "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(copied ? Theme.Palette.positive : Theme.Palette.textSecondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(minWidth: 14)
            }
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .frame(minHeight: 44)
            .chromeGlass(in: .capsule)
            .contentShape(.capsule)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Main wallet")
        .accessibilityValue(copied ? Text("Address copied") : Text(verbatim: address.shortAddress))
        .accessibilityHint("Copy your address or open Settings")
    }

    private var balance: some View {
        let parts = USDT.format(units: app.usdtUnits).split(separator: ".")
        return Button {
            withAnimation(.snappy) { hideBalance.toggle() }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text("Total balance")
                    Image(systemName: hideBalance ? "eye.slash" : "eye").font(.caption)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.Palette.textSecondary)

                Group {
                    if hideBalance {
                        Text("•••• $").font(Theme.Typography.amount(60, weight: .bold))
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(parts.first.map(String.init) ?? "0").font(Theme.Typography.amount(64, weight: .bold))
                            Text(".\(parts.count > 1 ? parts[1] : "00")")
                                .font(Theme.Typography.amount(30, weight: .bold))
                                .foregroundStyle(Theme.Palette.textSecondary)
                            Text("$")
                                .font(Theme.Typography.amount(30, weight: .bold))
                                .foregroundStyle(Theme.Palette.ember)
                        }
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    }
                }
                .foregroundStyle(Theme.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

                if let error = app.refreshError {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .animation(.snappy, value: app.usdtUnits)
        .accessibilityLabel(hideBalance ? "Balance hidden" : "Total balance \(USDT.format(units: app.usdtUnits)) dollars")
        .accessibilityHint(hideBalance ? "Shows your balance" : "Hides your balance")
    }

    // MARK: Send and Receive

    /// Side by side; stacked at accessibility text sizes so labels never truncate.
    private var primaryCards: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Button {
                Haptics.tap()
                app.sendRequest = .init()
            } label: {
                ActionCardLabel(title: "Send", subtitle: "USDT", symbol: "arrow.up.right", prominent: true, seed: 7)
            }
            .buttonStyle(CardPressStyle())
            .zoomSource(id: Self.sendZoomID, in: zoom)
            .accessibilityLabel("Send USDT")

            Button {
                Haptics.tap()
                path.append(.receive)
            } label: {
                ActionCardLabel(title: "Receive", subtitle: "TRON · TRC-20", symbol: "arrow.down.left", prominent: false, seed: 23)
            }
            .buttonStyle(CardPressStyle())
            .zoomSource(id: HomeRoute.receive, in: zoom)
            .accessibilityLabel("Receive USDT")
            .accessibilityHint("Shows your address and QR code")
        }
    }

    // MARK: Activity

    /// A balance line (up to 30 days) up top, the latest three transfers below.
    /// The whole card is one tap target that opens the Activity tab.
    private var activityCard: some View {
        Button {
            Haptics.tap()
            app.selectedTab = .activity
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Activity").font(.headline).foregroundStyle(Theme.Palette.textPrimary)
                    if !app.history.isEmpty {
                        Text("\(BalanceLineChart.span(for: app.history)) days").font(.caption.weight(.medium)).foregroundStyle(Theme.Palette.textTertiary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                if app.history.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No activity yet").font(.subheadline.weight(.semibold))
                        Text("Transfers show up here").font(.caption).foregroundStyle(Theme.Palette.textSecondary)
                    }
                    .foregroundStyle(Theme.Palette.textPrimary)
                } else {
                    BalanceLineChart(balance: app.usdtUnits, history: app.history, myAddress: app.address ?? "",
                                     days: BalanceLineChart.span(for: app.history))
                        .frame(height: 84)
                        .opacity(hideBalance ? 0.25 : 1)
                        .accessibilityHidden(true)
                    VStack(spacing: 0) {
                        ForEach(Array(app.history.prefix(3).enumerated()), id: \.element.id) { index, transfer in
                            if index > 0 { Divider().padding(.leading, 54) }
                            TransferRow(transfer: transfer, myAddress: app.address ?? "", hideAmount: hideBalance)
                                .padding(.vertical, 6)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .surface(cornerRadius: Theme.Radius.tile)
        }
        .buttonStyle(CardPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(activityLabel)
        .accessibilityHint("Opens the Activity tab")
        .accessibilityAddTraits(.isButton)
    }

    private var activityLabel: String {
        guard let last = app.history.first else { return String(localized: "Activity. No activity yet") }
        let outgoing = last.from == app.address
        let when = last.date.formatted(.relative(presentation: .named))
        if hideBalance {
            return outgoing ? String(localized: "Activity. Last: sent \(when)") : String(localized: "Activity. Last: received \(when)")
        }
        let amount = USDT.format(units: last.units)
        return outgoing ? String(localized: "Activity. Last: sent \(amount) USDT \(when)")
                        : String(localized: "Activity. Last: received \(amount) USDT \(when)")
    }

    // MARK: Currencies

    /// What the wallet holds: USDT, and the TRX that pays its network fees.
    private var currenciesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.tap()
                path.append(.currencies)
            } label: {
                HStack {
                    Text("Currencies")
                        .font(.headline)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 4)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .zoomSource(id: HomeRoute.currencies, in: zoom)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint("Opens all currencies, prices and charts")

            Button {
                Haptics.tap()
                path.append(.coin(.usdt))
            } label: {
                CurrencyRow(token: .usdt,
                            amount: USDT.format(units: app.usdtUnits),
                            value: Double(app.usdtUnits) / 1_000_000,
                            price: app.prices[.usdt],
                            hidden: hideBalance) { EmptyView() }
            }
            .buttonStyle(RowPressStyle())
            .accessibilityLabel(currencyLabel(.usdt, amount: USDT.format(units: app.usdtUnits), value: Double(app.usdtUnits) / 1_000_000))
            .zoomSource(id: HomeRoute.coin(.usdt), in: zoom)
            .accessibilityHint("Opens Tether USD")

            Divider().padding(.leading, 74).padding(.trailing, 18)

            Button {
                Haptics.tap()
                path.append(.coin(.trx))
            } label: {
                CurrencyRow(token: .trx,
                            amount: TRX.format(sun: app.trxSun),
                            value: Double(app.trxSun) / 1_000_000,
                            price: app.prices[.trx],
                            hidden: hideBalance) {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill").font(.caption2)
                        Text(feeNote)
                    }
                    .font(.caption.weight(app.fuelLevel == .good ? .regular : .semibold))
                    .foregroundStyle(app.fuelLevel.color)
                    .lineLimit(1)
                }
            }
            .buttonStyle(RowPressStyle())
            .zoomSource(id: HomeRoute.coin(.trx), in: zoom)
            .accessibilityLabel(currencyLabel(.trx, amount: TRX.format(sun: app.trxSun), value: Double(app.trxSun) / 1_000_000) + ". " + feeNote)
            .accessibilityHint("Opens TRON")
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(cornerRadius: Theme.Radius.tile)
    }

    private var feeNote: String { app.fuelLevel.note(transfersLeft: app.transfersLeft) }

    private func currencyLabel(_ token: TokenKind, amount: String, value: Double) -> String {
        if hideBalance { return token.symbol }
        guard let price = app.prices[token] else { return "\(amount) \(token.symbol)" }
        let usd = USDPrice.format(value * price.usd)
        return String(localized: "\(amount) \(token.symbol), about \(usd)")
    }

    // MARK: Actions

    #if DEBUG
    /// `-route receive|activity|currencies|fees|settings|send|coin-usdt|coin-trx` opens a screen at launch (screenshots, UI checks).
    private func openDebugRoute() {
        guard !debugRouteApplied else { return }
        debugRouteApplied = true
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "-route"), args.indices.contains(index + 1) else { return }
        switch args[index + 1] {
        case "receive": path = [.receive]
        case "activity": app.selectedTab = .activity
        case "currencies": path = [.currencies]
        case "fees": path = [.fees]
        case "settings": path = [.settings]
        case "send": app.sendRequest = .init()
        case let route where route.hasPrefix("coin-"):
            if let token = TokenKind(rawValue: String(route.dropFirst(5))) { path = [.coin(token)] }
        default: break
        }
    }
    #endif

    private func copyAddress() {
        guard let address = app.address else { return }
        Clipboard.copy(address)
        withAnimation(.snappy) { copied = true }
        AccessibilityNotification.Announcement(String(localized: "Address copied")).post()
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.snappy) { copied = false }
        }
    }
}

/// The Send and Receive cards: a big symbol up top, the verb at the bottom.
/// Send is the one accent-filled surface on the home.
private struct ActionCardLabel: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let symbol: String
    let prominent: Bool
    let seed: UInt64

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(prominent ? Color.white : Theme.Palette.ember)
                .frame(width: 44, height: 44)
                .background(prominent ? Color.white.opacity(0.18) : Theme.Palette.ember.opacity(0.14), in: .circle)
            Spacer(minLength: 18)
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(prominent ? Color.white : Theme.Palette.textPrimary)
            Text(subtitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(prominent ? Color.white.opacity(0.85) : Theme.Palette.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .contentShape(.rect)
        .background {
            AsciiDotField(seed: seed, color: prominent ? Color.white.opacity(0.26) : Theme.Palette.textTertiary.opacity(0.5))
                .mask(RadialGradient(colors: [.black, .black.opacity(0.6), .clear],
                                     center: .topTrailing, startRadius: 0, endRadius: 170))
                .clipShape(.rect(cornerRadius: Theme.Radius.tile, style: .continuous))
        }
        .background {
            if prominent {
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .fill(Theme.Palette.accent.gradient)
                    .shadow(color: Theme.Palette.accent.opacity(0.35), radius: 16, y: 8)
            }
        }
        .modifier(OptionalSurface(enabled: !prominent))
    }
}

private struct OptionalSurface: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled { content.surface(cornerRadius: Theme.Radius.tile) } else { content }
    }
}

/// Money in (up, green) and out (down, slate) for each of the last seven days.
/// Shape only, no axes: a glance at the week's rhythm, not a report.
struct WeekFlowChart: View {
    let history: [TokenTransfer]
    let myAddress: String

    private struct Day: Identifiable {
        let id: Date
        let inflow: Double
        let outflow: Double
    }

    private var days: [Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let items = history.filter { calendar.isDate($0.date, inSameDayAs: day) }
            let inflow = items.filter { $0.from != myAddress }.reduce(0.0) { $0 + Double($1.units) }
            let outflow = items.filter { $0.from == myAddress }.reduce(0.0) { $0 + Double($1.units) }
            return Day(id: day, inflow: inflow, outflow: outflow)
        }
    }

    var body: some View {
        let days = days
        let peak = max(days.map { max($0.inflow, $0.outflow) }.max() ?? 0, 1)
        // A floor so a small transfer still reads as a bar, not a speck.
        let height = { (value: Double) in value > 0 ? max(value / peak, 0.12) : 0 }
        Chart(days) { day in
            BarMark(x: .value("Day", day.id, unit: .day), y: .value("In", height(day.inflow)), width: .fixed(12))
                .foregroundStyle(Theme.Palette.positive)
                .clipShape(.rect(cornerRadius: 3))
            BarMark(x: .value("Day", day.id, unit: .day), y: .value("Out", -height(day.outflow)), width: .fixed(12))
                .foregroundStyle(Theme.Palette.outgoing)
                .clipShape(.rect(cornerRadius: 3))
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Theme.Palette.separator)
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartYScale(domain: -1...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

/// The wallet's USDT balance at the end of each recent day, rebuilt
/// backwards from today's balance through the fetched transfers. Days before
/// the oldest fetched transfer stay flat: no data, no invented movement.
private struct BalanceLineChart: View {
    let balance: UInt64
    let history: [TokenTransfer]
    let myAddress: String
    /// How many days the line spans (see `BalanceLineChart.span`).
    let days: Int

    /// A week at least, a month at most, otherwise just back to the oldest
    /// fetched transfer, so a young wallet isn't drawn as a long flat line.
    static func span(for history: [TokenTransfer]) -> Int {
        guard let oldest = history.map(\.date).min() else { return 7 }
        let calendar = Calendar.current
        let age = calendar.dateComponents([.day], from: calendar.startOfDay(for: oldest), to: calendar.startOfDay(for: .now)).day ?? 0
        return min(30, max(7, age + 2))
    }

    private struct Point: Identifiable {
        let id: Date
        let value: Double
    }

    private var points: [Point] {
        ActivityAnalytics.dailyBalances(current: balance, transfers: history, me: myAddress,
                                        days: days, now: .now, calendar: .current)
            .map { Point(id: $0.date, value: $0.usdt) }
    }

    var body: some View {
        let points = points
        let low = points.map(\.value).min() ?? 0
        let high = points.map(\.value).max() ?? 0
        // Pad the range so a flat line sits mid-card and peaks don't touch the edge.
        let pad = max((high - low) * 0.18, max(high, 1) * 0.05)
        Chart(points) { point in
            AreaMark(x: .value("Day", point.id, unit: .day),
                     yStart: .value("Floor", low - pad),
                     yEnd: .value("Balance", point.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(LinearGradient(colors: [Theme.Palette.accent.opacity(0.32), Theme.Palette.accent.opacity(0)],
                                                startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Day", point.id, unit: .day), y: .value("Balance", point.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(Theme.Palette.accentText)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            if point.id == points.last?.id {
                PointMark(x: .value("Day", point.id, unit: .day), y: .value("Balance", point.value))
                    .symbolSize(44)
                    .foregroundStyle(Theme.Palette.ember)
            }
        }
        .chartYScale(domain: (low - pad)...(high + pad))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

/// A coin in the Currencies card: icon, symbol and market price on the left,
/// what you hold and its dollar value on the right. `footnote` sits under the price.
private struct CurrencyRow<Footnote: View>: View {
    let token: TokenKind
    let amount: String
    let value: Double
    let price: TokenPrice?
    let hidden: Bool
    @ViewBuilder let footnote: Footnote

    var body: some View {
        HStack(spacing: 14) {
            TokenIcon(token: token, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(token.symbol).font(.body.weight(.semibold)).foregroundStyle(Theme.Palette.textPrimary)
                if let price {
                    HStack(spacing: 6) {
                        Text(USDPrice.format(price.usd, digits: price.usd < 1 ? 4 : 2))
                            .foregroundStyle(Theme.Palette.textSecondary)
                        if let change = price.change24h {
                            Text((change / 100).formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always()).locale(USDPrice.locale)))
                                .foregroundStyle(change >= 0 ? Theme.Palette.positive : Theme.Palette.danger)
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
                } else {
                    Text(LocalizedStringKey(token.name)).font(.caption).foregroundStyle(Theme.Palette.textSecondary)
                }
                footnote
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(hidden ? "••••" : amount)
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .contentTransition(.numericText())
                if let price {
                    Text(hidden ? "≈ ••••" : "≈ \(USDPrice.format(value * price.usd))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .contentShape(.rect)
    }
}

/// A row inside a card: a soft highlight while pressed instead of a scale.
private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.Palette.surfaceRaised : .clear)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// A faint field of ASCII dots gathered in the card's top-trailing corner and
/// thinning out before the title. Deterministic: the same seed always draws
/// the same field, so it never shimmers between renders.
private struct AsciiDotField: View {
    let seed: UInt64
    let color: Color

    private static let ramp: [Character] = [" ", "·", ".", ":", "+"]
    private static let cell = CGSize(width: 9, height: 11)

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let columns = Int(size.width / Self.cell.width) + 1
            let rows = Int(size.height / Self.cell.height) + 1
            let glyphs = Self.ramp.map { context.resolve(Text(String($0)).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(color)) }
            let corner = CGPoint(x: size.width, y: 0)
            let reach = hypot(size.width, size.height) * 0.62
            for row in 0..<rows {
                for column in 0..<columns {
                    let center = CGPoint(x: (CGFloat(column) + 0.5) * Self.cell.width, y: (CGFloat(row) + 0.5) * Self.cell.height)
                    let distance = hypot(center.x - corner.x, center.y - corner.y) / reach
                    guard distance < 1 else { continue }
                    let noise = Double(hash(column, row) % 1000) / 1000
                    // Dense near the corner, sparse further out; noise breaks up the rings.
                    let density = (1 - distance) * 1.25 - noise * 0.75
                    let level = min(Self.ramp.count - 1, max(0, Int(density * Double(Self.ramp.count))))
                    guard level > 0 else { continue }
                    context.draw(glyphs[level], at: center)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func hash(_ x: Int, _ y: Int) -> UInt64 {
        var h = seed &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(x) &* 0xBF58_476D_1CE4_E5B9 ^ UInt64(y) &* 0x94D0_49BB_1331_11EB
        h ^= h >> 31
        h = h &* 0xD6E8_FEB8_6659_FD93
        return h ^ (h >> 32)
    }
}

// MARK: - Building blocks

/// The wallet's badge: a blue-grey disc whose tone shifts slightly with the
/// address, so different wallets are told apart without leaving the palette.
struct WalletBadge: View {
    let address: String
    var size: CGFloat = 44

    var body: some View {
        let seed = address.unicodeScalars.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1.value) }
        // Hue stays in the slate-blue band (200°–235°); only the angle and tone vary.
        let hue = (200 + Double(seed % 36)) / 360
        let angle = Double(seed % 360)
        Circle()
            .fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.28, brightness: 0.72),
                                          Color(hue: hue, saturation: 0.34, brightness: 0.42)],
                                 startPoint: UnitPoint(x: 0.5 + 0.5 * cos(angle * .pi / 180), y: 0.5 + 0.5 * sin(angle * .pi / 180)),
                                 endPoint: UnitPoint(x: 0.5 - 0.5 * cos(angle * .pi / 180), y: 0.5 - 0.5 * sin(angle * .pi / 180))))
            .overlay(Circle().strokeBorder(.white.opacity(0.14)))
            .overlay(Image(systemName: "wallet.bifold.fill")
                .font(.system(size: size * 0.36, weight: .medium))
                .foregroundStyle(.white.opacity(0.92)))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct TransferRow: View {
    let transfer: TokenTransfer
    let myAddress: String
    var hideAmount = false
    /// Network fee in sun, when known; shown under sent transfers only.
    var feeSun: Int64? = nil

    private var outgoing: Bool { transfer.from == myAddress }
    /// Money in green, money out neutral slate.
    private var tint: Color { outgoing ? Theme.Palette.outgoing : Theme.Palette.positive }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: outgoing ? "arrow.up.right" : "arrow.down.left")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.14), in: .circle)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(outgoing ? "Sent" : "Received").font(.body.weight(.medium))
                Text("\(outgoing ? "To" : "From") \((outgoing ? transfer.to : transfer.from).shortAddress)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if outgoing, !hideAmount, let feeSun {
                    Text("Fee \(TRX.format(sun: feeSun)) TRX")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(hideAmount ? "••••" : "\(outgoing ? "−" : "+")\(USDT.format(units: transfer.units))")
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(outgoing ? Color.primary : Theme.Palette.positive)
                Text(transfer.date, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A transfer's details, as a sheet: amount and status up top, the other
/// side's address, everything else under "More", then a note and actions.
struct TransferDetailView: View {
    let transfer: TokenTransfer
    let myAddress: String
    /// Send again to the same address (sent transfers only).
    let onRepeat: (String) -> Void
    /// Just sent from this app: shows "Processing" until the transfer turns
    /// up in the wallet's history, then "Confirmed".
    var pending = false

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmed = false
    @State private var showMore = false
    @State private var copied: String?
    @State private var note = ""
    @State private var noteDraft = ""
    @State private var editingNote = false
    @State private var showSupport = false

    private var outgoing: Bool { transfer.from == myAddress }
    private var tint: Color { outgoing ? Theme.Palette.outgoing : Theme.Palette.positive }
    private var processing: Bool { pending && !confirmed }
    private var counterparty: String { outgoing ? transfer.to : transfer.from }
    private var noteKey: String { "transfer.note.\(transfer.id)" }
    private var tronscan: URL { URL(string: "https://tronscan.org/#/transaction/\(transfer.id)")! }

    /// Two decimals, or up to six when the amount has more.
    private var amount: String {
        USDT.format(units: transfer.units, fractionDigits: transfer.units % 10_000 == 0 ? 2 : 6)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    addressPanel
                    group {
                        actionRow(note.isEmpty ? "Add note" : note, icon: "pencil", secondary: !note.isEmpty) {
                            noteDraft = note
                            editingNote = true
                        }
                    }
                    group {
                        if outgoing {
                            actionRow("Repeat payment", icon: "arrow.clockwise") { onRepeat(transfer.to) }
                            Divider().padding(.leading, 56)
                        }
                        ShareLink(item: tronscan, message: Text(shareText)) {
                            rowLabel("Share", icon: "square.and.arrow.up")
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 56)
                        actionRow("Contact support", icon: "headphones") { showSupport = true }
                    }
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.bottom, 32)
                .readableWidth()
            }
            .background(Theme.Palette.background)
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SupportButton(inToolbar: true) { showSupport = true }
                }
            }
        }
        .onAppear { note = UserDefaults.standard.string(forKey: noteKey) ?? "" }
        .task {
            // A transfer just sent: it shows up in the history once TRON confirms it.
            while pending, !confirmed, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                await app.refresh()
                if app.history.contains(where: { $0.id == transfer.id }) {
                    Haptics.success()
                    confirmed = true
                }
            }
        }
        .alert("Note", isPresented: $editingNote) {
            TextField("What was this for?", text: $noteDraft)
            Button("Save") {
                note = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                UserDefaults.standard.set(note.isEmpty ? nil : note, forKey: noteKey)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only you see it, on this device.")
        }
        .sheet(isPresented: $showSupport) { SupportChatSheet() }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("\(outgoing ? "−" : "+") \(amount) USDT")
                    .font(Theme.Typography.amount(34, weight: .bold).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(transfer.date.formatted(.dateTime.hour().minute().second().day().month(.twoDigits).year(.twoDigits)))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 50)
            .padding(.bottom, 22)
            .surface(cornerRadius: Theme.Radius.panel)
            .overlay(alignment: .top) {
                Image(systemName: outgoing ? "arrow.up.right" : "arrow.down.left")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(tint.gradient, in: .rect(cornerRadius: Theme.Radius.xl))
                    .shadow(color: tint.opacity(0.35), radius: 8, y: 4)
                    .overlay(alignment: .bottomTrailing) {
                        if processing {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.black.opacity(0.85), in: .circle)
                                .overlay(Circle().strokeBorder(Theme.Palette.surface, lineWidth: 2))
                                .offset(x: 6, y: 6)
                        }
                    }
                    .offset(y: -30)
            }

            Text(processing ? "Processing" : "Confirmed")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(processing ? Theme.Palette.pending : Theme.Palette.positive,
                            in: UnevenRoundedRectangle(bottomLeadingRadius: Theme.Radius.m, bottomTrailingRadius: Theme.Radius.m))
                .padding(.horizontal, 14)
                .animation(.snappy, value: processing)
        }
        .padding(.top, 36)
    }

    // MARK: Addresses

    private var addressPanel: some View {
        group {
            copyRow(outgoing ? "Receive address" : "Sender address", counterparty)
            if outgoing, let fee = app.activity.fees[transfer.id] {
                Divider().padding(.leading, 16)
                feeRow(fee)
            }
            Divider().padding(.leading, 16)
            Button {
                withAnimation(.snappy) { showMore.toggle() }
            } label: {
                HStack {
                    Text("More").font(.body)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showMore ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 54)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if showMore {
                Divider().padding(.leading, 16)
                infoRow("Network", "TRON · TRC20")
                Divider().padding(.leading, 16)
                copyRow("Your address", myAddress)
                Divider().padding(.leading, 16)
                copyRow("Transaction ID", transfer.id)
                Divider().padding(.leading, 16)
                Link(destination: tronscan) {
                    HStack {
                        Text("View on Tronscan")
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Theme.Palette.accent)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 54)
                }
            }
        }
    }

    // MARK: Pieces

    private func group(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0) { content() }.surface(cornerRadius: Theme.Radius.tile)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.body)
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
    }

    /// The TRX this transfer burned, with its dollar value when a price is in.
    private func feeRow(_ sun: Int64) -> some View {
        HStack {
            Text("Network fee").foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(TRX.format(sun: sun)) TRX").monospacedDigit()
                if let price = app.prices[.trx]?.usd {
                    Text(verbatim: "≈ \(USDPrice.format(Double(sun) / 1_000_000 * price))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.body)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 54)
        .accessibilityElement(children: .combine)
    }

    private func copyRow(_ title: String, _ value: String) -> some View {
        Button {
            Clipboard.copy(value)
            copied = title
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if copied == title { copied = nil }
            }
        } label: {
            HStack(spacing: 8) {
                Text(title).foregroundStyle(.secondary).lineLimit(1).layoutPriority(1)
                Spacer(minLength: 8)
                Image(systemName: copied == title ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied == title ? Theme.Palette.positive : Color.secondary)
                Text(value.shortAddress).font(.body.weight(.medium).monospaced()).lineLimit(1)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(value)")
        .accessibilityHint("Copies to clipboard")
    }

    private func actionRow(_ title: String, icon: String, secondary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(title, icon: icon, secondary: secondary) }
            .buttonStyle(.plain)
    }

    private func rowLabel(_ title: String, icon: String, secondary: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.body.weight(.medium)).frame(width: 26)
            Text(title).lineLimit(2).foregroundStyle(secondary ? .secondary : .primary)
            Spacer()
            Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .contentShape(.rect)
    }

    private var shareText: String {
        "\(outgoing ? "Sent" : "Received") \(amount) USDT (TRON) \(outgoing ? "to" : "from") \(counterparty) on \(transfer.date.formatted(date: .abbreviated, time: .shortened))"
    }
}

struct NetworkFeeInfoView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            Section {
                Text("Every USDT transfer on TRON burns network energy, paid in TRX from this wallet — about 13–14 TRX when you have no staked energy. Receiving USDT is free.")
            }
            Section("To add TRX") {
                Text("Send TRX on the TRON network to your wallet address from any exchange or wallet.")
                if let address = app.address {
                    Button {
                        Clipboard.copy(address)
                    } label: {
                        Label("Copy my address", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .navigationTitle("Network fees")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
