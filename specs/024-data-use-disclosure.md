# 024 — App Store Connect Data Use Disclosure

参照: `specs/ROADMAP.md` §2 Phase 3C
依存: spec 023（Privacy Policy）完了済み、spec 016（OAuth）完了済み
ステータス: **設計確定**（App Store Connect 入力時に最終確認）

App Store Connect の Privacy Disclosure 質問に対する回答を事前に整理する。
spec 023 Privacy Policy と整合した内容を、Apple の質問形式に合わせてマッピング。

## 1. 目的

- App Store Connect の「App Privacy」セクションを正確に入力するための準備
- Toki が収集する / 収集しないデータを明確化
- 矛盾なく Privacy Policy（`docs/privacy.md` / `docs/privacy-en.md`）と整合させる

## 2. App Store Connect 入力フロー

App Store Connect の Privacy Disclosure は質問形式：
1. **Do you or your third-party partners collect data from this app?**
2. データ収集 = Yes の場合、各カテゴリ（Contact Info / Location / Health / ...）の質問
3. 各データ種別について：
   - 何のために使うか（Purposes: App Functionality / Analytics / Advertising / ...）
   - ユーザーアカウントに紐付けるか（Linked to User）
   - トラッキングに使うか（Used for Tracking）

## 3. Toki のデータ収集回答

### 3.1 トップレベル質問

**Q: Do you or your third-party partners collect data from this app?**

→ **Yes**

理由：
- Google Calendar API 経由でユーザーの予定情報を取得（処理は端末ローカル）
- MetricKit 経由でクラッシュレポートを Apple サーバに送信
- 「**端末ローカルで処理するデータも Apple のガイドラインでは「収集」に含まれる**」点に注意

### 3.2 データ種別ごとの回答

App Store Connect の Data Type カテゴリに沿って：

| カテゴリ | データ | 収集？ | Linked to User | Tracking | Purposes |
|---|---|---|---|---|---|
| **Contact Info** | Email Address | No | – | – | – |
| **Contact Info** | Name | No | – | – | – |
| **Contact Info** | Phone Number | No | – | – | – |
| **Contact Info** | Physical Address | No | – | – | – |
| **Contact Info** | Other User Contact Info | No | – | – | – |
| **Health & Fitness** | Health / Fitness | No | – | – | – |
| **Financial Info** | Payment Info / Credit Score / Other | No | – | – | – |
| **Location** | Precise / Coarse | No | – | – | – |
| **Sensitive Info** | Sensitive Info | No | – | – | – |
| **Contacts** | Contacts | No | – | – | – |
| **User Content** | Emails or Text Messages | No | – | – | – |
| **User Content** | Photos or Videos | No | – | – | – |
| **User Content** | Audio Data | No | – | – | – |
| **User Content** | Customer Support | No | – | – | – |
| **User Content** | Gameplay Content | No | – | – | – |
| **User Content** | Other User Content | **No**※ | – | – | – |
| **Browsing History** | Browsing History | No | – | – | – |
| **Search History** | Search History | No | – | – | – |
| **Identifiers** | User ID（OAuth account ID 等）| **No**※2 | – | – | – |
| **Identifiers** | Device ID | No | – | – | – |
| **Purchases** | Purchase History | No | – | – | – |
| **Usage Data** | Product Interaction | No | – | – | – |
| **Usage Data** | Advertising Data | No | – | – | – |
| **Usage Data** | Other Usage Data | No | – | – | – |
| **Diagnostics** | Crash Data | **Yes** | No | No | App Functionality / Analytics |
| **Diagnostics** | Performance Data | **Yes** | No | No | App Functionality / Analytics |
| **Diagnostics** | Other Diagnostic Data | No | – | – | – |
| **Other Data** | Other Data Types | No | – | – | – |

### 3.3 ※注釈

**※ User Content（Calendar events）の扱い**：

Toki は Google Calendar API でユーザーの予定情報を取得するが：
- データは **端末メモリのみ** で処理（永続化なし）
- アプリ終了で消失（OAuth token は Keychain に保存、events は揮発）
- Toki 開発者（私）のサーバには **送信されない**
- 第三者にも提供されない
- Apple のガイドラインでは「Collect」の定義：「transmits user data off the device」
- → **Toki は events を off-device に送信しないので「collect」に該当しない**

ただし審査時に質問される可能性あり。Privacy Policy で「ローカル処理のみ」明示済み。

**※2 User ID の扱い**：

OAuth で取得する Google アカウント識別子（access_token / refresh_token）：
- Keychain に **端末ローカルのみ** 保存
- Toki 開発者のサーバには送らない
- Google API 呼び出し時のみ Google に送信（Google は元々データの提供元）
- → off-device 送信は **Google にのみ**、これは「データを Google と共有」ではなく「Google API への認証」
- → User ID として「collect」扱いではない

### 3.4 Diagnostics = Yes の理由

MetricKit を採用しているため：
- macOS が自動でクラッシュレポートを Apple に送る（ユーザーの「Share Mac Analytics」設定に従う）
- Toki のコードから明示的に送信するわけではないが、Apple のガイドライン上「Diagnostics の収集」に該当
- **Linked to User: No**（Apple が匿名化）
- **Tracking: No**（Apple 内部の品質改善のみ）
- **Purposes: App Functionality / Analytics**

## 4. 第三者 SDK の宣言

App Store Connect の「Privacy Manifest」「Required Reason API」関連：

Toki が使用する SDK / Framework：
- **Foundation / SwiftUI / AppKit** — Apple 純正、宣言不要
- **AuthenticationServices**（ASWebAuthenticationSession） — Apple 純正、宣言不要
- **CryptoKit** — Apple 純正、宣言不要
- **Network**（loopback 廃止済み） — 削除済み

**第三者 SDK は一切使用していない**（spec 016 の決定）。
- AppAuth-iOS：使わない（自前実装）
- GoogleSignIn-iOS：使わない
- Firebase / Crashlytics 等：使わない

→ Privacy Manifest の `PrivacyAccessedAPITypes` 申告は **最小限** で済む。

## 5. Privacy Manifest（PrivacyInfo.xcprivacy）

Apple が 2024 から要求する `PrivacyInfo.xcprivacy` ファイル：
- App / SDK が使用する **Required Reason API** の理由コードを記述
- iOS App Store 提出時は必須、macOS は推奨（将来必須化の可能性）

Toki が触る可能性のある Required Reason API：
- `NSUserDefaults` → 設定保存用、reason: `CA92.1`（user-facing settings）
- `Keychain Services` → OAuth token 保存、reason: `CA92.1` の対応コード
- ファイルアクセス / Disk space 等：使用しない

これらを `PrivacyInfo.xcprivacy` に記述する。本 spec の §6 で実装。

## 6. 実装内容

### 6.1 PrivacyInfo.xcprivacy 新規作成

ファイル: `Toki/Toki/PrivacyInfo.xcprivacy`

内容：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeCrashData</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <false/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
                <string>NSPrivacyCollectedDataTypePurposeAnalytics</string>
            </array>
        </dict>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypePerformanceData</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <false/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array>
                <string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
                <string>NSPrivacyCollectedDataTypePurposeAnalytics</string>
            </array>
        </dict>
    </array>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

Synchronized Group のおかげで自動的に target に含まれる。

### 6.2 App Store Connect 入力（Phase 4A で実施）

spec 025（Phase 4A）で App Store Connect の「App Privacy」セクションに上記
§3.2 の表通り入力。

## 7. 完了条件

- [ ] `Toki/Toki/PrivacyInfo.xcprivacy` 新規作成
- [ ] `xcodebuild build` 通る
- [ ] `.app` バンドル内に `PrivacyInfo.xcprivacy` が含まれる
- [ ] App Store Connect 入力時の参考資料として本 spec が読める形

## 8. リスク・注意事項

- **「User Content」の Calendar events 扱い**：審査で質問される可能性、回答準備
  - 想定回答：「Events are processed in-memory only, never sent to our servers or third parties.」
- **OAuth token を Keychain 保存**：これは「収集」ではないが、Privacy Policy で明示
- **Apple Verification（OAuth）の取得後**：100 user 上限解除後の Privacy Policy も整合性確認

## 9. 次の Phase

- spec 025（Phase 4A）：App Store Connect レコード作成 + 本 spec の Disclosure 入力
- spec 021（Phase 2B）：Screenshot 作成
- spec 028（Phase 5）：審査提出

## 10. 参照

- `ROADMAP.md` §2 Phase 3C
- `docs/privacy.md` / `docs/privacy-en.md` — Privacy Policy（spec 023）
- [App Store Connect Help: App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [Privacy Manifest documentation](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)
- [Required Reason API documentation](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files/describing_use_of_required_reason_api)
