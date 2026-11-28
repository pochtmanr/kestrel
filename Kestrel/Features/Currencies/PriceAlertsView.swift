import SwiftUI
import UIKit

/// One coin's price alerts: the ones still waiting, the ones that went off,
/// and a way to add more. Pushed from the coin screen.
struct PriceAlertsView: View {
    let token: TokenKind
    var notifier: any PriceAlertNotifying = AlertNotifier.shared

    @Environment(AppModel.self) private var app
    @Environment(PriceAlertStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale
    @State private var authorization: AlertAuthorization?
    @State private var editor: EditorRequest?

    private struct EditorRequest: Identifiable {
        let id = UUID()
        var alert: PriceAlert?
    }

    private var current: Double? { app.prices[token]?.usd }
    private var mine: [PriceAlert] { store.alerts(for: token) }
    /// Highest target first, so the list reads like a price ladder.
    private var armed: [PriceAlert] { mine.filter(\.isArmed).sorted { $0.targetUSD > $1.targetUSD } }
    /// Most recent first.
    private var fired: [PriceAlert] {
        mine.filter { !$0.isArmed }.sorted { ($0.firedAt ?? .distantPast) > ($1.firedAt ?? .distantPast) }
    }
    private var animation: Animation? { reduceMotion ? nil : .snappy }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                header
                if authorization == .denied { deniedNotice }
                if mine.isEmpty {
                    emptyState
                } else {
                    if !armed.isEmpty { group("Active", alerts: armed) }
                    if !fired.isEmpty { group("Reached", alerts: fired) }
                }
                Text("Checked while \(Brand.name) is open and occasionally in the background. Alerts can arrive late.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.l)
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.xl)
            .readableWidth()
            .animation(animation, value: store.alerts)
            .animation(animation, value: authorization)
        }
        .background(Theme.Palette.background)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .navigationTitle("Price alerts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $editor) { request in
            PriceAlertEditor(token: token, editing: request.alert) { target, direction in
                save(target: target, direction: direction, editing: request.alert)
            } onDelete: {
                if let alert = request.alert { delete(alert) }
            }
            .formSheetSizing()
        }
        .task {
            authorization = await notifier.authorizationStatus()
            // Throttled by the model; keeps the header honest when opened cold.
            await app.refreshPrices()
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from the Settings app: the permission may have changed.
            guard phase == .active else { return }
            Task { authorization = await notifier.authorizationStatus() }
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 14) {
            TokenIcon(token: token, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(token.symbol) price")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.textSecondary)
                if let current {
                    Text(verbatim: USDPrice.price(current))
                        .font(Theme.Typography.amount(30))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .contentTransition(.numericText())
                        .animation(animation, value: current)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    Text("Price unavailable")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.l)
        .surface(cornerRadius: Theme.Radius.tile)
        .accessibilityElement(children: .combine)
    }

    private var deniedNotice: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Image(systemName: "bell.slash.fill")
                    .foregroundStyle(Theme.Palette.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications are off").font(.subheadline.weight(.semibold))
                    Text("Alerts are still tracked here, but you won't be notified until you allow notifications in Settings.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(cornerRadius: Theme.Radius.tile)
        .transition(.opacity)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: "bell.badge")
                .font(.largeTitle)
                .foregroundStyle(Theme.Palette.accentText)
                .padding(.bottom, Theme.Spacing.xxs)
                .accessibilityHidden(true)
            Text("No alerts yet").font(.headline)
            Text("Get a notification when \(token.symbol) reaches a price you choose.")
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.xl + Theme.Spacing.s)
        .surface(cornerRadius: Theme.Radius.tile)
    }

    private func group(_ title: LocalizedStringKey, alerts: [PriceAlert]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
                .padding(.horizontal, Theme.Spacing.l)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(alerts) { alert in
                    if alert.id != alerts.first?.id { Divider().padding(.leading, 66) }
                    row(alert)
                }
            }
            .surface(cornerRadius: Theme.Radius.tile)
        }
    }

    private func row(_ alert: PriceAlert) -> some View {
        let tint = alert.isArmed ? alert.direction.tint : Theme.Palette.textTertiary
        return HStack(spacing: Theme.Spacing.m) {
            Button { editor = EditorRequest(alert: alert) } label: {
                HStack(spacing: 14) {
                    Image(systemName: alert.direction.symbol)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(tint)
                        .frame(width: 36, height: 36)
                        .background(tint.opacity(0.14), in: .circle)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.direction == .above
                             ? "Above \(USDPrice.price(alert.targetUSD))"
                             : "Below \(USDPrice.price(alert.targetUSD))")
                            .font(.body.weight(.semibold))
                            .fontDesign(Theme.Typography.numeric)
                            .foregroundStyle(alert.isArmed ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
                        subtitle(alert)
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .contentTransition(.numericText())
                    }
                    Spacer(minLength: 0)
                    if alert.isArmed {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the alert for editing")

            if !alert.isArmed {
                Button("Re-arm") { rearm(alert) }
                    .buttonStyle(ChipButtonStyle())
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, 14)
        .contextMenu {
            Button { editor = EditorRequest(alert: alert) } label: { Label("Edit alert", systemImage: "pencil") }
            if !alert.isArmed {
                Button { rearm(alert) } label: { Label("Re-arm", systemImage: "arrow.clockwise") }
            }
            Button(role: .destructive) { delete(alert) } label: { Label("Delete alert", systemImage: "trash") }
        }
    }

    @ViewBuilder
    private func subtitle(_ alert: PriceAlert) -> some View {
        if let firedAt = alert.firedAt {
            Text("Reached \(firedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)))")
        } else if let current, let distance = PriceAlertRules.distancePercent(target: alert.targetUSD, current: current) {
            Text("\(USDPrice.percent(distance)) from the current price")
        } else {
            Text("Waiting for a price")
        }
    }

    private var bottomBar: some View {
        VStack(spacing: Theme.Spacing.s) {
            if store.isFull {
                Text("You can keep up to \(PriceAlertStore.limit) alerts. Delete one to add another.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button { editor = EditorRequest() } label: {
                Label("New alert", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(store.isFull)
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.s)
        .readableWidth()
        .background(Theme.Palette.background)
    }

    // MARK: Actions

    private func save(target: Double, direction: PriceAlert.Direction, editing: PriceAlert?) {
        withAnimation(animation) {
            if var alert = editing {
                alert.targetUSD = target
                alert.direction = direction
                // Saving is asking to be told again.
                alert.firedAt = nil
                store.update(alert)
            } else {
                store.add(token: token, direction: direction, targetUSD: target)
            }
        }
        Haptics.success()
        Task { await askPermissionIfNeeded() }
    }

    private func rearm(_ alert: PriceAlert) {
        // Already past its target: re-arming would fire at once. Let the user pick a new one.
        guard PriceAlertRules.validate(target: alert.targetUSD, current: current, direction: alert.direction) == nil else {
            editor = EditorRequest(alert: alert)
            return
        }
        withAnimation(animation) { store.rearm(alert.id) }
        Haptics.tap()
        Task { await askPermissionIfNeeded() }
    }

    private func delete(_ alert: PriceAlert) {
        withAnimation(animation) { store.delete(alert.id) }
        Haptics.tap()
    }

    /// The system prompt appears here, when an alert exists to be notified
    /// about, and never at launch. The demo wallet (screenshots) never asks.
    private func askPermissionIfNeeded() async {
        guard !app.isDemo else { return }
        if await notifier.authorizationStatus() == .notDetermined {
            await notifier.requestAuthorization()
        }
        authorization = await notifier.authorizationStatus()
    }
}

private extension PriceAlert.Direction {
    var title: LocalizedStringKey {
        switch self {
        case .above: "Above"
        case .below: "Below"
        }
    }

    var symbol: String {
        switch self {
        case .above: "arrow.up.right"
        case .below: "arrow.down.right"
        }
    }

    var tint: Color {
        switch self {
        case .above: Theme.Palette.positive
        case .below: Theme.Palette.danger
        }
    }
}

/// A small capsule for secondary actions inside a card (Re-arm, the ±% chips).
private struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.Palette.accentText)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Theme.Palette.surfaceRaised, in: .capsule)
            .contentShape(.capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Editor

/// New alert, or an existing one opened for editing.
private struct PriceAlertEditor: View {
    let token: TokenKind
    let editing: PriceAlert?
    let onSave: (Double, PriceAlert.Direction) -> Void
    let onDelete: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var text = ""
    @State private var direction: PriceAlert.Direction = .above
    /// Until the user picks Above or Below themselves, it follows the typed price.
    @State private var directionChosen = false
    @FocusState private var focused: Bool

    private static let steps: [Double] = [-10, -5, 5, 10]

    private var current: Double? { app.prices[token]?.usd }
    private var animation: Animation? { reduceMotion ? nil : .snappy }

    private enum Status: Equatable {
        case empty, unreadable
        case problem(PriceAlertRules.Problem)
        case ready(Double)
    }

    private var status: Status {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return .empty }
        guard let target = PriceAlertRules.parse(text) else { return .unreadable }
        if let problem = PriceAlertRules.validate(target: target, current: current, direction: direction) { return .problem(problem) }
        return .ready(target)
    }

    private var pickedDirection: Binding<PriceAlert.Direction> {
        Binding { direction } set: {
            direction = $0
            directionChosen = true
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    priceField
                    PillPicker(selection: pickedDirection, options: PriceAlert.Direction.allCases) { $0.title }
                    if let current { chips(current) }
                    note
                    Button("Save alert") { submit() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(status == .empty)
                    if editing != nil {
                        Button {
                            onDelete()
                            dismiss()
                        } label: {
                            Text("Delete alert").foregroundStyle(Theme.Palette.danger)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.xl)
                .readableWidth()
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.Palette.background)
            .navigationTitle(editing == nil ? "New alert" : "Edit alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: text) {
                guard !directionChosen, let current, let target = PriceAlertRules.parse(text) else { return }
                let suggested = PriceAlertRules.suggestedDirection(target: target, current: current)
                if suggested != direction { withAnimation(animation) { direction = suggested } }
            }
            .onAppear {
                if let editing {
                    text = PriceAlertRules.fieldText(editing.targetUSD)
                    direction = editing.direction
                    directionChosen = true
                }
                focused = true
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.Palette.background)
    }

    private var priceField: some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text(verbatim: "$")
                    .font(Theme.Typography.amount(30, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ember)
                    .accessibilityHidden(true)
                TextField("0", text: $text)
                    .font(Theme.Typography.amount(44))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .fixedSize()
                    .accessibilityLabel(Text("Target price in US dollars"))
            }
            Group {
                if let current {
                    Text("\(token.symbol) is at \(USDPrice.price(current))")
                        .contentTransition(.numericText())
                        .animation(animation, value: current)
                } else {
                    Text("Price unavailable")
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .surface(cornerRadius: Theme.Radius.panel)
        .onTapGesture { focused = true }
    }

    /// Targets a step away from the current price.
    private func chips(_ current: Double) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(Self.steps, id: \.self) { step in
                Button {
                    Haptics.tap()
                    withAnimation(animation) {
                        text = PriceAlertRules.fieldText(PriceAlertRules.target(from: current, percent: step))
                        direction = step > 0 ? .above : .below
                        directionChosen = true
                    }
                } label: {
                    // "+5%" reads the same in every language.
                    Text(verbatim: "\(step > 0 ? "+" : "−")\(Int(abs(step)))%")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ChipButtonStyle())
                .accessibilityLabel(step > 0
                    ? Text("\(Int(abs(step))) percent above the current price")
                    : Text("\(Int(abs(step))) percent below the current price"))
            }
        }
    }

    private var note: some View {
        Group {
            switch status {
            case .empty:
                Text("You'll get one notification when \(token.symbol) reaches this price.")
                    .foregroundStyle(Theme.Palette.textSecondary)
            case .unreadable:
                Text("Enter a price, like 0.35.").foregroundStyle(Theme.Palette.danger)
            case .problem(let problem):
                Text(verbatim: problem.message).foregroundStyle(Theme.Palette.danger)
            case .ready(let target):
                Group {
                    switch direction {
                    case .above: Text("You'll get one notification when \(token.symbol) rises to \(USDPrice.price(target)) or higher.")
                    case .below: Text("You'll get one notification when \(token.symbol) falls to \(USDPrice.price(target)) or lower.")
                    }
                }
                .foregroundStyle(Theme.Palette.textSecondary)
            }
        }
        .font(.footnote)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .animation(animation, value: status)
    }

    private func submit() {
        guard case .ready(let target) = status else {
            Haptics.error()
            return
        }
        onSave(target, direction)
        dismiss()
    }
}

#if DEBUG
#Preview("Price alerts") {
    let suite = "preview.price-alerts"
    UserDefaults.standard.removePersistentDomain(forName: suite)
    let store = PriceAlertStore(defaults: UserDefaults(suiteName: suite) ?? .standard)
    store.add(token: .trx, direction: .above, targetUSD: 0.35)
    store.add(token: .trx, direction: .below, targetUSD: 0.2)
    if let reached = store.add(token: .trx, direction: .above, targetUSD: 0.24) { store.markFired(reached.id) }
    let app = AppModel()
    app.loadDemo()
    return NavigationStack { PriceAlertsView(token: .trx) }
        .environment(app)
        .environment(store)
}
#endif
