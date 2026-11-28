import SwiftUI
import UIKit

/// Hides the app in the app switcher and whenever it isn't the active app.
///
/// A window of its own, above everything: a SwiftUI overlay on the root view
/// sits underneath sheets and full-screen covers, which are exactly where the
/// recovery phrase and the transfer being sent are shown. iOS takes the
/// switcher snapshot right after the scene deactivates, so the window goes up
/// in that notification, synchronously.
@MainActor
final class PrivacyCurtain {
    static let shared = PrivacyCurtain()

    /// Whether leaving the foreground-active state should cover the app.
    /// The lock screen shows nothing private, and Face ID over it deactivates the scene.
    var coversWhenInactive: () -> Bool = { true }

    private var window: UIWindow?
    private var observers: [NSObjectProtocol] = []

    func install() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIScene.willDeactivateNotification, object: nil, queue: .main) { note in
                let scene = note.object as? UIWindowScene
                MainActor.assumeIsolated { PrivacyCurtain.shared.deactivated(scene) }
            },
            center.addObserver(forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main) { note in
                let scene = note.object as? UIWindowScene
                MainActor.assumeIsolated { PrivacyCurtain.shared.show(in: scene) }
            },
            center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { PrivacyCurtain.shared.hide() }
            },
        ]
    }

    private func deactivated(_ scene: UIWindowScene?) {
        if coversWhenInactive() { show(in: scene) }
    }

    private func show(in scene: UIWindowScene?) {
        guard window == nil, let scene else { return }
        let curtain = UIWindow(windowScene: scene)
        // Above alerts and sheets, which live in the scene's main window.
        curtain.windowLevel = .alert + 1
        curtain.isUserInteractionEnabled = false
        let host = UIHostingController(rootView: CurtainView())
        host.view.backgroundColor = .clear
        curtain.rootViewController = host
        curtain.isHidden = false
        window = curtain
    }

    private func hide() {
        window?.isHidden = true
        window = nil
    }
}

private struct CurtainView: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Image("Logo").resizable().frame(width: 80, height: 80).clipShape(.rect(cornerRadius: Theme.Radius.card))
        }
    }
}

/// App-level hooks SwiftUI has no modifier for.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// No third-party keyboards anywhere in the app: one with Full Access sees
    /// every key, and this app's text fields take a recovery phrase and addresses.
    func application(
        _ application: UIApplication, shouldAllowExtensionPointIdentifier identifier: UIApplication.ExtensionPointIdentifier
    ) -> Bool {
        identifier != .keyboard
    }
}
