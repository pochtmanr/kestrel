import SwiftUI

struct PinDots: View {
    let filled: Int
    var isError = false

    var body: some View {
        HStack(spacing: 18) {
            ForEach(0 ..< PinStore.length, id: \.self) { i in
                Circle()
                    .fill(i < filled ? (isError ? Theme.Palette.danger : Theme.Palette.accent) : Color.primary.opacity(0.15))
                    .frame(width: 14, height: 14)
            }
        }
        .modifier(Shake(animatableData: isError ? 1 : 0))
        .animation(.default, value: isError)
        .accessibilityElement()
        .accessibilityLabel("\(filled) of \(PinStore.length) digits entered")
    }
}

private struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 4), y: 0))
    }
}

struct PinPad: View {
    var biometricSymbol: String?
    let onDigit: (String) -> Void
    let onDelete: () -> Void
    var onBiometric: () -> Void = {}

    var body: some View {
        Grid(horizontalSpacing: 28, verticalSpacing: 18) {
            ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]], id: \.self) { row in
                GridRow { ForEach(row, id: \.self) { digitKey($0) } }
            }
            GridRow {
                if let biometricSymbol {
                    key { onBiometric() } label: { Image(systemName: biometricSymbol).font(.title2) }
                        .accessibilityLabel("Unlock with \(Biometrics.label)")
                } else {
                    Color.clear.frame(width: 76, height: 76)
                }
                digitKey("0")
                key { onDelete() } label: { Image(systemName: "delete.left").font(.title2) }
                    .accessibilityLabel("Delete")
            }
        }
    }

    private func digitKey(_ digit: String) -> some View {
        key { onDigit(digit) } label: { Text(digit).font(Theme.Typography.amount(30, weight: .medium)) }
            .background(Theme.Palette.surface, in: .circle)
    }

    private func key<Label: View>(action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            label().frame(width: 76, height: 76).contentShape(.circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

/// Creates a PIN: the first one of a new wallet, or (with `changing`) a new one
/// for a wallet whose current PIN has just been entered.
struct PinSetupView: View {
    /// The recovery phrase the current PIN opened. nil: a new wallet's first PIN.
    var changing: String?
    /// Change only: the new PIN is saved, or the user backed out.
    var onDone: () -> Void = {}

    @Environment(AppModel.self) private var app
    @State private var first = ""
    @State private var entry = ""
    @State private var confirming = false
    @State private var mismatch = false
    @State private var failed = false
    @State private var saving = false
    @State private var offerBiometrics = false
    /// Held between saving the PIN and the answer to "Use Face ID?".
    @State private var phrase: String?

    private var subtitle: LocalizedStringKey {
        if failed { return "Couldn't save the PIN. Try again." }
        if mismatch { return "PINs didn't match. Start again." }
        if confirming { return "Enter the same 6 digits again." }
        return "You'll use it to open \(Brand.name)."
    }

    var body: some View {
        VStack(spacing: 0) {
            if changing != nil {
                HStack {
                    Spacer()
                    Button("Cancel") { onDone() }.disabled(saving)
                }
            }
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.Palette.accent)
            Text(confirming ? "Confirm your PIN" : "Create a PIN")
                .font(.title.bold())
                .padding(.top, 16)
            Text(subtitle)
                .foregroundStyle(mismatch || failed ? Theme.Palette.danger : .secondary)
                .padding(.top, 6)
            PinDots(filled: entry.count, isError: mismatch || failed).padding(.top, 36)
            Spacer()
            PinPad(onDigit: add, onDelete: { if !entry.isEmpty { entry.removeLast() } })
                .disabled(saving)
                .padding(.bottom, 24)
        }
        .padding()
        .fitOrScroll()
        .alert("Use \(Biometrics.label)?", isPresented: $offerBiometrics) {
            Button("Enable") {
                Task {
                    if let phrase, await Biometrics.authenticate(reason: tr("Enable \(Biometrics.label) for \(Brand.name)")) {
                        try? WalletVault.enableBiometrics(phrase: phrase)
                    }
                    finishFirstPIN()
                }
            }
            Button("Not now", role: .cancel) { finishFirstPIN() }
        } message: {
            Text("Unlock \(Brand.name) and confirm transfers with \(Biometrics.label) instead of typing your PIN.")
        }
        .onDisappear { phrase = nil }
    }

    private func finishFirstPIN() {
        phrase = nil
        app.pinCreated()
    }

    private func add(_ digit: String) {
        guard entry.count < PinStore.length, !saving else { return }
        mismatch = false
        failed = false
        entry += digit
        guard entry.count == PinStore.length else { return }

        if !confirming {
            first = entry
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                entry = ""
                confirming = true
            }
        } else if entry == first {
            save(entry)
        } else {
            Haptics.error()
            mismatch = true
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                restart()
                mismatch = true
            }
        }
    }

    /// Encrypting the phrase under the PIN takes a moment (key derivation), off the main thread.
    private func save(_ pin: String) {
        saving = true
        let changing = changing
        Task {
            let saved: String? = await Task.detached(priority: .userInitiated) {
                if let changing {
                    return (try? WalletVault.changePIN(phrase: changing, to: pin)) != nil ? changing : nil
                }
                return try? WalletVault.createPIN(pin)
            }.value
            saving = false
            guard let saved else {
                Haptics.error()
                restart()
                failed = true
                return
            }
            Haptics.success()
            PinThrottle.reset()
            if changing != nil {
                onDone()
            } else if Biometrics.kind != .none {
                phrase = saved
                offerBiometrics = true
            } else {
                app.pinCreated()
            }
        }
    }

    private func restart() {
        first = ""
        entry = ""
        confirming = false
    }
}

/// The digits typed so far and the check of a full PIN, shared by the lock
/// screen and the confirmation sheet. Wrong attempts are counted in the
/// Keychain (`PinThrottle`), so the wait survives a relaunch and both screens share it.
@MainActor
@Observable
final class PinEntry {
    private(set) var entry = ""
    private(set) var wrong = false
    private(set) var verifying = false
    private(set) var lockedUntil: Date? = PinThrottle.lockedUntil()

    func delete() {
        if !entry.isEmpty, !verifying { entry.removeLast() }
    }

    func add(_ digit: String, onPhrase: @escaping @MainActor (String) -> Void) {
        guard entry.count < PinStore.length, !verifying, lockedUntil == nil else { return }
        wrong = false
        entry += digit
        guard entry.count == PinStore.length else { return }
        let pin = entry
        verifying = true
        Task {
            let outcome = await PinGate.submit(pin)
            verifying = false
            switch outcome {
            case .phrase(let phrase):
                entry = ""
                onPhrase(phrase)
            case .wrong(let until):
                Haptics.error()
                wrong = true
                lockedUntil = until
                try? await Task.sleep(for: .milliseconds(600))
                entry = ""
            case .locked(let until):
                lockedUntil = until
                entry = ""
            }
        }
    }

    /// Run from `.task(id: lockedUntil)`: lifts the lock when its time comes.
    func waitOutLock() async {
        guard let until = lockedUntil else { return }
        let wait = until.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        guard !Task.isCancelled else { return }
        lockedUntil = PinThrottle.lockedUntil()
    }
}

/// "Wrong PIN", the wait after too many of them, or the screen's own prompt.
private struct PinPrompt: View {
    let pin: PinEntry
    let idle: LocalizedStringKey

    var body: some View {
        Group {
            if let until = pin.lockedUntil {
                Text("Too many attempts. Try again in \(Text(until, style: .timer)).").monospacedDigit()
            } else if pin.wrong {
                Text("Wrong PIN")
            } else {
                Text(idle)
            }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(pin.wrong || pin.lockedUntil != nil ? Theme.Palette.danger : .secondary)
    }
}

struct LockView: View {
    @Environment(AppModel.self) private var app
    @State private var pin = PinEntry()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image("Logo")
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(.rect(cornerRadius: Theme.Radius.xl))
            Text("Enter PIN").font(.title.bold()).padding(.top, 18)
            PinPrompt(pin: pin, idle: "Welcome back").padding(.top, 6)
            PinDots(filled: pin.entry.count, isError: pin.wrong).padding(.top, 36)
            Spacer()
            PinPad(
                biometricSymbol: Biometrics.isEnabled ? Biometrics.symbol : nil,
                onDigit: { pin.add($0) { _ in app.unlock() } },
                onDelete: pin.delete,
                onBiometric: biometric
            )
            .disabled(pin.lockedUntil != nil || pin.verifying)
            .padding(.bottom, 24)
        }
        .padding()
        .fitOrScroll()
        .task { if Biometrics.isEnabled { biometric() } }
        .task(id: pin.lockedUntil) { await pin.waitOutLock() }
    }

    /// Opens only if iOS releases the phrase's biometric copy: a face enrolled
    /// after Face ID was turned on here doesn't get in.
    private func biometric() {
        Task {
            if await Biometrics.unlockPhrase(reason: tr("Unlock \(Brand.name)")) != nil { app.unlock() }
        }
    }
}

/// The PIN before a sensitive action: showing the recovery phrase, sending
/// funds, changing the PIN. The right PIN decrypts the phrase, which is handed on.
struct ConfirmWithPINSheet: View {
    let title: LocalizedStringKey
    let onSuccess: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pin = PinEntry()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
            }
            Spacer()
            Text(title).font(.title2.bold())
            PinPrompt(pin: pin, idle: "Enter your PIN to continue").padding(.top, 6)
            PinDots(filled: pin.entry.count, isError: pin.wrong).padding(.top, 30)
            Spacer()
            PinPad(
                onDigit: { digit in
                    pin.add(digit) { phrase in
                        dismiss()
                        onSuccess(phrase)
                    }
                },
                onDelete: pin.delete
            )
            .disabled(pin.lockedUntil != nil || pin.verifying)
            .padding(.bottom, 16)
        }
        .padding()
        .fitOrScroll()
        .presentationDetents([.large])
        .task(id: pin.lockedUntil) { await pin.waitOutLock() }
    }
}

/// Full-height layouts (PIN pad, lock) that scroll only when the window is too
/// short for them, as in a small Stage Manager window or landscape on an iPad.
private struct FitOrScroll: ViewModifier {
    func body(content: Content) -> some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }.scrollBounceBehavior(.basedOnSize)
        }
    }
}

private extension View {
    func fitOrScroll() -> some View { modifier(FitOrScroll()) }
}
