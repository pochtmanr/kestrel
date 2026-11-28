import SwiftUI
import WebKit

/// Support and legal links. The pages are built from `website/` in this repo.
/// TODO(Simnetiq): fill in the Chatwoot values once the instance exists, and
/// update the site's privacy policy before switching the chat on. While those
/// are empty the support chat button stays hidden; while a URL is nil its row is hidden.
enum SupportConfig {
    static let chatwootBaseURL: URL? = nil
    /// Public website-inbox token (it's embedded in every chat widget page).
    static let chatwootWebsiteToken = ""
    private static let site = "https://kastrel.xyz"
    // Trailing slashes: the site serves every page at a directory URL.
    static let terms = URL(string: "\(site)/terms/")
    static let privacy = URL(string: "\(site)/privacy/")
    static let support = URL(string: "\(site)/support/")

    static var isChatConfigured: Bool { chatwootBaseURL != nil && !chatwootWebsiteToken.isEmpty }
}

/// Support chat, opened as a sheet from the wallet header. Chatwoot's widget
/// carries the FAQ, and has its own header with an X: closing it there
/// dismisses the sheet (see `chatwoot:closed` below).
struct SupportChatSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ChatwootWebView(onClose: { dismiss() })
            .ignoresSafeArea(edges: .bottom)
            .background(Theme.Palette.background)
            .formSheetSizing()
    }
}

/// Chatwoot's web widget, opened full screen and identified with a stable,
/// anonymous per-install id so the conversation survives relaunches.
private struct ChatwootWebView: UIViewRepresentable {
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onClose: onClose) }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }

        /// Only the chat itself loads in here. This view has no address bar, so
        /// a link from a conversation opening inside it could pass for the app
        /// (a page asking for the recovery phrase, say): links go to Safari.
        func webView(
            _ webView: WKWebView, decidePolicyFor action: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .cancel }
            if ChatwootWebView.isChatURL(url) { return .allow }
            if action.navigationType == .linkActivated, ["https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                await UIApplication.shared.open(url)
            }
            return .cancel
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "chatwootClosed" { onClose() }
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "chatwootClosed")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.loadHTMLString(html, baseURL: SupportConfig.chatwootBaseURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    /// The widget's own page and frames: the Chatwoot origin, and the inline
    /// documents (`about:blank`, `about:srcdoc`) its SDK builds its frame from.
    static func isChatURL(_ url: URL, base: URL? = SupportConfig.chatwootBaseURL) -> Bool {
        if url.scheme == "about" { return true }
        guard let base, url.scheme == "https", base.scheme == "https" else { return false }
        return url.host?.lowercased() == base.host?.lowercased() && url.port == base.port
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "chatwootClosed")
    }

    private var html: String {
        let base = SupportConfig.chatwootBaseURL?.absoluteString ?? ""
        return """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <style>html,body{margin:0;height:100%;background:#0A0A0B}</style>
        </head><body><script>
        window.chatwootSettings = { hideMessageBubble: true, locale: 'en', darkMode: 'dark', position: 'right' };
        window.addEventListener('chatwoot:ready', function () {
          window.$chatwoot.setUser('\(SupportIdentity.id)', { name: '\(Brand.name) user' });
          window.$chatwoot.setCustomAttributes({ app: 'kestrel-ios', mode: 'non-custodial' });
          window.$chatwoot.toggle('open');
        });
        // The widget's own X closes the native sheet too.
        window.addEventListener('chatwoot:closed', function () {
          window.webkit.messageHandlers.chatwootClosed.postMessage(true);
        });
        (function (d, t) {
          var g = d.createElement(t), s = d.getElementsByTagName(t)[0];
          g.src = '\(base)/packs/js/sdk.js'; g.async = true; s.parentNode.insertBefore(g, s);
          g.onload = function () { window.chatwootSDK.run({ websiteToken: '\(SupportConfig.chatwootWebsiteToken)', baseUrl: '\(base)' }); };
        })(document, 'script');
        </script></body></html>
        """
    }
}
