import Foundation
import WebKit
import AppKit
import Combine
import SwiftUI

// MARK: - SessionAuthManager

@MainActor
final class SessionAuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoggingIn = false
    @Published var lastError: String?
    @Published var organizationName: String?
    @Published var planName: String?
    @Published var capabilities: [String] = []

    private(set) var sessionKey: String?
    private(set) var organizationId: String?

    private static var configDir: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/aimeter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var sessionFile: URL { configDir.appendingPathComponent("session") }
    private static var orgFile: URL { configDir.appendingPathComponent("org") }
    private static var orgNameFile: URL { configDir.appendingPathComponent("org_name") }
    private static var planFile: URL { configDir.appendingPathComponent("plan") }
    private static var capsFile: URL { configDir.appendingPathComponent("capabilities") }

    init() {
        loadCredentials()
    }

    // MARK: - Credential Storage

    private func loadCredentials() {
        sessionKey = readFile(Self.sessionFile)
        organizationId = readFile(Self.orgFile)
        organizationName = readFile(Self.orgNameFile)
        planName = readFile(Self.planFile)
        if let capsData = try? Data(contentsOf: Self.capsFile),
           let caps = try? JSONDecoder().decode([String].self, from: capsData) {
            capabilities = caps
        }
        isAuthenticated = sessionKey != nil && organizationId != nil
    }

    func saveCredentials(sessionKey: String, orgId: String, orgName: String,
                         planName: String? = nil, capabilities: [String] = []) {
        writeFile(Self.sessionFile, content: sessionKey)
        writeFile(Self.orgFile, content: orgId)
        writeFile(Self.orgNameFile, content: orgName)
        if let plan = planName { writeFile(Self.planFile, content: plan) }
        if !capabilities.isEmpty,
           let data = try? JSONEncoder().encode(capabilities) {
            try? data.write(to: Self.capsFile, options: .atomic)
        }
        self.sessionKey = sessionKey
        self.organizationId = orgId
        self.organizationName = orgName
        self.planName = planName ?? self.planName
        self.capabilities = capabilities.isEmpty ? self.capabilities : capabilities
        self.isAuthenticated = true
        self.lastError = nil
    }

    func signOut() {
        try? FileManager.default.removeItem(at: Self.sessionFile)
        try? FileManager.default.removeItem(at: Self.orgFile)
        try? FileManager.default.removeItem(at: Self.orgNameFile)
        try? FileManager.default.removeItem(at: Self.planFile)
        try? FileManager.default.removeItem(at: Self.capsFile)
        sessionKey = nil
        organizationId = nil
        organizationName = nil
        planName = nil
        capabilities = []
        isAuthenticated = false
        lastError = nil
    }

    func openLoginWindow() {
        isLoggingIn = true
        lastError = nil
        WebLoginWindowManager.shared.openLoginWindow(authManager: self)
    }

    func loginCompleted() {
        isLoggingIn = false
    }

    func loginFailed(_ message: String) {
        isLoggingIn = false
        lastError = message
    }

    /// Parse rate_limit_tier into a human-readable plan name
    /// e.g. "default_claude_max_5x" → "Max 5×", "default_claude_pro" → "Pro"
    static func parsePlanName(rateLimitTier: String) -> String? {
        let tier = rateLimitTier.lowercased()
        if tier.contains("max_5x") { return "Max 5×" }
        if tier.contains("max") { return "Max" }
        if tier.contains("pro") { return "Pro" }
        if tier.contains("team") { return "Team" }
        if tier.contains("enterprise") { return "Enterprise" }
        if tier.contains("free") { return "Free" }
        return nil
    }

    private func readFile(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return str?.isEmpty == false ? str : nil
    }

    private func writeFile(_ url: URL, content: String) {
        try? Data(content.utf8).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

// MARK: - WebLoginWindowManager

@MainActor
final class WebLoginWindowManager {
    static let shared = WebLoginWindowManager()
    private var window: NSWindow?

    func openLoginWindow(authManager: SessionAuthManager) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let coordinator = WebLoginCoordinator(authManager: authManager)
        let view = WebLoginContentView(coordinator: coordinator)
        let hostingView = NSHostingView(rootView: view)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Sign in to Claude"
        win.contentView = hostingView
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: win,
            queue: .main
        ) { [weak self] _ in
            coordinator.cleanup()
            authManager.loginCompleted()
            self?.window = nil
        }

        window = win
    }

    func closeLoginWindow() {
        window?.close()
        window = nil
    }
}

// MARK: - WebLoginCoordinator

final class WebLoginCoordinator: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    enum LoginState: Equatable {
        case loading
        case waitingForLogin
        case validating
        case success(name: String)
        case failed(message: String)
    }

    @Published var loginState: LoginState = .loading
    @Published var loadProgress: Double = 0

    let webView: WKWebView
    private weak var authManager: SessionAuthManager?
    private var cookieTimer: Timer?
    private var progressObservation: NSKeyValueObservation?
    private var popupWebView: WKWebView?
    private var popupWindow: NSWindow?

    /// Block only help/support pages; allow everything else for OAuth
    private let blockedDomains: Set<String> = [
        "support.google.com", "support.apple.com", "help.apple.com"
    ]

    @MainActor
    init(authManager: SessionAuthManager) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
        self.webView = wv
        self.authManager = authManager
        super.init()
        wv.navigationDelegate = self
        wv.uiDelegate = self

        progressObservation = wv.observe(\.estimatedProgress) { [weak self] wv, _ in
            DispatchQueue.main.async { self?.loadProgress = wv.estimatedProgress }
        }
    }

    @MainActor
    func loadLoginPage() {
        guard let url = URL(string: "https://claude.ai/login") else { return }
        loginState = .loading
        webView.load(URLRequest(url: url))
    }

    func cleanup() {
        cookieTimer?.invalidate()
        cookieTimer = nil
        progressObservation = nil
        popupWindow?.close()
        popupWindow = nil
        popupWebView = nil
    }

    // MARK: - Cookie Monitoring

    private func startCookieMonitoring() {
        cookieTimer?.invalidate()
        cookieTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkForSessionKey()
        }
    }

    private func checkForSessionKey() {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            if let cookie = cookies.first(where: { $0.name == "sessionKey" && $0.domain.contains("claude.ai") }) {
                let key = cookie.value
                DispatchQueue.main.async {
                    self.cookieTimer?.invalidate()
                    self.cookieTimer = nil
                    self.validateSessionKey(key)
                }
            }
        }
    }

    private func validateSessionKey(_ sessionKey: String) {
        DispatchQueue.main.async { self.loginState = .validating }

        let url = URL(string: "https://claude.ai/api/organizations")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        ClaudeHeaderBuilder.applyHeaders(to: &request, sessionKey: sessionKey)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self, let data else {
                DispatchQueue.main.async {
                    self?.loginState = .failed(message: error?.localizedDescription ?? "Network error")
                    self?.startCookieMonitoring()
                }
                return
            }

            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                DispatchQueue.main.async {
                    self.loginState = .failed(message: "HTTP \(http.statusCode)")
                    self.startCookieMonitoring()
                }
                return
            }

            // Parse orgs with flexible field capture for plan detection
            guard let orgsJson = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let first = orgsJson.first,
                  let uuid = first["uuid"] as? String,
                  let name = first["name"] as? String else {
                DispatchQueue.main.async {
                    self.loginState = .failed(message: "No organizations found")
                    self.startCookieMonitoring()
                }
                return
            }

            // Extract plan from rate_limit_tier (e.g. "default_claude_max_5x" → "Max 5×")
            let rateLimitTier = first["rate_limit_tier"] as? String ?? ""
            let planName = SessionAuthManager.parsePlanName(rateLimitTier: rateLimitTier)
            let capabilities = first["capabilities"] as? [String] ?? []

            DispatchQueue.main.async {
                Task { @MainActor in
                    self.authManager?.saveCredentials(
                        sessionKey: sessionKey,
                        orgId: uuid,
                        orgName: name,
                        planName: planName,
                        capabilities: capabilities
                    )
                    self.loginState = .success(name: name)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        WebLoginWindowManager.shared.closeLoginWindow()
                    }
                }
            }
        }.resume()
    }

    // MARK: - WKUIDelegate (popup handling for Google Sign-In)

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Google Sign-In opens a popup — create a real child webview sharing the same session
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.customUserAgent = webView.customUserAgent
        popup.navigationDelegate = self
        popup.uiDelegate = self

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Sign in with Google"
        win.contentView = popup
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)

        self.popupWebView = popup
        self.popupWindow = win
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        // Google closes the popup after auth completes
        if webView === popupWebView {
            popupWindow?.close()
            popupWindow = nil
            popupWebView = nil
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.async {
            if case .validating = self.loginState { return }
            if case .success = self.loginState { return }
            self.loginState = .waitingForLogin
            self.startCookieMonitoring()
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        DispatchQueue.main.async {
            if case .validating = self.loginState { return }
            self.loginState = .loading
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        DispatchQueue.main.async {
            self.loginState = .failed(message: error.localizedDescription)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let host = navigationAction.request.url?.host?.lowercased() else {
            decisionHandler(.allow)
            return
        }
        let blocked = blockedDomains.contains { host == $0 || host.hasSuffix(".\($0)") }
        if blocked {
            if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
}

// MARK: - WebLoginContentView

struct WebLoginContentView: View {
    @ObservedObject var coordinator: WebLoginCoordinator

    var body: some View {
        VStack(spacing: 0) {
            statusBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            Divider()
            WebViewWrapper(webView: coordinator.webView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if coordinator.loadProgress > 0 && coordinator.loadProgress < 1.0 {
                ProgressView(value: coordinator.loadProgress)
                    .progressViewStyle(.linear)
            }
        }
        .onAppear { coordinator.loadLoginPage() }
        .onDisappear { coordinator.cleanup() }
    }

    @ViewBuilder
    private var statusBar: some View {
        switch coordinator.loginState {
        case .loading:
            statusRow(icon: "globe", color: .blue, text: "Loading...", spinner: true)
        case .waitingForLogin:
            VStack(alignment: .leading, spacing: 4) {
                statusRow(icon: "person.crop.circle", color: .orange, text: "Sign in to your Claude account", spinner: false)
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield.fill").font(.caption2).foregroundColor(.secondary)
                    Text("Your credentials stay on this device only")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
        case .validating:
            statusRow(icon: "checkmark.shield.fill", color: .blue, text: "Verifying session...", spinner: true)
        case .success(let name):
            statusRow(icon: "checkmark.circle.fill", color: .green, text: "Signed in as \(name)", spinner: false)
        case .failed(let msg):
            statusRow(icon: "exclamationmark.triangle.fill", color: .red, text: msg, spinner: false)
        }
    }

    private func statusRow(icon: String, color: Color, text: String, spinner: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundColor(color)
            Text(text).font(.subheadline)
            Spacer()
            if spinner { ProgressView().scaleEffect(0.7).frame(width: 16, height: 16) }
        }
    }
}

struct WebViewWrapper: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
