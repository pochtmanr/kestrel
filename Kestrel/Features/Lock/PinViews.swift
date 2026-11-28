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

struct PinSetupView: View {
    @Environment(AppModel.self) private var app
    @State private var first = ""
    @State private var entry = ""
    @State private var confirming = false
    @State private var mismatch = false
    @State private var offerBiometrics = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.Palette.accent)
            Text(confirming ? "Confirm your PIN" : "Create a PIN")
                .font(.title.bold())
                .padding(.top, 16)
            Text(mismatch ? "PINs didn't match. Start again." : confirming ? "Enter the same 6 digits again." : "You'll use it to open \(Brand.name).")
                .foregroundStyle(mismatch ? Theme.Palette.danger : .secondary)
                .padding(.top, 6)
            PinDots(filled: entry.count, isError: mismatch).padding(.top, 36)
            Spacer()
            PinPad(onDigit: add, onDelete: { if !entry.isEmpty { entry.removeLast() } })
                .padding(.bottom, 24)
        }
        .padding()
        .fitOrScroll()
        .alert("Use \(Biometrics.label)?", isPresented: $offerBiometrics) {
            Button("Enable") {
                Task {
                    if await Biometrics.authenticate(reason: tr("Enable \(Biometrics.label) for \(Brand.name)")) {
                        Biometrics.isEnabled = true
                    }
                    app.pinCreated()
                }
            }
            Button("Not now", role: .cancel) { app.pinCreated() }
        } message: {
            Text("Unlock \(Brand.name) and confirm transfers with \(Biometrics.label) instead of typing your PIN.")
        }
    }

    private func add(_ digit: String) {
        guard entry.count < PinStore.length else { return }
        mismatch = false
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
            do {
                try PinStore.set(entry)
                Haptics.success()
                if Biometrics.kind != .none { offerBiometrics = true } else { app.pinCreated() }
            } catch {
                restart()
            }
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

    private func restart() {
        first = ""
        entry = ""
        confirming = false
    }
}

struct LockView: View {
    @Environment(AppModel.self) private var app
    @State private var entry = ""
    @State private var wrong = false
    @State private var failures = 0
    @State private var lockedUntil: Date?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image("Logo")
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(.rect(cornerRadius: Theme.Radius.xl))
            Text("Enter PIN").font(.title.bold()).padding(.top, 18)
            Text(subtitle)
                .foregroundStyle(wrong ? Theme.Palette.danger : .secondary)
                .padding(.top, 6)
            PinDots(filled: entry.count, isError: wrong).padding(.top, 36)
            Spacer()
            PinPad(
                biometricSymbol: Biometrics.isEnabled ? Biometrics.symbol : nil,
                onDigit: add,
                onDelete: { if !entry.isEmpty { entry.removeLast() } },
                onBiometric: biometric
            )
            .disabled(isThrottled)
            .padding(.bottom, 24)
        }
        .padding()
        .fitOrScroll()
        .task { if Biometrics.isEnabled { biometric() } }
    }

    private var isThrottled: Bool { (lockedUntil ?? .distantPast) > .now }

    private var subtitle: String {
        if isThrottled { return tr("Too many attempts. Try again in 30 seconds.") }
        return wrong ? tr("Wrong PIN") : tr("Welcome back")
    }

    private func biometric() {
        Task {
            if await Biometrics.authenticate(reason: tr("Unlock \(Brand.name)")) { app.unlock() }
        }
    }

    private func add(_ digit: String) {
        guard entry.count < PinStore.length, !isThrottled else { return }
        wrong = false
        entry += digit
        guard entry.count == PinStore.length else { return }

        if PinStore.verify(entry) {
            failures = 0
            app.unlock()
        } else {
            Haptics.error()
            wrong = true
            failures += 1
            if failures % 5 == 0 { lockedUntil = .now.addingTimeInterval(30) }
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                entry = ""
            }
        }
    }
}

/// PIN (or biometrics) re-check before sensitive actions: showing the
/// recovery phrase, sending funds.
struct ConfirmWithPINSheet: View {
    let title: LocalizedStringKey
    let onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var entry = ""
    @State private var wrong = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
            }
            Spacer()
            Text(title).font(.title2.bold())
            Text(wrong ? "Wrong PIN" : "Enter your PIN to continue")
                .foregroundStyle(wrong ? Theme.Palette.danger : .secondary)
                .padding(.top, 6)
            PinDots(filled: entry.count, isError: wrong).padding(.top, 30)
            Spacer()
            PinPad(onDigit: add, onDelete: { if !entry.isEmpty { entry.removeLast() } })
                .padding(.bottom, 16)
        }
        .padding()
        .fitOrScroll()
        .presentationDetents([.large])
    }

    private func add(_ digit: String) {
        guard entry.count < PinStore.length else { return }
        wrong = false
        entry += digit
        guard entry.count == PinStore.length else { return }
        if PinStore.verify(entry) {
            dismiss()
            onSuccess()
        } else {
            Haptics.error()
            wrong = true
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                entry = ""
            }
        }
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
