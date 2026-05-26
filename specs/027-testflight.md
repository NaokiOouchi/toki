# 027 — TestFlight 配布手順

参照: `specs/ROADMAP.md` §2 Phase 4B
依存: spec 025（App Store Connect セットアップ）完了済み
ステータス: **手順書、未着手**（ユーザー Xcode + App Store Connect 操作）

Xcode で Archive → App Store Connect upload → TestFlight で β tester に配布する
手順。審査提出前に最終動作確認を行う。

## 1. 目的

- v1.0 リリース前に **実機 β テスト** で最終動作確認
- 自分以外のユーザーに使ってもらってフィードバック収集
- 審査提出時の build を確定させる

## 2. TestFlight をやる / やらないの判断

### 2.1 やる場合のメリット

- 実機で OAuth フロー / Calendar 表示が動くか確認できる
- β tester（友人 / SNS）のフィードバック
- リジェクト要因を事前に発見
- 自分以外の Mac 環境（macOS バージョン違い）で動作確認

### 2.2 スキップする場合

- 自分だけで動作確認済みなら直接審査提出も可
- v1.0 急ぐなら TestFlight 省略可

### 2.3 推奨

**やる**（β tester は最小 2-3 人、3-7 日で十分）。リジェクト 1 回で 1-2 週間
ロスするより、TestFlight で先回りした方が早い。

## 3. 前提条件

- ✅ Apple Developer Program 有効
- ✅ App Store Connect で App レコード作成済み（spec 025）
- ✅ Bundle ID `jp.co.noouchi.toki` 紐付け済み
- ✅ Distribution Certificate（Xcode が自動管理可）
- ✅ Provisioning Profile（Automatic signing で自動生成）

## 4. 手順

### Step 1: Xcode で Signing & Capabilities 確認

1. Xcode で `Toki/Toki.xcodeproj` を開く
2. TARGETS > Toki > **Signing & Capabilities** タブ
3. **Automatically manage signing**: ✅ ON
4. **Team**: あなたの Apple Developer team
5. **Bundle Identifier**: `jp.co.noouchi.toki`
6. **Signing Certificate**: `Apple Distribution` を自動選択
7. **Provisioning Profile**: 自動管理

### Step 2: Build Number / Version 確認

1. Xcode の Build Settings（or `Resources/Info.plist`）：
   - `CFBundleShortVersionString` = `1.0.0`（公開バージョン）
   - `CFBundleVersion` = `1`（ビルド番号、毎回 increment）
2. 修正版を upload する時は `CFBundleVersion` を `2`, `3`... と増やす

### Step 3: Archive 作成

1. Xcode 上部メニュー **Product** → **Destination** → **Any Mac (Apple Silicon, Intel)**
2. **Product** → **Archive**
3. Build → Archive 作業（数分）
4. 完了すると Xcode Organizer が自動で開く

エラー出る場合：
- Signing 未設定 → Step 1 確認
- Code signing 不一致 → 「Automatically manage signing」OFF/ON で再生成

### Step 4: App Store Connect に Upload

1. Xcode Organizer で 作成した Archive を選択
2. **Distribute App** ボタンクリック
3. ダイアログ：
   - **App Store Connect** を選択 → Next
   - **Upload** を選択 → Next
   - Signing 確認 → Next
   - Symbol を含む（Strip Swift Symbols）→ デフォルトで OK → Next
   - Profile 確認 → Next
   - Review → **Upload**
4. Upload 完了（数分〜30 分）

### Step 5: Build の処理待ち

1. https://appstoreconnect.apple.com → マイ App > Toki > **TestFlight** タブ
2. Build が **「処理中」** から **「利用可能」** に変わるまで待つ（通常 10-60 分）
3. Apple から「ビルドの処理が完了しました」メール届く

### Step 6: 暗号化情報の追加

1. Upload 後、TestFlight 画面でビルドに **「暗号化に関する記述が必要」** マークが出る
2. ビルドをクリック → 「暗号化」セクション
3. **「暗号化を使用していません」** を選択（または HTTPS のみ）
   - Toki は HTTPS（Google API）のみ → exempt 該当
4. Save

### Step 7: 内部テスター招待

1. **TestFlight** タブ → **内部テスト** セクション
2. **「+」** → **「内部テストグループ」を作成**
3. グループ名（例：`Toki Internal`）
4. **テスター追加** → Apple ID（App Store Connect Users で User 追加 → Tester 権限）
5. ビルド選択 → テスターに自動でメール通知

### Step 8: 外部テスター招待（任意）

1. **外部テスト** セクション
2. **「+」** → **「外部テストグループ」を作成**
3. **「ビルドの送信」** → 「Beta App Review」必要（軽量審査、1-2 日）
4. Beta Review 通過後、メール / 公開リンクで招待

最大 10,000 人まで（メール）。リンク配布なら無制限。

### Step 9: TestFlight アプリで β tester がインストール

テスター側手順：
1. App Store から **TestFlight** アプリ（macOS）を入手
2. 招待メール内の「**View in TestFlight**」リンク
3. **「インストール」**
4. アプリ起動 → 通常使用

### Step 10: フィードバック収集

- TestFlight 経由でスクリーンショット + コメント送信可能
- 開発者は App Store Connect 上で確認

## 5. β テスト期間の運用

### 5.1 推奨期間

- **3-7 日**：十分な動作確認 + フィードバック
- 大きな問題が出たら build 修正 → 再 upload → 新 build を tester に配布

### 5.2 確認してほしいシナリオ

β tester に依頼するチェック内容：

- [ ] アプリ起動 / 終了 OK
- [ ] OAuth サインイン成功
- [ ] Google Calendar 予定が時計に表示される
- [ ] 設定変更が保持される（再起動後も）
- [ ] サインアウト → 再サインイン
- [ ] アイコンが Finder / Dock で正しく表示
- [ ] メニューバーアイコンの動作
- [ ] エラー時に分かるメッセージが出る（network 切断時等）
- [ ] macOS バージョン違いで動く（14.0 / 15.x / 26.x 等）

### 5.3 修正版 build upload

1. Source 修正
2. `CFBundleVersion` を increment（1 → 2）
3. Archive → Upload
4. TestFlight で新 build が tester に通知

## 6. 完了条件

- [ ] Archive 作成成功
- [ ] App Store Connect upload 成功
- [ ] ビルド処理完了（TestFlight で利用可能状態）
- [ ] 内部テスター 1 人以上で動作確認
- [ ] （任意）外部テスター 2-5 人でフィードバック収集
- [ ] 重大な bug 0 件
- [ ] 審査提出用 build を確定

## 7. リスク・注意事項

- **Code signing エラー**：Automatic signing 推奨、手動だと面倒
- **Upload エラー**：Xcode Organizer の Validate App で事前チェック可能
- **暗号化記述忘れ**：Step 6 を忘れると tester に配布できない
- **CFBundleVersion 重複**：同じ build 番号で 2 度 upload するとエラー、increment 必須
- **β tester が macOS 14.0 未満**：Toki の deployment target なので動かない、tester 側で要確認

## 8. 次の Phase

spec 027 完了 → spec 028（審査提出）へ。

## 9. 参照

- `ROADMAP.md` §2 Phase 4B
- [TestFlight Beta Testing - Apple](https://developer.apple.com/testflight/)
- [Distributing your app for beta testing - Apple](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
