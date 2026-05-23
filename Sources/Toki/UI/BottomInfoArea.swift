import SwiftUI

/// 時計の下に表示する情報エリア。spec 013 改修で導入。
/// 通常は priority に応じて 1 行だけ表示し、hover で全行を「下に伸ばして」展開する。
///
/// テキスト行が将来増える対策として collapsible UI を採用：
/// - 通常時は最小フットプリント（1 行 + 右端の最終更新）
/// - hover で詳細展開、フットプリントが必要なときだけ伸びる
/// - 新しい row 種別を追加しても collapsed 表示は変わらない
///
/// 表示優先度：
///   1. 終日 event（あれば）
///   2. 次の予定（あれば）
///   3. （いずれも nil なら）最終更新だけ右端に表示
struct BottomInfoArea: View {
    @ObservedObject var viewModel: ClockViewModel
    var textScale: CGFloat = 1.0

    @State private var isHovered = false

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
            isHovered = hovering
        }
        // 「下に伸びる」感じの展開アニメーション
        .animation(.easeInOut(duration: 0.2), value: isHovered)
    }

    /// 通常表示の 1 行。priority: 終日 > 次の予定 > 最終更新のみ。
    /// 右端には常に「最終更新 X 分前」を既存挙動踏襲で表示。
    @ViewBuilder
    private var primaryRow: some View {
        if let allDay = viewModel.allDayLineState {
            AllDayEventLine(state: allDay,
                            lastUpdatedText: viewModel.lastUpdatedFormatted,
                            textScale: textScale)
        } else {
            NextEventLine(state: viewModel.nextLineState,
                          lastUpdatedText: viewModel.lastUpdatedFormatted,
                          textScale: textScale)
        }
    }

    /// 展開時のみ表示する追加行。primary に出ていない情報を補完する。
    /// 将来 row 種別（明日 / 緊急 alert 等）が増えてもここに追加するだけ。
    @ViewBuilder
    private var extraRows: some View {
        // primary が allDay の時、次の予定を追加表示（重複した最終更新は出さない）
        if viewModel.allDayLineState != nil, viewModel.nextLineState != nil {
            NextEventLine(state: viewModel.nextLineState,
                          lastUpdatedText: nil,
                          textScale: textScale)
        }
    }
}
