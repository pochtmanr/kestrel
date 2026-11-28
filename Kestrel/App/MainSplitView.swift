import SwiftUI

/// The unlocked app on wide screens (iPad, an unfolded iPhone): the system's
/// adaptable tab bar, a floating bar along the top that opens into a sidebar
/// and back with its own toggle. iPhone and compact iPad windows (Split View,
/// Slide Over) keep the bottom tab bar in `MainTabView`.
@available(iOS 18, *)
struct SidebarTabShell: View {
    let zoom: Namespace.ID

    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        // Flat tabs, no sections: a sectioned tab is left out of the top bar,
        // and Settings has to be reachable in both forms.
        TabView(selection: $app.selectedTab) {
            ForEach(AppModel.Tab.allCases, id: \.self) { tab in
                Tab(tab.title, systemImage: tab.icon, value: tab) {
                    SectionDetail(tab: tab, zoom: zoom)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarHeader { SidebarSendButton().padding(.bottom, Theme.Spacing.s) }
        .tabViewSidebarBottomBar { SidebarWalletFooter() }
        .environment(\.isSplitShell, true)
    }
}

/// iOS 17 has no adaptable tab bar: a sidebar beside the selected section.
struct MainSplitView: View {
    let zoom: Namespace.ID

    @Environment(AppModel.self) private var app
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 320)
        } detail: {
            SectionDetail(tab: app.selectedTab, zoom: zoom)
                // A fresh stack per section, so switching sections starts at its root.
                .id(app.selectedTab)
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.isSplitShell, true)
    }
}

/// One section of the wide-screen shell, in its own navigation stack.
private struct SectionDetail: View {
    let tab: AppModel.Tab
    let zoom: Namespace.ID

    var body: some View {
        switch tab {
        case .wallet: WalletView(zoom: zoom)
        case .activity: ActivityView()
        case .currencies: SectionStack { CurrenciesView() }
        case .receive: SectionStack { DepositView() }
        case .settings: SectionStack { SettingsView() }
        }
    }
}

/// A section's own navigation stack, resolving the same routes the home pushes.
private struct SectionStack<Root: View>: View {
    @ViewBuilder var root: Root

    var body: some View {
        NavigationStack {
            root.navigationDestination(for: HomeRoute.self) { RouteDestination(route: $0) }
        }
    }
}

private struct SidebarView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List(selection: Binding<AppModel.Tab?>(get: { app.selectedTab }, set: { if let tab = $0 { app.selectedTab = tab } })) {
            Section {
                SidebarSendButton()
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 12, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                ForEach(AppModel.Tab.allCases.filter { $0 != .settings }, id: \.self) { tab in
                    Label(tab.title, systemImage: tab.icon).tag(tab)
                }
            }
            Section {
                Label(AppModel.Tab.settings.title, systemImage: AppModel.Tab.settings.icon).tag(AppModel.Tab.settings)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.background)
        .navigationTitle(Brand.name)
        .safeAreaInset(edge: .bottom) {
            SidebarWalletFooter()
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.m)
        }
    }
}

/// Send is the app's main action: it leads the sidebar, above the sections.
private struct SidebarSendButton: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            Haptics.tap()
            app.sendRequest = .init()
        } label: {
            Label("Send", systemImage: "arrow.up.right")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .accessibilityLabel("Send USDT")
    }
}

/// Who you are, one tap from copying: the address is on the home's menu on
/// iPhone; here the sidebar always has room for it.
private struct SidebarWalletFooter: View {
    @Environment(AppModel.self) private var app
    @State private var copied = false

    var body: some View {
        let address = app.address ?? ""
        Button(action: copyAddress) {
            HStack(spacing: 10) {
                WalletBadge(address: address, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Main wallet").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.Palette.textPrimary)
                    Text(verbatim: address.shortAddress).font(.caption.monospaced()).foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer(minLength: 4)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(copied ? Theme.Palette.positive : Theme.Palette.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(12)
            .surface(cornerRadius: Theme.Radius.l)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(app.address == nil)
        .accessibilityLabel("Main wallet")
        .accessibilityValue(copied ? Text("Address copied") : Text(verbatim: address.shortAddress))
        .accessibilityHint("Copies your address")
    }

    private func copyAddress() {
        guard let address = app.address else { return }
        Clipboard.copy(address)
        withAnimation(.snappy) { copied = true }
        AccessibilityNotification.Announcement(tr("Address copied")).post()
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.snappy) { copied = false }
        }
    }
}
