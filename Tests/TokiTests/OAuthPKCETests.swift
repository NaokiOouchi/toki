import XCTest
@testable import Toki

/// PKCE (RFC 7636) のテストベクトル検証。
/// spec 016 で GoogleOAuthClient.makeCodeVerifier / codeChallenge を public test 用に再公開。
final class OAuthPKCETests: XCTestCase {

    /// RFC 7636 Section 4.6 のテストベクトル：
    /// code_verifier  = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    /// code_challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    func testRFC7636TestVector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expected = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

        let challenge = GoogleOAuthClient.codeChallenge(from: verifier)

        XCTAssertEqual(challenge, expected,
                       "RFC 7636 Section 4.6 のテストベクトルに一致しない")
    }

    /// code_verifier が 32 byte ランダム → Base64URL（pad 除去）で生成されることを確認。
    /// Base64URL は 32 byte → 43 文字（pad なし）。
    func testCodeVerifierLengthAndFormat() {
        let verifier = GoogleOAuthClient.makeCodeVerifier()

        // 32 byte を Base64URL する → 43 文字（pad なし）
        XCTAssertEqual(verifier.count, 43,
                       "32 byte 乱数の Base64URL は 43 文字（pad なし）であるべき")

        // Base64URL 文字セットのみ（A-Z, a-z, 0-9, -, _）
        let allowedSet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let verifierSet = CharacterSet(charactersIn: verifier)
        XCTAssertTrue(allowedSet.isSuperset(of: verifierSet),
                      "verifier に Base64URL 以外の文字が含まれている")

        // pad 文字 = は含まれない
        XCTAssertFalse(verifier.contains("="),
                       "Base64URL は pad なしであるべき")
    }

    /// code_verifier がランダム性を持つ（連続生成で異なる値）。
    func testCodeVerifierRandomness() {
        let v1 = GoogleOAuthClient.makeCodeVerifier()
        let v2 = GoogleOAuthClient.makeCodeVerifier()
        let v3 = GoogleOAuthClient.makeCodeVerifier()

        XCTAssertNotEqual(v1, v2)
        XCTAssertNotEqual(v2, v3)
        XCTAssertNotEqual(v1, v3)
    }

    /// code_challenge も Base64URL フォーマット（SHA-256 32 byte → 43 文字）。
    func testCodeChallengeFormat() {
        let verifier = GoogleOAuthClient.makeCodeVerifier()
        let challenge = GoogleOAuthClient.codeChallenge(from: verifier)

        XCTAssertEqual(challenge.count, 43,
                       "SHA-256 ハッシュの Base64URL は 43 文字")
        XCTAssertFalse(challenge.contains("="),
                       "challenge も pad なしであるべき")
    }
}
