import AppKit
import WebKit

// MARK: - In-app Claude sign-in (WKWebView)
//
// Replaces the DevTools copy-paste flow: the user logs into claude.ai in a real
// web view, and we capture the session cookies the moment `sessionKey` appears.
// We hand back the full claude.ai cookie header — exactly what the user used to
// paste by hand — so the rest of the app is unchanged.
//
// Google/Apple SSO deliberately block embedded web views (the `disallowed_useragent`
// policy). We mitigate two ways: (1) present as desktop Safari so Google's UA gate
// is satisfied, and (2) route popup-based logins back into the main frame so the
// SSO button actually does something. Email/password login works regardless; users
// who still can't SSO can fall back to manual cookie paste.
final class LoginWindowController: NSWindowController, WKHTTPCookieStoreObserver, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    private var webView: WKWebView!
    private let onCapture: (String) -> Void
    private var captured = false
    // The cookie-change observer and full-page-load events are unreliable for
    // HttpOnly cookies set during the SPA navigation after login/terms, so we
    // also poll the cookie store while the window is open.
    private var pollTimer: Timer?
    // Child windows for SSO popups (Google/Apple); released on close.
    private var popupWindows: [NSWindow] = []

    // Recent desktop Safari UA — gets past Google's embedded-web-view block.
    private let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"

    init(onCapture: @escaping (String) -> Void) {
        self.onCapture = onCapture

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to Claude"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self

        let config = WKWebViewConfiguration()
        // Non-persistent store: the login view always starts logged-out, so any
        // captured `sessionKey` is one the user just minted (never a stale cookie
        // left over from a prior, now server-expired session — which would trap
        // the re-auth flow in a 401 loop). Also keeps the Claude session out of
        // the app's on-disk data store.
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: window.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.customUserAgent = desktopUserAgent
        window.contentView?.addSubview(webView)
        self.webView = webView

        config.websiteDataStore.httpCookieStore.add(self)
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))

        // Poll the cookie store as the primary, event-independent capture path.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.captureIfReady(from: self.webView.configuration.websiteDataStore.httpCookieStore)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Only react to the main login window closing (popups aren't delegated here).
        guard (notification.object as? NSWindow) == window else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        webView?.configuration.websiteDataStore.httpCookieStore.remove(self)
        popupWindows.forEach { $0.close() }
        popupWindows.removeAll()
    }

    // Fired when claude.ai sets/refreshes cookies (the normal login signal).
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        captureIfReady(from: cookieStore)
    }

    // Safety net: if a valid session is restored without a cookie change
    // (e.g. re-login while a session still exists), catch it on page load.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        captureIfReady(from: webView.configuration.websiteDataStore.httpCookieStore)
    }

    // SSO (Google Identity Services, Apple) opens login in a real popup and
    // postMessages the result back to the OPENER. So we must give it an actual
    // child web view in its own window — loading the popup in the main frame
    // would navigate claude.ai away and break that handshake (no sessionKey).
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Must reuse the passed `configuration` so the popup shares the opener's
        // process/cookie store and keeps the window.opener relationship.
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.customUserAgent = desktopUserAgent
        popup.navigationDelegate = self
        popup.uiDelegate = self

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        w.title = "Sign in"
        w.isReleasedWhenClosed = false
        w.contentView = popup
        w.center()
        w.makeKeyAndOrderFront(nil)
        popupWindows.append(w)
        return popup
    }

    // SSO popups call window.close() when done — honor it and release the window.
    func webViewDidClose(_ webView: WKWebView) {
        if let w = webView.window {
            w.close()
            popupWindows.removeAll { $0 == w }
        }
    }

    private func captureIfReady(from cookieStore: WKHTTPCookieStore) {
        cookieStore.getAllCookies { [weak self] cookies in
            guard let self = self, !self.captured else { return }

            let claudeCookies = cookies.filter { $0.domain.hasSuffix("claude.ai") }
            // `sessionKey` is only set after a successful login — treat its
            // presence as the signal that we have a usable session.
            guard claudeCookies.contains(where: { $0.name == "sessionKey" && !$0.value.isEmpty })
            else { return }

            let header = claudeCookies
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")

            self.captured = true
            DispatchQueue.main.async {
                self.pollTimer?.invalidate()
                self.pollTimer = nil
                self.close()
                self.onCapture(header)
            }
        }
    }

    deinit {
        pollTimer?.invalidate()
    }
}
