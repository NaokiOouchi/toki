# 012 — next-future-event: Tasks

参照: `specs/012-next-future-event.md` / `specs/012-next-future-event-plan.md`

合計: **5 tasks**

実装順序：上から順に。各 task は fresh subagent に渡して 1 commit ずつ（小規模 task はオーケストレータが直接対応も可）。

新規ファイル 0、編集 5 ファイル。Domain 36 テスト無変更で全 pass 維持。

---

## Task 1: GoogleCalendarAPI.fetchTodayEvents を fetchEventsAhead に rename

**Commit**: `refactor(infra): GoogleCalendarAPI.fetchTodayEvents を fetchEventsAhead に rename`

**目的**: API シグネチャ rename のみ。中身は無変更（events.list の query は既に timeMin/timeMax で N 日対応）。Gateway 側の呼び出し箇所も同 commit で更新（build break 回避）。

**実装**:

### ファイル 1: `Sources/Toki/Infrastructure/GoogleCalendarAPI.swift`（編集）

クラス先頭コメント（L4-7）：
```swift
// 既存：今日の event を全 calendar 横断で取得することに特化する。
// 変更：指定期間の event を全 calendar 横断で取得する。
```

メソッド名（L48）：
```swift
// 既存：func fetchTodayEvents(timeMin: Date, timeMax: Date) async throws -> [GoogleAPIEvent]
// 変更：func fetchEventsAhead(timeMin: Date, timeMax: Date) async throws -> [GoogleAPIEvent]
```

メソッド doc コメント（L44-47）も汎用表現に：
```swift
/// 指定期間（timeMin..<timeMax）の event を全 calendar 横断で並列取得する。
/// 各 calendar の events.list を並列実行し、親 calendar の summary / color を詰めて
/// GoogleAPIEvent 配列で返す。個別 calendar 失敗は空配列で扱う（silent fail）。
```

### ファイル 2: `Sources/Toki/Infrastructure/GoogleCalendarGateway.swift`（編集）

呼び出し箇所 1 つを置換：
```swift
// 既存：api.fetchTodayEvents(timeMin: ..., timeMax: ...)
// 変更：api.fetchEventsAhead(timeMin: ..., timeMax: ...)
```

**完了条件**:
```bash
grep -n "fetchTodayEvents" Sources/Toki/
# → 0 件

grep -n "func fetchEventsAhead" Sources/Toki/Infrastructure/GoogleCalendarAPI.swift
# → 1 件

grep -n "api.fetchEventsAhead" Sources/Toki/Infrastructure/GoogleCalendarGateway.swift
# → 1 件

swift build  # 成功
swift test   # 36 ケース pass
```

**コミット**:
```bash
git add Sources/Toki/Infrastructure/GoogleCalendarAPI.swift Sources/Toki/Infrastructure/GoogleCalendarGateway.swift
git commit -m "refactor(infra): GoogleCalendarAPI.fetchTodayEvents を fetchEventsAhead に rename"
```

**依存**: なし

---

## Task 2: GoogleCalendarGateway の fetch 範囲を 7 日先に拡張し nextFutureEvent を Publish

**Commit**: `feat(infra): GoogleCalendarGateway の fetch 範囲を 7 日先に拡張し nextFutureEvent を Publish`

**目的**: Gateway を「今日 1 日 fetch」から「7 日 fetch + 今日/未来分離 + 未来 1 件選択 + Publish」に拡張。Domain DayTimeline は今日 1 日責務を維持、明日以降は `@Published nextFutureEvent: Event?` で別経路提供。

**実装**:

ファイル: `Sources/Toki/Infrastructure/GoogleCalendarGateway.swift`（編集）

### Step 1: @Published nextFutureEvent 追加

`@Published private(set) var lastReloadAt: Date?` の近くに：

```swift
/// 明日以降の最初の未来 event（spec 012）。
/// 今日の予定が全て終了 / ゼロのとき NextEventLine に表示する。
/// 7 日先まで何もない場合は nil。Event の Equatable は id ベースで重複変更時の再描画を抑制する。
/// 終日（all-day）event は時刻ラベルが付けられないため除外する。
@Published private(set) var nextFutureEvent: Event? = nil
```

### Step 2: fetchTimelineAndNextFuture private 関数を追加（旧 fetchTodayTimeline を置き換え）

```swift
/// 7 日先までの event を fetch し、今日分は DayTimeline、明日以降分の
/// 先頭 1 件（時刻付き）は nextFutureEvent として返す（spec 012）。
/// 既存の DayTimeline は今日 1 日分の責務を維持する（Domain 不変条件）。
private func fetchTimelineAndNextFuture() async -> (DayTimeline, Event?) {
    let dayStart = calendar.startOfDay(for: Date())
    guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart),
          let weekEnd = calendar.date(byAdding: .day, value: 7, to: dayStart) else {
        return (DayTimeline(date: dayStart, events: []), nil)
    }
    guard oauthClient.isAuthorized else {
        return (DayTimeline(date: dayStart, events: []), nil)
    }
    do {
        let apiEvents = try await api.fetchEventsAhead(timeMin: dayStart, timeMax: weekEnd)

        // 7 日分を「今日」「明日以降の時刻付き」に分離。明日以降の all-day は除外。
        var todayRaw: [Event] = []
        var todayAllDay: [Bool] = []
        var futureEvents: [Event] = []
        for ge in apiEvents {
            guard let (event, isAllDay) = Self.convert(ge) else { continue }
            if event.start < dayEnd {
                todayRaw.append(event)
                todayAllDay.append(isAllDay)
            } else if !isAllDay {
                futureEvents.append(event)
            }
        }
        let timeline = DayTimeline.make(date: dayStart,
                                        rawEvents: todayRaw,
                                        allDayFlags: todayAllDay,
                                        calendar: calendar)
        // 未来 event は start 昇順で並び替え、先頭 1 件を採用
        let nextFuture = futureEvents.sorted { $0.start < $1.start }.first
        return (timeline, nextFuture)
    } catch {
        print("Google Calendar API fetch failed: \(error)")
        // 失敗時は last-known 維持（spec 008 と整合）
        return (subject.value, self.nextFutureEvent)
    }
}
```

### Step 3: reload() を fetchTimelineAndNextFuture 経由に切替

```swift
func reload() async {
    let (timeline, nextFuture) = await fetchTimelineAndNextFuture()
    isAuthorized = oauthClient.isAuthorized
    lastReloadAt = Date()
    nextFutureEvent = nextFuture
    subject.send(timeline)
}
```

### Step 4: 旧 fetchTodayTimeline 関数を削除

該当 private 関数を完全削除。

**完了条件**:
```bash
# 新規 publisher
grep -n "@Published private(set) var nextFutureEvent" Sources/Toki/Infrastructure/GoogleCalendarGateway.swift
# → 1 件

# 新規 private 関数
grep -n "func fetchTimelineAndNextFuture" Sources/Toki/Infrastructure/GoogleCalendarGateway.swift
# → 1 件

# fetch 範囲が 7 日
grep -n "value: 7" Sources/Toki/Infrastructure/GoogleCalendarGateway.swift
# → 1 件以上

# 旧関数削除
grep -c "func fetchTodayTimeline" Sources/Toki/Infrastructure/GoogleCalendarGateway.swift
# → 0 件

# reload() が新関数経由
grep -nA 2 "func reload" Sources/Toki/Infrastructure/GoogleCalendarGateway.swift | grep "fetchTimelineAndNextFuture"
# → 1 件

swift build  # 成功
swift test   # 36 ケース pass
./scripts/build-app.sh
```

実機目視（subagent 範囲外）：
- OAuth 接続後、ログでエラーなく fetch 完了
- 既存挙動（今日の event 表示、最終更新、ホバー、popover）が変わらない

**コミット**:
```bash
git add Sources/Toki/Infrastructure/GoogleCalendarGateway.swift
git commit -m "feat(infra): GoogleCalendarGateway の fetch 範囲を 7 日先に拡張し nextFutureEvent を Publish"
```

**依存**: Task 1

---

## Task 3: NextLineState に dateLabel を追加し NextEventLine の表示拡張

**Commit**: `feat(ui): NextLineState に dateLabel を追加し NextEventLine の表示拡張`

**目的**: `NextLineState` に `dateLabel: String?` を追加（デフォルト nil で既存呼び出し吸収）。View 内で `displayText` helper を追加し、dateLabel があれば時刻の前に prefix 表示する。

**実装**:

ファイル: `Sources/Toki/UI/NextEventLine.swift`（編集）

完全版（既存 50 行 → 約 60 行）：

```swift
import SwiftUI

/// NextEventLine の表示状態。
/// dateLabel は spec 012 で追加：今日の event なら nil、明日以降なら
/// "明日" / "明後日" / "土曜" / "5/26 (月)" のような賢いラベル。
struct NextLineState: Equatable {
    let timeHHMM: String
    let title: String
    let dateLabel: String?

    init(timeHHMM: String, title: String, dateLabel: String? = nil) {
        self.timeHHMM = timeHHMM
        self.title = title
        self.dateLabel = dateLabel
    }
}

struct NextEventLine: View {
    let state: NextLineState?
    let lastUpdatedText: String?
    var textScale: CGFloat = 1.0

    var body: some View {
        if state != nil || lastUpdatedText != nil {
            HStack {
                if let s = state {
                    Text("次")
                        .font(.system(size: 11 * textScale))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(displayText(s))
                        .font(.system(size: 11 * textScale))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                } else {
                    Spacer()
                }
                if let text = lastUpdatedText {
                    Text(text)
                        .font(.system(size: 9 * textScale))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
        } else {
            Color.clear
        }
    }

    /// dateLabel があれば時刻の前に prefix、なければ既存通り。
    /// spec 012 で導入、1 行レイアウト維持のため文字列結合で完結させる。
    private func displayText(_ s: NextLineState) -> String {
        if let label = s.dateLabel {
            return "\(label) \(s.timeHHMM) \(s.title)"
        }
        return "\(s.timeHHMM) \(s.title)"
    }
}
```

**完了条件**:
```bash
grep -n "let dateLabel: String?" Sources/Toki/UI/NextEventLine.swift
# → 1 件

grep -n "func displayText" Sources/Toki/UI/NextEventLine.swift
# → 1 件

grep -n "init(timeHHMM:.*title:.*dateLabel:.*= nil" Sources/Toki/UI/NextEventLine.swift
# → 1 件

wc -l Sources/Toki/UI/NextEventLine.swift
# → < 100 行

swift build  # 成功
swift test   # 36 ケース pass
```

**コミット**:
```bash
git add Sources/Toki/UI/NextEventLine.swift
git commit -m "feat(ui): NextLineState に dateLabel を追加し NextEventLine の表示拡張"
```

**依存**: なし（Composition より先に UI 側を整える）

---

## Task 4: formatDateLabel + nextFutureEvent 購読 + nextLineState 選択ロジック拡張

**Commit**: `feat(composition): formatDateLabel + nextFutureEvent 購読 + nextLineState 選択ロジック拡張`

**目的**: ClockViewModel に：
1. `@Published nextFutureEvent` を追加し Gateway の Publisher を sink
2. `nextLineState` computed property の選択ロジックを拡張（今日残ゼロ時に未来 event を表示）
3. `formatDateLabel` / `weekdayName` / `shortDateLabel` の 3 つの private static helper を追加

**実装**:

ファイル: `Sources/Toki/Composition/ClockViewModel.swift`（編集）

### Step 1: @Published nextFutureEvent 追加

`@Published private(set) var lastUpdatedAt: Date?` の近くに：

```swift
/// 明日以降の最初の未来 event（spec 012）。
/// Gateway の $nextFutureEvent を sink して同期する。
/// 今日の予定が全終了 / ゼロのとき NextEventLine で日付ラベル付き表示する。
@Published private(set) var nextFutureEvent: Event? = nil
```

### Step 2: start() 内で sink 追加

既存の `$lastReloadAt` / `$isAuthorized` の sink パターンに合わせて追加：

```swift
// spec 012: 明日以降の最初の未来 event を sink
gateway?.$nextFutureEvent
    .receive(on: DispatchQueue.main)
    .sink { [weak self] ev in self?.nextFutureEvent = ev }
    .store(in: &cancellables)
```

### Step 3: nextLineState 選択ロジック拡張

既存の `nextLineState` computed property を以下に置き換え：

```swift
/// 下部「次の予定」ラインの状態。
/// 今日の予定残あり → 今日の next event（既存挙動、日付ラベルなし）
/// 今日の予定残ゼロ → 明日以降の最初の未来 event（spec 012、日付ラベル付き）
/// 7 日先までゼロ → nil（NextEventLine 非表示）
var nextLineState: NextLineState? {
    guard accessGranted else { return nil }

    // 今日の予定残あり → 既存ロジック
    if let tl = timeline, let nxt = tl.nextEvent(after: now) {
        return NextLineState(
            timeHHMM: Self.formatHHMM(nxt.start, calendar: calendar),
            title: nxt.title,
            dateLabel: nil
        )
    }

    // spec 012: 今日の予定残ゼロ → 明日以降の最初の未来 event
    if let future = nextFutureEvent {
        return NextLineState(
            timeHHMM: Self.formatHHMM(future.start, calendar: calendar),
            title: future.title,
            dateLabel: Self.formatDateLabel(future.start, relativeTo: now, calendar: calendar)
        )
    }
    return nil
}
```

### Step 4: 日付ラベル整形 helpers（private static）

`formatHHMM` の隣に 3 つの helper を追加：

```swift
/// 日付ラベル整形 helper（spec 012）。
/// now を起点に target までの日数差で表示形式を切り替える。
/// - 今日：nil
/// - 翌日："明日"
/// - 翌々日："明後日"
/// - 3〜6 日後：曜日名（"金曜" / "土曜" 等）
/// - 7 日後以降："M/d (曜)" フォーマット
/// 日数差は startOfDay 同士の Calendar.dateComponents で算出（DST 跨ぎ安全）。
private static func formatDateLabel(_ target: Date,
                                    relativeTo now: Date,
                                    calendar: Calendar) -> String? {
    let nowDay = calendar.startOfDay(for: now)
    let targetDay = calendar.startOfDay(for: target)
    let comps = calendar.dateComponents([.day], from: nowDay, to: targetDay)
    guard let dayDiff = comps.day else { return nil }
    switch dayDiff {
    case ..<1: return nil
    case 1: return "明日"
    case 2: return "明後日"
    case 3...6: return weekdayName(of: target, calendar: calendar)
    default: return shortDateLabel(of: target, calendar: calendar)
    }
}

/// 曜日名（"日曜" / "月曜" / ...）。
/// DateFormatter のロケール依存を避けるため日本語ハードコード。
/// CLAUDE.md「個人利用、Mac専用」前提で日本語固定 OK。
private static func weekdayName(of date: Date, calendar: Calendar) -> String {
    let weekday = calendar.component(.weekday, from: date)  // 1=日, 2=月, ..., 7=土
    let names = ["日曜", "月曜", "火曜", "水曜", "木曜", "金曜", "土曜"]
    return names[max(1, min(7, weekday)) - 1]
}

/// "M/d (曜)" 形式（例：5/26 (月)）。7 日後の境界用。
private static func shortDateLabel(of date: Date, calendar: Calendar) -> String {
    let c = calendar.dateComponents([.month, .day], from: date)
    let m = c.month ?? 1
    let d = c.day ?? 1
    let weekday = calendar.component(.weekday, from: date)
    let shortNames = ["日", "月", "火", "水", "木", "金", "土"]
    return "\(m)/\(d) (\(shortNames[max(1, min(7, weekday)) - 1]))"
}
```

**完了条件**:
```bash
# @Published
grep -n "@Published private(set) var nextFutureEvent" Sources/Toki/Composition/ClockViewModel.swift
# → 1 件

# sink 追加
grep -n "gateway?.\$nextFutureEvent" Sources/Toki/Composition/ClockViewModel.swift
# → 1 件

# 3 つの helper
grep -n "func formatDateLabel" Sources/Toki/Composition/ClockViewModel.swift
grep -n "func weekdayName" Sources/Toki/Composition/ClockViewModel.swift
grep -n "func shortDateLabel" Sources/Toki/Composition/ClockViewModel.swift
# → 各 1 件

# nextLineState 拡張：dateLabel の使用
grep -n "dateLabel: Self.formatDateLabel" Sources/Toki/Composition/ClockViewModel.swift
# → 1 件

# ファイル長 < 400 行
wc -l Sources/Toki/Composition/ClockViewModel.swift

swift build  # 成功
swift test   # 36 ケース pass
./scripts/build-app.sh
```

実機目視チェック（手動）：
- M1: 今日予定あり → 既存通り（日付ラベルなし）
- M2: 今日最終 event 終了後 / 明日 9:00 予定 → `次 明日 09:00 ...`
- M3: 今日空 / 明後日予定 → `次 明後日 ...`
- M4: 4 日後（曜日内）→ `次 土曜 ...`
- M5: 7 日後の event → `次 5/30 (土) ...`
- M6: 7 日先ゼロ → 空（既存挙動）

**コミット**:
```bash
git add Sources/Toki/Composition/ClockViewModel.swift
git commit -m "feat(composition): formatDateLabel + nextFutureEvent 購読 + nextLineState 選択ロジック拡張"
```

**依存**: Task 2, 3

---

## Task 5: SPEC.md spec 012 完了反映（任意）

**Commit**: `docs(spec): SPEC.md を spec 012 完了状態に追従更新`

**目的**: SPEC.md §6 Phase 3 「直近の有力候補」から「表示するカレンダー選択」は spec 013 候補にずらし（または現状維持）、「今日の予定がない時に次未来 event を表示」を **spec 012 完了**としてマーク。

**実装**:

ファイル: `SPEC.md`（編集）

§6 Phase 3 内に「✅ spec 012 完了：今日の予定がない時に次未来 event を表示」と記載。

**完了条件**:
```bash
grep -n "spec 012" SPEC.md
# → 1 件以上

swift build && swift test  # 36 ケース pass
```

**コミット**:
```bash
git add SPEC.md
git commit -m "docs(spec): SPEC.md を spec 012 完了状態に追従更新"
```

**依存**: Task 4

---

## 全 task 完了後

### 回帰確認

- [ ] `swift test`：Domain 36 ケース全 pass
- [ ] `./scripts/build-app.sh && open .build/Toki.app`：実機目視で spec 012 §AC walkthrough

### 手動チェックリスト（spec 012 plan §11 ベース）

| # | 状況 | 期待表示 |
|---|---|---|
| M1 | 今日予定あり、次 16:00 | `次 16:00 タイトル`（既存） |
| M2 | 今日最終 event 終了後、明日 9:00 | `次 明日 09:00 朝会` |
| M3 | 今日空、明後日 14:00 | `次 明後日 14:00 ミーティング` |
| M4 | 今日空、4 日後 10:00（土曜） | `次 土曜 10:00 個人作業` |
| M5 | 今日空、7 日後の event | `次 5/30 (土) 09:00 出張準備` |
| M6 | 7 日先まで何もない | NextEventLine 空（lastUpdated のみ） |
| M7 | OAuth 未接続 | NextEventLine nil（既存） |
| M8 | ホバー / popover / 円弧 / 設定 / OAuth / リサイズ | 全て無変更 |
| M9 | 進行中 + 次の今日 event | 既存通り |
| M10 | 進行中のみ、今日残ゼロ、明日朝会 | `次 明日 09:00 朝会` |

### コードレビュー（任意）

- `code-reviewer` agent で spec 012 全体レビュー
