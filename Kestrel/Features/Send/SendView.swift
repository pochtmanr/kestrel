import SwiftUI

/// Send USDT: where to (address, network, fee), how much (keypad), a review,
/// PIN or Face ID, then a status screen that follows the transfer from
/// "Sending" to "Confirmed", or explains what went wrong and what's safe to do.
struct SendView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var recipient: String
    @State private var amount: String
    @State private var path = NavigationPath()
    /// A line under the address field: what a pasted request filled in, or why a paste did nothing.
    @State private var fieldNote: String?
    @State private var showScanner = false
    @State private var showReview = false
    @State private var showPIN = false
    @State private var showSupport = false
    /// Face ID is up: the confirm button must not start a second prompt.
    @State private var authorizing = false
    /// The transfer that PIN or Face ID is approving.
    @State private var approving: SendTransfer?
    /// Set once a transfer is submitted: the status screen covers the flow.
    @State private var submission: SendSubmission?
    #if DEBUG
    @State private var debugTRXSun: Int64?
    @State private var debugFailure: SendFailure?
    #endif

    private enum Step: Hashable { case amount }

    init(recipient: String = "", amount: String = "") {
        // A prefill can be a whole payment request ("tron:T…?amount=5").
        if PaymentRequest.isRequestLike(recipient), let request = PaymentRequest.parse(recipient) {
            _recipient = State(initialValue: request.address)
            _amount = State(initialValue: request.amount ?? amount)
        } else {
            _recipient = State(initialValue: recipient)
            _amount = State(initialValue: amount)
        }
    }

    // MARK: Derived state

    private var trimmedRecipient: String { recipient.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var recipientCheck: RecipientCheck { RecipientRules.check(recipient, ownAddress: app.address) }
    /// Balances are only judged once they've loaded at least once.
    private var balancesKnown: Bool { app.isDemo || app.lastRefresh != nil }

    private var trxSun: Int64 {
        #if DEBUG
        if let debugTRXSun { return debugTRXSun }
        #endif
        return app.trxSun
    }

    private var hasFee: Bool { trxSun >= TRX.minimumForTransferSun }

    private var amountCheck: AmountCheck {
        AmountRules.check(amount, usdtUnits: balancesKnown ? app.usdtUnits : nil, trxSun: balancesKnown ? trxSun : nil)
    }

    private var canContinue: Bool { recipientCheck.isValid }
    private var canReview: Bool { canContinue && amountCheck.units != nil }

    // MARK: Body

    var body: some View {
        ZStack {
            NavigationStack(path: $path) {
                addressStep
                    .navigationDestination(for: Step.self) { _ in amountStep }
                    .navigationDestination(for: HomeRoute.self) { RouteDestination(route: $0) }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { dismiss() } label: { Image(systemName: "xmark") }
                                .accessibilityLabel("Close")
                        }
                    }
            }

            if let submission {
                SendStatusView(
                    submission: submission,
                    onDone: { dismiss() },
                    onRetry: { authorize(SendTransfer(to: submission.to, units: submission.units)) },
                    onEdit: { closeStatus(then: [Step.amount]) },
                    onReceiveTRX: { closeStatus(then: [Step.amount], route: .receive) },
                    onFees: { closeStatus(then: [Step.amount], route: .fees) },
                    onActivity: {
                        app.selectedTab = .activity
                        dismiss()
                    },
                    onFound: { txID in
                        Haptics.success()
                        self.submission?.state = .sent(txID: txID)
                    },
                    onSupport: { showSupport = true }
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(.snappy, value: submission?.state)
        .onAppear {
            #if DEBUG
            openDebugPreview()
            #endif
            // Repeat payment: the address is known, go straight to the amount.
            if canContinue && path.isEmpty { path.append(Step.amount) }
        }
        .task {
            // Fresh balances for the checks; the home may not have loaded them yet.
            async let prices: Void = app.refreshPrices()
            await app.refresh()
            await prices
        }
        .onChange(of: recipient) { _, text in applyRequest(text) }
        .sheet(isPresented: $showScanner) {
            QRScannerSheet { scanned in handleScan(scanned) }
        }
        .sheet(isPresented: $showReview) {
            if let units = amountCheck.units {
                ReviewTransferSheet(recipient: trimmedRecipient, units: units, authorizing: authorizing) {
                    authorize(SendTransfer(to: trimmedRecipient, units: units))
                }
            }
        }
        .sheet(isPresented: $showPIN) {
            ConfirmWithPINSheet(title: "Confirm transfer") {
                if let approving { send(approving) }
            }
        }
        .sheet(isPresented: $showSupport) { SupportChatSheet() }
    }

    // MARK: Step 1 — where to

    private var addressStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Send").font(.largeTitle.bold())

                addressField
                addressStatus

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
                    .accessibilityElement(children: .combine)
                    Divider().padding(.leading, 16)
                    infoRow("Transfer time", icon: "timer", value: "≈ 1 minute")
                    Divider().padding(.leading, 16)
                    infoRow("Network fee", icon: "bolt", value: "≈ 13–14 TRX",
                            warning: balancesKnown && !hasFee ? String(localized: "You have \(TRX.format(sun: trxSun)) TRX") : nil)
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
            BlackButton(title: "Next", enabled: canContinue) { path.append(Step.amount) }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.bottom, 8)
                .readableWidth()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { SupportButton(inToolbar: true) { showSupport = true } }
        }
    }

    private var addressField: some View {
        HStack(spacing: 14) {
            TextField("Destination address", text: $recipient, axis: .vertical)
                .lineLimit(1 ... 3)
                .font(recipient.isEmpty ? .body : .body.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .accessibilityLabel("Destination address")
            if !recipient.isEmpty {
                Button {
                    recipient = ""
                    fieldNote = nil
                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .accessibilityLabel("Clear address")
            }
            Button { showScanner = true } label: { Image(systemName: "qrcode.viewfinder") }
                .accessibilityLabel("Scan QR code")
            Button(action: paste) { Image(systemName: "doc.on.clipboard") }
                .accessibilityLabel("Paste address")
        }
        .font(.title3)
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 60)
        .surface(cornerRadius: Theme.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(hasRecipientProblem ? Theme.Palette.danger : .clear, lineWidth: 1.5)
                .allowsHitTesting(false)
        )
    }

    private var hasRecipientProblem: Bool {
        if case .problem = recipientCheck { return true }
        return false
    }

    @ViewBuilder
    private var addressStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch recipientCheck {
            case .problem(let problem):
                statusLine(problem.message, icon: "exclamationmark.circle.fill", color: Theme.Palette.danger)
            case .incomplete(let count):
                Text("\(count) of \(RecipientRules.addressLength) characters")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            case .valid:
                statusLine(String(localized: "Valid TRON address"), icon: "checkmark.circle.fill", color: Theme.Palette.positive)
            case .empty:
                EmptyView()
            }
            if let fieldNote {
                statusLine(fieldNote, icon: "info.circle.fill", color: Theme.Palette.accentText)
            }
        }
        .padding(.horizontal, 4)
    }

    private func statusLine(_ text: String, icon: String, color: Color) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
        }
        .font(.footnote)
        .foregroundStyle(color)
    }

    private func infoRow(_ title: LocalizedStringKey, icon: String, value: LocalizedStringKey, warning: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 26).accessibilityHidden(true)
            Text(title).foregroundStyle(.secondary).lineLimit(1).layoutPriority(1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                if let warning { Text(warning).font(.caption).foregroundStyle(Theme.Palette.warning) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
    }

    // MARK: Step 2 — how much

    private var amountStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            VStack(spacing: 12) {
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Amount")
                .accessibilityValue(Text("\(amount.isEmpty ? "0" : amount) USDT"))

                if let usd = usdEquivalent {
                    Text(verbatim: "≈ \(usd)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("About \(usd)")
                }

                Button { fillMax() } label: {
                    Label("\(balanceText) USDT", systemImage: "wallet.bifold")
                        .font(.body.weight(.medium).monospacedDigit())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .surface(cornerRadius: Theme.Radius.tile)
                }
                .buttonStyle(.plain)
                .disabled(!balancesKnown || app.usdtUnits == 0)
                .accessibilityLabel("Balance: \(balanceText) USDT")
                .accessibilityHint("Sends your whole balance")

                amountMessage
            }
            Spacer(minLength: 8)

            if balancesKnown && !hasFee {
                FeeNeededCard(trxSun: trxSun,
                              onReceive: { path.append(HomeRoute.receive) },
                              onFees: { path.append(HomeRoute.fees) })
                    .padding(.horizontal, Theme.Spacing.screen)
                    .padding(.bottom, 12)
                    .readableWidth()
            }

            HStack(spacing: 12) {
                Button { fillMax() } label: {
                    Text("Max")
                        .font(.headline)
                        .frame(minWidth: 64, minHeight: 56)
                        .padding(.horizontal, 4)
                        .surface(cornerRadius: Theme.Radius.hero)
                }
                .buttonStyle(.plain)
                .disabled(!balancesKnown || app.usdtUnits == 0)
                .accessibilityHint("Fills in your whole USDT balance")
                BlackButton(title: "Review", enabled: canReview) { showReview = true }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.bottom, 12)
            .readableWidth()

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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sending to \(trimmedRecipient)")
            }
            ToolbarItem(placement: .topBarTrailing) { SupportButton(inToolbar: true) { showSupport = true } }
        }
    }

    /// One line, always there, so the layout doesn't jump as the message comes and goes.
    @ViewBuilder
    private var amountMessage: some View {
        if case .problem(let problem) = amountCheck, problem != .needsTRX {
            Text(problem.message)
                .font(.footnote)
                .foregroundStyle(problem.isWarning ? Color.secondary : Theme.Palette.danger)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.screen)
        } else {
            Text(verbatim: " ").font(.footnote).accessibilityHidden(true)
        }
    }

    private var usdEquivalent: String? {
        guard let price = app.prices[.usdt]?.usd, let units = USDT.units(from: amount), units > 0 else { return nil }
        return USDPrice.format(Double(units) / 1_000_000 * price)
    }

    /// The balance with two decimals, or more only when the wallet holds dust.
    private var balanceText: String {
        guard balancesKnown else { return "…" }
        return USDT.format(units: app.usdtUnits, fractionDigits: app.usdtUnits % 10_000 == 0 ? 2 : 6)
    }

    private func fillMax() {
        Haptics.tap()
        amount = AmountRules.text(units: app.usdtUnits)
    }

    // MARK: Paste and scan

    private func paste() {
        guard let text = Clipboard.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            fieldNote = String(localized: "There's nothing to paste. Copy an address first.")
            return
        }
        fieldNote = nil
        recipient = text
    }

    /// A pasted or typed request: keep its address, move its amount to step 2.
    private func applyRequest(_ text: String) {
        guard PaymentRequest.isRequestLike(text), let request = PaymentRequest.parse(text),
              request.address != text else { return }
        recipient = request.address
        if let requested = request.amount {
            amount = requested
            fieldNote = String(localized: "Amount from the payment request: \(requested) USDT")
        } else if request.otherToken {
            fieldNote = String(localized: "This request is for another coin. Enter the USDT amount yourself.")
        }
    }

    /// nil accepts the code (and closes the scanner); a message keeps it open.
    private func handleScan(_ scanned: String) -> String? {
        let request = PaymentRequest.parse(scanned)
        let address = request?.address ?? scanned.trimmingCharacters(in: .whitespacesAndNewlines)
        switch RecipientRules.check(address, ownAddress: app.address) {
        case .valid:
            recipient = address
            if let requested = request?.amount {
                amount = requested
                fieldNote = String(localized: "Amount from the payment request: \(requested) USDT")
            } else {
                fieldNote = request?.otherToken == true
                    ? String(localized: "This request is for another coin. Enter the USDT amount yourself.") : nil
            }
            showScanner = false
            return nil
        case .problem(let problem) where [.ownAddress, .tokenContract, .ethereumAddress].contains(problem):
            return problem.message
        default:
            return String(localized: "This QR code isn't a TRON address. Try another code, or paste the address.")
        }
    }

    // MARK: Authorise and send

    /// PIN or Face ID, exactly as before: Face ID when it's on, falling back to the PIN.
    private func authorize(_ transfer: SendTransfer) {
        guard !authorizing else { return }
        approving = transfer
        if Biometrics.isEnabled {
            authorizing = true
            Task {
                let approved = await Biometrics.authenticate(reason: "Confirm sending USDT")
                authorizing = false
                if approved {
                    send(transfer)
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

    private func send(_ transfer: SendTransfer) {
        // One broadcast per approval, whatever gets tapped twice.
        if submission?.state == .sending { return }
        showReview = false
        let started = Date.now
        withAnimation(.snappy) {
            submission = SendSubmission(to: transfer.to, units: transfer.units, from: app.address ?? "",
                                        started: started, knownIDs: Set(app.history.map(\.id)), state: .sending)
        }
        let usdtBalance = app.usdtUnits
        Task {
            let outcome: SendSubmission.State
            do {
                let txID = try await broadcast(transfer)
                outcome = .sent(txID: txID)
            } catch {
                outcome = .failed(SendFailure.from(error, units: transfer.units, usdtBalance: usdtBalance))
            }
            if case .sent = outcome { Haptics.success() } else { Haptics.error() }
            submission?.state = outcome
            Task { await app.refresh() }
        }
    }

    private func broadcast(_ transfer: SendTransfer) async throws -> String {
        #if DEBUG
        // The demo wallet never touches the network or the Keychain's real keys.
        if app.isDemo {
            try await Task.sleep(for: .seconds(1.5))
            if let debugFailure { throw DebugSendError(failure: debugFailure) }
            return "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        }
        #endif
        let keys: TronKeys
        do {
            guard let stored = try WalletVault.keys() else { throw WalletMissing() }
            keys = stored
        } catch {
            throw WalletMissing()
        }
        return try await app.tron.sendUSDT(from: keys, to: transfer.to, units: transfer.units)
    }

    /// Leave the status screen for an earlier step (to fix what failed).
    private func closeStatus(then steps: [Step], route: HomeRoute? = nil) {
        withAnimation(.snappy) { submission = nil }
        var next = NavigationPath()
        steps.forEach { next.append($0) }
        if let route { next.append(route) }
        path = next
    }

    // MARK: Debug previews

    #if DEBUG
    /// `-sendPreview amount|review|lowtrx|invalid|own|sending|success|fail-<kind>` with `-demo -route send`:
    /// opens Send in that state (screenshots, UI checks). Kinds: offline, busy, trx, usdt, rejected, timeout, unknown.
    private func openDebugPreview() {
        let args = CommandLine.arguments
        guard app.isDemo, let index = args.firstIndex(of: "-sendPreview"), args.indices.contains(index + 1) else { return }
        let to = "TXJgMdjVX5dKiQaUi9QobwNxtSQaFqccvd"
        let units: UInt64 = 125_500_000
        let preview = args[index + 1]
        func status(_ state: SendSubmission.State) {
            submission = SendSubmission(to: to, units: units, from: app.address ?? "", started: .now, knownIDs: [], state: state)
        }
        switch preview {
        case "invalid": recipient = "TXJgMdjVX5dKiQaUi9QobwNxtSQaFqccvx"
        case "own": recipient = app.address ?? ""
        case "amount", "review", "lowtrx", "over":
            recipient = to
            amount = preview == "over" ? "9000" : "125.5"
            if preview == "lowtrx" { debugTRXSun = 3_200_000 }
            path.append(Step.amount)
            if preview == "review" {
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    showReview = true
                }
            }
        case "sending": status(.sending)
        case "success": status(.sent(txID: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"))
        case let kind where kind.hasPrefix("fail-"):
            let failure: SendFailure = switch kind.dropFirst(5) {
            case "offline": .offline
            case "busy": .rateLimited
            case "trx": .insufficientTRX
            case "usdt": .insufficientUSDT
            case "rejected": .rejected("Contract validate error : Validate TransferContract error, no OwnerAccount.")
            case "timeout": .outcomeUnknown
            default: .unknown("The data couldn't be read because it isn't in the correct format.")
            }
            debugFailure = failure
            status(.failed(failure))
        default: break
        }
    }
    #endif
}

#if DEBUG
/// Lets the demo send fail with a chosen failure.
private struct DebugSendError: Error { let failure: SendFailure }
#endif

/// What PIN or Face ID approves: one recipient, one amount.
struct SendTransfer: Equatable {
    let to: String
    let units: UInt64
}

/// A transfer handed to the network, and how it's going.
struct SendSubmission: Equatable {
    let to: String
    let units: UInt64
    let from: String
    let started: Date
    /// History before the send, so an unclear outcome can spot the new transfer.
    let knownIDs: Set<String>
    var state: State

    enum State: Equatable {
        case sending
        case sent(txID: String)
        case failed(SendFailure)
    }
}

/// What to do when the TRX balance can't pay the network fee.
private struct FeeNeededCard: View {
    let trxSun: Int64
    let onReceive: () -> Void
    let onFees: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Add TRX to pay the network fee").font(.subheadline.weight(.semibold))
                    Text("A USDT transfer burns about 13–14 TRX. You have \(TRX.format(sun: trxSun)) TRX.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "bolt.fill").foregroundStyle(Theme.Palette.warning)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 8) {
                Button(action: onReceive) {
                    Label("Receive TRX", systemImage: "arrow.down.left")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(.white)
                        .background(Theme.Palette.accent, in: .capsule)
                }
                Button(action: onFees) {
                    Text("About fees")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Theme.Palette.surfaceRaised, in: .capsule)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .surface(cornerRadius: Theme.Radius.card)
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
                                    Text(verbatim: key)
                                }
                            }
                            .font(Theme.Typography.amount(28, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(key == "." || key == "⌫" ? Color.clear : Theme.Palette.surface, in: .rect(cornerRadius: Theme.Radius.s))
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(key == "⌫" ? Text("Delete") : key == "." ? Text("Decimal point") : Text(verbatim: key))
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
