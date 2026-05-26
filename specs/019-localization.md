# 019 — ローカライズ（日英）

参照: `specs/ROADMAP.md` §2 Phase 1E
依存: Phase 1 主要 spec 完了済み（015 / 015a / 016 / 017）
ステータス: **設計確定、実装未着手**

ROADMAP §4.1 で確定した「日本語 + 英語」対応を実装する。UI 文言を全て
String Catalog 経由にして、日本語 / 英語の両言語で配信可能にする。

## 1. 目的

- 全 UI 文言を **String Catalog（.xcstrings）** に集約
- 日本語をベース言語、英語を追加言語として翻訳
- macOS のシステム言語に応じて自動切替（ユーザー操作不要）
- リリース後の文言追加 / 修正をシンプルに（catalog に追記するだけ）

## 2. なぜ String Catalog か

Xcode 15+ から導入された **`.xcstrings` 形式**を採用：
- JSON ベースで diff が見やすい（旧 `.strings` より）
- 自動抽出（コードから `String(localized:)` を拾う）
- 翻訳状態の可視化（pending / verified）
- 複数 catalog ファイル不要（1 ファイルで全言語管理）

旧 `.strings` ファイルは使わない（diff が辛い、保守性低い）。

## 3. ハイブリッド構成での扱い

Toki は SwiftPM + Xcode project のハイブリッド：

| build | 文言の扱い |
|---|---|
| Xcode build（リリース）| String Catalog 経由、システム言語に応じて翻訳 |
| SwiftPM build（開発）| `String(localized:)` の defaultValue（日本語）をそのまま表示 |

→ 開発時は日本語固定、リリース時のみ多言語対応。これで開発フローを壊さない。

String Catalog は Xcode 側 `Toki/Toki/Localizable.xcstrings` に配置。

## 4. スコープ

### 4.1 翻訳対象

| カテゴリ | 件数概算 | 例 |
|---|---|---|
| 中央テキスト | 6 | 「メニューバーから接続」「接続中…」「読み込み中」等 |
| メニュー | 4 | 「Google Calendar 接続」「再読込」「設定…」「Toki を終了」|
| BottomInfoArea | 4 | 「次」「終日:」「最終更新 X 分前」「たった今」等 |
| Popover / Tooltip | 5 | 「参加者」「他 N 名」「Meet で開く」「Calendar で開く」等 |
| 設定 UI | 30+ | 各設定軸の見出し / option ラベル（小・標準・大 等）|
| エラー | 5 | 「サインインをキャンセルしました」「接続に失敗しました」等 |

合計：**約 60 〜 80 文言** 程度。

### 4.2 やらないこと

- 第三国語対応（中国語 / 韓国語 / ヨーロッパ言語等）→ 将来検討
- ボディコピー / マーケコピー（spec 022 で別管理）
- README / Privacy Policy / Support サイト（spec 023 で別管理、`docs/` 配下）
- 日付・時刻フォーマット（既に `DateFormatter` が locale 対応済み、再確認のみ）

## 5. 実装方針

### 5.1 ステップ

1. **文言抽出**：全 `.swift` を grep して String literal を抽出
2. **`String(localized:)` 化**：抽出した文言を 1 つずつ置換
   - 例：`"メニューバーから接続"` → `String(localized: "Connect from menu bar")` ※ key は英語推奨
   - または `Text("メニューバーから接続")` → `Text("Connect from menu bar")` （SwiftUI 自動 localize）
3. **String Catalog 作成**：Xcode で `Localizable.xcstrings` 新規作成
4. **抽出ビルド**：Xcode が自動で全 `String(localized:)` を catalog に追加
5. **英訳追加**：catalog の各 key に英訳追加（ChatGPT 初稿 → 手で調整）
6. **日本語訳追加**：defaultValue（英語 key）に対応する日本語訳
7. **動作確認**：システム言語切替 → アプリ再起動 → 言語が切り替わるか

### 5.2 Key 命名規則

文言の **英語** を key にする（一般的なパターン）：

```swift
// 旧
return .freeTime(time: timeStr, subtitle: "メニューバーから接続")

// 新
return .freeTime(time: timeStr, subtitle: String(localized: "Connect from menu bar"))
```

カテゴリプレフィックス（任意）：
- メニュー: `menu.connect_google_calendar`
- エラー: `error.sign_in_cancelled`
- 中央テキスト: `center.loading`

ただし、シンプルさを優先して英語 key そのままも OK（catalog で grouping できる）。

### 5.3 SwiftUI の Text の扱い

SwiftUI の `Text("...")` は `LocalizedStringKey` を自動的に拾うため、
String Catalog があれば自動 localize される（`String(localized:)` 不要）：

```swift
Text("Connect from menu bar")  // 自動 localize される
```

ただし、変数 interpolation がある場合は `String(localized:)` で format 必要：

```swift
Text(String(localized: "Updated \(minutes) min ago"))
```

### 5.4 動的文言の扱い

「X 分前」「他 N 名」等のプルラル形式：

```swift
String(
    localized: "Updated \(minutes) min ago",
    comment: "BottomInfoArea: 最終更新時刻"
)
```

String Catalog で Plural Rules を設定（1 / many の使い分け）。

## 6. 翻訳の品質保証

- 初稿：ChatGPT or DeepL で英訳生成
- 微調整：私（Claude）が context を踏まえて確認
- 短い文言（メニュー / 設定ラベル）は機械翻訳でも十分
- エラー文言 / 説明文は丁寧に手で調整
- 数字や記号の扱い（句読点、改行）に注意

## 7. 実装内容

### 7.1 ファイル変更

| ファイル | 変更内容 |
|---|---|
| `Toki/Toki/Localizable.xcstrings` | **新規作成**（Xcode で）|
| `Sources/Toki/UI/*.swift` | `Text` / `String` を localize 形式に |
| `Sources/Toki/Composition/ClockViewModel.swift` | エラー文言 / 中央テキストを localize |
| `Sources/Toki/App/AppDelegate.swift` | メニュータイトル / エラー文言を localize |
| `Sources/Toki/UI/Settings/*.swift` | 設定 UI ラベルを localize |
| `Toki/Toki.xcodeproj/project.pbxproj` | Localizable.xcstrings を target に追加 |

### 7.2 SwiftPM 側の影響

- Sources/Toki/* のコード変更は SwiftPM build でも問題なし
- `String(localized:)` は Foundation API、SwiftPM でも動く
- ただし String Catalog の翻訳は **SwiftPM build には反映されない**（defaultValue = 日本語が表示される）
- 開発時は日本語固定、リリース時のみ多言語

### 7.3 動作確認方法

英語表示の確認：
```bash
defaults write jp.co.noouchi.toki AppleLanguages '("en")'
open .build/Toki.app  # ← SwiftPM build だと無効、Xcode build .app で確認
```

または macOS のシステム設定 > 言語と地域 > 言語を English にして再起動。

## 8. 完了条件

- [ ] 全 `.swift` の UI 文言を抽出
- [ ] `String(localized:)` / `Text(_:)` に置換（約 60-80 件）
- [ ] `Toki/Toki/Localizable.xcstrings` 作成
- [ ] 日本語訳すべて確認
- [ ] 英訳すべて入力（ChatGPT 初稿 → 手で調整）
- [ ] Xcode build → 英語システムで表示確認
- [ ] Xcode build → 日本語システムで表示確認
- [ ] swift build / swift test も引き続き通る（48 tests pass）

## 9. リスク・注意事項

- **String literal の取りこぼし**：grep で発見するが、動的生成等で漏れる可能性
- **書式付き文字列の翻訳**：「X 分前」等の変数位置が言語で違う場合の対応
- **英訳の不自然さ**：個人開発者の英語力に依存、必要なら native review 依頼
- **「Toki」のブランド名**：翻訳しない（固有名詞）
- **Apple HIG**：英語版の文言は macOS の英語ガイドラインに準拠（Title Case / Sentence case 等）

## 10. 次の Phase

spec 019 完了で Phase 1 完了。Phase 2 / 3 / 4 / 5 へ：
- Phase 2B Screenshot 作成（spec 021）
- Phase 3C Data Use Disclosure（spec 024）
- Phase 4A App Store Connect セットアップ（spec 025）
- Phase 4B TestFlight（spec 027）
- Phase 5 審査提出（spec 028）

## 11. 参照

- `ROADMAP.md` §2 Phase 1E、§4.1 ローカライズ決定
- [String Catalogs documentation - Apple](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)
- [WWDC 2023: Discover String Catalogs](https://developer.apple.com/videos/play/wwdc2023/10155/)
- [SwiftUI Text localization](https://developer.apple.com/documentation/swiftui/text)
