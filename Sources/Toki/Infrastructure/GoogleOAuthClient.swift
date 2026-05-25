import Foundation
import AppKit
import CryptoKit
import AuthenticationServices

/// Google OAuth 2.0 (iOS client + custom URL scheme + PKCE only) を管理するクライアント。
/// spec 016 で全面改修：
/// - LoopbackOAuthReceiver 廃止 → ASWebAuthenticationSession に移行
/// - client_secret 完全廃止（iOS client は secret 不要、PKCE で守る）
/// - redirect は custom scheme（`com.googleusercontent.apps.xxx:/oauthredirect`）
/// - token は KeychainStore に保存（変更なし）
///
/// クラス自体は actor isolation なし（KeychainStore は thread-safe）。
/// ASWebAuth 起動部分のみ @MainActor 局所適用。
final class GoogleOAuthClient: NSObject {
    enum OAuthClientError: Error {
        case tokenExchangeFailed(String)
        case refreshFailed(String)
        case revokeFailed(String)
        case noRefreshToken
        case invalidResponse
        case userCancelled
        case authSessionFailed(String)
    }

    private let config: OAuthConfig
    private let keychain: KeychainStore
    private let session: URLSession

    private static let consentURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenURL = "https://oauth2.googleapis.com/token"
    private static let revokeURL = "https://oauth2.googleapis.com/revoke"
    private static let scope = "https://www.googleapis.com/auth/calendar.readonly"

    private static let keyAccessToken = "oauth.access_token"
    private static let keyRefreshToken = "oauth.refresh_token"
    private static let keyExpiry = "oauth.access_token_expiry"

    init(config: OAuthConfig,
         keychain: KeychainStore,
         session: URLSession = .shared) {
        self.config = config
        self.keychain = keychain
        self.session = session
        super.init()
    }

    /// refresh_token が Keychain にあれば認証済みとみなす。
    var isAuthorized: Bool {
        keychain.get(Self.keyRefreshToken) != nil
    }

    /// OAuth consent を開始する（ASWebAuthenticationSession 経由）。
    /// 1. PKCE verifier / state nonce 生成
    /// 2. ASWebAuthenticationSession で consent URL を開く
    /// 3. custom scheme callback で code を受信、state 検証
    /// 4. code を token に交換して Keychain 保存
    func beginAuthorization() async throws {
        let verifier = Self.makeCodeVerifier()
        let challenge = Self.codeChallenge(from: verifier)
        let state = Self.makeNonce()

        let consentURL = makeConsentURL(challenge: challenge, state: state)
        let callbackURL = try await startWebAuthSession(url: consentURL)
        let code = try Self.extractCode(from: callbackURL, expectedState: state)
        try await exchange(code: code, verifier: verifier)
    }

    /// 有効な access_token を返す。
    /// expiry まで 60 秒以上あればそのまま返し、なければ refresh する。
    func getValidAccessToken() async throws -> String {
        if let token = keychain.get(Self.keyAccessToken),
           let expiryStr = keychain.get(Self.keyExpiry),
           let expiry = Double(expiryStr),
           Date(timeIntervalSince1970: expiry) > Date().addingTimeInterval(60) {
            return token
        }
        return try await refresh()
    }

    /// token を revoke して Keychain 全エントリを削除する。
    /// network 失敗 / non-2xx でも Keychain は必ずクリア（再認証で復旧可）。
    func revoke() async throws {
        guard let refreshToken = keychain.get(Self.keyRefreshToken) else {
            throw OAuthClientError.noRefreshToken
        }
        let url = URL(string: "\(Self.revokeURL)?token=\(refreshToken)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                print("GoogleOAuthClient.revoke: status \(http.statusCode), Keychain は引き続きクリア")
            }
        } catch {
            print("GoogleOAuthClient.revoke: network error: \(error), Keychain は引き続きクリア")
        }
        try? keychain.delete(Self.keyAccessToken)
        try? keychain.delete(Self.keyRefreshToken)
        try? keychain.delete(Self.keyExpiry)
    }

    // MARK: - private

    /// consent URL を組み立てる（PKCE / state / offline access / consent prompt 込み）。
    /// client_secret は **含めない**（PKCE が認証を担うため）。
    private func makeConsentURL(challenge: String, state: String) -> URL {
        var components = URLComponents(string: Self.consentURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return components.url!
    }

    /// ASWebAuthenticationSession を起動して callback URL を待つ。
    /// callback scheme は OAuthConfig.callbackURLScheme から取得。
    /// session.start() と presentation anchor は MainActor 必須。
    @MainActor
    private func startWebAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: config.callbackURLScheme
            ) { callbackURL, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: OAuthClientError.userCancelled)
                    } else {
                        continuation.resume(throwing: OAuthClientError.authSessionFailed(error.localizedDescription))
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: OAuthClientError.invalidResponse)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            // ephemeral=false：Safari の cookies / iCloud Keychain 連携で
            // 既ログインユーザーの 1 クリック認証を可能にする。
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    /// callback URL から `code` と `state` を抽出し、state を検証して `code` を返す。
    private static func extractCode(from url: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else {
            throw OAuthClientError.invalidResponse
        }
        let code = items.first(where: { $0.name == "code" })?.value
        let state = items.first(where: { $0.name == "state" })?.value
        guard state == expectedState else {
            throw OAuthClientError.authSessionFailed("state mismatch")
        }
        guard let code else {
            throw OAuthClientError.invalidResponse
        }
        return code
    }

    /// code → access_token / refresh_token 交換。
    /// client_secret は **送信しない**（PKCE only）。
    private func exchange(code: String, verifier: String) async throws {
        let body = [
            "client_id": config.clientId,
            "code": code,
            "redirect_uri": config.redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier
        ]
        let response = try await postForm(url: Self.tokenURL, body: body)
        guard let access = response["access_token"] as? String,
              let refresh = response["refresh_token"] as? String,
              let expiresIn = response["expires_in"] as? Double else {
            throw OAuthClientError.tokenExchangeFailed("missing fields")
        }
        let expiry = Date().addingTimeInterval(expiresIn).timeIntervalSince1970
        try keychain.set(access, forKey: Self.keyAccessToken)
        try keychain.set(refresh, forKey: Self.keyRefreshToken)
        try keychain.set(String(expiry), forKey: Self.keyExpiry)
    }

    /// refresh_token から access_token を更新する。
    /// client_secret は **送信しない**（PKCE only）。
    /// refresh も失敗（401 等）なら Keychain クリアして throw。
    private func refresh() async throws -> String {
        guard let refreshToken = keychain.get(Self.keyRefreshToken) else {
            throw OAuthClientError.noRefreshToken
        }
        let body = [
            "client_id": config.clientId,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        do {
            let response = try await postForm(url: Self.tokenURL, body: body)
            guard let access = response["access_token"] as? String,
                  let expiresIn = response["expires_in"] as? Double else {
                throw OAuthClientError.refreshFailed("missing fields")
            }
            let expiry = Date().addingTimeInterval(expiresIn).timeIntervalSince1970
            try keychain.set(access, forKey: Self.keyAccessToken)
            try keychain.set(String(expiry), forKey: Self.keyExpiry)
            return access
        } catch {
            // refresh 失敗 → Keychain クリアで未接続状態へ
            try? keychain.delete(Self.keyAccessToken)
            try? keychain.delete(Self.keyRefreshToken)
            try? keychain.delete(Self.keyExpiry)
            throw error
        }
    }

    /// application/x-www-form-urlencoded POST。
    private func postForm(url urlString: String, body: [String: String]) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else {
            throw OAuthClientError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let bodyString = body.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        let (data, _) = try await session.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthClientError.invalidResponse
        }
        return json
    }

    /// PKCE verifier：32 byte ランダム → base64url（pad 除去）。
    static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    /// PKCE challenge：SHA-256(verifier) を base64url。
    static func codeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    /// state nonce：32 byte ランダム → base64url（CSRF 防止）。
    private static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension GoogleOAuthClient: ASWebAuthenticationPresentationContextProviding {
    @MainActor
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // メインウィンドウを presentation anchor として返す。
        // メニューバー駐在型でメインウィンドウが取れないケースも考慮し、
        // フォールバックで NSApp.keyWindow → NSApp.windows.first を順に試す。
        if let main = NSApp.mainWindow {
            return main
        }
        if let key = NSApp.keyWindow {
            return key
        }
        if let first = NSApp.windows.first {
            return first
        }
        // 最終 fallback：新規ウィンドウ（実際にはここに来る前にいずれかの window が取れるはず）
        return NSWindow()
    }
}

extension Data {
    /// base64url（pad 除去、`+`→`-`、`/`→`_`）。
    func base64URLEncodedString() -> String {
        return base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
