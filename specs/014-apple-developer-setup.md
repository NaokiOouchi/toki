# 014 — Apple Developer 登録 + Bundle ID 確定

参照: `specs/ROADMAP.md` §2 Phase 0
ステータス: **未着手**（ユーザー作業待ち）

Toki の Mac App Store 公開の最初のステップ。Apple Developer Program 登録から
Bundle ID 登録までの手続きを行う。実装作業ではなく、ユーザーの Web フォーム
入力 + 待ち時間が中心。

## 1. 目的

- Apple Developer Program に登録し、開発者アカウントを取得
- Bundle ID `jp.co.noouchi.toki` を Apple に登録
- 税務情報・銀行口座情報を入力（将来の Tip Jar / Pro 機能に備える）

## 2. 前提

- ユーザーの Apple ID（**二要素認証必須**、未設定なら先に設定）
- 本人名義のクレジットカード（年会費 約 ¥14,800 を引き落とし）
- 個人情報（氏名 / 住所 / 電話番号）
- マイナンバー（Tax Forms で必要）
- 受取用の銀行口座情報（SWIFT コード含む）

## 3. スコープ

### 3.1 やること
1. Apple Developer Program 登録（**個人 = Individual**）
2. Bundle ID `jp.co.noouchi.toki` を Apple に登録
3. Tax Forms（W-8BEN）入力 ※将来の収益化に備えて先に
4. Bank Information 入力 ※同上

### 3.2 やらないこと（別 spec / Phase）
- App Store Connect での App レコード作成（spec 025 / Phase 4A）
- Certificates / Provisioning Profiles 作成（spec 015 / Phase 1A で必要時）
- Capabilities 設定（spec 015 で App Sandbox 対応時）

## 4. 手順

### Step 1: Apple Developer Program 登録

1. https://developer.apple.com/programs/ にアクセス
2. Apple ID でサインイン（**二要素認証必須**）
3. 「Enroll」クリック
4. **Individual / Sole Proprietor** を選択
   - 法人（Organization）は D-U-N-S Number 取得が必要 → Toki は個人プロジェクトなので **Individual** で OK
5. 個人情報入力（氏名 / 住所 / 電話番号）
   - **必ず Apple ID に登録した情報と一致させる**（不一致だと審査落ち）
6. クレジットカード情報入力（**年 約 ¥14,800**、USD $99 を当日為替で換算）
7. 規約同意して送信

**待ち時間**：通常 **1-2 営業日**、最長 1 週間（Apple の本人確認）。承認メール待ち。

### Step 2: Bundle ID 登録（承認後）

1. https://developer.apple.com/account にアクセス
2. 左サイドバー「**Certificates, Identifiers & Profiles**」
3. 「**Identifiers**」を選択 → 「+」ボタン
4. 「**App IDs**」 → 「**App**」を選択 → Continue
5. 入力：
   - **Description**: `Toki - Circle Calendar Clock`
   - **Bundle ID**: `Explicit` を選択 → `jp.co.noouchi.toki` と入力
   - **Capabilities**: **何も選択しない**（spec 015 で必要に応じて追加）
6. 「Continue」→ 「Register」

### Step 3: Tax Forms（重要）

v1.0 は無料リリースだが、**Tip Jar / Pro 化時に必須**。今入れておけば後で楽。

1. https://appstoreconnect.apple.com にサインイン
2. 「**Business**」 → 「**Tax Forms**」
3. 米国向け：**W-8BEN**（日米租税条約適用で米国源泉徴収率 0%）
4. マイナンバー / 居住国情報入力

### Step 4: Bank Information

同様に、v1.0 では収益発生しないが将来必要。

1. 「Business」 → 「**Banking**」
2. 銀行口座情報入力（**受取通貨：JPY**）
3. SWIFT コード / 銀行名 / 支店 / 口座番号

## 5. 注意事項

- **Apple Developer 登録は変更しにくい**：Individual → Organization 切替は手間。最初の選択を慎重に
- **Bundle ID は変更不可**：一度登録したら永久不変。Toki = `jp.co.noouchi.toki` で確定
- **Tax Forms / Bank は後でも OK だが、収益発生時に未入力だと支払い保留される**
- **登録費は年次更新**：継続公開には毎年 $99 USD 支払い必要、未払いだと App が App Store から削除される
- **本人確認の情報不一致に注意**：Apple ID / クレジットカード / 個人情報が一致しないと審査で落ちる

## 6. 完了条件

- [ ] Apple Developer Program 登録完了（承認メール受信）
- [ ] Bundle ID `jp.co.noouchi.toki` が developer.apple.com で確認できる
- [ ] Tax Forms 入力完了（W-8BEN）
- [ ] Bank Information 入力完了
- [ ] App Store Connect にアクセスできる（agreements 同意済み）

## 7. 並行作業の提案

Apple 承認待ち（数日〜1 週間）の間、Claude が並行で進められる作業：

| Spec | 内容 | 依存 |
|---|---|---|
| spec 022 | App 説明文 / キーワード（日英）起草 | なし |
| spec 023 | Privacy Policy 草案 | なし |
| spec 026 | GitHub Issues / Templates 整備 | なし |
| spec 020 | App Icon 要件 spec（デザイン作業はユーザー側）| なし |

## 8. 次の Phase

- **spec 015**：App Sandbox 対応（Phase 1A、最初の技術 spec）
- Apple Developer 登録 + Bundle ID 確定後に着手可能

## 9. 参照

- `ROADMAP.md` §2 Phase 0、§3 クリティカルパス
- [Apple Developer Program](https://developer.apple.com/programs/)
- [App Store Connect](https://appstoreconnect.apple.com/)
- [Choosing a Membership](https://developer.apple.com/support/compare-memberships/) — Individual vs Organization 比較
