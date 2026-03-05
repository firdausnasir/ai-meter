import Foundation

enum ClaudeHeaderBuilder {
    static func applyHeaders(to request: inout URLRequest, sessionKey: String, orgId: String? = nil) {
        let headers: [String: String] = [
            "accept": "*/*",
            "accept-language": "en-US,en;q=0.9",
            "content-type": "application/json",
            "anthropic-client-platform": "web_claude_ai",
            "anthropic-client-version": "1.0.0",
            "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            "origin": "https://claude.ai",
            "referer": "https://claude.ai/settings/usage",
            "sec-fetch-dest": "empty",
            "sec-fetch-mode": "cors",
            "sec-fetch-site": "same-origin",
            "Cookie": "sessionKey=\(sessionKey)"
        ]
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }
}
