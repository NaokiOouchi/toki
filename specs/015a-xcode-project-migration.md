# 015a — Xcode Project への移行（ハイブリッド構成）

参照: `specs/ROADMAP.md` §2 Phase 1A 前段
ステータス: **設計確定、実装未着手**

spec 015（App Sandbox 対応）の前段として、Mac App Store 配布に必要な Xcode
project を整備する。SwiftPM ベースの開発体験は維持しつつ、App ターゲットの
署名 / Entitlements / Archive / TestFlight / MAS upload に対応する。

## 1. 目的

- MAS 配布に必要な `.xcarchive` 生成 + App Store Connect upload を可能にする
- 既存の SwiftPM 開発フロー（`swift build` / `swift run` / `swift test`）を維持
- Entitlements ファイル管理を Xcode の GUI で行えるようにする（spec 015 の前提）
- TestFlight 配布フローに乗せる（spec 027 の前提）

## 2. 背景

### 2.1 現状把握

| 要素 | 現状 |
|---|---|
| ビルドシステム | SwiftPM 単独（`Package.swift` のみ）|
| 開発フロー | `swift build` / `swift run` / `swift test` |
| .app バンドル生成 | `scripts/build-app.sh` で手動 bundle 構築 + codesign |
| Info.plist | `Resources/Info.plist`（Bundle ID は古い `dev.pokotech.Toki`）|
| Entitlements | **無し**（App Sandbox / Network 等の宣言なし）|
| Asset Catalog | **無し**（App Icon 未配置）|
| @main 配置 | `Sources/Toki/App/TokiApp.swift` |

### 2.2 MAS 配布で足りないもの

- App Store Connect upload に必要な `.xcarchive`（xcodebuild archive 必須）
- Entitlements ファイル（App Sandbox + network.client）
- AppIcon.appiconset（Asset Catalog）
- Provisioning Profile 連携
- Code Signing for distribution（現状は development 署名のみ）

### 2.3 なぜハイブリッドか

- **Package.swift だけ** で MAS upload も理論上可能だが、実績 / ノウハウが薄い
- **Xcode project 一本化** だと既存の `swift test` / Domain テストの軽量実行が失われる
- → **両方併存** が現実的：
  - 日常開発・テスト → SwiftPM（高速、CLI で完結）
  - リリース・配布 → Xcode project（archive / upload）

## 3. 構成方針：ハイブリッド

### 3.1 ディレクトリ構造（移行後）

```
toki/
├── Package.swift              # 既存（ライブラリ + テスト）
├── Sources/
│   └── Toki/                  # 既存コード（Xcode からも参照）
├── Tests/
│   └── TokiTests/             # 既存テスト（swift test で実行）
├── Toki.xcodeproj/            # NEW: App ターゲット用
├── App/                       # NEW: Xcode project 専用ファイル
│   ├── Toki.entitlements      # NEW: App Sandbox / Network 等
│   ├── Info.plist             # 移動（Resources/ から）
│   └── Assets.xcassets/       # NEW: AppIcon 等
│       └── AppIcon.appiconset/
├── scripts/
│   └── build-app.sh           # 既存（開発用、後方互換）
└── specs/                     # 既存
```

### 3.2 役割分担

| ターゲット | 管理ツール | 用途 |
|---|---|---|
| `Toki` (SwiftPM executable) | Package.swift | 開発時の `swift run`、Domain テスト |
| `Toki.app` (Xcode App) | Toki.xcodeproj | リリース、App Sandbox、Archive、MAS upload |
| `TokiTests` (SwiftPM test) | Package.swift | `swift test` で実行 |

**両ターゲットは `Sources/Toki/*.swift` を共有**（参照、コピー禁止）。

### 3.3 @main の扱い

- 現状 `Sources/Toki/App/TokiApp.swift` に `@main` がある
- SwiftPM の executableTarget としても、Xcode の App ターゲットとしても、`@main` でエントリポイントを認識
- → **そのまま共有可能**、特別な処置不要

## 4. 実装手順

### Step 1: Xcode で新規 macOS App project 作成

1. Xcode を起動 → File > New > Project
2. macOS > App を選択
3. 設定：
   - **Product Name**: `Toki`
   - **Team**: Apple Developer Program 登録後の team を選択（spec 014 完了後）
   - **Organization Identifier**: `jp.co.noouchi`
   - **Bundle Identifier**: 自動で `jp.co.noouchi.Toki` になる
     - ⚠️ ROADMAP では `jp.co.noouchi.toki`（小文字）。Xcode default の大文字 `T` を **小文字に修正**
   - **Interface**: SwiftUI
   - **Language**: Swift
   - **Use Core Data**: OFF
   - **Include Tests**: OFF（SwiftPM 側で十分）
4. 保存先：**プロジェクトルート**（`/Users/.../toki/`）
   - SwiftPM の Package.swift と同一ディレクトリに `Toki.xcodeproj` ができる

### Step 2: Xcode の自動生成ファイルを整理

新規 project 作成で以下が生成される：

- `Toki/TokiApp.swift`（@main 重複）→ **削除**（既存 `Sources/Toki/App/TokiApp.swift` を使う）
- `Toki/ContentView.swift` → **削除**
- `Toki/Assets.xcassets` → 残す（後で AppIcon 配置）
- `Toki/Toki.entitlements` → spec 015 で編集
- `Toki/Info.plist` → 既存 `Resources/Info.plist` の内容を統合（後述）

### Step 3: Sources/Toki/* を Xcode project に参照追加

1. Xcode の Project Navigator で右クリック → "Add Files to Toki..."
2. `Sources/Toki/` ディレクトリを選択
3. オプション：
   - **Create groups** を選択（Create folder references は NG、import に支障）
   - **Copy items if needed**: OFF（コピー禁止、参照のみ）
   - **Add to targets**: Toki にチェック
4. すべての .swift が App ターゲットに含まれることを確認

### Step 4: Info.plist の統合

既存 `Resources/Info.plist` の内容を Xcode project の `Toki/Info.plist` に統合：

| Key | 値 |
|---|---|
| `CFBundleIdentifier` | `jp.co.noouchi.toki` ← 変更（旧: `dev.pokotech.Toki`）|
| `CFBundleName` | `Toki` |
| `CFBundleDisplayName` | `Toki` |
| `CFBundleExecutable` | `$(EXECUTABLE_NAME)` |
| `CFBundleShortVersionString` | `1.0.0` ← 変更（旧: `0.1.0`、v1.0 リリース版）|
| `CFBundleVersion` | `1` |
| `LSMinimumSystemVersion` | `14.0` |
| `LSUIElement` | `YES`（メニューバー駐在、Dock に出さない）|

完了後、**旧 `Resources/Info.plist` は削除**（重複防止）。

### Step 5: build-app.sh の維持判断

選択肢：
- **(A) 維持**: 開発時の素早い .app 確認用（推奨）
- **(B) 廃止**: Xcode build に一本化

→ **A 推奨**。理由：CLI で完結する開発フローを保つ、Xcode 起動なしで動作確認可能。
ただし、リリース時は **必ず Xcode の Archive を使う**（署名 / entitlements 整合性のため）。

### Step 6: ビルド確認

両方が動くことを確認：

```bash
# SwiftPM
swift build
swift run
swift test

# Xcode
xcodebuild -project Toki.xcodeproj -scheme Toki -configuration Debug build
open ./build/Debug/Toki.app  # 起動確認

# Archive（spec 027 で正式利用）
xcodebuild -project Toki.xcodeproj -scheme Toki -configuration Release archive \
  -archivePath ./build/Toki.xcarchive
```

### Step 7: .gitignore 更新

```gitignore
# Xcode
*.xcodeproj/xcuserdata/
*.xcodeproj/project.xcworkspace/xcuserdata/
build/
*.xcarchive
DerivedData/

# 既存
.build/
.DS_Store
```

`Toki.xcodeproj/project.pbxproj` は **コミット必要**（プロジェクト構成）。
`xcuserdata` は **各 dev 環境固有** なので除外。

## 5. 注意事項

- **Bundle ID は変更不可**：一度 MAS に提出したら永久不変。Step 4 で `jp.co.noouchi.toki` を確実に
- **SwiftPM と Xcode の deployment target を一致**：両方とも macOS 14.0
- **Asset Catalog は Xcode 側で管理**：SwiftPM の Resources/ ディレクトリと混在させない
- **Entitlements は spec 015 で本格設定**：本 spec では「ファイル存在」までで OK
- **`@main` の重複に注意**：Step 2 の Xcode 自動生成 TokiApp.swift を確実に削除しないと build エラー
- **既存 codesign 識別子（Toki Dev）は開発用維持**：MAS 配布では Apple 発行の Distribution 証明書を使う

## 6. リスク

| リスク | 影響 | 対策 |
|---|---|---|
| @main 重複でビルド不能 | 高 | Step 2 で確実に削除、build で検証 |
| Sources/Toki を Xcode 参照する際の path 解決問題 | 中 | Step 3 で "Create groups" + 相対 path |
| SwiftPM build と Xcode build で artifact 競合 | 低 | .build/ と build/ は別ディレクトリ |
| Domain テストが Xcode 側でも勝手に走る | 低 | Xcode 側は Test ターゲット作らない、SwiftPM 側のみ |

## 7. 完了条件

- [ ] `Toki.xcodeproj` 作成済み（プロジェクトルート配置）
- [ ] `Sources/Toki/*` が Xcode App ターゲットに参照追加されている
- [ ] Xcode の自動生成 `TokiApp.swift` / `ContentView.swift` 削除済み
- [ ] Info.plist 統合（Bundle ID = `jp.co.noouchi.toki`、Version = 1.0.0）
- [ ] 旧 `Resources/Info.plist` 削除済み
- [ ] `swift build` / `swift run` / `swift test` が動く
- [ ] `xcodebuild build` で `.app` 生成 → 起動確認
- [ ] `.gitignore` 更新
- [ ] `Toki.xcodeproj/project.pbxproj` がコミットされている

## 8. 次の Phase

- **spec 015**：App Sandbox 対応（Entitlements / Keychain / Network 検証）
- **spec 016**：OAuth 公開対応
- Phase 1 並列：spec 017 / 018 / 019

## 9. 参照

- `ROADMAP.md` §2 Phase 1A
- `scripts/build-app.sh`（既存、開発用に維持）
- [Apple - Distributing your app to registered devices](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)
- [Apple - Distributing your app for beta testing and releases](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
