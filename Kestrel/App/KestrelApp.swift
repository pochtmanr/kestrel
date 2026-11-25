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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                // Onboarding is the night-sky brand screen: always dark.
                .preferredColorScheme(app.stage == .setup ? .dark : appearance.colorScheme)
                .tint(Theme.Palette.accent)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    /// Cold launch only: covers the first moment, then fades into the app.
    @State private var splash = true

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()
            switch app.stage {
            case .setup: OnboardingView()
            case .createPIN: PinSetupView()
            case .locked: LockView()
            case .unlocked: MainTabView()
            }
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

/// Two tabs on the left, search apart on the right (iOS 26 draws it as its
/// own glass button, like Music). Send is presented here, over any tab.
struct MainTabView: View {
    @Environment(AppModel.self) private var app
    @Namespace private var zoom
    @State private var searchText = ""

    var body: some View {
        @Bindable var app = app
        tabs
            .fullScreenCover(item: $app.sendRequest) { request in
                SendView(recipient: request.recipient)
                    .zoomDestination(id: WalletView.sendZoomID, in: zoom)
            }
    }

    @ViewBuilder
    private var tabs: some View {
        @Bindable var app = app
        if #available(iOS 18, *) {
            TabView(selection: $app.selectedTab) {
                Tab("Wallet", systemImage: "wallet.bifold", value: AppModel.Tab.wallet) { WalletView(zoom: zoom) }
                Tab("Activity", systemImage: "chart.bar.xaxis", value: AppModel.Tab.activity) { ActivityView() }
                Tab(value: AppModel.Tab.search, role: .search) { AssetSearchView(query: $searchText) }
            }
            // Search on the tab view (not inside the tab) is what lets the
            // system detach it into its own button and morph it into a field.
            .searchable(text: $searchText, prompt: Text("USDT, TRX…"))
            .modifier(MinimizeTabBarOnScroll())
        } else {
            TabView(selection: $app.selectedTab) {
                WalletView(zoom: zoom)
                    .tabItem { Label("Wallet", systemImage: "wallet.bifold") }
                    .tag(AppModel.Tab.wallet)
                ActivityView()
                    .tabItem { Label("Activity", systemImage: "chart.bar.xaxis") }
                    .tag(AppModel.Tab.activity)
                AssetSearchView(query: $searchText, ownsSearchField: true)
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    .tag(AppModel.Tab.search)
            }
        }
    }
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
