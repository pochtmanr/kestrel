import SwiftUI

@main
struct KestrelApp: App {
    @State private var app: AppModel = {
        let model = AppModel()
        #if DEBUG
        // `-demo` launch argument: sample data, no network (screenshots, UI checks).
        if CommandLine.arguments.contains("-demo") { model.loadDemo() }
        // `-welcome`: the onboarding screens, leaving any saved wallet alone.
        if CommandLine.arguments.contains("-welcome") { model.showOnboardingPreview() }
        #endif
        return model
    }()
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system
    @State private var alerts = PriceAlertStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Lets a price alert show as a banner while the app is open. Never prompts.
        AlertNotifier.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(alerts)
                .modifier(AppPreferences())
                // Onboarding is the night-sky brand screen: always dark.
                .preferredColorScheme(app.stage == .setup ? .dark : appearance.colorScheme)
                .tint(Theme.Palette.accent)
                .onChange(of: app.marketsUpdatedAt) { checkAlerts() }
                // Prices otherwise refresh only when a screen asks: with an alert
                // armed, keep them moving while the app is open.
                .task(id: alertPolling) {
                    guard alertPolling else { return }
                    while !Task.isCancelled {
                        await app.refreshPrices()
                        try? await Task.sleep(for: .seconds(65))
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { PriceAlerts.scheduleBackgroundRefresh(store: alerts) }
        }
        // iOS decides when (and whether) this runs: alerts can arrive late.
        .backgroundTask(.appRefresh(PriceAlerts.backgroundTaskID)) {
            await refreshAlertsInBackground()
        }
    }

    private var alertPolling: Bool {
        scenePhase == .active && alerts.hasArmedAlerts && !app.isDemo
    }

    private func checkAlerts() {
        guard !app.isDemo else { return }
        Task { await checkPriceAlerts(store: alerts, prices: app.prices.mapValues(\.usd)) }
    }

    @MainActor
    private func refreshAlertsInBackground() async {
        guard !app.isDemo, alerts.hasArmedAlerts else { return }
        await app.refreshPrices()
        await checkPriceAlerts(store: alerts, prices: app.prices.mapValues(\.usd))
        PriceAlerts.scheduleBackgroundRefresh(store: alerts)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppLanguage.storageKey, store: SharedWallet.defaults) private var language: AppLanguage = .system
    /// Cold launch only: covers the first moment, then fades into the app.
    @State private var splash = true

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()
            Group {
                switch app.stage {
                case .setup: OnboardingView()
                case .createPIN: PinSetupView()
                case .locked: LockView()
                case .unlocked: MainTabView()
                }
            }
            // Strings built in code don't watch the locale: a new language
            // rebuilds the screens (not this view, or the splash would replay).
            .id(language)
        }
        .animation(.default, value: app.stage)
        .overlay {
            // Hide balances and recovery phrases in the app switcher and while backgrounded.
            if scenePhase == .background || (scenePhase == .inactive && app.stage != .locked) {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
                    Image("Logo").resizable().frame(width: 80, height: 80).clipShape(.rect(cornerRadius: Theme.Radius.card))
                }
            }
        }
        .overlay {
            if splash {
                SplashView()
                    .transition(.opacity.animation(.easeInOut(duration: 0.45)))
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.1))
            withAnimation(.easeInOut(duration: 0.45)) { splash = false }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { app.lock() }
        }
    }
}

/// The unlocked app: tabs on iPhone, the adaptable tab bar on wide screens. Send is
/// presented here, over any tab or section.
struct MainTabView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Namespace private var zoom

    var body: some View {
        @Bindable var app = app
        if sizeClass == .regular {
            wideShell
                // A form-sized sheet: a full-screen keypad on a 13" display is all air.
                .sheet(item: $app.sendRequest) { request in
                    SendView(recipient: request.recipient)
                        .formSheetSizing()
                        .interactiveDismissDisabled()
                }
        } else {
            tabs
                .fullScreenCover(item: $app.sendRequest) { request in
                    SendView(recipient: request.recipient)
                        .zoomDestination(id: WalletView.sendZoomID, in: zoom)
                }
                // Back from the wide layout (Split View, Slide Over): sidebar-only
                // sections have no tab here, so land on the home instead.
                .onAppear { if !app.selectedTab.isPhoneTab { app.selectedTab = .wallet } }
        }
    }

    @ViewBuilder
    private var wideShell: some View {
        if #available(iOS 18, *) {
            SidebarTabShell(zoom: zoom)
        } else {
            MainSplitView(zoom: zoom)
        }
    }

    @ViewBuilder
    private var tabs: some View {
        @Bindable var app = app
        let wallet = AppModel.Tab.wallet, activity = AppModel.Tab.activity
        if #available(iOS 18, *) {
            TabView(selection: $app.selectedTab) {
                Tab(wallet.title, systemImage: wallet.icon, value: wallet) { WalletView(zoom: zoom) }
                Tab(activity.title, systemImage: activity.icon, value: activity) { ActivityView() }
            }
            .modifier(MinimizeTabBarOnScroll())
        } else {
            TabView(selection: $app.selectedTab) {
                WalletView(zoom: zoom)
                    .tabItem { Label(wallet.title, systemImage: wallet.icon) }
                    .tag(wallet)
                ActivityView()
                    .tabItem { Label(activity.title, systemImage: activity.icon) }
                    .tag(activity)
            }
        }
    }
}

private extension AppModel.Tab {
    var isPhoneTab: Bool { self == .wallet || self == .activity }
}

/// iOS 26: the tab bar shrinks while scrolling down, like Music.
private struct MinimizeTabBarOnScroll: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

