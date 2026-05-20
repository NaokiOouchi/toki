# 001 — clock-mvp: Tasks

参照: `specs/001-clock-mvp.md` / `specs/001-clock-mvp-plan.md`

合計: **17 tasks**

実装順序：上から順に。各 task は fresh subagent に渡して 1 commit ずつ。

レイヤー順：Domain（テストファースト）→ Infrastructure → Window/App 骨格 → UI（ハードコード）→ Composition で本接続 + クリック。

---

## Task 1: SwiftPM プロジェクト初期化と .app バンドル化スクリプト

**Commit**: `chore: SwiftPM プロジェクト初期化と .app バンドル化スクリプト`

**目的**: 開発の土台を作る。executable target + test target、`Info.plist`、`.app` バンドル化スクリプトを用意。

**コンテキスト**:
- 参照: plan §3「Module/file plan」/ §9「.app バンドル構築」
- 前提: macOS 14+、Swift 5.9+、SwiftPM、AppKit + SwiftUI + EventKit
- 確定済み方針：`Info.plist` を確実に効かせるため最初から `.app` バンドル化する（SPEC.md §9 の `swift run` で十分という記述からは外れる）

**実装内容**:
- ファイル: `Package.swift`（新規）
  - `swift-tools-version:5.9`
  - `name: "Toki"`、`platforms: [.macOS(.v14)]`
  - executable target `Toki`（`path: "Sources/Toki"`）
  - test target `TokiTests`（`path: "Tests/TokiTests"`、depends on `Toki`）
  - `Resources/Info.plist` は SwiftPM の resource として含めない（バンドル化スクリプトで直接コピーするため）
- ファイル: `Resources/Info.plist`（新規）
  - `LSUIElement = YES`（Dock 非表示）
  - `NSCalendarsUsageDescription = "カレンダーの予定を時計上に表示するために使用します"`
  - `CFBundleIdentifier = "dev.pokotech.Toki"`
  - `CFBundleName = "Toki"`
  - `CFBundleExecutable = "Toki"`
  - `CFBundleShortVersionString = "0.1.0"`
  - `CFBundleVersion = "1"`
  - `LSMinimumSystemVersion = "14.0"`
  - `CFBundlePackageType = "APPL"`
- ファイル: `scripts/build-app.sh`（新規、実行権限付与）
  ```bash
  #!/bin/bash
  set -euo pipefail
  CONFIG="${1:-debug}"
  swift build -c "$CONFIG"
  BIN_DIR=".build/$CONFIG"
  APP_DIR=".build/Toki.app"
  CONTENTS="$APP_DIR/Contents"
  rm -rf "$APP_DIR"
  mkdir -p "$CONTENTS/MacOS"
  mkdir -p "$CONTENTS/Resources"
  cp "$BIN_DIR/Toki" "$CONTENTS/MacOS/Toki"
  cp "Resources/Info.plist" "$CONTENTS/Info.plist"
  echo "Built $APP_DIR"
  echo "Run: open $APP_DIR"
  ```
- ファイル: `Sources/Toki/main.swift`（暫定、Task 14 で削除予定）
  - `print("Toki: SwiftPM init OK")` だけのスタブ。`swift build` を通すためのプレースホルダ

**完了条件**:
- [ ] `swift build` がエラーなく成功
- [ ] `swift test` がエラーなく成功（テストはまだ 0 件）
- [ ] `chmod +x scripts/build-app.sh && ./scripts/build-app.sh` が成功し、`.build/Toki.app/Contents/{MacOS/Toki, Info.plist}` が存在
- [ ] `Resources/Info.plist` を `plutil -lint` が通る

**依存**: なし

---

## Task 2: Domain `TimeOfDay`（テスト + 実装）

**Commit**: `feat(domain): TimeOfDay 実装（時計角度算出と境界バリデーション）`

**目的**: 0:00–23:59 を扱う Value Object。24 時間時計上の角度を算出する純関数を提供。

**コンテキスト**:
- 参照: spec §「Domain Model」TimeOfDay / plan §4「Domain layer detail / TimeOfDay」/ SPEC.md §5 TimeOfDay
- 前提: Foundation のみに依存（Domain 層、純粋ロジック）
- 角度仕様：0:00 が真上（-π/2）、12:00 が真下（+π/2）、時計回り

**実装内容**:
- ファイル: `Tests/TokiTests/TimeOfDayTests.swift`（新規、**先に書く**）
  - `import XCTest; @testable import Toki`
  - テストケース：
    - `testClockAngleAtMidnight`: `(0, 0).clockAngle ≈ -.pi / 2`（誤差 0.0001）
    - `testClockAngleAt6am`: `(6, 0).clockAngle ≈ 0`
    - `testClockAngleAtNoon`: `(12, 0).clockAngle ≈ .pi / 2`
    - `testClockAngleAt6pm`: `(18, 0).clockAngle ≈ .pi`
    - `testClockAngleAt6_30am`: 6:30 の角度が 6:00 と 7:00 の中間にあること
    - `testFailableInit_hour24`: `init(hour: 24, minute: 0)` が nil
    - `testFailableInit_minute60`: `init(hour: 0, minute: 60)` が nil
    - `testFailableInit_negative`: `init(hour: -1, minute: 0)` が nil
    - `testComparable`: `(9, 30) < (10, 0)`、`(9, 30) < (9, 31)`
    - `testMinutesSinceMidnight`: `(9, 30).minutesSinceMidnight == 570`
    - `testFromDate`: `Date` から正しい hour/minute が取れる（Calendar.current 使用）
- ファイル: `Sources/Toki/Domain/TimeOfDay.swift`（新規）
  ```swift
  struct TimeOfDay: Equatable, Comparable, Hashable {
      let hour: Int
      let minute: Int
      init?(hour: Int, minute: Int)  // 0..<24, 0..<60 外は nil
      var minutesSinceMidnight: Int { hour * 60 + minute }
      var clockAngle: Double {
          let fraction = Double(minutesSinceMidnight) / (24 * 60)
          return fraction * 2 * .pi - .pi / 2
      }
      static func now(calendar: Calendar = .current) -> TimeOfDay
      static func from(date: Date, calendar: Calendar = .current) -> TimeOfDay
      static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool
  }
  ```
- 暫定 `Sources/Toki/main.swift` は残したまま（Task 14 で削除）

**完了条件**:
- [ ] `swift test` で `TimeOfDayTests` が pass（11 ケース）
- [ ] `swift build` が通る
- [ ] `TimeOfDay.swift` は Foundation のみ import

**依存**: Task 1

---

## Task 3: Domain `Event`（テスト + 実装）

**Commit**: `feat(domain): Event 実装（start<end の不変条件、id ベース Equatable）`

**目的**: カレンダーイベントを表す Value Object。`start < end` を failable init で強制。

**コンテキスト**:
- 参照: spec §「Domain Model」Event / plan §4「Domain layer detail / Event」/ SPEC.md §5 Event
- 前提: `EKEvent` 等 EventKit 型は Domain に漏らさない。`calendarColor: CGColor` は CoreGraphics（Foundation 系）なので OK
- 注意：`CGColor` の `Equatable` 比較はポインタ比較になるため、`Event.Equatable` は **`id` ベース限定**で実装

**実装内容**:
- ファイル: `Tests/TokiTests/EventTests.swift`（新規、**先に書く**）
  - テストケース：
    - `testInit_zeroDuration`: `start == end` で init nil
    - `testInit_startAfterEnd`: `start > end` で init nil
    - `testInit_emptyId`: `id = ""` で init nil
    - `testInit_normal`: 通常のイベントで init 成功、プロパティが正しく入る
    - `testEquatable_byId`: 同じ id・異なるタイトルの 2 つが等しい（id ベース比較）
    - `testEquatable_differentId`: 違う id なら不等
- ファイル: `Sources/Toki/Domain/Event.swift`（新規）
  ```swift
  import Foundation
  import CoreGraphics

  struct Event: Identifiable {
      let id: String
      let title: String
      let start: Date
      let end: Date
      let calendarColor: CGColor
      let externalIdentifier: String?

      init?(id: String, title: String, start: Date, end: Date,
            calendarColor: CGColor, externalIdentifier: String?) {
          guard !id.isEmpty, start < end else { return nil }
          self.id = id; self.title = title; self.start = start; self.end = end
          self.calendarColor = calendarColor; self.externalIdentifier = externalIdentifier
      }
  }

  extension Event: Equatable {
      static func == (lhs: Event, rhs: Event) -> Bool { lhs.id == rhs.id }
  }
  ```

**完了条件**:
- [ ] `swift test` で `EventTests` が pass（6 ケース）
- [ ] `swift build` が通る
- [ ] `Event.swift` は Foundation と CoreGraphics のみ import

**依存**: Task 1

---

## Task 4: Domain `EventStatus`（テスト + 実装）

**Commit**: `feat(domain): EventStatus + Event.status(at:) 実装`

**目的**: イベントの過去/現在/未来を判定する純関数。

**コンテキスト**:
- 参照: spec §「Domain Model」EventStatus / plan §4「Domain layer detail / EventStatus」/ SPEC.md §5 EventStatus
- 判定ルール：`end <= now` past、`start > now` future、それ以外 current
- 境界の扱い注意：`end == now` は past（イベント終了済み）、`start == now` は current（ちょうど始まった）

**実装内容**:
- ファイル: `Tests/TokiTests/EventStatusTests.swift`（新規、**先に書く**）
  - テストケース：
    - `testPast`: end が 1 秒前 → past
    - `testFuture`: start が 1 秒後 → future
    - `testCurrent_inside`: now が start と end の間 → current
    - `testBoundary_endEqualsNow`: `end == now` → past
    - `testBoundary_startEqualsNow`: `start == now` → current
- ファイル: `Sources/Toki/Domain/EventStatus.swift`（新規）
  ```swift
  import Foundation

  enum EventStatus { case past, current, future }

  extension Event {
      func status(at now: Date) -> EventStatus {
          if end <= now { return .past }
          if start > now { return .future }
          return .current
      }
  }
  ```

**完了条件**:
- [ ] `swift test` で `EventStatusTests` が pass（5 ケース）
- [ ] `swift build` が通る

**依存**: Task 3

---

## Task 5: Domain `DayTimeline`（テスト + 実装）

**Commit**: `feat(domain): DayTimeline 実装（clip / filterOverlaps / make ファクトリ）`

**目的**: 今日のイベント集約。日跨ぎ clip、all-day 除外、重なり「earliest start wins」フィルタを Domain で完結させる。

**コンテキスト**:
- 参照: spec §「Domain Model」DayTimeline / plan §4「Domain layer detail / DayTimeline」/ SPEC.md §5 DayTimeline
- 設計判断（plan §4 最後）：「重なり除去 / 日跨ぎ clip / all-day 除外」は Domain で前処理する。UI は描画のみ
- Invariants：`events` は start 昇順（同 start は end 昇順）、all-day を含まない、各 event は date の 0:00–24:00 に収まる

**実装内容**:
- ファイル: `Tests/TokiTests/DayTimelineTests.swift`（新規、**先に書く**）
  - テストケース：
    - `testEventsSortedByStart`: 順不同で渡しても init 後は start 昇順
    - `testCurrentEvent_returnsMatch`: 3 件中の真ん中だけ current → それを返す
    - `testCurrentEvent_noneCurrent`: 全て past または future → nil
    - `testNextEvent_returnsFirstFuture`: now より start が大きい最初の event
    - `testNextEvent_allPast`: 全イベント過去 → nil
    - `testClip_midnightCrossing_endsNextDay`: 23:30–翌 0:30 → 23:30–24:00 にトリム
    - `testClip_midnightCrossing_startsPrevDay`: 前日 23:30–今日 0:30 → 0:00–0:30 にトリム
    - `testClip_fullyNextDay`: 完全に翌日 → nil
    - `testClip_fullyPrevDay`: 完全に前日 → nil
    - `testFilterOverlaps_partialOverlap`: 9:00–10:00 と 9:30–9:45 → 前者のみ残る
    - `testFilterOverlaps_fullyNested`: 9:00–11:00 が先、10:00–10:30 が後 → 前者のみ
    - `testFilterOverlaps_noOverlap`: 9:00–10:00 と 10:00–11:00（端接触）→ 両方残る
    - `testMake_excludesAllDay`: all-day flag 付きの raw → 除外される
    - `testMake_combined`: all-day + 日跨ぎ + 重なりが混在 → 全ルール適用後の正規化結果
- ファイル: `Sources/Toki/Domain/DayTimeline.swift`（新規）
  ```swift
  import Foundation

  struct DayTimeline {
      let date: Date
      let events: [Event]  // start 昇順、同 start は end 昇順

      init(date: Date, events: [Event]) {
          self.date = date
          self.events = events.sorted { lhs, rhs in
              if lhs.start != rhs.start { return lhs.start < rhs.start }
              return lhs.end < rhs.end
          }
      }

      func currentEvent(at now: Date) -> Event? {
          events.first { $0.status(at: now) == .current }
      }

      func nextEvent(after now: Date) -> Event? {
          events.first { $0.start > now }
      }

      static func clip(_ event: Event, toDayOf date: Date, calendar: Calendar) -> Event?
      static func filterOverlaps(_ events: [Event]) -> [Event]
      static func make(date: Date, rawEvents: [Event], allDayFlags: [Bool], calendar: Calendar) -> DayTimeline
  }
  ```
  - `clip`：今日の `startOfDay`〜翌日の `startOfDay` と event 範囲の交差を計算、交差なしは nil、交差を新 Event で返す（id 保持）
  - `filterOverlaps`：start 昇順走査、`lastEnd` を持って `event.start < lastEnd` ならスキップ、それ以外は採用して `lastEnd = event.end` 更新
  - `make`：`zip(rawEvents, allDayFlags)` で `!isAllDay` のみ抽出 → 各 event を `clip` → nil を除く → `filterOverlaps` → `DayTimeline(date:events:)` 構築

**完了条件**:
- [ ] `swift test` で `DayTimelineTests` が pass（14 ケース）
- [ ] `swift build` が通る
- [ ] `DayTimeline.swift` は Foundation のみ import

**依存**: Task 3, Task 4

---

## Task 6: Infrastructure `EventKitGateway` 骨格（権限要求 + 今日の取得）

**Commit**: `feat(infra): EventKitGateway 骨格（権限要求と今日のイベント取得）`

**目的**: EventKit と Domain を繋ぐ Gateway の最小限を作る。権限要求と今日のイベント取得まで。変換と購読は後続 task。

**コンテキスト**:
- 参照: spec §「カレンダー連携」/ plan §5「Infrastructure layer detail」/ SPEC.md §7「EventKit 権限要求」
- 前提: macOS 14+ なので `requestFullAccessToEvents()` を使う（`requestAccess(to:)` は deprecated）
- 設計：protocol は切らない（CLAUDE.md「protocol を念のため切らない」）。Combine Publisher 経由で外に公開するが本 task では `fetchTodayTimeline()` のみ実装

**実装内容**:
- ファイル: `Sources/Toki/Infrastructure/EventKitGateway.swift`（新規）
  ```swift
  import Foundation
  import EventKit
  import Combine

  enum AccessResult {
      case granted, denied
      case error(Error)
  }

  final class EventKitGateway {
      private let store = EKEventStore()
      private let calendar: Calendar
      init(calendar: Calendar = .current) { self.calendar = calendar }

      func requestAccess() async -> AccessResult {
          do {
              let granted = try await store.requestFullAccessToEvents()
              return granted ? .granted : .denied
          } catch {
              return .error(error)
          }
      }

      func fetchTodayTimeline() async -> DayTimeline {
          let start = calendar.startOfDay(for: Date())
          let end = calendar.date(byAdding: .day, value: 1, to: start)!
          let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
          let ekEvents = store.events(matching: predicate)
          // Task 7 で変換を実装、ここでは空の DayTimeline を返す
          return DayTimeline(date: start, events: [])
      }
  }
  ```

**完了条件**:
- [ ] `swift build` が通る
- [ ] `Sources/Toki/main.swift` をテスト用に書き換えて以下を確認（後で revert / Task 14 で削除）：
  ```swift
  Task {
      let gw = EventKitGateway()
      let result = await gw.requestAccess()
      print("Access: \(result)")
      let tl = await gw.fetchTodayTimeline()
      print("Timeline events: \(tl.events.count)")  // 0 でよい、Task 7 で実装
      exit(0)
  }
  RunLoop.main.run()
  ```
  - **`./scripts/build-app.sh && open .build/Toki.app`** で実機実行 → 権限ダイアログが表示される（許可後は何も起きずに終了でよい）
- [ ] `swift run` ではなく `.app` バンドル経由で実行することを確認

**依存**: Task 1, Task 5

---

## Task 7: Infrastructure `EKEvent → Event` 変換

**Commit**: `feat(infra): EKEvent → Event 変換と DayTimeline 構築`

**目的**: 取得した `EKEvent` 配列を Domain の `Event` + all-day flag に変換し、`DayTimeline.make` に渡す。

**コンテキスト**:
- 参照: plan §5「Infrastructure layer detail / 責務」/ Open Question #12「recurring id 合成」
- 確定済み：`id = "\(eventIdentifier ?? UUID().uuidString)#\(startDate.timeIntervalSince1970)"`、`externalIdentifier = eventIdentifier`
- 防御：nil タイトル、0 分以下は捨てる（`Event` の failable init で自動的に弾かれるが事前にチェック）

**実装内容**:
- ファイル: `Sources/Toki/Infrastructure/EventKitGateway.swift`（編集）
  - `fetchTodayTimeline()` を書き換え：
    ```swift
    func fetchTodayTimeline() async -> DayTimeline {
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let ekEvents = store.events(matching: predicate)

        var rawEvents: [Event] = []
        var allDayFlags: [Bool] = []
        for ek in ekEvents {
            guard let event = Self.convert(ek) else { continue }
            rawEvents.append(event)
            allDayFlags.append(ek.isAllDay)
        }
        return DayTimeline.make(date: start, rawEvents: rawEvents,
                                allDayFlags: allDayFlags, calendar: calendar)
    }

    private static func convert(_ ek: EKEvent) -> Event? {
        let baseId = ek.eventIdentifier ?? UUID().uuidString
        let id = "\(baseId)#\(ek.startDate.timeIntervalSince1970)"
        return Event(
            id: id,
            title: ek.title ?? "(無題)",
            start: ek.startDate,
            end: ek.endDate,
            calendarColor: ek.calendar.cgColor,
            externalIdentifier: ek.eventIdentifier
        )
    }
    ```

**完了条件**:
- [ ] `swift build` が通る
- [ ] `main.swift` の確認コードを実行（`.app` 経由）：`print("Timeline events: \(tl.events.count)")` が 0 以上の現実的な数（自分のカレンダーに今日の予定があれば > 0）
- [ ] `EKEvent` は Gateway 内部のみで触り、外には `Event` / `DayTimeline` のみ返ることをコードレビュー

**依存**: Task 6

---

## Task 8: Infrastructure 変更通知購読 + Publisher 公開

**Commit**: `feat(infra): EKEventStoreChanged 購読と timelineUpdates Publisher 公開`

**目的**: カレンダー変更を購読し、300ms debounce を挟んで自動再 fetch、結果を Publisher 経由で外に公開。

**コンテキスト**:
- 参照: spec §「カレンダー連携」最後 / plan §5「Infrastructure layer detail」/ Open Question #10「300ms debounce」
- 設計：`CurrentValueSubject<DayTimeline, Never>` で最新値を保持、`AnyPublisher<DayTimeline, Never>` で公開

**実装内容**:
- ファイル: `Sources/Toki/Infrastructure/EventKitGateway.swift`（編集）
  - プロパティ追加：
    ```swift
    private let subject = CurrentValueSubject<DayTimeline, Never>(
        DayTimeline(date: Date(), events: [])
    )
    private var cancellables = Set<AnyCancellable>()

    var timelineUpdates: AnyPublisher<DayTimeline, Never> {
        subject.eraseToAnyPublisher()
    }
    ```
  - メソッド追加：
    ```swift
    func start() {
        NotificationCenter.default
            .publisher(for: .EKEventStoreChanged, object: store)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.reload() }
            }
            .store(in: &cancellables)
        Task { await reload() }  // 初回ロード
    }

    func stop() {
        cancellables.removeAll()
    }

    private func reload() async {
        let timeline = await fetchTodayTimeline()
        subject.send(timeline)
    }
    ```

**完了条件**:
- [ ] `swift build` が通る
- [ ] `main.swift` の確認コードを更新：`gw.start()` を呼び、`gw.timelineUpdates.sink { print("Update: \($0.events.count) events") }.store(in: &cs)` で購読、`.app` 経由で起動して「初回ロード後にカレンダー.app でイベント追加 → ~300ms 後に Toki 側のログに新しい count が出る」ことを目視確認
- [ ] `start()` を 2 回呼ばれても多重購読しないことをコードで確認（`cancellables.removeAll()` を冒頭に入れるか、フラグで防御）

**依存**: Task 7

---

## Task 9: Window `FloatingClockWindow`

**Commit**: `feat(window): FloatingClockWindow（borderless + floating + canBecomeKey=false）`

**目的**: ボーダーレス・常時前面・全 Space 表示の NSWindow サブクラスとファクトリ。

**コンテキスト**:
- 参照: spec §「ウィンドウ・常駐挙動」/ plan §8「FloatingClockWindow」/ SPEC.md §7「Floating Window セットアップ」/ Open Question #13「canBecomeKey OFF」
- 仕様：280×320、borderless、`.floating` レベル、`[.canJoinAllSpaces, .stationary, .ignoresCycle]`、背景透明、影あり、背景ドラッグ可、key window にならない

**実装内容**:
- ファイル: `Sources/Toki/Window/FloatingClockWindow.swift`（新規）
  ```swift
  import AppKit
  import SwiftUI

  final class FloatingClockWindow: NSWindow {
      override var canBecomeKey: Bool { false }
      override var canBecomeMain: Bool { false }

      static func make<Content: View>(contentView: Content) -> FloatingClockWindow {
          let w = FloatingClockWindow(
              contentRect: NSRect(x: 0, y: 0, width: 280, height: 320),
              styleMask: [.borderless, .fullSizeContentView],
              backing: .buffered,
              defer: false
          )
          w.level = .floating
          w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
          w.isOpaque = false
          w.backgroundColor = .clear
          w.hasShadow = true
          w.isMovableByWindowBackground = true
          w.contentView = NSHostingView(rootView: contentView)
          return w
      }
  }
  ```

**完了条件**:
- [ ] `swift build` が通る
- [ ] 単独ではまだ実行確認できないが、Task 10 と組み合わせて検証する

**依存**: Task 1

---

## Task 10: App `TokiApp` + `AppDelegate`（空ウィンドウ + メニューバー）

**Commit**: `feat(app): TokiApp + AppDelegate でメニューバー常駐と空ウィンドウ表示`

**目的**: メニューバーアイコンクリックでウィンドウをトグル表示するアプリ骨格。中身は空のプレースホルダ View、ViewModel はまだ繋がない。

**コンテキスト**:
- 参照: spec §「ウィンドウ・常駐挙動」/ plan §8「TokiApp / AppDelegate」/ 確定済み：初回位置はメイン画面の右上 16px インセット
- 仕様：`@main` から AppKit ライフサイクル、SwiftUI `App` プロトコルは使わない、`setActivationPolicy(.accessory)` で Dock 二重ガード

**実装内容**:
- ファイル: `Sources/Toki/App/TokiApp.swift`（新規）
  ```swift
  import AppKit

  @main
  enum TokiApp {
      static func main() {
          let app = NSApplication.shared
          let delegate = AppDelegate()
          app.delegate = delegate
          app.setActivationPolicy(.accessory)
          app.run()
      }
  }
  ```
- ファイル: `Sources/Toki/App/AppDelegate.swift`（新規）
  ```swift
  import AppKit
  import SwiftUI

  final class AppDelegate: NSObject, NSApplicationDelegate {
      private var window: FloatingClockWindow?
      private var statusItem: NSStatusItem?

      func applicationDidFinishLaunching(_ notification: Notification) {
          // 暫定のプレースホルダ View（Task 14 で ClockView に差し替え）
          let placeholder = Text("Toki")
              .frame(width: 280, height: 320)
              .background(Color(NSColor.windowBackgroundColor))
          window = FloatingClockWindow.make(contentView: placeholder)

          if let screen = NSScreen.main, let w = window {
              let frame = screen.visibleFrame
              let origin = NSPoint(
                  x: frame.maxX - w.frame.width - 16,
                  y: frame.maxY - w.frame.height - 16
              )
              w.setFrameOrigin(origin)
          }
          window?.orderFrontRegardless()

          let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
          item.button?.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "Toki")
          item.button?.action = #selector(toggleWindow)
          item.button?.target = self
          statusItem = item
      }

      @objc private func toggleWindow() {
          guard let w = window else { return }
          if w.isVisible { w.orderOut(nil) } else { w.orderFrontRegardless() }
      }
  }
  ```
- ファイル: `Sources/Toki/main.swift`（削除）
  - `@main` が AppDelegate 側に移ったため不要

**完了条件**:
- [ ] `swift build` が通る
- [ ] `./scripts/build-app.sh && open .build/Toki.app` で起動
  - メニューバーに時計アイコンが表示される
  - Dock にアイコンが出ない
  - 起動時に右上にウィンドウが表示される
  - 背景ドラッグでウィンドウが動く
  - メニューバーアイコンクリックで表示/非表示がトグル
  - Mission Control で別の Space に切替えてもウィンドウが見える（`.canJoinAllSpaces + .stationary` の検証）
  - 他のアプリをアクティブにしても Toki ウィンドウが最前面に残る

**依存**: Task 9

---

## Task 11: UI `ClockGeometry` + `ClockFaceCanvas`（時計盤 + 針 + マーク）

**Commit**: `feat(ui): ClockGeometry と ClockFaceCanvas 骨格（時刻マークと針）`

**目的**: イベント円弧抜きの時計盤を描画。中心・内外径などの幾何データを構造化、時刻マーク 0/6/12/18 と現在時刻針を描く。

**コンテキスト**:
- 参照: spec §「時計描画」/ plan §6「ClockFaceCanvas」/ SPEC.md §2 UI 仕様、§7 Canvas で annulus
- 仕様：24 時間時計、0:00 真上、時計回り、内径 110 / 外径 130、針は中心から外径 130 まで、針の z-index は最上位

**実装内容**:
- ファイル: `Sources/Toki/UI/ClockGeometry.swift`（新規）
  ```swift
  import CoreGraphics

  struct ClockGeometry {
      let center: CGPoint
      let innerRadius: CGFloat
      let outerRadius: CGFloat
      static func standard(in size: CGSize) -> ClockGeometry {
          ClockGeometry(
              center: CGPoint(x: size.width / 2, y: size.height / 2),
              innerRadius: 110,
              outerRadius: 130
          )
      }
  }
  ```
- ファイル: `Sources/Toki/UI/ClockFaceCanvas.swift`（新規）
  ```swift
  import SwiftUI

  struct ClockFaceCanvas: View {
      let now: Date
      // Task 12 でイベント円弧を追加、Task 14 で events を引数に追加

      var body: some View {
          Canvas { ctx, size in
              let geom = ClockGeometry.standard(in: size)
              drawHourMarks(in: &ctx, geometry: geom)
              drawHand(in: &ctx, geometry: geom, now: now)
          }
      }

      private func drawHourMarks(in ctx: inout GraphicsContext, geometry: ClockGeometry) {
          // 0/6/12/18 の位置に数字を描く
          // 角度計算：TimeOfDay(hour: H, minute: 0)!.clockAngle で取得
          // 描画位置：center + cos(angle) * (outerR + 8) のような外側オフセット
      }

      private func drawHand(in ctx: inout GraphicsContext, geometry: ClockGeometry, now: Date) {
          let tod = TimeOfDay.from(date: now)
          let angle = tod.clockAngle
          let end = CGPoint(
              x: geometry.center.x + cos(angle) * geometry.outerRadius,
              y: geometry.center.y + sin(angle) * geometry.outerRadius
          )
          var path = Path()
          path.move(to: geometry.center)
          path.addLine(to: end)
          ctx.stroke(path, with: .color(.primary), lineWidth: 1.5)
      }
  }
  ```

**完了条件**:
- [ ] `swift build` が通る
- [ ] AppDelegate のプレースホルダを `ClockFaceCanvas(now: Date()).frame(width: 280, height: 280)` に一時差し替え（次 task で戻す）して `.app` 起動 → 時計盤（0/6/12/18 のマーク + 現在時刻を指す針）が見えることを目視確認
- [ ] 針の角度が現在時刻と合っている（例：15:00 なら右下方向）

**依存**: Task 2, Task 10

---

## Task 12: UI `EventArcRenderer` + `RenderableEvent`

**Commit**: `feat(ui): EventArcRenderer と RenderableEvent で円弧描画とヒットテスト`

**目的**: イベントの annulus segment 描画ロジック（free function 群）と、UI 表示に必要な情報をまとめた `RenderableEvent` 型。

**コンテキスト**:
- 参照: spec §「イベント円弧」/ plan §6「EventArcRenderer」/ SPEC.md §7「SwiftUI Canvas で annulus segment」
- 設計：struct ではなく free function（CLAUDE.md「protocol を念のため切らない」、状態を持たない）
- 状態別 alpha：past 0.3、current 1.0 + 0.75px アウトライン、future 1.0

**実装内容**:
- ファイル: `Sources/Toki/UI/RenderableEvent.swift`（新規）
  ```swift
  import CoreGraphics

  struct RenderableEvent: Identifiable, Equatable {
      let id: String
      let title: String
      let startAngle: Double
      let endAngle: Double
      let color: CGColor
      let status: EventStatus
      let externalIdentifier: String?

      static func == (lhs: RenderableEvent, rhs: RenderableEvent) -> Bool { lhs.id == rhs.id }
  }
  ```
- ファイル: `Sources/Toki/UI/EventArcRenderer.swift`（新規）
  ```swift
  import SwiftUI
  import CoreGraphics

  func annulusPath(center: CGPoint, innerR: CGFloat, outerR: CGFloat,
                   startAngle: Double, endAngle: Double) -> Path {
      var path = Path()
      path.addArc(center: center, radius: outerR,
                  startAngle: .radians(startAngle), endAngle: .radians(endAngle),
                  clockwise: false)
      path.addArc(center: center, radius: innerR,
                  startAngle: .radians(endAngle), endAngle: .radians(startAngle),
                  clockwise: true)
      path.closeSubpath()
      return path
  }

  func drawEventArc(in ctx: inout GraphicsContext, event: RenderableEvent, geometry: ClockGeometry) {
      let path = annulusPath(
          center: geometry.center,
          innerR: geometry.innerRadius,
          outerR: geometry.outerRadius,
          startAngle: event.startAngle,
          endAngle: event.endAngle
      )
      let baseColor = Color(cgColor: event.color)
      let alpha: Double = event.status == .past ? 0.3 : 1.0
      ctx.fill(path, with: .color(baseColor.opacity(alpha)))
      if event.status == .current {
          ctx.stroke(path, with: .color(baseColor.opacity(0.8)), lineWidth: 0.75)
      }
  }

  func hitTest(point: CGPoint, events: [RenderableEvent], geometry: ClockGeometry) -> RenderableEvent? {
      for event in events {
          let path = annulusPath(
              center: geometry.center,
              innerR: geometry.innerRadius,
              outerR: geometry.outerRadius,
              startAngle: event.startAngle,
              endAngle: event.endAngle
          )
          if path.contains(point) { return event }
      }
      return nil
  }
  ```
- ファイル: `Sources/Toki/UI/ClockFaceCanvas.swift`（編集）
  - `events: [RenderableEvent]` を引数追加
  - `drawHourMarks` と `drawHand` の間に：
    ```swift
    // past を先、current を最後（アウトラインを上に）
    let sorted = events.sorted { lhs, rhs in
        statusOrder(lhs.status) < statusOrder(rhs.status)
    }
    for ev in sorted { drawEventArc(in: &ctx, event: ev, geometry: geom) }
    ```
  - `private func statusOrder(_ s: EventStatus) -> Int { s == .past ? 0 : s == .future ? 1 : 2 }`

**完了条件**:
- [ ] `swift build` が通る
- [ ] AppDelegate のプレースホルダで以下のハードコード `events` を渡して目視確認（次 task で戻す）：
  - past（過去）/ current（進行中、現在時刻が含まれるもの）/ future（未来）の 3 件
  - past は薄く（alpha 0.3）、current にアウトラインが見える、future は通常濃度
  - 円弧が時計盤の外周（内径 110〜外径 130）に正しく描画される
  - 針が円弧の上に重なる（z-index 最上位）

**依存**: Task 11, Task 5

---

## Task 13: UI `CurrentEventLabel` + `NextEventLine`

**Commit**: `feat(ui): CurrentEventLabel と NextEventLine 実装`

**目的**: 中央 3 行テキストと下部「次の予定」1 行を表示する dumb View。

**コンテキスト**:
- 参照: spec §「中央テキスト」「次の予定ライン」/ plan §6「CurrentEventLabel / NextEventLine」/ SPEC.md §2「中央テキスト」「下部 次の予定」
- 仕様：
  - 中央：現在時刻 11px tertiary / イベント名 15px primary weight 500 / 残り時間 11px tertiary（予定中）または「—」 / 「次まで XX 分」（空き時間）
  - 次の予定：左「次」secondary 11px、右「HH:MM タイトル」secondary 11px、truncationMode .tail

**実装内容**:
- ファイル: `Sources/Toki/UI/CurrentEventLabel.swift`（新規）
  ```swift
  import SwiftUI

  enum CenterState: Equatable {
      case duringEvent(time: String, title: String, remaining: String)
      case freeTime(time: String, subtitle: String)  // "次まで 30分" / "予定なし" / "権限が必要"
  }

  struct CurrentEventLabel: View {
      let state: CenterState
      var body: some View {
          VStack(spacing: 2) {
              switch state {
              case .duringEvent(let time, let title, let remaining):
                  Text(time).font(.system(size: 11)).foregroundStyle(.tertiary)
                  Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
                      .lineLimit(1).truncationMode(.tail)
                  Text(remaining).font(.system(size: 11)).foregroundStyle(.tertiary)
              case .freeTime(let time, let subtitle):
                  Text(time).font(.system(size: 11)).foregroundStyle(.tertiary)
                  Text("—").font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
                  Text(subtitle).font(.system(size: 11)).foregroundStyle(.tertiary)
              }
          }
      }
  }
  ```
- ファイル: `Sources/Toki/UI/NextEventLine.swift`（新規）
  ```swift
  import SwiftUI

  struct NextLineState: Equatable {
      let timeHHMM: String  // "16:00"
      let title: String
  }

  struct NextEventLine: View {
      let state: NextLineState?
      var body: some View {
          if let s = state {
              HStack {
                  Text("次").font(.system(size: 11)).foregroundStyle(.secondary)
                  Spacer()
                  Text("\(s.timeHHMM) \(s.title)")
                      .font(.system(size: 11)).foregroundStyle(.secondary)
                      .lineLimit(1).truncationMode(.tail)
              }
              .padding(.horizontal, 16)
          } else {
              Color.clear
          }
      }
  }
  ```

**完了条件**:
- [ ] `swift build` が通る
- [ ] AppDelegate のプレースホルダで各 state パターンを目視確認（次 task で統合）：
  - `CurrentEventLabel(state: .duringEvent(...))` で 3 行が想定通り
  - `CurrentEventLabel(state: .freeTime(time:"14:30", subtitle:"次まで 30分"))` で「—」中央表示
  - `NextEventLine(state: .init(timeHHMM:"16:00", title:"ENEOS実装"))` で 1 行表示
  - `NextEventLine(state: nil)` で非表示

**依存**: Task 11

---

## Task 14: UI `ClockView` 統合（ハードコードデータで描画）

**Commit**: `feat(ui): ClockView 統合とハードコード Event でのフル描画確認`

**目的**: `ClockFaceCanvas` + `CurrentEventLabel` + `NextEventLine` を `ClockView` に統合し、AppDelegate のプレースホルダと差し替え。ハードコード Event 配列でフル描画を目視確認。

**コンテキスト**:
- 参照: plan §6「ClockView」/ SPEC.md §2 UI 仕様
- 仕様：VStack で時計エリア（ZStack: Canvas + 中央 Label）+ Divider + NextEventLine

**実装内容**:
- ファイル: `Sources/Toki/UI/ClockView.swift`（新規）
  ```swift
  import SwiftUI

  struct ClockView: View {
      let events: [RenderableEvent]
      let now: Date
      let centerState: CenterState
      let nextLineState: NextLineState?

      var body: some View {
          VStack(spacing: 0) {
              ZStack {
                  ClockFaceCanvas(now: now, events: events)
                  CurrentEventLabel(state: centerState)
              }
              .frame(width: 280, height: 280)
              Divider().frame(height: 0.5)
              NextEventLine(state: nextLineState)
                  .frame(height: 40)
          }
          .frame(width: 280, height: 320)
          .background(Color(NSColor.windowBackgroundColor))
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .overlay(
              RoundedRectangle(cornerRadius: 12)
                  .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
          )
      }
  }
  ```
- ファイル: `Sources/Toki/App/AppDelegate.swift`（編集）
  - プレースホルダを `ClockView(...)` に差し替え。**ハードコードデータ**で組み立て：
    - 今日の 9:00–10:00（past）/ 今の時刻を含む 1 時間（current）/ 17:00–18:00（future）の `RenderableEvent` を 3 件
    - `centerState` は `.duringEvent` または `.freeTime` を仮設定
    - `nextLineState` は仮設定
  - 配色は `CGColor` で適当な色を 3 つ用意（赤・青・緑）
  - 後続 Task 16 で ViewModel 経由に差し替えるため「ハードコード」コメントを残す

**完了条件**:
- [ ] `swift build` が通る
- [ ] `./scripts/build-app.sh && open .build/Toki.app` で起動
  - 時計、3 つの円弧（past 薄い・current 太枠・future 通常）、中央 3 行テキスト、下部「次」行が全て見える
  - 280×320 の角丸ウィンドウになっており、はみ出さない
  - 右上 16px インセットに表示される
  - 背景ドラッグで移動できる
- [ ] スクリーンショットを撮って spec のイメージと大きく乖離していないこと

**依存**: Task 11, Task 12, Task 13

---

## Task 15: Composition `ClockViewModel`

**Commit**: `feat(composition): ClockViewModel 実装（@Published 状態と派生 + タイマー + wake 対応）`

**目的**: Gateway と UI を繋ぐ ViewModel。`@Published` で `now` / `timeline` / `accessGranted` を持ち、computed property で View 用の state を派生。1 分タイマーと sleep/wake 対応。

**コンテキスト**:
- 参照: plan §7「ClockViewModel」/ SPEC.md §7「1 分タイマーの精度」「EventKit の変更購読」/ Open Question #11「sleep/wake 復帰」
- 仕様：
  - `Timer.publish(every: 60)` の前に次の `:00` までの差分だけ `asyncAfter`
  - `NSWorkspace.didWakeNotification` で `now` を即時補正 + タイマー再アライン
  - `gateway.timelineUpdates` を `assign(to: &$timeline)`

**実装内容**:
- ファイル: `Sources/Toki/Composition/ClockViewModel.swift`（新規）
  ```swift
  import Foundation
  import AppKit
  import Combine
  import SwiftUI

  @MainActor
  final class ClockViewModel: ObservableObject {
      @Published private(set) var now: Date = Date()
      @Published private(set) var timeline: DayTimeline? = nil
      @Published private(set) var accessGranted: Bool = false

      private let gateway: EventKitGateway
      private let calendar: Calendar
      private var cancellables = Set<AnyCancellable>()
      private var minuteTimerCancellable: AnyCancellable?

      init(gateway: EventKitGateway, calendar: Calendar = .current) {
          self.gateway = gateway
          self.calendar = calendar
      }

      func start() async {
          let result = await gateway.requestAccess()
          accessGranted = (result == .granted)
          gateway.start()
          gateway.timelineUpdates
              .receive(on: DispatchQueue.main)
              .sink { [weak self] tl in self?.timeline = tl }
              .store(in: &cancellables)
          scheduleMinuteTimer()
          NSWorkspace.shared.notificationCenter
              .publisher(for: NSWorkspace.didWakeNotification)
              .sink { [weak self] _ in
                  self?.now = Date()
                  self?.scheduleMinuteTimer()
                  Task { await self?.gateway.start() }  // 必要なら reload
              }
              .store(in: &cancellables)
      }

      private func scheduleMinuteTimer() {
          minuteTimerCancellable?.cancel()
          let nowDate = Date()
          let seconds = 60 - calendar.component(.second, from: nowDate)
          DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) { [weak self] in
              guard let self else { return }
              self.now = Date()
              self.minuteTimerCancellable = Timer.publish(every: 60, on: .main, in: .common)
                  .autoconnect()
                  .sink { [weak self] _ in self?.now = Date() }
          }
      }

      // 派生 state
      var canvasEvents: [RenderableEvent] {
          guard let tl = timeline else { return [] }
          return tl.events.map { ev in
              RenderableEvent(
                  id: ev.id,
                  title: ev.title,
                  startAngle: TimeOfDay.from(date: ev.start, calendar: calendar).clockAngle,
                  endAngle: TimeOfDay.from(date: ev.end, calendar: calendar).clockAngle,
                  color: ev.calendarColor,
                  status: ev.status(at: now),
                  externalIdentifier: ev.externalIdentifier
              )
          }
      }

      var centerState: CenterState {
          let timeStr = Self.formatHHMM(now, calendar: calendar)
          if !accessGranted { return .freeTime(time: timeStr, subtitle: "権限が必要") }
          guard let tl = timeline else { return .freeTime(time: timeStr, subtitle: "読み込み中") }
          if let cur = tl.currentEvent(at: now) {
              let remaining = Int(ceil(cur.end.timeIntervalSince(now) / 60))
              return .duringEvent(time: timeStr, title: cur.title, remaining: "残り \(remaining)分")
          }
          if let nxt = tl.nextEvent(after: now) {
              let until = Int(ceil(nxt.start.timeIntervalSince(now) / 60))
              return .freeTime(time: timeStr, subtitle: "次まで \(until)分")
          }
          return .freeTime(time: timeStr, subtitle: "予定なし")
      }

      var nextLineState: NextLineState? {
          guard accessGranted, let tl = timeline, let nxt = tl.nextEvent(after: now) else { return nil }
          return NextLineState(timeHHMM: Self.formatHHMM(nxt.start, calendar: calendar), title: nxt.title)
      }

      private static func formatHHMM(_ date: Date, calendar: Calendar) -> String {
          let c = calendar.dateComponents([.hour, .minute], from: date)
          return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
      }
  }
  ```

**完了条件**:
- [ ] `swift build` が通る
- [ ] `Composition/ClockViewModel.swift` は EventKit を直接 import しない（Gateway 経由のみ）
- [ ] `RenderableEvent` の `endAngle < startAngle` の場合（日跨ぎ clip 後は発生しない想定だが）を考慮しなくて OK（DayTimeline.make で clip 済み）

**依存**: Task 5, Task 8, Task 12, Task 13

---

## Task 16: App AppDelegate を ViewModel 経由に差し替え

**Commit**: `refactor(app): AppDelegate を ClockViewModel + EventKitGateway 経由に差し替え`

**目的**: Task 14 のハードコードを外し、実際の EventKit データで動作する状態にする。

**コンテキスト**:
- 参照: plan §8「AppDelegate」/ plan §10「Phase 1e」
- 仕様：`EventKitGateway` を作って `ClockViewModel` に注入、`ClockView` は ViewModel を `@ObservedObject` で受け取る

**実装内容**:
- ファイル: `Sources/Toki/UI/ClockView.swift`（編集）
  - `let events: [RenderableEvent]` 等の個別引数をやめ、`@ObservedObject var viewModel: ClockViewModel` を受け取る形に変更：
    ```swift
    struct ClockView: View {
        @ObservedObject var viewModel: ClockViewModel
        var body: some View {
            VStack(spacing: 0) {
                ZStack {
                    ClockFaceCanvas(now: viewModel.now, events: viewModel.canvasEvents)
                    CurrentEventLabel(state: viewModel.centerState)
                }
                .frame(width: 280, height: 280)
                Divider().frame(height: 0.5)
                NextEventLine(state: viewModel.nextLineState)
                    .frame(height: 40)
            }
            // 残りの修飾は同じ
        }
    }
    ```
- ファイル: `Sources/Toki/App/AppDelegate.swift`（編集）
  - プロパティ追加：`private var gateway: EventKitGateway?`、`private var viewModel: ClockViewModel?`
  - `applicationDidFinishLaunching` を書き換え：
    ```swift
    let gw = EventKitGateway()
    let vm = ClockViewModel(gateway: gw)
    gateway = gw
    viewModel = vm
    window = FloatingClockWindow.make(contentView: ClockView(viewModel: vm))
    // 位置設定は同じ
    window?.orderFrontRegardless()
    Task { await vm.start() }
    // StatusBar 設定は同じ
    ```
  - ハードコードの `RenderableEvent` 配列、`CenterState`、`NextLineState` は全て削除

**完了条件**:
- [ ] `swift build` が通る
- [ ] `./scripts/build-app.sh && open .build/Toki.app` で起動
  - 初回起動なら EventKit 権限ダイアログ → 許可
  - 今日のカレンダーイベントが時計に円弧で表示される
  - 中央 3 行が現在の状況（進行中なら残り時間、空きなら次まで）に応じて表示される
  - 下部に次の予定が表示される（今日もう予定がなければ空欄）
- [ ] カレンダー.app で今日のイベントを追加 → 数百 ms 後に Toki に反映される
- [ ] PC をスリープして復帰 → 針が正しい時刻を指す
- [ ] 1 分待つと針が進む（次の `:00` でカクつかない）

**依存**: Task 14, Task 15

---

## Task 17: UI イベント円弧クリックで純正カレンダー.app を開く

**Commit**: `feat(ui): イベント円弧クリックで純正カレンダー.app を該当イベントで開く`

**目的**: spec AC「イベントクリック」を実装。クリック位置をヒットテストし、対応イベントの `externalIdentifier` で `ical://ekevent/...` を開く。

**コンテキスト**:
- 参照: spec §「イベントクリック」/ SPEC.md §7「純正カレンダー.app を特定イベントで開く」/ plan §7「クリックハンドラ」
- 仕様：`hitTest` で `RenderableEvent` を特定 → `NSWorkspace.shared.open(URL(string: "ical://ekevent/\(extID)?method=show&options=more"))`
- 注意：URL scheme は非公式、動かなければ `NSWorkspace.shared.open(URL(string: "ical:")!)` で fallback

**実装内容**:
- ファイル: `Sources/Toki/Composition/ClockViewModel.swift`（編集）
  - メソッド追加：
    ```swift
    func handleArcTap(at point: CGPoint, geometry: ClockGeometry) {
        guard let event = hitTest(point: point, events: canvasEvents, geometry: geometry) else { return }
        guard let extID = event.externalIdentifier,
              let url = URL(string: "ical://ekevent/\(extID)?method=show&options=more") else { return }
        if !NSWorkspace.shared.open(url) {
            // fallback: カレンダー.app を起動だけする
            if let fallback = URL(string: "ical:") {
                NSWorkspace.shared.open(fallback)
            }
        }
    }
    ```
- ファイル: `Sources/Toki/UI/ClockFaceCanvas.swift`（編集）
  - 引数追加：`var onTap: ((CGPoint, ClockGeometry) -> Void)? = nil`
  - `Canvas` を `GeometryReader` でラップし、`.onTapGesture(coordinateSpace: .local)` で位置を取得：
    ```swift
    GeometryReader { proxy in
        Canvas { ctx, size in /* 既存の描画 */ }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(coordinateSpace: .local)
                    .onEnded { value in
                        let geom = ClockGeometry.standard(in: proxy.size)
                        onTap?(value.location, geom)
                    }
            )
    }
    ```
  - `SpatialTapGesture` は iOS 16 / macOS 13+ で利用可能、本プロジェクトは macOS 14+ なので OK
- ファイル: `Sources/Toki/UI/ClockView.swift`（編集）
  - `ClockFaceCanvas` の呼び出しに `onTap: { point, geom in viewModel.handleArcTap(at: point, geometry: geom) }` を追加

**完了条件**:
- [ ] `swift build` が通る
- [ ] `./scripts/build-app.sh && open .build/Toki.app` で起動
  - 今日のイベント円弧をクリック → 純正カレンダー.app が前面に出て該当イベントが選択される（または開く）
  - クリック位置がリング外なら何も起きない（無音）
  - URL scheme が無視された場合でも少なくともカレンダー.app は起動する（fallback 確認）
- [ ] `canBecomeKey = false` を守ったまま動作する（Toki ウィンドウが key window にならず、クリックがフォーカス奪いの副作用を起こさない）

**依存**: Task 16

---

## 全 task 完了後

- `code-reviewer` agent で全体レビューを実行
  - 特にチェック：依存方向（Domain ← Infrastructure / UI、UI が Infrastructure 直接参照していないか）、`EKEvent` の Domain 漏れがないか、protocol を不要に切っていないか、ファイル長 < 400 行
- レビュー結果をもとに修正があれば追加 task として積む
- 修正完了後、SPEC.md §9「.app バンドル化は MVP では不要」を実態（最初から .app バンドル化）に合わせて修正
- README.md に「`./scripts/build-app.sh && open .build/Toki.app` で起動」を追記
- main ブランチへマージ
