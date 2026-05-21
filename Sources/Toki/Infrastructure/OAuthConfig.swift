import Foundation

/// Google OAuth Client の設定。
/// ユーザーが Google Cloud Console で OAuth Client（Desktop アプリ）を作成し
/// `~/.config/toki/oauth.json` に貼り付ける運用。
/// 設定ファイルが存在しない場合は nil を返し、OAuth 未設定として扱う。
///
/// JSON フォーマット：
/// {
///   "client_id": "...",
///   "client_secret": "...",
///   "redirect_uri": "http://localhost:8081/callback"
/// }
struct OAuthConfig: Decodable {
    let clientId: String
    let clientSecret: String
    let redirectURI: String

    private enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case clientSecret = "client_secret"
        case redirectURI = "redirect_uri"
    }

    /// `~/.config/toki/oauth.json` を読み込んで `OAuthConfig` を返す。
    /// ファイル無し / パース失敗 / 必須キー欠落の場合は nil。
    static func load() -> OAuthConfig? {
        let path = ("~/.config/toki/oauth.json" as NSString).expandingTildeInPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        return try? JSONDecoder().decode(OAuthConfig.self, from: data)
    }
}
