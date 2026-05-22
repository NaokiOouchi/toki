# 012 — 今日の予定がない時に次の未来 event を表示

## Why

実用中に発覚した pain：**今日の予定がない / 全て終わったとき、Toki の下部 NextEventLine が空になる**。「次の予定が何時か」がアプリ内で全く見えず、Google Calendar をブラウザで開いて確認する手間が発生する。

具体的シーン：
- 朝起きて Toki を見る → 今日は会議なし → 下部が空 → 「次の予定はいつ？」がわからない
- 午後の最後の会議が終わる → 下部が空 → 「明日の朝何時から？」がわからない
- 休日：Toki が無情報になる → 翌営業日の予定の確認に Google Calendar 起動

期待される動作：今日の予定がない / 全て終わったときは、**次の未来 event**（明日以降）を NextEventLine に賢い日付ラベル付きで表示する：

```
（今日の予定が全部終わった or ない時）

次  明日 14:00 ミーティング         最終更新 2 分前
次  5/26 (月) 10:00 定例           最終更新 5 分前
```

「event = タスク」運用しているユーザーにとって、**次の作業時刻がすぐに見える** ことは Toki のコア価値（時間軸の視覚化）と直結する。

## Goal

Phase 3.2（本 iteration 完了時）に達成する状態：

1. **API 拡張**：Google Calendar API fetch を「今日 → 7 日先まで」に拡張、今日の event は既存通り円弧描画 / 中央テキストに反映
2. **次未来 event の選択ロジック**：今日の event が全て終了 or ゼロ → 明日以降の最初の event を `nextFutureEvent` として選ぶ
3. **NextEventLine 拡張**：日付ラベル付き表示
   - 今日：日付ラベルなし（既存通り、`14:00 タイトル`）
   - 明日：`明日 14:00 タイトル`
   - 明後日：`明後日 14:00 タイトル`
   - 今週内（2〜6 日後）：`土曜 14:00 タイトル` のような曜日名
   - 7 日後以降：`5/26 (月) 14:00 タイトル`
4. **トリガー条件**：今日の予定が全て終了 OR ゼロのとき **だけ** 表示。今日の予定残あり時は既存通り次の今日 event を表示
5. **fallback**：7 日先まで何もない場合は NextEventLine は空（現状と同じ）
6. **既存挙動の維持**：今日の予定がある間は完全に同一挙動
7. **Domain テスト 36 ケース全 pass**：必要に応じてヘルパ拡張で吸収

## Non-goals

本 iteration では明示的にやらない：

- **30 日以上先の event 検索**：API レスポンスサイズが増える、7 日で十分
- **中央テキスト変更**：「次は明日 14:00」を主役にする UI は別案件、本 spec では NextEventLine のみ
- **複数日 navigation**（マウスホイール / 横スクロール）：別 spec
- **次未来 event の hover ツールチップ / popover**：本 spec では NextEventLine 内テキスト表示のみ
- **次未来 event クリックで popover / ブラウザ起動**：別 spec、今は NextEventLine は表示のみ
- **設定で「次未来表示を ON/OFF」**：本 spec では常に有効
- **明日以降の全 event 視覚化**（2 段リング / 翌日プレビュー等）：別 spec
- **タイムゾーン跨ぎの event 対応**：spec 005 以来既定の localTimeZone を継承、本 spec では新規対応なし
- **次未来 event の参加可否操作**：spec 010 §Non-goals に従い見送り
- **API レスポンスを events.list の `fields` 絞り込み**：spec 010 §Non-goals 由来、今回も対応しない

## Acceptance Criteria

### トリガー条件

- The 今日の予定が **1 件以上残っている** とき：NextEventLine は既存通り「次の今日 event」を表示する
- The 今日の予定が **全て終了 OR ゼロ** のとき：NextEventLine は明日以降の最初の event（`nextFutureEvent`）を日付ラベル付きで表示する
- The 7 日先まで何もない場合：NextEventLine は空（現状の挙動と同等）
- The 進行中の event がある場合（今日の予定残あり）：本機能は無効、既存通り次の今日 event を表示

### 表示フォーマット

#### 日付ラベルのルール

now を起点に：

- The **今日** の event：日付ラベルなし（既存通り、`14:00 タイトル`）
- The **明日** の event：`明日 14:00 タイトル`
- The **明後日** の event：`明後日 14:00 タイトル`
- The **今週内（3〜6 日後）**：`土曜 14:00 タイトル` のような曜日名（`金曜` / `土曜` / `日曜` / `月曜` 等）
- The **7 日先**：境界、`5/26 (月) 14:00 タイトル` フォーマット
- The **8 日以上先**：本 spec では検索しない（API fetch を 7 日先で打ち切り）

#### NextEventLine の表示要素

- The 「次」ラベル（既存通り、`secondary` フォント）
- The 日付ラベル（あれば、`明日` / `明後日` / `土曜` / `5/26 (月)` 等）
- The 時刻 `HH:MM`
- The タイトル
- The 「最終更新 N 分前」（既存通り、右側 `tertiary` フォント）

例：
```
次  明日 14:00 定例ミーティング        2 分前
次  土曜 10:00 個人作業              5 分前
次  5/26 (月) 09:00 出張準備         12 分前
```

### Infrastructure 拡張

- The `GoogleCalendarAPI.fetchTodayEvents(timeMin:timeMax:)` を `fetchEventsAhead(timeMin:timeMax:)` に rename / 拡張（API シグネチャ自体は変えず、呼び出し側の `timeMax` を「今日終了 → 7 日後終了」に拡張）
- The 既存の events.list API call は parameters のみ変更、parse / convert ロジックは無変更
- The Today / 未来 event の振り分けは Composition 層で行う（Infrastructure は素直に「N 日分の event」を返す）

### Composition 拡張

- The `ClockViewModel` に `nextFutureEvent: RenderableEvent?`（または同等の表示用型）プロパティ追加
- The 既存の `nextLineState: NextLineState?` を拡張：日付ラベル `dateLabel: String?` フィールドを追加
- The `nextLineState` の選択ロジックを変更：
  - 今日の予定残 1 件以上 → 既存通り次の今日 event
  - 今日の予定残ゼロ → `nextFutureEvent` を選んで日付ラベル付きで表示
- The 日付ラベル整形は static helper（`formatDateLabel(_:relativeTo:calendar:)`）として ClockViewModel に追加

### Domain / UI 拡張

- The Domain 層は **無変更**（時間軸 / Event 不変条件は維持）
- The `NextLineState`（既存）に `dateLabel: String?` フィールドを追加
- The `NextEventLine` View が `dateLabel` を受け取り、あれば時刻の前に表示

### 既存挙動の維持

- The 今日の予定がある間は完全に同一挙動（円弧描画 / 中央テキスト / NextEventLine の表示 / クリック / ホバー）
- The OAuth フロー / 設定 UI 11 軸 / popover / リサイズ / 位置記憶 / 最終更新表示は無変更
- The 2 分ポーリング / focus reload は無変更（fetch 範囲が 7 日に広がるだけ）

### Domain テスト

- The Domain テスト 36 ケース無変更で全 pass
- 新規 Domain テストは追加しない（spec 008 / 010 と同じスタンス、UI / Composition 中心の変更）

## Domain Model

本 iteration は Domain 層に変更を入れない。Composition / Infrastructure / UI のみ変更。

- `NextLineState` は spec 008 で導入された UI / Composition 寄りの値型（Domain ではない）。`dateLabel: String?` を追加するのは UI / Composition の責務範囲

## Open Questions

実装着手前に判断したい論点：

### API 拡張範囲
1. **fetch 範囲**：7 日先まで（spec §Goal 確定）。確認のみ：[CONFIDENT]
2. **fetch シグネチャ rename**：`fetchTodayEvents` → `fetchEventsAhead` に rename するか、引数だけ変えるか。**rename 推奨**（意図が明確、`fetchEventsAhead(timeMin:timeMax:)` で N 日分対応を表現）：[CONFIDENT]

### 日付ラベル整形
3. **「今週内」の定義**：3〜6 日後（4 日間）。曜日名表示。**確定**：[CONFIDENT]
4. **曜日名フォーマット**：`日曜` / `月曜` / `火曜` 等。**確定**（macOS 標準ロケール）：[CONFIDENT]
5. **7 日先（境界）の表示**：曜日名 vs 日付付き。**日付付き**（`5/26 (月) HH:MM タイトル`）：[CONFIDENT]
6. **タイムゾーン**：localTimeZone（spec 005 以来既定）：[CONFIDENT]

### Composition / UI
7. **`nextLineState` の選択ロジック配置**：ClockViewModel computed property / 別 helper。**ClockViewModel.nextLineState の中で完結**（既存通り）：[CONFIDENT]
8. **`nextFutureEvent` の Equatable**：既存 RenderableEvent と同様 id ベース。**既存挙動踏襲**：[CONFIDENT]
9. **NextEventLine の日付ラベル表示位置**：時刻の前 `明日 14:00 タイトル` vs 別行 `明日\n14:00 タイトル`。**時刻の前** 1 行表示推奨（既存レイアウト維持）：[CONFIDENT]

### 既存テスト
10. **テストヘルパ拡張**：`NextLineState` に `dateLabel` 引数追加（デフォルト nil で既存ケース吸収）。**既存スタンス踏襲**：[CONFIDENT]

[NEEDS INPUT] は最大 3 件以下に絞る → 0 件、すべて [CONFIDENT] で着手可能。

## Out of scope / Phase 3 以降

参考：

- **複数日 navigation**（マウスホイール / 横スクロール）：別 spec
- **次未来 event クリック → popover / ブラウザ起動**：別 spec（本 spec は表示のみ）
- **明日以降の event を円弧プレビュー表示**：別 spec（2 段リング系）
- **設定で次未来表示を ON/OFF**：本 spec では常時 ON
- **30 日先までの検索 / オフラインキャッシュ**：spec 006 §Non-goals 由来、未対応

## 補足：UI イメージ

| 状況 | 中央テキスト | 下部 NextEventLine |
|---|---|---|
| 今日：朝、定例 10:00 待ち | 「—」「次まで 1 時間 30 分」 | `次 10:00 定例` |
| 今日：定例実行中 | 残時間 + タイトル | `次 14:00 ミーティング` |
| 今日：最終 event 終了後 | 「—」 | **`次 明日 09:00 朝会`**（NEW） |
| 休日：今日 event ゼロ | 「—」 | **`次 月曜 09:00 朝会`**（NEW） |
| 長期休暇：7 日先まで event なし | 「—」 | 空（現状維持） |
