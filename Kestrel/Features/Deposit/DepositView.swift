import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Receive: the address as a QR code, copy and share, an optional requested
/// amount, and a live "Received" banner when a payment lands while it's open.
///
/// `token` is what the screen was opened for: USDT by default, TRX from the
/// TRX coin screen's "Add TRX". The address is the same for both; the token
/// changes the warning, the QR's payment URI and the share text.
struct DepositView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("receive.addressName") private var addressName = ""

    @State private var selected: TokenKind
    @State private var requestUnits: UInt64?
    @State private var editingAmount = false
    @State private var copied = false
    @State private var copyTask: Task<Void, Never>?
    @State private var editingName = false
    @State private var nameDraft = ""
    @State private var watch = IncomingWatch()
    @State private var received: [ReceivedPayment] = []
    @State private var detail: TokenTransfer?
    @State private var lastAttempt: Date?
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
                withAnimation(.snappy) { requestUnits = units }
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
        .onChange(of: app.history) { evaluate() }
        .onChange(of: app.trxSun) { evaluate() }
        .onChange(of: selected) {
            // A requested amount is in one coin; it doesn't carry over to the other.
            requestUnits = nil
        }
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

    // MARK: Content

    private func content(_ address: String) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                PillPicker(selection: $selected, options: [.usdt, .trx]) { $0 == .usdt ? "USDT" : "TRX" }
                    .accessibilityLabel("Coin to receive")

                ForEach(received) { payment in
                    ReceivedBanner(payment: payment, requested: requestUnits) {
                        if let transfer = payment.transfer { detail = transfer }
                    } onDismiss: {
                        withAnimation(.snappy) { received.removeAll { $0.id == payment.id } }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let refreshError {
                    OfflineNotice(message: refreshError)
                        .transition(.opacity)
                }

                addressCard(address)
                NetworkWarning(token: selected, trxSun: app.trxSun, transfersLeft: app.transfersLeft)
                if refreshError == nil { listeningStatus }
                feesRow
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, 4)
            .padding(.bottom, 16)
            .readableWidth()
            .animation(.snappy, value: refreshError)
        }
        .safeAreaInset(edge: .bottom) { actionBar(address) }
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

            TetherQRCode(text: payload, token: selected,
                         label: requestUnits.map { qrLabel(units: $0) } ?? String(localized: "QR code of your wallet address"))
                .frame(maxWidth: 224)

            requestRow

            Button {
                nameDraft = addressName
                editingName = true
            } label: {
                HStack(spacing: 6) {
                    Text(addressName.isEmpty ? "Address name" : addressName)
                        .foregroundStyle(addressName.isEmpty ? Theme.Palette.textTertiary : Theme.Palette.textPrimary)
                    Image(systemName: "pencil").foregroundStyle(Theme.Palette.textSecondary)
                }
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(addressName.isEmpty ? Text("Add an address name") : Text("Address name: \(addressName)"))
            .accessibilityHint("Only you see it, on this device.")

            groupedAddress(address)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 18)
        .surface(cornerRadius: Theme.Radius.panel)
    }

    private func qrLabel(units: UInt64) -> String {
        String(localized: "QR code requesting \(ReceiveLogic.decimalAmount(units)) \(selected.symbol)")
    }

    /// "Request an amount", or the amount being requested with edit and clear.
    @ViewBuilder
    private var requestRow: some View {
        if let units = requestUnits {
            HStack(spacing: 10) {
                Button {
                    editingAmount = true
                } label: {
                    VStack(spacing: 2) {
                        Text("Requesting")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .textCase(.uppercase)
                        Text(verbatim: "\(ReceiveLogic.decimalAmount(units)) \(selected.symbol)")
                            .font(Theme.Typography.amount(26))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Requesting \(ReceiveLogic.decimalAmount(units)) \(selected.symbol)"))
                .accessibilityHint("Changes the amount")

                Button {
                    Haptics.tap()
                    withAnimation(.snappy) { requestUnits = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear amount")
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
            .padding(.vertical, 6)
            .background(Theme.Palette.surfaceRaised, in: .rect(cornerRadius: Theme.Radius.l, style: .continuous))
        } else {
            Button {
                Haptics.tap()
                editingAmount = true
            } label: {
                Label("Request an amount", systemImage: "plus.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.accentText)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    /// The full address in groups of four, tap to copy. VoiceOver spells it
    /// out a group at a time.
    private func groupedAddress(_ address: String) -> some View {
        let groups = ReceiveLogic.addressGroups(address)
        return Button { copy(address) } label: {
            VStack(spacing: 8) {
                Text(verbatim: groups.joined(separator: " "))
                    .font(.body.weight(.medium).monospaced())
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Label(copied ? "Copied" : "Tap to copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(copied ? Theme.Palette.positive : Theme.Palette.textSecondary)
                    .contentTransition(.symbolEffect(.replace))
            }
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

    private var listeningStatus: some View {
        HStack(spacing: 10) {
            PulsingDot()
            Text("Watching for incoming payments")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer(minLength: 4)
            if let last = app.lastRefresh {
                Text("Checked \(last, style: .relative) ago")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .accessibilityLabel(Text("Last checked \(last, style: .relative) ago"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .surface(cornerRadius: Theme.Radius.card)
        .accessibilityElement(children: .combine)
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

    private func actionBar(_ address: String) -> some View {
        // Copying lives on the address card ("Tap to copy"); the bar is just Share.
        ShareLink(item: shareText(address),
                  subject: Text(selected == .usdt ? "My USDT (TRC-20) address" : "My TRX address"),
                  preview: SharePreview(Text(selected == .usdt ? "USDT on TRON (TRC-20)" : "TRX on TRON"))) {
            Label("Share", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .readableWidth()
        .background(alignment: .top) {
            // Solid, so the scrolled address never shows through the buttons;
            // a short fade above it softens the edge.
            Theme.Palette.background
                .overlay(alignment: .top) {
                    LinearGradient(colors: [Theme.Palette.background.opacity(0), Theme.Palette.background],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 16)
                        .offset(y: -16)
                }
        }
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
        AccessibilityNotification.Announcement(String(localized: "Address copied")).post()
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
            return String(localized: "Please send \(ReceiveLogic.decimalAmount(units)) USDT on the TRON network (TRC-20) to:\n\(address)\n\nPayment link: \(uri)\n\nSend only USDT on TRON (TRC-20). Other networks lose the funds.")
        case (.trx, let units?):
            return String(localized: "Please send \(ReceiveLogic.decimalAmount(units)) TRX on the TRON network to:\n\(address)\n\nPayment link: \(uri)")
        case (.usdt, nil):
            return String(localized: "My USDT address on the TRON network (TRC-20):\n\(address)\n\nSend only USDT on TRON (TRC-20). Other networks lose the funds.")
        case (.trx, nil):
            return String(localized: "My TRX address on the TRON network:\n\(address)")
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
        guard !events.isEmpty else { return }
        let payments = events.map(ReceivedPayment.init)
        Haptics.success()
        for payment in payments {
            AccessibilityNotification.Announcement(payment.announcement).post()
        }
        withAnimation(.snappy) {
            received.insert(contentsOf: payments, at: 0)
            // Most recent few only; the rest are in Activity.
            if received.count > 3 { received.removeLast(received.count - 3) }
        }
    }
}

// MARK: - Received payment

/// A payment that arrived while Receive was open.
private struct ReceivedPayment: Identifiable {
    let id: String
    let token: TokenKind
    let units: UInt64
    /// USDT only: TRX arrivals are seen as a balance change, with no transaction.
    let transfer: TokenTransfer?

    init(_ event: IncomingWatch.Event) {
        switch event {
        case .usdt(let transfer):
            id = transfer.id
            token = .usdt
            units = transfer.units
            self.transfer = transfer
        case .trx(let sun):
            id = "trx-\(UUID().uuidString)"
            token = .trx
            units = UInt64(sun)
            transfer = nil
        }
    }

    var amount: String {
        USDT.format(units: units, fractionDigits: units % 10_000 == 0 ? 2 : 6)
    }

    var announcement: String {
        if let transfer {
            String(localized: "Received \(amount) \(token.symbol) from \(transfer.from.shortAddress)")
        } else {
            String(localized: "Received \(amount) \(token.symbol)")
        }
    }
}

private struct ReceivedBanner: View {
    let payment: ReceivedPayment
    let requested: UInt64?
    let onOpen: () -> Void
    let onDismiss: () -> Void

    private var matchesRequest: Bool { requested == payment.units }

    private var summary: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(Theme.Palette.positive)
                .symbolEffect(.bounce, value: payment.id)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Received \(payment.amount) \(payment.token.symbol)")
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.textPrimary)
                if let transfer = payment.transfer {
                    Text("From \(transfer.from.shortAddress)")
                        .font(.footnote.monospaced())
                        .foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    Text("Added to your TRX balance")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                if matchesRequest {
                    Label("Matches your request", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.Palette.positive)
                }
            }
            Spacer(minLength: 0)
            if payment.transfer != nil {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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
                    .frame(width: 28, height: 28)
                    .background(Theme.Palette.surfaceRaised, in: .circle)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .padding(.top, -8)
            .padding(.trailing, -8)
            .accessibilityLabel("Dismiss")
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Palette.positive.opacity(0.12))
                .strokeBorder(Theme.Palette.positive.opacity(0.35), lineWidth: 1)
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
private struct NetworkWarning: View {
    let token: TokenKind
    let trxSun: Int64
    let transfersLeft: Int64

    private var feeTRX: String { ReceiveLogic.decimalAmount(UInt64(TRX.minimumForTransferSun)) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Theme.Palette.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                switch token {
                case .usdt:
                    Text("Send only USDT on TRON (TRC-20)")
                        .font(.subheadline.weight(.semibold))
                    Text("USDT sent on another network, such as Ethereum (ERC-20) or BNB Chain (BEP-20), or any other token, will be lost for good.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Text("TRX for fees can be sent to this same address.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.textSecondary)
                case .trx:
                    Text("Send only TRX on the TRON network")
                        .font(.subheadline.weight(.semibold))
                    Text("TRX pays the network fee when you send USDT: about \(feeTRX) TRX per transfer. When withdrawing from an exchange, choose the TRON (TRX) network.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Text("You have \(TRX.format(sun: trxSun)) TRX, enough for about \(transfersLeft) transfers. USDT (TRC-20) arrives at this same address.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .surface(cornerRadius: Theme.Radius.card)
        .accessibilityElement(children: .combine)
    }
}

private struct PulsingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Theme.Palette.positive)
            .frame(width: 8, height: 8)
            .background {
                Circle()
                    .fill(Theme.Palette.positive.opacity(0.35))
                    .scaleEffect(pulse ? 2.4 : 1)
                    .opacity(pulse ? 0 : 1)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
            }
            .accessibilityHidden(true)
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

/// The QR in slate with the coin's mark in the middle (high error correction
/// keeps it scannable under the mark).
private struct TetherQRCode: View {
    let text: String
    let token: TokenKind
    let label: String

    var body: some View {
        if let image = Self.modules(text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(LinearGradient(colors: [Theme.Palette.qrStart, Theme.Palette.qrEnd],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    TokenIcon(token: token, size: 44)
                        .padding(6)
                        .background(Color.white, in: .circle)
                }
                // Dark modules on a white plate in both modes: scanners need the contrast.
                .padding(12)
                .background(Color.white, in: .rect(cornerRadius: Theme.Radius.l, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: label))
                .accessibilityAddTraits(.isImage)
        } else {
            // CoreImage failing is near impossible; the address below still works.
            Label("QR code unavailable. Copy the address below.", systemImage: "qrcode")
                .font(.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    /// The QR modules as opaque pixels on transparent, ready to tint.
    private static func modules(_ text: String) -> UIImage? {
        let qr = CIFilter.qrCodeGenerator()
        qr.message = Data(text.utf8)
        qr.correctionLevel = "H"
        let invert = CIFilter.colorInvert()
        invert.inputImage = qr.outputImage
        let mask = CIFilter.maskToAlpha()
        mask.inputImage = invert.outputImage
        guard let output = mask.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Debug hooks

#if DEBUG
/// Launch flags for screenshots and UI checks (with `-demo -route receive`):
/// `-receive-token trx`, `-receive-amount 50`, `-receive-simulate` (a payment
/// lands after 2 s), `-receive-offline`, `-receive-nowallet`.
private struct DebugHooks {
    private static var args: [String] { CommandLine.arguments }
    var injected: [TokenTransfer] = []
    var trxBump: Int64 = 0

    var offline: Bool { Self.args.contains("-receive-offline") }
    var noWallet: Bool { Self.args.contains("-receive-nowallet") }

    private static func value(after flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    static func launchState(token: inout TokenKind, units: inout UInt64?) {
        if let raw = value(after: "-receive-token"), let kind = TokenKind(rawValue: raw) { token = kind }
        if let raw = value(after: "-receive-amount"), case .valid(let value) = ReceiveLogic.parseAmount(raw) { units = value }
    }

    static func simulatedArrival(token: TokenKind, units: UInt64?, me: String) async
        -> (injected: [TokenTransfer], trxBump: Int64)? {
        guard args.contains("-receive-simulate") else { return nil }
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { return nil }
        switch token {
        case .trx: return ([], Int64(units ?? 25_000_000))
        case .usdt:
            let transfer = TokenTransfer(id: "f0e1d2c3b4a5f6e7d8c9b0a1f2e3d4c5b6a7f8e9d0c1b2a3f4e5d6c7b8a9f0e1",
                                         date: .now, from: "TLa2f6VPqDgRE67v1736s7bJ8Ray5wYjU7", to: me,
                                         units: units ?? 50_000_000)
            return ([transfer], 0)
        }
    }
}
#endif
