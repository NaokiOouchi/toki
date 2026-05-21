import Foundation
import AppKit
import CryptoKit

/// Google OAuth 2.0 (Loopback IP) フローを管理するクライアント。
/// consent URL 生成（PKCE 付き）、code → token 交換、refresh、revoke を担当する。
/// token は KeychainStore に保存。
final class GoogleOAuthClient {
    enum OAuthClientError: Error {
        case tokenExchangeFailed(String)
        case refreshFailed(String)
        case revokeFailed(String)
        case noRefreshToken
        case invalidResponse
    }

    private let config: OAuthConfig
    private let keychain: KeychainStore
    private let receiver: LoopbackOAuthReceiver
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
         receiver: LoopbackOAuthReceiver,
         session: URLSession = .shared) {
        self.config = config
        self.keychain = keychain
        self.receiver = receiver
        self.session = session
    }

    /// refresh_token が Keychain にあれば認証済みとみなす。
    var isAuthorized: Bool {
        keychain.get(Self.keyRefreshToken) != nil
    }

    /// OAuth consent を開始する。
    /// 1. PKCE verifier / state nonce 生成
    /// 2. consent URL をデフォルトブラウザで開く
    /// 3. loopback で code を待つ
    /// 4. code を token に交換して Keychain 保存
    func beginAuthorization() async throws {
        let verifier = Self.makeCodeVerifier()
        let challenge = Self.codeChallenge(from: verifier)
        let state = Self.makeNonce()

        let consentURL = makeConsentURL(challenge: challenge, state: state)
        NSWorkspace.shared.open(consentURL)

        let port = Self.port(from: config.redirectURI) ?? 8081
        let code = try await receiver.waitForCode(port: port, expectedState: state)
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

    /// code → access_token / refresh_token 交換。
    private func exchange(code: String, verifier: String) async throws {
        let body = [
            "client_id": config.clientId,
            "client_secret": config.clientSecret,
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
    /// refresh も失敗（401 等）なら Keychain クリアして throw。
    private func refresh() async throws -> String {
        guard let refreshToken = keychain.get(Self.keyRefreshToken) else {
            throw OAuthClientError.noRefreshToken
        }
        let body = [
            "client_id": config.clientId,
            "client_secret": config.clientSecret,
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
    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    /// PKCE challenge：SHA-256(verifier) を base64url。
    private static func codeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    /// state nonce：32 byte ランダム → base64url（CSRF 防止）。
    private static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    /// redirect_uri 文字列からポート番号を抽出する。
    /// 例：`http://localhost:8081/callback` → 8081
    private static func port(from redirectURI: String) -> UInt16? {
        guard let url = URL(string: redirectURI), let port = url.port else { return nil }
        return UInt16(port)
    }
}

private extension Data {
    /// base64url（pad 除去、`+`→`-`、`/`→`_`）。
    func base64URLEncodedString() -> String {
        return base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
