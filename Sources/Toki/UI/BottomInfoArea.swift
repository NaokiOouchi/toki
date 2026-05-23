import SwiftUI

/// 時計の下に表示する情報エリア。spec 013 改修で導入。
/// 通常は priority に応じて 1 行だけ表示し、hover で全行を「下に伸ばして」展開する。
///
/// テキスト行が将来増える対策として collapsible UI を採用：
/// - 通常時は最小フットプリント（1 行のみ、最終更新は非表示）
/// - hover で詳細展開、フットプリントが必要なときだけ伸びる
/// - 新しい row 種別を追加しても collapsed 表示は変わらない
///
/// 表示優先度（actionable な情報を優先）：
///   1. 次の予定（あれば、最も actionable）
///   2. 終日 event（次の予定が無いとき）
///   3. （いずれも nil なら）最終更新のみ右端に表示
///
/// hover 振動対策：境界線上の cursor 揺れで window が無限に伸び縮みするのを防ぐため、
/// 出方向（true → false）に 350ms の grace period を設けて吸収する。
struct BottomInfoArea: View {
    @ObservedObject var viewModel: ClockViewModel
    var textScale: CGFloat = 1.0
    /// hover 状態の変化通知（spec 013 改修）。
    /// AppDelegate がこれを受けて NSWindow を下方向に伸ばす（時計領域を保つため）。
    var onHoverChanged: (Bool) -> Void = { _ in }

    @State private var isHovered = false
    /// hover 状態変化の debounce 用 work item。境界揺れによる無限振動を防ぐ。
    @State private var hoverWorkItem: DispatchWorkItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            primaryRow
            if isHovered {
                extraRows
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        // hover を取りやすくするため透明な hit-test 領域を確保
        .contentShape(Rectangle())
        .onHover { hovering in
            // 非対称 debounce：入りは即時応答、出は 350ms 待つことで
            // 境界線上の cursor 揺れによる window 振動を吸収する
            hoverWorkItem?.cancel()
            let delay: Double = hovering ? 0.05 : 0.35
            let work = DispatchWorkItem {
                guard isHovered != hovering else { return }
                isHovered = hovering
                onHoverChanged(hovering)
            }
            hoverWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
        // 「下に伸びる」感じの展開アニメーション（NSWindow.setFrame の animate と並走）
        .animation(.easeInOut(duration: 0.2), value: isHovered)
    }

    /// 通常表示の 1 行。priority: 次の予定 > 終日 > 最終更新のみ。
    /// 次の予定が一番 actionable なので優先、終日は補助情報として扱う。
    /// 最終更新は通常 1 行には表示せず、hover 展開時の最終行で見せる。
    /// ただし event が何もない時は最終更新を primary に出す（hover で詳細が無いため）。
    @ViewBuilder
    private var primaryRow: some View {
        if viewModel.nextLineState != nil {
            NextEventLine(state: viewModel.nextLineState,
                          lastUpdatedText: nil,
                          textScale: textScale)
        } else if let allDay = viewModel.allDayLineState {
            AllDayEventLine(state: allDay,
                            lastUpdatedText: nil,
                            textScale: textScale)
        } else {
            // event が無い時：最終更新だけを常時表示（hover で追加情報なし）
            NextEventLine(state: nil,
                          lastUpdatedText: viewModel.lastUpdatedFormatted,
                          textScale: textScale)
        }
    }

    /// 展開時のみ表示する追加行。primary に出ていない情報を補完する。
    /// 最終更新は最終行に右寄せで表示（hover 時にだけ見える）。
    /// 将来 row 種別（明日 / 緊急 alert 等）が増えてもここに追加するだけ。
    @ViewBuilder
    private var extraRows: some View {
        // primary が next の時、終日があれば補助表示
        if viewModel.nextLineState != nil, let allDay = viewModel.allDayLineState {
            AllDayEventLine(state: allDay,
                            lastUpdatedText: nil,
                            textScale: textScale)
        }
        // event があるときの最終更新（hover 時のみ末尾表示、event がないときは primary に出てる）
        if (viewModel.nextLineState != nil || viewModel.allDayLineState != nil),
           let text = viewModel.lastUpdatedFormatted {
            HStack {
                Spacer()
                Text(text)
                    .font(.system(size: 9 * textScale))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
        }
    }
}
