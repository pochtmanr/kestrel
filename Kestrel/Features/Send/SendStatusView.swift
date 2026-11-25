import SwiftUI

/// Covers the Send flow once a transfer is submitted: sending, then sent
/// (processing → confirmed), or a failure that says what happened and only
/// offers a retry when the transfer certainly didn't go through.
struct SendStatusView: View {
    let submission: SendSubmission
    let onDone: () -> Void
    let onRetry: () -> Void
    let onEdit: () -> Void
    let onReceiveTRX: () -> Void
    let onFees: () -> Void
    let onActivity: () -> Void
    /// An unclear failure turned out to have gone through.
    let onFound: (String) -> Void
    let onSupport: () -> Void

    var body: some View {
        Group {
            switch submission.state {
            case .sending:
                SendingContent(submission: submission)
            case .sent(let txID):
                SentContent(submission: submission, txID: txID, onDone: onDone)
            case .failed(let failure):
                FailedContent(submission: submission, failure: failure, onDone: onDone, onRetry: onRetry,
                              onEdit: onEdit, onReceiveTRX: onReceiveTRX, onFees: onFees,
                              onActivity: onActivity, onFound: onFound, onSupport: onSupport)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.background.ignoresSafeArea())
    }
}

// MARK: - Pieces shared by every state

/// The big round symbol at the top of each state.
private struct StatusBadge: View {
    let symbol: String
    let tint: Color
    var spinning = false

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.14))
            if spinning {
                ProgressView().controlSize(.large).tint(tint)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: symbol)
            }
        }
        .frame(width: 96, height: 96)
        .accessibilityHidden(true)
    }
}

/// Amount and recipient of the transfer, on every state.
private struct TransferSummary: View {
    let submission: SendSubmission

    var body: some View {
        VStack(spacing: 6) {
            Text(verbatim: "\(SendFormat.usdt(submission.units)) USDT")
                .font(Theme.Typography.amount(34, weight: .bold).monospacedDigit())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("to \(submission.to.shortAddress)")
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(SendFormat.usdt(submission.units)) USDT to \(submission.to)")
    }
}

/// Scrolling content up top, buttons pinned to the bottom.
private struct StatusLayout<Content: View, Actions: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    var body: some View {
        ScrollView {
            VStack(spacing: 18) { content }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.top, 56)
                .padding(.bottom, 24)
                .readableWidth()
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) { actions }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .readableWidth()
                .background(Theme.Palette.background)
        }
    }
}

private func announce(_ text: String) {
    AccessibilityNotification.Announcement(text).post()
}

// MARK: - Sending

private struct SendingContent: View {
    let submission: SendSubmission
    @State private var slow = false

    var body: some View {
        StatusLayout {
            StatusBadge(symbol: "paperplane.fill", tint: Theme.Palette.accentText, spinning: true)
            Text("Sending…").font(.title2.bold())
            TransferSummary(submission: submission)
            Text(slow ? "The network is slow right now. Keep Kestrel open: the result will show here."
                      : "Signing on this device and handing the transfer to the TRON network.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.snappy, value: slow)
        } actions: {
            // Nothing to tap: a second tap must never send twice.
            Text("Don't close the app")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minHeight: 54)
        }
        .task {
            announce(String(localized: "Sending"))
            try? await Task.sleep(for: .seconds(8))
            slow = true
        }
    }
}

// MARK: - Sent

private struct SentContent: View {
    let submission: SendSubmission
    let txID: String
    let onDone: () -> Void

    @Environment(AppModel.self) private var app
    @State private var confirmed = false
    @State private var slow = false
    @State private var copied = false

    private var tronscan: URL { URL(string: "https://tronscan.org/#/transaction/\(txID)")! }

    var body: some View {
        StatusLayout {
            StatusBadge(symbol: "checkmark", tint: Theme.Palette.positive)
            Text(confirmed ? "Transfer complete" : "Transfer sent").font(.title2.bold())
            TransferSummary(submission: submission)
            statusPill

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recipient").foregroundStyle(.secondary)
                    Text(submission.to)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .accessibilityElement(children: .combine)
                Divider().padding(.leading, 16)
                Button(action: copyID) {
                    row("Transaction ID") {
                        HStack(spacing: 6) {
                            Text(txID.shortAddress).font(.body.monospaced())
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .foregroundStyle(copied ? Theme.Palette.positive : Color.secondary)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copied ? Text("Transaction ID copied") : Text("Transaction ID: \(txID)"))
                .accessibilityHint("Copies to clipboard")
                Divider().padding(.leading, 16)
                row("Network fee") { Text("≈ 13–14 TRX").monospacedDigit() }
                Divider().padding(.leading, 16)
                Link(destination: tronscan) {
                    HStack {
                        Text("View on Tronscan")
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Theme.Palette.accentText)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 54)
                }
            }
            .surface(cornerRadius: Theme.Radius.card)

            if slow && !confirmed {
                Text("Confirmation is taking longer than usual. You can close this screen: the transfer will appear in Activity once the network confirms it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } actions: {
            Button("Done", action: onDone).buttonStyle(PrimaryButtonStyle())
        }
        .task { await waitForConfirmation() }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            if confirmed {
                Image(systemName: "checkmark.seal.fill")
            } else {
                ProgressView().controlSize(.small).tint(Theme.Palette.pending)
            }
            Text(confirmed ? "Confirmed" : "Processing")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(confirmed ? Theme.Palette.positive : Theme.Palette.pending)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background((confirmed ? Theme.Palette.positive : Theme.Palette.pending).opacity(0.14), in: .capsule)
        .animation(.snappy, value: confirmed)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(confirmed ? Text("Status: confirmed") : Text("Status: processing"))
    }

    /// Same mechanism as the transfer details screen: the transfer is
    /// confirmed once it shows up in the wallet's (confirmed-only) history.
    private func waitForConfirmation() async {
        announce(String(localized: "Transfer sent. Processing."))
        let started = Date.now
        while !confirmed, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(4))
            #if DEBUG
            if app.isDemo {
                confirmed = true
                break
            }
            #endif
            await app.refresh()
            if app.history.contains(where: { $0.id == txID }) { confirmed = true }
            if Date.now.timeIntervalSince(started) > 120 { slow = true }
        }
        if confirmed {
            Haptics.success()
            announce(String(localized: "Transfer confirmed"))
        }
    }

    private func copyID() {
        Clipboard.copy(txID)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    private func row(_ title: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).foregroundStyle(.secondary).layoutPriority(1)
            Spacer(minLength: 8)
            value()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 54)
    }
}

// MARK: - Failed

private struct FailedContent: View {
    let submission: SendSubmission
    let failure: SendFailure
    let onDone: () -> Void
    let onRetry: () -> Void
    let onEdit: () -> Void
    let onReceiveTRX: () -> Void
    let onFees: () -> Void
    let onActivity: () -> Void
    let onFound: (String) -> Void
    let onSupport: () -> Void

    @Environment(AppModel.self) private var app
    /// Rate limited: the retry waits out a short cool-down.
    @State private var coolDown = 0
    @State private var checking = false

    private var tint: Color { failure.mightHaveSent ? Theme.Palette.warning : Theme.Palette.danger }

    var body: some View {
        StatusLayout {
            StatusBadge(symbol: failure.symbol, tint: tint)
            Text(failure.title).font(.title2.bold()).multilineTextAlignment(.center)
            TransferSummary(submission: submission)
            Text(failure.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = failure.detail {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Message from the network").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(detail).font(.footnote.monospaced()).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .surface(cornerRadius: Theme.Radius.l)
            }

            if failure.mightHaveSent { checkingNote }

            if SupportConfig.isChatConfigured {
                Button("Contact support", action: onSupport)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.Palette.accentText)
            }
        } actions: {
            actions
        }
        .task(id: failure) {
            announce(failure.title)
            if failure == .rateLimited { await runCoolDown() }
            if failure.mightHaveSent { await lookForTransfer() }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch failure {
        case .insufficientTRX:
            Button(action: onReceiveTRX) { Label("Receive TRX", systemImage: "arrow.down.left") }
                .buttonStyle(PrimaryButtonStyle())
            Button("About network fees", action: onFees).buttonStyle(SecondaryButtonStyle())
        case .insufficientUSDT:
            Button("Change amount", action: onEdit).buttonStyle(PrimaryButtonStyle())
            Button("Close", action: onDone).buttonStyle(SecondaryButtonStyle())
        case .outcomeUnknown, .unknown:
            Button(action: onActivity) { Label("Check Activity", systemImage: "list.bullet") }
                .buttonStyle(PrimaryButtonStyle())
            Button("Close", action: onDone).buttonStyle(SecondaryButtonStyle())
        case .rejected:
            Button(action: onRetry) { Label("Try again", systemImage: "arrow.clockwise") }
                .buttonStyle(PrimaryButtonStyle())
            Button("Change transfer", action: onEdit).buttonStyle(SecondaryButtonStyle())
        case .offline, .rateLimited, .walletMissing:
            Button(action: onRetry) {
                if coolDown > 0 {
                    Text("Try again in \(coolDown) s").monospacedDigit()
                } else {
                    Label("Try again", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(coolDown > 0)
            Button("Close", action: onDone).buttonStyle(SecondaryButtonStyle())
        }
    }

    /// While the outcome is unclear, watch the confirmed history for it.
    private var checkingNote: some View {
        HStack(spacing: 10) {
            if checking { ProgressView().controlSize(.small) } else { Image(systemName: "info.circle") }
            Text(checking ? "Checking the network for this transfer…"
                          : "Not found yet. Transfers usually confirm within a minute, so check Activity again shortly.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surface(cornerRadius: Theme.Radius.l)
        .accessibilityElement(children: .combine)
    }

    private func runCoolDown() async {
        coolDown = 5
        while coolDown > 0, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            coolDown -= 1
        }
    }

    /// Never sends anything: it only reads history, for up to three minutes.
    private func lookForTransfer() async {
        checking = true
        defer { checking = false }
        let deadline = Date.now.addingTimeInterval(180)
        while Date.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(6))
            await app.refresh()
            if let found = SendOutcome.match(in: app.history, from: submission.from, to: submission.to,
                                             units: submission.units, since: submission.started,
                                             excluding: submission.knownIDs) {
                onFound(found.id)
                return
            }
        }
    }
}
