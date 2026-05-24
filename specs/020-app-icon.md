# 020 — App Icon 要件 / デザインガイド

参照: `specs/ROADMAP.md` §2 Phase 2A
ステータス: **要件確定済み、デザイン未着手**（ユーザー作業）

Toki の App Icon の要件・デザインガイド・納品仕様を定義する。
実際のデザイン作業（描く / 発注する）は本 spec の範囲外。本 spec は
「何を作るか」を確定し、ユーザーが自分で作る場合 / デザイナーに依頼する場合の
仕様書として機能する。

## 1. 目的

- App Store / macOS Finder / Dock / Launchpad / 設定 等で表示される
  Toki のブランド顔を確立する
- 検索結果や周辺アプリの中で **0.5 秒で「これが Toki」と認識される** デザイン
- App Store 審査基準（macOS Human Interface Guidelines）を満たす

## 2. デザイン方針

### 2.1 モチーフ
- **円形時計** がアプリの本質、そのまま icon の中核に配置
- 12 / 3 / 6 / 9 の時刻マーク（small dots or lines）
- 時針 / 分針（minimal）
- 1 〜 2 つのイベント円弧（彩り、Toki の特徴的な要素）

### 2.2 デザイン原則
- **Squircle 形状**は不要（macOS は自動で角丸を適用しない、デザイナー側で対応）
  - 正確には：**正方形のキャンバスに、角丸正方形 background** で描く
  - macOS の角丸は **マスクされない**、デザイナーが角丸正方形を描く必要あり
  - 推奨角丸半径：1024px キャンバスで **180px**（Apple の Squircle に近い）
- ライト / ダーク両モードで視認性確保
- 縮小時（16px）でも認識可能なシンプルさ
- 装飾は最小限、要素は 3-5 個まで

### 2.3 カラー方針
- ベース色：Toki ブランドカラー（現状未定、検討候補）
  - **Option A**：Blue 系（`#4A90E2` 付近）— 信頼 / 時間 / プロフェッショナル感
  - **Option B**：Orange / Coral 系（`#FF6B6B` 付近）— 親しみ / 暖かさ
  - **Option C**：Gradient（Blue → Purple 等）— モダン / Liquid Glass 系統
- アクセント色：時針 / 円弧の色（コントラスト確保）
- 背景：単色 or 微妙なグラデーション

### 2.4 何を入れない
- **テキスト「Toki」は不要**（App 名は icon の下に表示される）
- 過度な詳細（縮小で潰れる）
- 写真的なリアル描写
- 影 / 立体感の過剰な多用（macOS は flat 系トレンド）

## 3. 納品仕様（必須サイズ）

macOS App Icon は **AppIcon.appiconset** に以下のサイズを納品：

| サイズ | 用途 | ファイル名例 |
|---|---|---|
| 16×16 (1x) | Finder list view | icon_16x16.png |
| 32×32 (2x of 16) | Retina Finder list | icon_16x16@2x.png |
| 32×32 (1x) | Finder grid small | icon_32x32.png |
| 64×64 (2x of 32) | Retina | icon_32x32@2x.png |
| 128×128 (1x) | Finder grid medium | icon_128x128.png |
| 256×256 (2x of 128) | Retina | icon_128x128@2x.png |
| 256×256 (1x) | Finder grid large | icon_256x256.png |
| 512×512 (2x of 256) | Retina | icon_256x256@2x.png |
| 512×512 (1x) | App Store / Finder cover flow | icon_512x512.png |
| 1024×1024 (2x of 512) | App Store / Retina | icon_512x512@2x.png |

**合計 10 ファイル**、すべて PNG 形式（24-bit RGBA、透過対応）。

**1024×1024 の元データ** から自動生成するのが効率的。Xcode の Asset Catalog
は自動でリサンプリングしないため、**各サイズを個別に書き出す** 必要がある。

## 4. 推奨ツール

### 4.1 デザインツール
- **Figma**（無料、ブラウザ）— 推奨、複数サイズの export 容易
- **Sketch**（有料、Mac 専用）
- **Affinity Designer**（買い切り、コスパ）
- **Bjango Icon Set Creator**（macOS 専用、icon に特化）

### 4.2 自動生成 / 補助
- **AppIconMaker.co**（1024px → 全サイズ自動生成）
- **Bakery**（macOS, $5、Asset Catalog 直接書き出し）
- **iconKitchen**（無料、ブラウザ）

### 4.3 AI 生成（ベースアイデア）
- Midjourney / DALL-E でアイデアスケッチ → デザインツールで整形
- AI 出力をそのまま使うのは品質 / Apple 規約両面で非推奨

## 5. ファイル配置

Xcode プロジェクトの Asset Catalog に配置：

```
Sources/Toki/Resources/Assets.xcassets/
└── AppIcon.appiconset/
    ├── Contents.json     # サイズと filename の mapping
    ├── icon_16x16.png
    ├── icon_16x16@2x.png
    ├── icon_32x32.png
    ├── icon_32x32@2x.png
    ├── icon_128x128.png
    ├── icon_128x128@2x.png
    ├── icon_256x256.png
    ├── icon_256x256@2x.png
    ├── icon_512x512.png
    └── icon_512x512@2x.png
```

**現状の Toki は SwiftPM ベース** であり、Asset Catalog の構造を変える必要が
ある可能性。具体配置は spec 015 (App Sandbox) と合わせて Resources ディレクトリ
構造を整理する際に確定。

## 6. デザインモックの方向性（参考）

```
┌─────────────────┐
│   ╱─────────╲   │
│  │  ●        │  │   ← 12 / 3 / 6 / 9 の時刻マーク（淡色 dot）
│  │           │  │
│  │ ╱─●  ━━━ │  │   ← 時針（中央から外側に）
│  │   ◯      │  │   ← 中央の点
│  │           │  │
│  │  ●     ●  │  │
│   ╲─────────╱   │
└─────────────────┘
```

イベント円弧を 1 〜 2 個（彩り）、円形時計の本質を保ちつつブランド色で着色。

## 7. 完了条件

- [ ] 1024×1024 のマスター icon が完成
- [ ] 10 サイズすべてに書き出し済み
- [ ] AppIcon.appiconset/Contents.json 設定済み
- [ ] Xcode (or SwiftPM build) で icon が反映される
- [ ] 16px サイズで認識可能か確認（Finder / Dock）
- [ ] ライト / ダーク両モードで視認性確認

## 8. リスク・注意事項

- **デザインは時間がかかる**：自分で作る場合 1-3 日、デザイナー依頼なら 1-2 週間
- **Apple HIG 準拠**：派手すぎる / 写真ベース / 商標流用 は審査落ち
- **App Store SDK の事前確認**：Bjango / AppIconMaker 系で Contents.json まで
  自動生成される場合がある、手動編集前に確認
- **ブランドカラーの早期決定**：icon の色は アプリ内のテーマカラーとも整合性を
  取りたい（現状の AppearanceModel デフォルトカラーとの整合）

## 9. 並行作業との関係

- spec 022 (App 説明文) と整合：説明文での「視覚的にスケジュール把握」イメージ
- spec 021 (スクリーンショット) より先：icon の色 / トーンが基準になる

## 10. 参照

- [Apple Human Interface Guidelines - App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [macOS App Icon design guidelines](https://developer.apple.com/design/human-interface-guidelines/app-icons#macOS)
- `ROADMAP.md` §2 Phase 2A
