import Combine
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Receive: the address as a QR code that visibly waits for money. A halo
/// around the code breathes while the wallet is being checked; when a payment
/// lands, the code turns into a receipt for a moment, then the payment joins
/// a short "Received now" list.
///
/// `token` is what the screen was opened for: USDT by default, TRX from the
/// TRX coin screen's "Add TRX". The address is the same for both; the token
/// changes the warning, the QR's payment URI and the share text.
struct DepositView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.isSplitShell) private var isSplitShell
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("receive.addressName") private var addressName = ""
    @AppStorage("receive.detailsExpanded") private var detailsExpanded = true

    @State private var selected: TokenKind
    @State private var requestUnits: UInt64?
    @State private var editingAmount = false
    @State private var copied = false
    @State private var copyTask: Task<Void, Never>?
    @State private var editingName = false
    @State private var nameDraft = ""
    @State private var watch = IncomingWatch()
    /// Settled payments, newest first: the "Received now" list.
    @State private var received: [ReceivedPayment] = []
    /// The payment whose receipt is on the QR plate right now.
    @State private var celebration: ReceivedPayment?
    /// Receipts waiting their turn: one is showing, or a sheet is in the way.
    @State private var queue: [ReceivedPayment] = []
    @State private var burst = 0
    @State private var detail: TokenTransfer?
    @State private var lastAttempt: Date?
    @State private var plateShown = false
    @State private var haloShown = false
    @State private var onScreen = false
    @State private var qrVisible = true
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    #if DEBUG
    @State private var debug = DebugHooks()
    #endif

    init(token: TokenKind = .usdt) {
        var token = token
        var units: UInt64?
        #if DEBUG
        DebugHooks.launchState(token: &token, units: &units)
        #endif
        _selected = State(initialValue: token)
        _requestUnits = State(initialValue: units)
    }

    /// Refresh at most this often while open. The home's own 15 s loop may be
    /// running underneath, so this only fills the gaps instead of doubling it.
    private static let pollInterval: TimeInterval = 12
    /// How long a receipt stays on the plate before the code comes back.
    private static let receiptHold: Duration = .seconds(4)
    private static let listLimit = 3

    var body: some View {
        Group {
            if let address = walletAddress {
                content(address)
            } else {
                noWallet
            }
        }
        .background(Theme.Palette.background)
        .navigationTitle("Receive")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $editingAmount) {
            AmountRequestSheet(token: selected, initial: requestUnits) { units in
                withAnimation(motion()) { requestUnits = units }
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
        .alert("Address name", isPresented: $editingName) {
            TextField("e.g. Savings", text: $nameDraft)
            Button("Save") { addressName = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only you see it, on this device.")
        }
        .task(id: app.address) { await watchForPayments() }
        .task(id: celebration?.id) { await holdReceipt() }
        .onChange(of: app.history) { evaluate() }
        .onChange(of: app.trxSun) { evaluate() }
        .onChange(of: selected) {
            // A requested amount is in one coin; it doesn't carry over to the other.
            requestUnits = nil
        }
        // A receipt never starts under a sheet or an alert: it waits for it to close.
        .onChange(of: nothingPresented) { presentNextReceipt() }
        .onChange(of: refreshError != nil) { _, offline in
            if offline { AccessibilityNotification.Announcement(tr("Can't check for new payments")).post() }
        }
        // One haptic per receipt, chosen by how it compares with the request.
        .sensoryFeedback(trigger: celebration) { _, new in
            guard let new else { return nil }
            return new.outcome.isShort ? .warning : .success
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: DispatchQueue.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onAppear {
            onScreen = true
            guard !plateShown else { return }
            withAnimation(motion(.snappy(duration: 0.35))) { plateShown = true }
            withAnimation(motion(.easeOut(duration: 0.4)).delay(0.2)) { haloShown = true }
        }
        .onDisappear { onScreen = false }
        #if DEBUG
        .task {
            guard let arrival = await DebugHooks.simulatedArrival(token: selected, units: requestUnits,
                                                                  me: app.address ?? "") else { return }
            debug.injected = arrival.injected
            debug.trxBump = arrival.trxBump
            evaluate()
        }
        #endif
    }

    private var walletAddress: String? {
        #if DEBUG
        if debug.noWallet { return nil }
        #endif
        return app.address
    }

    private var refreshError: String? {
        #if DEBUG
        if debug.offline { return TronClient.Failure.rateLimited.errorDescription }
        #endif
        return app.refreshError
    }

    /// The house `.snappy`, or a short fade when Reduce Motion is on.
    private func motion(_ animation: Animation = .snappy) -> Animation {
        .motion(animation, reduced: reduceMotion)
    }

    private var nothingPresented: Bool { !editingAmount && !editingName && detail == nil }

    /// The halo animates only while it means something and someone can see it;
    /// otherwise it's a still ring and costs nothing.
    private var haloMode: ListeningHalo.Mode {
        if refreshError != nil { return .offline }
        let listening = scenePhase == .active && app.lastRefresh != nil && !lowPower
            && onScreen && qrVisible && nothingPresented && celebration == nil
        return listening ? .listening : .still
    }

    // MARK: Content

    private func content(_ address: String) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                PillPicker(selection: $selected, options: [.usdt, .trx]) { $0 == .usdt ? "USDT" : "TRX" }
                    .accessibilityLabel("Coin to receive")

                if let refreshError {
                    OfflineNotice(message: refreshError)
                        .transition(.opacity)
                }

                // Wide screens: the code on one side, what arrived and what to know on the other.
                AdaptiveColumns(minWidth: 760, spacing: 12, leadingFraction: 0.5) {
                    addressCard(address)
                } trailing: {
                    if !received.isEmpty { receivedList }
                    DetailsSection(expanded: $detailsExpanded) {
                        NetworkWarning(token: selected, trxSun: app.trxSun, transfersLeft: app.transfersLeft, style: .body)
                        feesRow
                        nameRow
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, 4)
            .padding(.bottom, Theme.Spacing.xl)
            .readableWidth(isSplitShell ? 980 : Theme.Layout.readable)
            .animation(motion(), value: refreshError)
        }
    }

    private func addressCard(_ address: String) -> some View {
        let payload = ReceiveLogic.paymentPayload(address: address, token: selected, units: requestUnits)
        return VStack(spacing: 14) {
            HStack(spacing: 8) {
                TokenIcon(token: selected, size: 22)
                Text(selected == .usdt ? "USDT on TRON (TRC-20)" : "TRX on TRON")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityElement(children: .combine)

            RequestHeadline(units: requestUnits, symbol: selected.symbol) {
                Haptics.tap()
                editingAmount = true
            } onClear: {
                Haptics.tap()
                withAnimation(motion()) { requestUnits = nil }
            }

            LiveQRPlate(payload: payload, token: selected,
                        label: requestUnits.map { qrLabel(units: $0) } ?? tr("QR code of your wallet address"),
                        receipt: celebration, halo: haloMode, haloShown: haloShown,
                        checked: app.lastRefresh, burst: burst) { settleReceipt() }
                // 12 pt of plate on each side: the code itself is never under 200 pt.
                .frame(minWidth: 224, maxWidth: isSplitShell ? 300 : 224)
                .scaleEffect(plateShown ? 1 : 0.94)
                .opacity(plateShown ? 1 : 0)
                .padding(.vertical, Theme.Spacing.xxs)
                .trackingScrollVisibility($qrVisible)
                // The halo spreads past the plate; keep it under the lines around it.
                .zIndex(-1)

            statusLine

            NetworkWarning(token: selected, trxSun: app.trxSun, transfersLeft: app.transfersLeft, style: .strip)

            groupedAddress(address)

            addressActions(address)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 18)
        .surface(cornerRadius: Theme.Radius.panel)
    }

    private func qrLabel(units: UInt64) -> String {
        tr("QR code requesting \(ReceiveLogic.decimalAmount(units)) \(selected.symbol)")
    }

    /// One line under the code: what the screen is doing about incoming money.
    /// The time ticks on its own; VoiceOver reads it only when asked.
    @ViewBuilder
    private var statusLine: some View {
        Group {
            if celebration != nil {
                // The receipt on the plate says the same as its hint.
                Text("Tap to show the code")
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .accessibilityHidden(true)
            } else if refreshError != nil {
                status(Text("Not checking · your code still works"),
                       dot: Theme.Palette.textTertiary, text: Theme.Palette.warning)
            } else if let last = app.lastRefresh {
                status(Text("Listening · checked \(last, style: .relative) ago"),
                       dot: Theme.Palette.positive, text: Theme.Palette.textSecondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Listening for payments, last checked \(last, style: .relative) ago"))
            } else {
                status(Text("Watching for incoming payments"),
                       dot: Theme.Palette.positive, text: Theme.Palette.textSecondary)
            }
        }
        .font(.footnote.weight(.medium).monospacedDigit())
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    private func status(_ text: Text, dot: Color, text color: Color) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(dot)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            text.foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }

    /// The full address in groups of four. Tapping it copies too (the Copy
    /// button below says so). VoiceOver spells it out a group at a time.
    private func groupedAddress(_ address: String) -> some View {
        let groups = ReceiveLogic.addressGroups(address)
        return Button { copy(address) } label: {
            Text(verbatim: groups.joined(separator: " "))
                .font(.body.weight(.medium).monospaced())
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .background(Theme.Palette.surfaceRaised, in: .rect(cornerRadius: Theme.Radius.l, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your address")
        .accessibilityValue(Text(verbatim: groups.joined(separator: ", ")).speechSpellsOutCharacters())
        .accessibilityHint("Copies the address")
    }

    /// Copy and Share right under the address, equal halves of the card.
    /// Large text stacks them: two full-width capsules read better than two
    /// squeezed ones.
    private func addressActions(_ address: String) -> some View {
        let layout = typeSize > .xLarge
            ? AnyLayout(VStackLayout(spacing: Theme.Spacing.s))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.s))
        return layout {
            Button { copy(address) } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel(copied ? "Copied" : "Copy address")

            ShareLink(item: shareText(address),
                      subject: Text(selected == .usdt ? "My USDT (TRC-20) address" : "My TRX address"),
                      preview: SharePreview(Text(selected == .usdt ? "USDT on TRON (TRC-20)" : "TRX on TRON"))) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        // Long translations ("Скопировать", "Поделиться") shrink a little rather than wrap or clip.
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// Payments that arrived while the screen was open, newest first.
    private var receivedList: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text("Received now")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.xxs)
                .accessibilityAddTraits(.isHeader)

            ForEach(received) { payment in
                ReceivedRow(payment: payment) {
                    if let transfer = payment.transfer { detail = transfer }
                } onDismiss: {
                    withAnimation(motion()) { received.removeAll { $0.id == payment.id } }
                }
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .transition(.opacity)
    }

    private var feesRow: some View {
        NavigationLink(value: HomeRoute.fees) {
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.Palette.accent.gradient, in: .rect(cornerRadius: Theme.Radius.s))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Receiving is free").font(.subheadline.weight(.semibold))
                    Text("Sending USDT needs some TRX for network fees.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .surface(cornerRadius: Theme.Radius.card)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Explains network fees")
    }

    /// A private label for this address, for people who keep several wallets.
    private var nameRow: some View {
        Button {
            nameDraft = addressName
            editingName = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "tag.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.accentText)
                    .frame(width: 40, height: 40)
                    .background(Theme.Palette.surfaceRaised, in: .rect(cornerRadius: Theme.Radius.s))
                VStack(alignment: .leading, spacing: 2) {
                    Text(addressName.isEmpty ? "Address name" : addressName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("Only you see it, on this device.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .padding(12)
            .surface(cornerRadius: Theme.Radius.card)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(addressName.isEmpty ? Text("Add an address name") : Text("Address name: \(addressName)"))
        .accessibilityHint("Only you see it, on this device.")
        .accessibilityAddTraits(.isButton)
    }

    private var noWallet: some View {
        ContentUnavailableView {
            Label("No wallet on this device", systemImage: "wallet.pass")
        } description: {
            Text("Create or restore a wallet to get an address for receiving USDT and TRX.")
        }
    }

    // MARK: Actions

    private func copy(_ address: String) {
        // The address only, never the payment URI: it's what people paste into
        // an exchange's withdraw form. It's public, so no expiry.
        UIPasteboard.general.string = address
        Haptics.success()
        AccessibilityNotification.Announcement(tr("Address copied")).post()
        withAnimation(.snappy) { copied = true }
        copyTask?.cancel()
        copyTask = Task {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { copied = false }
        }
    }

    private func shareText(_ address: String) -> String {
        let uri = ReceiveLogic.paymentPayload(address: address, token: selected, units: requestUnits)
        switch (selected, requestUnits) {
        case (.usdt, let units?):
            return tr("Please send \(ReceiveLogic.decimalAmount(units)) USDT on the TRON network (TRC-20) to:\n\(address)\n\nPayment link: \(uri)\n\nSend only USDT on TRON (TRC-20). Other networks lose the funds.")
        case (.trx, let units?):
            return tr("Please send \(ReceiveLogic.decimalAmount(units)) TRX on the TRON network to:\n\(address)\n\nPayment link: \(uri)")
        case (.usdt, nil):
            return tr("My USDT address on the TRON network (TRC-20):\n\(address)\n\nSend only USDT on TRON (TRC-20). Other networks lose the funds.")
        case (.trx, nil):
            return tr("My TRX address on the TRON network:\n\(address)")
        }
    }

    // MARK: Incoming payments

    private func watchForPayments() async {
        evaluate()
        while !Task.isCancelled {
            let latest = [app.lastRefresh, lastAttempt].compactMap { $0 }.max()
            if latest.map({ Date.now.timeIntervalSince($0) >= Self.pollInterval }) ?? true {
                lastAttempt = .now
                await app.refresh()
                evaluate()
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func evaluate() {
        guard let me = app.address else { return }
        var history = app.history
        var trxSun = app.trxSun
        #if DEBUG
        history = debug.injected + history
        trxSun += debug.trxBump
        #endif
        let events = watch.observe(history: history, trxSun: trxSun, myAddress: me,
                                   loaded: app.lastRefresh != nil, watchTRX: true)
        // Each payment is held against what is still owed: after 30 of 50 the
        // request becomes 20, so the rest reads as paid in full, not short again.
        var owed = requestUnits
        var payments: [ReceivedPayment] = []
        for event in events {
            let payment = ReceivedPayment(event, selected: selected, requested: owed)
            if case .short(let rest) = payment.outcome { owed = rest }
            payments.append(payment)
        }
        if owed != requestUnits {
            withAnimation(motion()) { requestUnits = owed }
        }
        guard let pick = ReceiveLogic.celebratedIndex(payments.map(\.outcome)) else { return }
        for payment in payments {
            AccessibilityNotification.Announcement(payment.spoken).post()
        }
        // One payment gets the receipt (its haptic fires with it); the rest of
        // the poll goes straight to the list.
        queue.append(payments.remove(at: pick))
        if !payments.isEmpty {
            withAnimation(motion()) { list(payments) }
        }
        presentNextReceipt()
    }

    private func list(_ payments: [ReceivedPayment]) {
        received.insert(contentsOf: payments, at: 0)
        // Most recent few only; the rest are in Activity.
        if received.count > Self.listLimit { received.removeLast(received.count - Self.listLimit) }
    }

    private func presentNextReceipt() {
        guard celebration == nil, nothingPresented, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        burst += 1
        withAnimation(motion()) { celebration = next }
    }

    /// The receipt holds for a few seconds, then gives the code back. With
    /// VoiceOver it waits to be dismissed: a timer would pull it from under the reader.
    private func holdReceipt() async {
        guard celebration != nil, !UIAccessibility.isVoiceOverRunning else { return }
        #if DEBUG
        if debug.holdReceipt { return }
        #endif
        try? await Task.sleep(for: Self.receiptHold)
        guard !Task.isCancelled else { return }
        settleReceipt()
    }

    /// Receipt → list row. A request that was met is done, so it clears; one
    /// that came up short stays, still waiting for the rest.
    private func settleReceipt() {
        guard let payment = celebration else { return }
        withAnimation(motion()) {
            celebration = nil
            list([payment])
            if payment.outcome.fulfilsRequest, selected == payment.token, requestUnits == payment.requested {
                requestUnits = nil
            }
        }
        presentNextReceipt()
    }
}

// MARK: - Motion

private extension Animation {
    /// The one place Receive decides how things move: the given animation, or
    /// a short fade when Reduce Motion is on.
    static func motion(_ animation: Animation = .snappy, reduced: Bool) -> Animation {
        reduced ? .easeInOut(duration: 0.15) : animation
    }
}

private extension AnyTransition {
    /// Swapping what's on the QR plate: a blur-replace, or a plain fade under Reduce Motion.
    @MainActor
    static func plateSwap(reduced: Bool) -> AnyTransition {
        reduced ? .opacity : AnyTransition(.blurReplace)
    }
}

private extension View {
    /// Reports whether the view is scrolled into sight (iOS 18+; earlier it counts as visible).
    @ViewBuilder
    func trackingScrollVisibility(_ isVisible: Binding<Bool>) -> some View {
        if #available(iOS 18, *) {
            onScrollVisibilityChange(threshold: 0.2) { isVisible.wrappedValue = $0 }
        } else {
            self
        }
    }
}

// MARK: - Received payment

/// A payment that arrived while Receive was open.
private struct ReceivedPayment: Identifiable, Equatable {
    let id: String
    let token: TokenKind
    let units: UInt64
    /// USDT only: TRX arrivals are seen as a balance change, with no transaction.
    let transfer: TokenTransfer?
    /// What was being requested when it arrived, and how the payment compares.
    let requested: UInt64?
    let outcome: RequestOutcome

    init(_ event: IncomingWatch.Event, selected: TokenKind, requested: UInt64?) {
        self.requested = requested
        switch event {
        case .usdt(let transfer):
            id = transfer.id
            token = .usdt
            units = transfer.units
            self.transfer = transfer
            outcome = ReceiveLogic.outcome(paymentToken: .usdt, paymentUnits: transfer.units,
                                           selectedToken: selected, requestedUnits: requested)
        case .trx(let sun):
            id = "trx-\(UUID().uuidString)"
            token = .trx
            units = UInt64(sun)
            transfer = nil
            // A balance change, not a transaction: two top-ups in one poll
            // merge into one number, so it can't be held against a request.
            outcome = .unrelated
        }
    }

    private static func format(_ units: UInt64) -> String {
        USDT.format(units: units, fractionDigits: units % 10_000 == 0 ? 2 : 6)
    }

    var amount: String { Self.format(units) }

    /// The amount with every digit blanked to zero: where the receipt's number rolls in from.
    var amountPlaceholder: String {
        String(amount.map { $0.isNumber ? "0" : $0 })
    }

    var announcement: String {
        if let transfer {
            tr("Received \(amount) \(token.symbol) from \(transfer.from.shortAddress)")
        } else {
            tr("Received \(amount) \(token.symbol)")
        }
    }

    /// How it compares with the request, in words. nil when there's nothing to compare.
    var outcomeText: String? {
        switch outcome {
        case .exact: tr("Matches your request")
        case .over(let by): tr("\(Self.format(by)) \(token.symbol) more than requested")
        case .short(let by): tr("\(Self.format(by)) \(token.symbol) less than requested")
        case .unrelated: nil
        }
    }

    /// The receipt's one-line outcome.
    var outcomeLine: String {
        outcomeText ?? (transfer == nil ? tr("Added to your TRX balance") : tr("Received"))
    }

    /// What VoiceOver hears: the payment, then the outcome.
    var spoken: String {
        [announcement, outcomeText].compactMap { $0 }.joined(separator: ". ")
    }

    var tint: Color { outcome.isShort ? Theme.Palette.warning : Theme.Palette.positive }
    var symbol: String { outcome.isShort ? "exclamationmark.circle.fill" : "checkmark.circle.fill" }
}

private extension RequestOutcome {
    var isShort: Bool {
        if case .short = self { true } else { false }
    }

    /// The request was paid in full (or more), so it has done its job.
    var fulfilsRequest: Bool {
        switch self {
        case .exact, .over: true
        case .short, .unrelated: false
        }
    }
}

/// A settled payment in the "Received now" list. USDT rows open the transfer;
/// the x, or a sideways swipe, dismisses.
private struct ReceivedRow: View {
    let payment: ReceivedPayment
    let onOpen: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: CGFloat = 0

    private static let dismissDistance: CGFloat = 90

    private var summary: some View {
        HStack(spacing: 10) {
            Image(systemName: payment.symbol)
                .font(.title3)
                .foregroundStyle(payment.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Received \(payment.amount) \(payment.token.symbol)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                if let outcome = payment.outcomeText {
                    Text(verbatim: outcome)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(payment.tint)
                } else if let transfer = payment.transfer {
                    Text("From \(transfer.from.shortAddress)")
                        .font(.footnote.monospaced())
                        .foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    Text("Added to your TRX balance")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if payment.transfer != nil {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
    }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                // TRX arrivals have no transaction to open: plain content, not a dimmed button.
                if payment.transfer != nil {
                    Button(action: onOpen) { summary.contentShape(.rect) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows the transfer")
                } else {
                    summary
                }
            }
            .accessibilityElement(children: .combine)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 12)
        .padding(.vertical, Theme.Spacing.xxs)
        .surface(cornerRadius: Theme.Radius.l)
        .offset(x: drag)
        .opacity(1 - min(abs(drag) / (Self.dismissDistance * 2), 0.6))
        // Starts late and only sideways, so scrolling the page still wins.
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    drag = value.translation.width
                }
                .onEnded { value in
                    if abs(drag) > Self.dismissDistance, abs(value.translation.width) > abs(value.translation.height) {
                        onDismiss()
                    } else {
                        withAnimation(.motion(reduced: reduceMotion)) { drag = 0 }
                    }
                }
        )
    }
}

// MARK: - Request headline

/// The card's headline: the amount being waited for (tap to change, x to
/// clear), or "Ready to receive" with a way to ask for an amount.
private struct RequestHeadline: View {
    let units: UInt64?
    let symbol: String
    let onEdit: () -> Void
    let onClear: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var amountSize: CGFloat = 34

    private static let maxAmountSize: CGFloat = 44

    var body: some View {
        ZStack {
            if let units {
                waiting(units).transition(.opacity)
            } else {
                ready.transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.motion(reduced: reduceMotion), value: units)
    }

    private func waiting(_ units: UInt64) -> some View {
        VStack(spacing: 2) {
            Text("Waiting for")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
                .textCase(.uppercase)
                .accessibilityHidden(true)

            Button(action: onEdit) {
                Text(verbatim: "\(ReceiveLogic.decimalAmount(units)) \(symbol)")
                    .font(Theme.Typography.amount(min(amountSize, Self.maxAmountSize)))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Requesting \(ReceiveLogic.decimalAmount(units)) \(symbol)"))
            .accessibilityHint("Changes the amount")
            // Room for the x on the right, and the same on the left so the amount stays centred.
            .padding(.horizontal, 44)
            .overlay(alignment: .trailing) {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear amount")
            }
        }
    }

    private var ready: some View {
        VStack(spacing: 2) {
            Text("Ready to receive")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.center)
            Button(action: onEdit) {
                Label("Request an amount", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.accentText)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Live QR plate

/// The white plate: the QR code, or for a moment the receipt of a payment
/// that just landed, at exactly the same size. The halo sits behind the
/// plate and never touches the code or its quiet zone.
private struct LiveQRPlate: View {
    let payload: String
    let token: TokenKind
    let label: String
    let receipt: ReceivedPayment?
    let halo: ListeningHalo.Mode
    let haloShown: Bool
    let checked: Date?
    let burst: Int
    let onDismissReceipt: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let swap = AnyTransition.plateSwap(reduced: reduceMotion)
        // A fixed square, so swapping what's on the plate can't resize it.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    if let receipt {
                        ReceiptFace(payment: receipt, onTap: onDismissReceipt)
                            // One receipt straight after another is a new face, not an edited one.
                            .id(receipt.id)
                            .transition(swap)
                    } else {
                        TetherQRCode(text: payload, token: token, label: label)
                            .transition(swap)
                    }
                }
                .animation(.motion(reduced: reduceMotion), value: payload)
                .animation(.motion(reduced: reduceMotion), value: receipt?.id)
            }
            // Dark modules on a white plate in both modes: scanners need the contrast.
            .padding(12)
            .background(Color.white, in: .rect(cornerRadius: Theme.Radius.l, style: .continuous))
            .background {
                ListeningHalo(mode: halo, tint: receipt?.tint ?? Theme.Palette.positive,
                              checked: checked, burst: burst)
                    .opacity(haloShown ? 1 : 0)
            }
    }
}

/// A ring just outside the plate. It breathes out while the wallet is being
/// checked, ripples once when a check completes and bursts once when a
/// payment lands. Anything else (offline, Low Power Mode, out of sight,
/// Reduce Motion) is a still ring.
private struct ListeningHalo: View {
    enum Mode { case listening, still, offline }

    let mode: Mode
    let tint: Color
    /// Changes when a network check completes.
    let checked: Date?
    /// Counts receipts: each one bursts once.
    let burst: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The 2 pt line starts 6 pt outside the plate's edge.
    private static let gap: CGFloat = 6
    private static let lineWidth: CGFloat = 2
    private static let restOpacity = 0.35

    /// The slow loop.
    private enum Breath: CaseIterable {
        case rest, out, reset

        var scale: CGFloat { self == .out ? 1.06 : 1 }
        var opacity: Double { self == .rest ? 0.45 : 0 }
        var animation: Animation {
            switch self {
            case .out: .easeOut(duration: 2.4)
            case .reset: .linear(duration: 0.05)
            case .rest: .easeIn(duration: 0.35)
            }
        }
    }

    /// One ring that flashes and spreads, once per trigger.
    private enum Ripple: CaseIterable {
        case idle, flash, spread

        func scale(to spread: CGFloat) -> CGFloat { self == .spread ? spread : 1 }
        func opacity(peak: Double) -> Double { self == .flash ? peak : 0 }
        func animation(duration: Double) -> Animation {
            switch self {
            case .idle: .linear(duration: 0.05)
            case .flash: .easeOut(duration: 0.12)
            case .spread: .easeOut(duration: duration)
            }
        }
    }

    private func ring(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.l + Self.gap + Self.lineWidth, style: .continuous)
            .strokeBorder(color, lineWidth: Self.lineWidth)
    }

    var body: some View {
        ZStack {
            ring(mode == .offline ? Theme.Palette.textTertiary : tint)
                .opacity(Self.restOpacity)

            if !reduceMotion {
                if mode == .listening {
                    PhaseAnimator(Breath.allCases) { phase in
                        ring(tint).scaleEffect(phase.scale).opacity(phase.opacity)
                    } animation: { $0.animation }

                    PhaseAnimator(Ripple.allCases, trigger: checked) { phase in
                        ring(tint).scaleEffect(phase.scale(to: 1.1)).opacity(phase.opacity(peak: 0.9))
                    } animation: { $0.animation(duration: 0.9) }
                }

                PhaseAnimator(Ripple.allCases, trigger: burst) { phase in
                    ring(tint).scaleEffect(phase.scale(to: 1.25)).opacity(phase.opacity(peak: 1))
                } animation: { $0.animation(duration: 0.7) }
            }
        }
        .padding(-(Self.gap + Self.lineWidth))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// What the plate shows while a payment is being celebrated: a check, the
/// amount, how it compares with the request, and who sent it. Tap for the code.
private struct ReceiptFace: View {
    let payment: ReceivedPayment
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: payment.symbol)
                    .font(.system(size: 44))
                    .foregroundStyle(payment.tint)
                    .symbolEffect(.bounce, value: revealed)

                // The real amount rolls in over blanked digits. It never
                // counts up through amounts that weren't paid.
                Text(verbatim: "+\(revealed ? payment.amount : payment.amountPlaceholder) \(payment.token.symbol)")
                    .font(Theme.Typography.amount(26))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: revealed ? Double(payment.units) : 0))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text(verbatim: payment.outcomeLine)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(payment.tint)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                if let transfer = payment.transfer {
                    Text("From \(transfer.from.shortAddress)")
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(Theme.Spacing.xxs)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // The plate is white in both appearances, so the receipt is always the light palette.
        .environment(\.colorScheme, .light)
        // The plate doesn't grow with text size; the largest sizes would only clip.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityLabel(Text(verbatim: payment.spoken))
        .accessibilityHint("Tap to show the code")
        .onAppear {
            if reduceMotion {
                revealed = true
            } else {
                withAnimation(.snappy) { revealed = true }
            }
        }
    }
}

// MARK: - Details

/// "Details": what to know about the address, under a header that shows or
/// hides it. Side by side (iPad) it's always open and has no chevron.
private struct DetailsSection<Content: View>: View {
    @Binding var expanded: Bool
    @ViewBuilder var content: Content

    @Environment(\.isSideBySide) private var isSideBySide
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far the clip reaches past the cards, so their shadows aren't cut.
    private var shadowRoom: CGFloat { 20 }

    private var title: some View {
        Text("Details")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.Palette.textSecondary)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isSideBySide {
                title
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.xxs)
                    .accessibilityAddTraits(.isHeader)
            } else {
                Button(action: toggle) {
                    HStack {
                        title
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .padding(.horizontal, Theme.Spacing.xxs)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isHeader)
                .accessibilityValue(expanded ? Text("Expanded") : Text("Collapsed"))
                .sensoryFeedback(.selection, trigger: expanded)
            }

            // Clipped at the top so the cards slide out from under the header,
            // with room on the other sides for their shadows.
            VStack(spacing: 0) {
                if expanded || isSideBySide {
                    VStack(spacing: 12) { content }
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding([.horizontal, .bottom], shadowRoom)
            .clipped()
            .padding([.horizontal, .bottom], -shadowRoom)
        }
    }

    private func toggle() {
        withAnimation(.motion(reduced: reduceMotion)) { expanded.toggle() }
        Task {
            // After the cards have settled, so VoiceOver finds them in place.
            try? await Task.sleep(for: .milliseconds(350))
            AccessibilityNotification.LayoutChanged().post()
        }
    }
}

// MARK: - Notices

/// Refresh failing: say so without blocking anything. The address and QR
/// never need the network.
private struct OfflineNotice: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.headline)
                .foregroundStyle(Theme.Palette.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Can't check for new payments")
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: message)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
                Text("Your address and QR code still work. Payments sent now will show up once the connection is back.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Palette.warning.opacity(0.12))
                .strokeBorder(Theme.Palette.warning.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}


/// Which network and coin this address takes, and what happens otherwise.
/// The headline is a strip that's always on the address card; the rest lives in Details.
private struct NetworkWarning: View {
    enum Style { case strip, body }

    let token: TokenKind
    let trxSun: Int64
    let transfersLeft: Int64
    let style: Style

    var body: some View {
        switch style {
        case .strip: strip
        case .body: paragraphs
        }
    }

    /// Never collapsed, never truncated: the one line nobody may miss.
    private var strip: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Palette.warning)
                .accessibilityHidden(true)
            Text(token == .usdt ? "Send only USDT on TRON (TRC-20)" : "Send only TRX on the TRON network")
                .foregroundStyle(Theme.Palette.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                .fill(Theme.Palette.warning.opacity(0.12))
                .strokeBorder(Theme.Palette.warning.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var paragraphs: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            switch token {
            case .usdt:
                Text("USDT sent on another network, such as Ethereum (ERC-20) or BNB Chain (BEP-20), or any other token, will be lost for good.")
                Text("TRX for fees can be sent to this same address.")
            case .trx:
                Text("TRX pays the network fee when you send USDT: about 7–14 TRX per transfer. When withdrawing from an exchange, choose the TRON (TRX) network.")
                Text("You have \(TRX.format(sun: trxSun)) TRX, enough for about \(transfersLeft) transfers. USDT (TRC-20) arrives at this same address.")
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.Palette.textSecondary)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surface(cornerRadius: Theme.Radius.card)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Request an amount

private struct AmountRequestSheet: View {
    let token: TokenKind
    let initial: UInt64?
    let onSet: (UInt64) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var showProblem = false
    @FocusState private var focused: Bool

    private var input: ReceiveLogic.AmountInput { ReceiveLogic.parseAmount(text) }

    private var problem: LocalizedStringKey? {
        switch input {
        case .valid, .empty: nil
        case .invalid: "Enter a number, like 25 or 12.50."
        case .zero: "Enter an amount above zero."
        case .tooManyDecimals: "Use up to 6 decimal places."
        case .tooLarge: "That amount is too large."
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("0", text: $text)
                        .font(Theme.Typography.amount(44))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        .fixedSize()
                        .accessibilityLabel(Text("Amount in \(token.symbol)"))
                    Text(verbatim: token.symbol)
                        .font(Theme.Typography.amount(26, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .surface(cornerRadius: Theme.Radius.panel)
                .onTapGesture { focused = true }

                Group {
                    if showProblem, let problem {
                        Text(problem).foregroundStyle(Theme.Palette.danger)
                    } else {
                        Text(token == .usdt
                             ? "The QR code and share link will ask for this amount of USDT on TRON."
                             : "The QR code and share link will ask for this amount of TRX.")
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                }
                .font(.footnote)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

                Button("Set amount") { submit() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(input == .empty)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, 8)
            .readableWidth()
            .background(Theme.Palette.background)
            .navigationTitle("Request an amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: text) { showProblem = false }
            .onAppear {
                if let initial { text = ReceiveLogic.decimalAmount(initial) }
                focused = true
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.Palette.background)
    }

    private func submit() {
        guard case .valid(let units) = input else {
            showProblem = true
            Haptics.error()
            return
        }
        Haptics.tap()
        onSet(units)
        dismiss()
    }
}


// MARK: - QR

/// The QR modules in slate with the coin's mark in the middle (high error
/// correction keeps it scannable under the mark). The white plate and its
/// quiet zone belong to `LiveQRPlate`.
private struct TetherQRCode: View {
    let text: String
    let token: TokenKind
    let label: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let image = QRModules.image(for: text) {
            ZStack {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(LinearGradient(colors: [Theme.Palette.qrStart, Theme.Palette.qrEnd],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    // A new coin or amount is a new code: only the modules swap, the plate stays put.
                    .id(text)
                    .transition(.plateSwap(reduced: reduceMotion))

                TokenIcon(token: token, size: 44)
                    .padding(6)
                    .background(Color.white, in: .circle)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: label))
            .accessibilityAddTraits(.isImage)
        } else {
            // CoreImage failing is near impossible; the address below still works.
            Label("QR code unavailable. Copy the address below.", systemImage: "qrcode")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.qrStart)
                .multilineTextAlignment(.center)
        }
    }
}

/// QR images by payload. Views re-run their bodies on every animation frame
/// around them; the code is rendered once and reused.
@MainActor
private enum QRModules {
    private static var cache: [String: UIImage] = [:]
    private static let context = CIContext()
    /// A screen's worth of coin and amount changes; past that, start over.
    private static let limit = 24

    static func image(for text: String) -> UIImage? {
        if let cached = cache[text] { return cached }
        guard let image = render(text) else { return nil }
        if cache.count >= limit { cache.removeAll() }
        cache[text] = image
        return image
    }

    /// The QR modules as opaque pixels on transparent, ready to tint.
    private static func render(_ text: String) -> UIImage? {
        let qr = CIFilter.qrCodeGenerator()
        qr.message = Data(text.utf8)
        qr.correctionLevel = "H"
        let invert = CIFilter.colorInvert()
        invert.inputImage = qr.outputImage
        let mask = CIFilter.maskToAlpha()
        mask.inputImage = invert.outputImage
        guard let output = mask.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Debug hooks

#if DEBUG
/// Launch flags for screenshots and UI checks (with `-demo -route receive`):
/// `-receive-token trx`, `-receive-amount 50`, `-receive-simulate` (a payment
/// lands after 2 s), `-receive-simulate-short` (it's less than the request;
/// asks for 50 if no amount is given), `-receive-receipt` (opens on the
/// receipt and holds it, no timer), `-receive-offline`, `-receive-nowallet`.
private struct DebugHooks {
    private static var args: [String] { CommandLine.arguments }
    var injected: [TokenTransfer] = []
    var trxBump: Int64 = 0

    var offline: Bool { Self.args.contains("-receive-offline") }
    var noWallet: Bool { Self.args.contains("-receive-nowallet") }
    var holdReceipt: Bool { Self.args.contains("-receive-receipt") }

    private static var short: Bool { args.contains("-receive-simulate-short") }

    private static func value(after flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    static func launchState(token: inout TokenKind, units: inout UInt64?) {
        if let raw = value(after: "-receive-token"), let kind = TokenKind(rawValue: raw) { token = kind }
        if let raw = value(after: "-receive-amount"), case .valid(let value) = ReceiveLogic.parseAmount(raw) { units = value }
        // A short payment needs a request to be short of.
        if short, units == nil { units = 50_000_000 }
    }

    static func simulatedArrival(token: TokenKind, units: UInt64?, me: String) async
        -> (injected: [TokenTransfer], trxBump: Int64)? {
        let receipt = args.contains("-receive-receipt")
        guard args.contains("-receive-simulate") || short || receipt else { return nil }
        try? await Task.sleep(for: receipt ? .milliseconds(500) : .seconds(2))
        guard !Task.isCancelled else { return nil }
        let full = units ?? (token == .trx ? 25_000_000 : 50_000_000)
        let amount = short ? max(full * 3 / 5, 1) : full
        switch token {
        case .trx: return ([], Int64(amount))
        case .usdt:
            let transfer = TokenTransfer(id: "f0e1d2c3b4a5f6e7d8c9b0a1f2e3d4c5b6a7f8e9d0c1b2a3f4e5d6c7b8a9f0e1",
                                         date: .now, from: "TLa2f6VPqDgRE67v1736s7bJ8Ray5wYjU7", to: me,
                                         units: amount)
            return ([transfer], 0)
        }
    }
}
#endif
