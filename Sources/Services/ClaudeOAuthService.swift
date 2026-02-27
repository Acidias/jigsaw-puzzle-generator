import Foundation
import AppKit
import WebKit
import CryptoKit

// MARK: - OAuth Tokens

struct OAuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    var isExpired: Bool {
        Date() >= expiresAt
    }

    /// Whether the token expires within the given interval (default 5 minutes).
    func expiresSoon(within interval: TimeInterval = 300) -> Bool {
        Date().addingTimeInterval(interval) >= expiresAt
    }
}

// MARK: - Claude OAuth Service

/// Handles OAuth 2.0 Authorization Code + PKCE flow for Claude authentication.
/// Uses WKWebView in an NSWindow to present the login page and intercept the callback.
enum ClaudeOAuthService {

    // MARK: - OAuth Configuration

    private static let authorizeURL = "https://claude.ai/oauth/authorize"
    private static let tokenURL = "https://console.anthropic.com/v1/oauth/token"
    private static let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let scopes = "org:create_api_key user:profile user:inference"

    // MARK: - PKCE

    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private static func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncoded()
    }

    // MARK: - Public API

    /// Opens a WKWebView window for the user to authenticate with Claude.
    /// Returns the authenticated email address on success.
    @MainActor
    static func authenticate() async throws -> String {
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)

        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        let authURL = components.url!

        // Present WKWebView and wait for the authorization code
        let code = try await presentAuthWindow(url: authURL)

        // Exchange code for tokens
        let tokens = try await exchangeCodeForTokens(code: code, codeVerifier: codeVerifier)
        ChatCredentialStore.claudeOAuthTokens = tokens

        // Fetch user profile for email display
        let email = await fetchUserEmail(accessToken: tokens.accessToken)
        ChatCredentialStore.claudeOAuthEmail = email

        return email
    }

    /// Returns a valid access token, refreshing if needed.
    static func getValidToken() async throws -> String {
        guard let tokens = ChatCredentialStore.claudeOAuthTokens else {
            throw OAuthError.notAuthenticated
        }

        if !tokens.expiresSoon() {
            return tokens.accessToken
        }

        // Token is expired or expiring soon - refresh it
        let newTokens = try await refreshTokens(using: tokens.refreshToken)
        await MainActor.run {
            ChatCredentialStore.claudeOAuthTokens = newTokens
        }
        return newTokens.accessToken
    }

    /// Clears all stored OAuth tokens and email.
    static func signOut() {
        ChatCredentialStore.claudeOAuthTokens = nil
        ChatCredentialStore.claudeOAuthEmail = nil
    }

    /// Whether valid OAuth tokens exist.
    static var isAuthenticated: Bool {
        ChatCredentialStore.isClaudeOAuthActive
    }

    // MARK: - Token Exchange

    private static func exchangeCodeForTokens(code: String, codeVerifier: String) async throws -> OAuthTokens {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "grant_type=authorization_code",
            "code=\(code.urlQueryEncoded())",
            "redirect_uri=\(redirectURI.urlQueryEncoded())",
            "client_id=\(clientID.urlQueryEncoded())",
            "code_verifier=\(codeVerifier.urlQueryEncoded())",
        ]
        request.httpBody = bodyParams.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.tokenExchangeFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OAuthError.tokenExchangeFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        return try parseTokenResponse(data: data)
    }

    private static func refreshTokens(using refreshToken: String) async throws -> OAuthTokens {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken.urlQueryEncoded())",
            "client_id=\(clientID.urlQueryEncoded())",
        ]
        request.httpBody = bodyParams.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.refreshFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            // If refresh fails (e.g. token revoked), clear credentials
            if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
                signOut()
            }
            throw OAuthError.refreshFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        return try parseTokenResponse(data: data)
    }

    private static func parseTokenResponse(data: Data) throws -> OAuthTokens {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String else {
            throw OAuthError.tokenExchangeFailed("Invalid token response format")
        }

        // expiresIn defaults to 8 hours if not provided
        let expiresIn = json["expires_in"] as? TimeInterval ?? 28800
        let expiresAt = Date().addingTimeInterval(expiresIn)

        return OAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt
        )
    }

    // MARK: - User Profile

    private static func fetchUserEmail(accessToken: String) async -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/me")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let email = json["email"] as? String {
                return email
            }
        } catch {
            // Non-critical - just won't show email
        }
        return "Claude User"
    }

    // MARK: - Auth Window (WKWebView)

    @MainActor
    private static func presentAuthWindow(url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 700),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Sign in with Claude"
            window.center()

            let webView = WKWebView(frame: window.contentView!.bounds)
            webView.autoresizingMask = [.width, .height]
            window.contentView!.addSubview(webView)

            let delegate = OAuthNavigationDelegate(
                redirectURI: redirectURI,
                window: window,
                continuation: continuation
            )
            webView.navigationDelegate = delegate

            // Store delegate to prevent deallocation
            objc_setAssociatedObject(
                window,
                &OAuthNavigationDelegate.associatedKey,
                delegate,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )

            // Also watch for window close (user cancelled)
            let closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                delegate.handleWindowClose()
            }
            objc_setAssociatedObject(
                window,
                &OAuthNavigationDelegate.observerKey,
                closeObserver,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )

            webView.load(URLRequest(url: url))
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Errors

    enum OAuthError: LocalizedError {
        case notAuthenticated
        case cancelled
        case authCodeNotFound
        case tokenExchangeFailed(String)
        case refreshFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "Not signed in to Claude. Please sign in first."
            case .cancelled:
                return "Sign-in was cancelled."
            case .authCodeNotFound:
                return "Could not extract authorization code from callback."
            case .tokenExchangeFailed(let detail):
                return "Token exchange failed: \(detail)"
            case .refreshFailed(let detail):
                return "Token refresh failed: \(detail)"
            }
        }
    }
}

// MARK: - WKWebView Navigation Delegate

private class OAuthNavigationDelegate: NSObject, WKNavigationDelegate {
    static var associatedKey = 0
    static var observerKey = 1

    private let redirectURI: String
    private let window: NSWindow
    private var continuation: CheckedContinuation<String, Error>?

    init(redirectURI: String, window: NSWindow, continuation: CheckedContinuation<String, Error>) {
        self.redirectURI = redirectURI
        self.window = window
        self.continuation = continuation
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url,
              url.absoluteString.hasPrefix(redirectURI) else {
            decisionHandler(.allow)
            return
        }

        // This is the callback - extract the authorization code
        decisionHandler(.cancel)

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
            resolve(with: .success(code))
        } else {
            // Try extracting from fragment as fallback
            if let fragment = url.fragment,
               let fragmentComponents = URLComponents(string: "?\(fragment)"),
               let code = fragmentComponents.queryItems?.first(where: { $0.name == "code" })?.value {
                resolve(with: .success(code))
            } else {
                resolve(with: .failure(ClaudeOAuthService.OAuthError.authCodeNotFound))
            }
        }
    }

    func handleWindowClose() {
        resolve(with: .failure(ClaudeOAuthService.OAuthError.cancelled))
    }

    private func resolve(with result: Result<String, Error>) {
        guard let continuation = continuation else { return }
        self.continuation = nil
        window.close()
        continuation.resume(with: result)
    }
}

// MARK: - Helpers

private extension Data {
    /// Base64url encoding (RFC 7636): no padding, URL-safe characters.
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    /// Percent-encodes for use in application/x-www-form-urlencoded body.
    func urlQueryEncoded() -> String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
