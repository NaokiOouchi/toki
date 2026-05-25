import Foundation

/// Google OAuth Client（iOS type）の設定。
/// spec 016 で公開対応に移行：
/// - PKCE 採用により client_secret は **不要**（iOS client は secret を持たない）
/// - Bundle 内に client_id のみ埋め込み（バイナリ解析されても PKCE で安全）
/// - redirect は custom URL scheme（loopback ではない）
/// - Info.plist の CFBundleURLTypes に同 scheme を登録すること
///
/// 旧版（spec 016 前）の `~/.config/toki/oauth.json` 読み込みは廃止。
/// Sandbox 環境で外部ファイルにアクセスできないため、Bundle 同梱方式に移行した。
struct OAuthConfig {
    let clientId: String
    let redirectURI: String

    /// Toki Mac App 用の iOS OAuth Client。
    /// Google Cloud Console で発行（Bundle ID: jp.co.noouchi.toki）。
    /// 詳細は specs/016-oauth-pkce-public.md §5.1 参照。
    static let `default` = OAuthConfig(
        clientId: "509549478487-up4ti0ct4rdc9fupqdslgk8egjvck75s.apps.googleusercontent.com",
        redirectURI: "com.googleusercontent.apps.509549478487-up4ti0ct4rdc9fupqdslgk8egjvck75s:/oauthredirect"
    )

    /// redirect URI から callback scheme を抽出する。
    /// 例：`com.googleusercontent.apps.xxx:/oauthredirect` → `com.googleusercontent.apps.xxx`
    /// ASWebAuthenticationSession の `callbackURLScheme` 引数に渡す。
    var callbackURLScheme: String {
        guard let colonIndex = redirectURI.firstIndex(of: ":") else {
            return redirectURI
        }
        return String(redirectURI[..<colonIndex])
    }
}
