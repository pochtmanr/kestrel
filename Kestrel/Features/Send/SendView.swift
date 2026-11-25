import SwiftUI

/// Send USDT in two steps: where to (address, network, fee), then how much
/// (big amount, balance, keypad). Review and PIN/Face ID confirm as before.
struct SendView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var recipient: String
    @State private var path: [Step] = []

    init(recipient: String = "", amount: String = "") {
        _recipient = State(initialValue: recipient)
        _amount = State(initialValue: amount)
    }
    @State private var amount: String
    @State private var showScanner = false
    @State private var showReview = false
    @State private var showPIN = false
    @State private var showSupport = false
    @State private var sending = false
    @State private var sentTxID: String?
    @State private var sentUnits: UInt64 = 0
    @State private var repeatTo: String?
    @State private var error: String?

    private enum Step: Hashable { case amount }

    private var trimmedRecipient: String { recipient.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var recipientValid: Bool { TronAddress.isValid(trimmedRecipient) }
    private var units: UInt64? { USDT.units(from: amount) }

    private var addressProblem: String? {
        if !recipient.isEmpty && !recipientValid { return "That isn't a valid TRON address." }
        if trimmedRecipient == app.address { return "That's your own address." }
        return nil
    }

    private var amountProblem: String? {
        if !amount.isEmpty, let units {
            if units < 1_000_000 { return "Minimum transfer is 1 USDT." }
            if units > app.usdtUnits { return "More than your balance." }
        }
        if !app.hasGasForTransfer { return "You need at least 14 TRX for the network fee." }
        return nil
    }

    private var canContinue: Bool { recipientValid && addressProblem == nil }
    private var canReview: Bool { canContinue && units != nil && amountProblem == nil }

    var body: some View {
        NavigationStack(path: $path) {
            addressStep
                .navigationDestination(for: Step.self) { _ in amountStep }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Close")
                    }
                }
        }
        .onAppear {
            // Repeat payment: the address is known, go straight to the amount.
            if canContinue && path.isEmpty { path = [.amount] }
        }
        .sheet(isPresented: $showScanner) {
            QRScannerSheet { scanned in
                recipient = Self.address(fromScan: scanned)
                showScanner = false
            }
        }
        .sheet(isPresented: $showReview) {
            ReviewTransferSheet(recipient: trimmedRecipient, units: units ?? 0, sending: sending) {
                authorize()
            }
        }
        .sheet(isPresented: $showPIN) {
            ConfirmWithPINSheet(title: "Confirm transfer") { send() }
        }
        .sheet(isPresented: $showSupport) { SupportChatSheet() }
        // Step 3: the transfer's details, "Processing" until TRON confirms it.
        .fullScreenCover(item: Binding(get: { sentTxID.map(SentTransfer.init) }, set: { sentTxID = $0?.id }), onDismiss: {
            // Repeat payment: same address, new amount. Otherwise the send is done.
            if let to = repeatTo {
                recipient = to
                amount = ""
                path = [.amount]
                repeatTo = nil
            } else {
                dismiss()
            }
        }) { sent in
            TransferDetailView(
                transfer: TokenTransfer(id: sent.id, date: .now, from: app.address ?? "", to: trimmedRecipient, units: sentUnits),
                myAddress: app.address ?? "",
                onRepeat: { to in
                    repeatTo = to
                    sentTxID = nil
                },
                pending: true
            )
        }
        .alert("Transfer failed", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    // MARK: Step 1 — where to

    private var addressStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Send").font(.system(size: 32, weight: .bold))

                HStack(spacing: 14) {
                    TextField("Destination address", text: $recipient, axis: .vertical)
                        .font(recipient.isEmpty ? .body : .body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button { showScanner = true } label: { Image(systemName: "qrcode.viewfinder") }
                        .accessibilityLabel("Scan QR code")
                    Button {
                        recipient = Clipboard.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? recipient
                    } label: { Image(systemName: "doc.on.clipboard") }
                        .accessibilityLabel("Paste address")
                }
                .font(.title3)
                .foregroundStyle(.primary)
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .frame(minHeight: 60)
                .surface(cornerRadius: Theme.Radius.card)

                if let addressProblem {
                    Text(addressProblem).font(.footnote).foregroundStyle(Theme.Palette.danger).padding(.horizontal, 4)
                }

                Text("Network").font(.headline).foregroundStyle(.secondary).padding(.horizontal, 4).padding(.top, 6)
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        TokenIcon(token: .trx, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tron")
                            Text("TRC-20").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 68)
                    Divider().padding(.leading, 16)
                    infoRow("Transfer time", icon: "timer", value: "≈ 1 minute")
                    Divider().padding(.leading, 16)
                    infoRow("Network fee", icon: "bolt", value: "≈ 13–14 TRX",
                            warning: app.hasGasForTransfer ? nil : "You have \(TRX.format(sun: app.trxSun)) TRX")
                }
                .surface(cornerRadius: Theme.Radius.card)

                Text("Transfers on the blockchain can't be reversed. Check the address.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .readableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.Palette.background)
        .safeAreaInset(edge: .bottom) {
            BlackButton(title: "Next", enabled: canContinue) { path = [.amount] }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.bottom, 8)
                .readableWidth()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { SupportButton(inToolbar: true) { showSupport = true } }
        }
    }

    private func infoRow(_ title: String, icon: String, value: String, warning: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 26)
            Text(title).foregroundStyle(.secondary).lineLimit(1).layoutPriority(1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                if let warning { Text(warning).font(.caption).foregroundStyle(Theme.Palette.warning) }
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
    }

    // MARK: Step 2 — how much

    private var amountStep: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(amount.isEmpty ? "0" : amount)
                        .foregroundStyle(amount.isEmpty ? Color.secondary : Color.primary)
                        .contentTransition(.numericText())
                    Text("USDT").foregroundStyle(Theme.Palette.accentText)
                        .font(Theme.Typography.amount(36, weight: .bold))
                }
                .font(Theme.Typography.amount(56, weight: .bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .padding(.horizontal, Theme.Spacing.screen)

                Button { fillMax() } label: {
                    Label("\(balanceText) USDT", systemImage: "wallet.bifold")
                        .font(.body.weight(.medium).monospacedDigit())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .surface(cornerRadius: Theme.Radius.tile)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Sends your whole balance")

                Text(amountProblem ?? " ")
                    .font(.footnote)
                    .foregroundStyle(amountProblem?.contains("TRX") == true ? Theme.Palette.warning : Theme.Palette.danger)
            }
            Spacer()

            HStack(spacing: 12) {
                Button { fillMax() } label: {
                    Text("Max")
                        .font(.headline)
                        .frame(width: 64, height: 56)
                        .surface(cornerRadius: Theme.Radius.hero)
                }
                .buttonStyle(.plain)
                BlackButton(title: "Next", enabled: canReview) { showReview = true }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.bottom, 12)

            AmountKeypad(amount: $amount)
        }
        .background(Theme.Palette.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(trimmedRecipient.shortAddress).font(.headline.monospaced())
                    Text("Tron TRC-20").font(.caption).foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) { SupportButton(inToolbar: true) { showSupport = true } }
        }
    }

    /// The balance with two decimals, or more only when the wallet holds dust.
    private var balanceText: String {
        USDT.format(units: app.usdtUnits, fractionDigits: app.usdtUnits % 10_000 == 0 ? 2 : 6)
    }

    private func fillMax() {
        amount = USDT.format(units: app.usdtUnits, fractionDigits: 6)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    /// Accepts a bare address or a "tron:T…?amount=" style payment URI.
    static func address(fromScan text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = value.firstIndex(of: ":") { value = String(value[value.index(after: colon)...]) }
        if let query = value.firstIndex(of: "?") { value = String(value[..<query]) }
        return value
    }

    private func authorize() {
        if Biometrics.isEnabled {
            Task {
                if await Biometrics.authenticate(reason: "Confirm sending USDT") {
                    send()
                } else {
                    showReview = false
                    showPIN = true
                }
            }
        } else {
            showReview = false
            showPIN = true
        }
    }

    private func send() {
        guard let units, !sending else { return }
        sending = true
        Task {
            defer { sending = false }
            do {
                guard let keys = try WalletVault.keys() else { throw TronClient.Failure.rejected("Wallet not found on this device.") }
                let txID = try await app.tron.sendUSDT(from: keys, to: trimmedRecipient, units: units)
                Haptics.success()
                showReview = false
                sentUnits = units
                sentTxID = txID
                Task { await app.refresh() }
            } catch {
                Haptics.error()
                showReview = false
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.error = message.localizedCaseInsensitiveContains("balance") || message.localizedCaseInsensitiveContains("energy")
                    ? "Not enough USDT or TRX in your wallet. You need about 14 TRX for the network fee."
                    : message
            }
        }
    }
}

/// Full-width black (white in dark mode) capsule button.
private struct BlackButton: View {
    let title: LocalizedStringKey
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.Palette.background)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Color.primary.opacity(enabled ? 1 : 0.3), in: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// The amount keypad: digits, a decimal point and delete. Up to six decimals.
private struct AmountKeypad: View {
    @Binding var amount: String

    private let keys: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [".", "0", "⌫"]]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button { press(key) } label: {
                            Group {
                                if key == "⌫" {
                                    Image(systemName: "delete.left")
                                } else {
                                    Text(key)
                                }
                            }
                            .font(Theme.Typography.amount(28, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(key == "." || key == "⌫" ? Color.clear : Theme.Palette.surface, in: .rect(cornerRadius: Theme.Radius.s))
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(key == "⌫" ? "Delete" : key == "." ? "Decimal point" : key)
                    }
                }
            }
        }
        .padding(8)
        .padding(.bottom, 4)
        .background(Color.primary.opacity(0.05))
    }

    private func press(_ key: String) {
        Haptics.tap()
        switch key {
        case "⌫":
            if !amount.isEmpty { amount.removeLast() }
        case ".":
            if !amount.contains(".") { amount = amount.isEmpty ? "0." : amount + "." }
        default:
            if let dot = amount.firstIndex(of: "."), amount.distance(from: dot, to: amount.endIndex) > 6 { return }
            if amount == "0" { amount = key } else if amount.count < 12 { amount += key }
        }
    }
}

private struct SentTransfer: Identifiable {
    let id: String
}

private struct ReviewTransferSheet: View {
    let recipient: String
    let units: UInt64
    let sending: Bool
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text("You're sending").foregroundStyle(.secondary)
                    Text("\(USDT.format(units: units, fractionDigits: 6).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)) USDT")
                        .font(Theme.Typography.amount(40, weight: .bold))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 14) {
                    LabeledContent("To") { Text(recipient).font(.footnote.monospaced()).multilineTextAlignment(.trailing) }
                    Divider()
                    LabeledContent("Network", value: "TRON (TRC20)")
                    Divider()
                    LabeledContent("Network fee", value: "≈ 13–14 TRX")
                }
                .padding(18)
                .surface(cornerRadius: Theme.Radius.xl)

                Text("Transfers on the blockchain are final. Check the address before you confirm.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer()
                Button(action: onConfirm) {
                    if sending { ProgressView().tint(.white) } else {
                        Label("Confirm with \(Biometrics.isEnabled ? Biometrics.label : "PIN")",
                              systemImage: Biometrics.isEnabled ? Biometrics.symbol : "lock.fill")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(sending)
            }
            .padding(24)
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() }.disabled(sending) } }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(sending)
    }
}
