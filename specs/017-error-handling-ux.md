# 017 — エラーハンドリング強化 + 接続誘導 UX 改善

参照: `specs/ROADMAP.md` §2 Phase 1C
依存: spec 015 / 016 完了済み
ステータス: **完了**（2026-05-26、主要部分実装 + 動作確認済み。時計領域の context menu 追加は将来別タスク）

公開アプリとしてユーザーが詰まらないよう、エラー時の表示と接続誘導の UX を
整える。Phase 1 の仕上げ spec。

## 1. 目的

- **「右クリックで接続」誘導の改善**：時計を右クリックしても何も起きない混乱を解消
- **エラー時にユーザーに見える形でフィードバック**：console.log だけでなく UI に
- ネットワーク / 認証 / API エラーに対する基本的な対応

## 2. 現状の問題

### 2.1 接続誘導 UX

現状：
- 未接続時の中央テキスト: 「右クリックで接続」（`Sources/Toki/Composition/ClockViewModel.swift:232`）
- 実際は **メニューバー 🕐 を右クリック** が正解
- 時計領域を右クリックしても何も起きない
- → ユーザーは「右クリックしてもメニュー出ない、壊れてる？」と混乱

### 2.2 エラー時の UX

現状：
- OAuth エラー → `print()` だけで UI 変化なし
- API エラー → 同上
- ユーザーには「何も起きない」「なんで動かないか分からない」状態

### 2.3 想定エラーシナリオ

| シナリオ | 現状の挙動 | 望ましい挙動 |
|---|---|---|
| OAuth サインインキャンセル | print | 中央に「サインインがキャンセルされました」|
| OAuth エラー（network 等）| print | 中央に「接続失敗、もう一度お試しください」|
| Calendar API ネットワーク失敗 | print | データ古いまま、bottom area に最終更新時刻 |
| Token refresh 失敗（再認証必要）| Keychain クリア | 中央に「再ログインが必要」|
| API クォータ超過 | print | 中央に「一時的に取得できません」|

## 3. スコープ

### 3.1 やること
- 中央テキスト「右クリックで接続」を **「メニューバーから接続」** に変更（具体的に誘導）
- 中央テキストの誘導性向上（矢印 emoji や色等）
- **時計領域の右クリックでもメニュー表示**（メニューバーアイコン右クリックと同じメニュー）
- OAuth エラー時の中央テキスト表示（最低限）
- Network エラー時の bottom area への最終更新時刻表示（既存？確認）
- Token refresh 失敗時の中央テキスト表示

### 3.2 やらないこと
- バナー / トースト通知（過剰）
- 詳細エラー画面（個別 spec）
- 自動リトライ機構（spec 016 含み、今は手動誘導で十分）
- ローカライズ（spec 019 で）

## 4. 設計

### 4.1 中央テキスト誘導の改善

`ClockViewModel.swift:232` の `subtitle` 文言を変更：

| 現状 | 改善案 A | 改善案 B（推奨）|
|---|---|---|
| `右クリックで接続` | `🕐 を右クリックで接続` | `メニューバーから接続` |

改善案 B の理由：
- 「右クリック」が時計を指してると誤解されない
- 「メニューバー」が場所を明示
- emoji なし（macOS の文字制限考慮）

### 4.2 時計領域での右クリック対応

時計領域を右クリックしたら、メニューバーアイコン右クリックと **同じメニュー** を表示。

実装：
- ClockView に `.contextMenu { ... }` を追加
- AppDelegate の `showContextMenu()` ロジックを共通化（できれば）

ただし、SwiftUI の `.contextMenu` は AppKit の NSMenu とは別実装。
SwiftUI でメニュー項目を組み立て直す必要あり。

最小実装：
- ClockView.swift に `.contextMenu` 追加
- 4 項目（接続/切断、再読込、設定、終了）を SwiftUI Button として
- 各 button が AppDelegate の対応メソッドを呼ぶ（onAction 経由）

### 4.3 エラー表示の統一

`ClockViewModel.centerState` に新しい case を追加：

```swift
enum CenterState {
    case freeTime(time: String, subtitle: String?)
    case currentEvent(...)
    case error(message: String)  // NEW
}
```

または既存の `freeTime` の subtitle に流用：
- error も `freeTime(time: ..., subtitle: "接続失敗")` で十分？

最小実装：subtitle 流用で OK（追加 case は不要）。

### 4.4 OAuth エラーの伝播

`AppDelegate.handleConnect` でエラーを catch → `ViewModel.showError(message:)` 呼び出し
→ ViewModel が一定時間後に通常表示に戻す（5 秒程度のタイマー）。

```swift
@MainActor
func showError(message: String) {
    errorMessage = message
    errorTask?.cancel()
    errorTask = Task {
        try? await Task.sleep(for: .seconds(5))
        if !Task.isCancelled {
            self.errorMessage = nil
        }
    }
}
```

`centerState` 計算時に `errorMessage` があればそれを subtitle として優先表示。

## 5. 実装内容

### 5.1 ClockViewModel.swift

- `@Published var errorMessage: String? = nil` 追加
- `showError(message:)` メソッド追加
- `centerState` の computed property を更新：
  - `errorMessage` があれば優先
  - なければ既存ロジック
- 「右クリックで接続」→ 「メニューバーから接続」に変更

### 5.2 AppDelegate.swift

- `handleConnect` で `try await oauthClient.beginAuthorization()` の catch を実装
- エラーの種類で message を分岐：
  - `OAuthClientError.userCancelled` → 「サインインをキャンセルしました」
  - その他 → 「接続に失敗しました。もう一度お試しください」
- `viewModel.showError(message:)` 呼び出し

### 5.3 ClockView.swift

- `.contextMenu { ... }` を outer ZStack に追加
- メニュー項目（4 個）を SwiftUI Button で実装
- onAction は ClockViewModel 経由で AppDelegate のメソッドを呼ぶ
  - または、ClockViewModel に handleConnect / handleDisconnect / handleReload / handleOpenSettings の delegate コールバックを持たせる

複雑になるなら、最小実装：
- 「メニューバーアイコンから操作してください」を表示するだけ（context menu なし）
- 文言誘導で十分とする

### 5.4 GoogleCalendarGateway / API のエラー伝播（オプション）

- API エラー時にも showError を呼ぶか
- bottom area の最終更新時刻表示で十分か

最小実装：bottom area で対応（既存実装の確認）。

## 6. テスト

エラーパスは手動テストが中心：

- [ ] 「メニューバーから接続」表示確認
- [ ] OAuth キャンセル → エラー表示確認
- [ ] OAuth サインイン途中で network 切断 → エラー表示確認
- [ ] エラー表示が 5 秒で消えること
- [ ] 時計領域の右クリック → メニュー表示確認（実装する場合）

## 7. 完了条件

- [ ] 中央テキスト「右クリックで接続」を「メニューバーから接続」に変更
- [ ] ClockViewModel に errorMessage 機能追加
- [ ] AppDelegate.handleConnect で OAuth エラー catch + showError
- [ ] 5 秒後に自動でエラー表示が消える
- [ ] 時計領域の右クリックでも何らかの誘導表示（context menu or hint）
- [ ] `swift build` / `swift test` / `xcodebuild build` 通る
- [ ] 手動テストで上記シナリオ確認

## 8. 関連 spec

- spec 015 §5.3 既知の UX 問題（「右クリックで接続」）→ 本 spec で解決
- spec 016 完了 → エラーハンドリングの対象が明確に

## 9. 次の Phase

- spec 018: アクセシビリティ最低限（VoiceOver / キーボード）
- spec 019: ローカライズ（日英）

これらは並行着手可能。

## 10. 参照

- `ROADMAP.md` §2 Phase 1C
- 既存実装：
  - `Sources/Toki/Composition/ClockViewModel.swift:230-232`
  - `Sources/Toki/App/AppDelegate.swift:handleConnect`
