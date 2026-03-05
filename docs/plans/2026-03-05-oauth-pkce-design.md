# OAuth PKCE Flow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace Claude Code Keychain token with AIMeter's own OAuth PKCE flow for a separate rate limit bucket.

**Architecture:** New OAuthManager handles PKCE auth flow, file-based token storage at ~/.config/aimeter/token. User signs in via browser, pastes code. Own token = own rate limit bucket, polling back to 60s.

**Tech Stack:** Swift/SwiftUI, CryptoKit (SHA256 for PKCE), URLSession, file-based token storage

---

### Task 1: Create OAuthManager

**Files:**
- Create: `AIMeter/Sources/App/OAuthManager.swift`

**Step 1: Write OAuthManager**

```swift
import Foundation
import CryptoKit
import AppKit

@MainActor
final class OAuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isAwaitingCode = false
    @Published var lastError: String?

    private let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let redirectUri = "https://console.anthropic.com/oauth/code/callback"
    private let tokenEndpoint = URL(string: "https://console.anthropic.com/v1/oauth/token")!

    // PKCE state (lives only during an auth flow)
    private var codeVerifier: String?
    private var oauthState: String?

    // File-based token storage
    private static var tokenFileURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/aimeter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("token")
    }

    init() {
        isAuthenticated = loadToken() != nil
    }

    // MARK: - Token Access

    func loadToken() -> String? {
        guard let data = try? Data(contentsOf: Self.tokenFileURL) else { return nil }
        let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return token?.isEmpty == false ? token : nil
    }

    private func saveToken(_ token: String) {
        let url = Self.tokenFileURL
        try? Data(token.utf8).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func deleteToken() {
        try? FileManager.default.removeItem(at: Self.tokenFileURL)
    }

    // MARK: - OAuth PKCE Flow

    func startOAuthFlow() {
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        let state = generateCodeVerifier()

        codeVerifier = verifier
        oauthState = state

        var components = URLComponents(string: "https://claude.ai/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: "user:profile user:inference"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]

        if let url = components.url {
            NSWorkspace.shared.open(url)
            isAwaitingCode = true
            lastError = nil
        }
    }

    func submitOAuthCode(_ rawCode: String) async {
        let parts = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "#", maxSplits: 1)
        let code = String(parts[0])

        if parts.count > 1 {
            let returnedState = String(parts[1])
            guard returnedState == oauthState else {
                lastError = "OAuth state mismatch — try again"
                isAwaitingCode = false
                codeVerifier = nil
                oauthState = nil
                return
            }
        }

        guard let verifier = codeVerifier else {
            lastError = "No pending OAuth flow"
            isAwaitingCode = false
            return
        }

        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "state": oauthState ?? "",
            "client_id": clientId,
            "redirect_uri": redirectUri,
            "code_verifier": verifier,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                lastError = "Invalid token response"
                return
            }
            guard http.statusCode == 200 else {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                lastError = "Token exchange failed: HTTP \(http.statusCode) \(bodyStr)"
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String else {
                lastError = "Could not parse token response"
                return
            }

            saveToken(accessToken)
            isAuthenticated = true
            isAwaitingCode = false
            lastError = nil
            codeVerifier = nil
            oauthState = nil
        } catch {
            lastError = "Token exchange error: \(error.localizedDescription)"
        }
    }

    func signOut() {
        deleteToken()
        isAuthenticated = false
        lastError = nil
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded()
    }
}

// MARK: - Base64URL

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

**Step 2: Regenerate and build**

```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter && xcodegen generate
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

**Step 3: Commit**

```bash
git add AIMeter/Sources/App/OAuthManager.swift && git commit -m "feat: add OAuthManager with PKCE flow and file-based token storage"
```

---

### Task 2: Update APIClient to use OAuthManager

**Files:**
- Modify: `AIMeter/Sources/Shared/APIClient.swift`

**Step 1: Remove token parameter, accept token directly**

The APIClient.fetchUsage already accepts a token parameter — keep that interface but the caller (UsageService) will now get the token from OAuthManager instead of KeychainHelper.

Actually, APIClient is fine as-is — it takes a token string. The change is in UsageService (Task 3). No changes needed here.

**Step 2: Commit** — skip, no changes.

---

### Task 3: Update UsageService to use OAuthManager

**Files:**
- Modify: `AIMeter/Sources/App/UsageService.swift`

**Step 1: Replace KeychainHelper with OAuthManager**

```swift
import Foundation
import Combine
import WidgetKit

@MainActor
final class UsageService: ObservableObject {
    @Published var usageData: UsageData = SharedDefaults.load() ?? .empty
    @Published var isStale: Bool = false
    @Published var error: UsageError? = nil

    private var timer: Timer?
    private var refreshInterval: TimeInterval = 60
    private weak var oauthManager: OAuthManager?

    enum UsageError: Error, Equatable {
        case noToken
        case fetchFailed
        case rateLimited(retryAfter: TimeInterval)
    }

    func start(interval: TimeInterval = 60, oauthManager: OAuthManager) {
        self.refreshInterval = interval
        self.oauthManager = oauthManager
        if let cached = SharedDefaults.load() {
            self.usageData = cached
            self.isStale = Date().timeIntervalSince(cached.fetchedAt) > refreshInterval * 2
        }
        Task { await fetch() }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.fetch() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func rescheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { [weak self] in await self?.fetch() }
        }
    }

    func fetch() async {
        guard let token = oauthManager?.loadToken() else {
            self.error = .noToken
            return
        }

        do {
            let data = try await APIClient.fetchUsage(token: token)
            self.usageData = data
            self.isStale = false
            if case .rateLimited = self.error { rescheduleTimer(interval: refreshInterval) }
            self.error = nil
            SharedDefaults.save(data)
            WidgetCenter.shared.reloadAllTimelines()
            NotificationManager.shared.check(metrics: NotificationManager.metrics(from: data))
        } catch let usageError as UsageError {
            self.isStale = true
            self.error = usageError
            if case .rateLimited(let retryAfter) = usageError {
                rescheduleTimer(interval: retryAfter + 5)
            }
        } catch {
            self.isStale = true
            self.error = .fetchFailed
        }
    }
}
```

**Step 2: Build and verify**

```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

Note: Build will fail until Task 4 updates AIMeterApp to pass oauthManager. That's expected.

**Step 3: Commit**

```bash
git add AIMeter/Sources/App/UsageService.swift && git commit -m "feat: UsageService uses OAuthManager instead of KeychainHelper"
```

---

### Task 4: Wire OAuthManager into AIMeterApp and PopoverView

**Files:**
- Modify: `AIMeter/Sources/App/AIMeterApp.swift`
- Modify: `AIMeter/Sources/App/PopoverView.swift`

**Step 1: Add OAuthManager StateObject in AIMeterApp**

Add `@StateObject private var oauthManager = OAuthManager()` and pass it to PopoverView. Update service.start calls to pass oauthManager:

```swift
PopoverView(
    service: service,
    copilotService: copilotService,
    glmService: glmService,
    updaterManager: updaterManager,
    oauthManager: oauthManager
)
.task {
    service.start(interval: refreshInterval, oauthManager: oauthManager)
    copilotService.start(interval: refreshInterval)
    glmService.start(interval: refreshInterval)
}
.onChange(of: refreshInterval) { _, newValue in
    service.stop()
    service.start(interval: newValue, oauthManager: oauthManager)
    copilotService.stop()
    copilotService.start(interval: newValue)
    glmService.stop()
    glmService.start(interval: newValue)
}
```

**Step 2: Add oauthManager to PopoverView**

Add `@ObservedObject var oauthManager: OAuthManager` property. Pass to InlineSettingsView:

```swift
case .settings:
    InlineSettingsView(updaterManager: updaterManager, oauthManager: oauthManager)
```

Update the Claude tab to check oauthManager.isAuthenticated:

```swift
case .claude:
    if !oauthManager.isAuthenticated {
        signInPromptView
    } else {
        ClaudeTabView(service: service, timeZone: configuredTimeZone)
    }
```

Remove the old `noTokenView` and replace with a `signInPromptView` that shows "Sign in with Claude" button.

**Step 3: Build and verify**

```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter
xcodegen generate
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

**Step 4: Commit**

```bash
git add AIMeter/Sources/App/AIMeterApp.swift AIMeter/Sources/App/PopoverView.swift && git commit -m "feat: wire OAuthManager into app, popover, and settings"
```

---

### Task 5: Add Sign In/Out UI to InlineSettingsView

**Files:**
- Modify: `AIMeter/Sources/App/PopoverView.swift` (InlineSettingsView section)

**Step 1: Add oauthManager property and auth UI**

Add `@ObservedObject var oauthManager: OAuthManager` to InlineSettingsView. Add sign-in/out section at the top of the settings body:

```swift
// Auth section
VStack(alignment: .leading, spacing: 8) {
    Text("Claude Account")
        .font(.system(size: 11))
        .foregroundColor(.secondary)

    if oauthManager.isAuthenticated {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 12))
            Text("Signed in")
                .font(.system(size: 12))
                .foregroundColor(.white)
            Spacer()
            Button("Sign Out") {
                oauthManager.signOut()
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundColor(.red)
        }
    } else if oauthManager.isAwaitingCode {
        Text("Paste the code from your browser:")
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        HStack {
            TextField("code#state", text: $oauthCode)
                .font(.system(size: 12))
                .textFieldStyle(.plain)
            Button("Submit") {
                Task { await oauthManager.submitOAuthCode(oauthCode) }
                oauthCode = ""
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .disabled(oauthCode.isEmpty)
        }
    } else {
        Button("Sign in with Claude") {
            oauthManager.startOAuthFlow()
        }
        .font(.system(size: 12))
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
    }

    if let error = oauthManager.lastError {
        Text(error)
            .font(.system(size: 10))
            .foregroundColor(.red)
    }
}
```

Add `@State private var oauthCode: String = ""` to InlineSettingsView.

**Step 2: Build and verify**

```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

**Step 3: Commit**

```bash
git add AIMeter/Sources/App/PopoverView.swift && git commit -m "feat: add OAuth sign in/out UI in settings"
```

---

### Task 6: Delete KeychainHelper and update defaults

**Files:**
- Delete: `AIMeter/Sources/Shared/KeychainHelper.swift`
- Modify: `AIMeter/project.yml` — change default refresh interval references
- Modify: `AIMeter/Sources/App/AIMeterApp.swift` — default interval to 60

**Step 1: Delete KeychainHelper**

```bash
rm /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter/Sources/Shared/KeychainHelper.swift
```

**Step 2: Update default intervals back to 60s**

In `AIMeterApp.swift`, change:
```swift
@AppStorage("refreshInterval") private var refreshInterval: Double = 60
```

In `PopoverView.swift` InlineSettingsView, change default and picker options:
```swift
@AppStorage("refreshInterval") private var refreshInterval: Double = 60
```

Update the picker to include 60s option:
```swift
Picker("", selection: $refreshInterval) {
    Text("1m").tag(60.0)
    Text("2m").tag(120.0)
    Text("3m").tag(180.0)
    Text("5m").tag(300.0)
}
```

Remove the migration guard `if refreshInterval < 100 { refreshInterval = 100 }` from onAppear.

**Step 3: Regenerate and build**

```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter && xcodegen generate
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: delete KeychainHelper, restore 60s default polling interval"
```

---

### Task 7: Delete unused SettingsView.swift

**Files:**
- Delete: `AIMeter/Sources/App/SettingsView.swift`

**Step 1: Delete**

```bash
rm /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter/Sources/App/SettingsView.swift
```

**Step 2: Regenerate and build**

```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter && xcodegen generate
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

**Step 3: Commit**

```bash
git add -A && git commit -m "chore: delete unused SettingsView.swift"
```

---

### Task 8: Build verification and re-auth after sign-in

**Step 1: Full build**

```bash
cd /Volumes/KhaiSSD/Documents/Github/personal/claude-usage-quota/AIMeter && xcodegen generate
xcodebuild -project AIMeter.xcodeproj -scheme AIMeter -configuration Debug build ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

**Step 2: Verify UsageService re-fetches after sign-in**

In AIMeterApp.swift, add onChange for oauthManager.isAuthenticated to trigger fetch:

```swift
.onChange(of: oauthManager.isAuthenticated) { _, isAuth in
    if isAuth {
        Task { await service.fetch() }
    }
}
```

**Step 3: Build and commit**

```bash
git add -A && git commit -m "feat: trigger usage fetch immediately after OAuth sign-in"
```
