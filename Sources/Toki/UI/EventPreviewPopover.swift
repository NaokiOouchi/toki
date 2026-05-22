import SwiftUI

/// 円弧クリック時に表示される event 詳細 popover の presentation View。
/// 整形済み文字列とアクションコールバックを受け取り描画のみ行う（純粋 View）。
/// `tokiGlassBackground` で Liquid Glass / Material 背景を適用。
struct EventPreviewPopover: View {
    let timeLabel: String           // "14:00 - 15:00"
    let title: String
    let location: String?
    let attendees: [Attendee]
    let note: String?
    let hasMeetURL: Bool
    let hasCalendarURL: Bool
    var textScale: CGFloat = 1.0

    let onOpenMeet: () -> Void
    let onOpenCalendar: () -> Void
    let onClose: () -> Void

    /// 参加者表示の上限。超過分は「他 N 名」表示。
    private static let attendeeDisplayLimit = 5

    /// note の最大文字数。超過時は省略 `…`。
    private static let noteMaxChars = 200

    /// note の最大表示行数。
    private static let noteMaxLines = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            titleSection
            if let location, !location.isEmpty {
                locationSection(location)
            }
            if !attendees.isEmpty {
                attendeesSection
            }
            if let note, !note.isEmpty {
                noteSection(note)
            }
            actionButtons
        }
        .padding(12)
        .frame(minWidth: 200, idealWidth: 280, maxWidth: 400,
               minHeight: 140, maxHeight: 500, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .tokiGlassBackground(cornerRadius: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.35), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
    }

    /// ヘッダー：時刻範囲 + × ボタン（ESC でも close）。
    private var header: some View {
        HStack {
            Text(timeLabel)
                .font(.system(size: 11 * textScale))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14 * textScale))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
    }

    /// タイトル（最大 2 行、超過は省略 …）。
    private var titleSection: some View {
        Text(title)
            .font(.system(size: 13 * textScale, weight: .medium))
            .lineLimit(2)
            .truncationMode(.tail)
    }

    /// 場所行（地図ピン SF Symbol + 1 行）。
    private func locationSection(_ location: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 10 * textScale))
                .foregroundStyle(.secondary)
            Text(location)
                .font(.system(size: 11 * textScale))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// 参加者リスト（5 名上限 + 「他 N 名」、status SF Symbol 付き）。
    private var attendeesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("参加者")
                .font(.system(size: 10 * textScale))
                .foregroundStyle(.tertiary)
            ForEach(Array(attendees.prefix(Self.attendeeDisplayLimit).enumerated()), id: \.offset) { _, attendee in
                HStack(spacing: 4) {
                    Image(systemName: Self.statusSymbolName(attendee.responseStatus))
                        .font(.system(size: 10 * textScale))
                        .foregroundStyle(.secondary)
                    Text(attendee.displayLabel)
                        .font(.system(size: 11 * textScale))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            if attendees.count > Self.attendeeDisplayLimit {
                Text("他 \(attendees.count - Self.attendeeDisplayLimit) 名")
                    .font(.system(size: 10 * textScale))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// description セクション（200 文字 / 3 行でトリム）。
    private func noteSection(_ note: String) -> some View {
        Text(Self.truncatedNote(note))
            .font(.system(size: 11 * textScale))
            .foregroundStyle(.secondary)
            .lineLimit(Self.noteMaxLines)
            .truncationMode(.tail)
    }

    /// アクションボタン Row：Meet / Calendar、それぞれ URL 有無で表示制御。
    private var actionButtons: some View {
        HStack(spacing: 8) {
            if hasMeetURL {
                Button(action: onOpenMeet) {
                    Label("Meet で開く", systemImage: "video.fill")
                        .font(.system(size: 11 * textScale))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if hasCalendarURL {
                Button(action: onOpenCalendar) {
                    Label("Calendar で開く", systemImage: "calendar")
                        .font(.system(size: 11 * textScale))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Spacer()
        }
    }

    /// 200 文字を超える note を `…` でトリム。
    /// 行数制限は SwiftUI の `.lineLimit` に任せる。
    private static func truncatedNote(_ text: String) -> String {
        if text.count <= noteMaxChars { return text }
        let endIndex = text.index(text.startIndex, offsetBy: noteMaxChars)
        return String(text[..<endIndex]) + "…"
    }

    /// ResponseStatus に対応する SF Symbol 名。
    private static func statusSymbolName(_ status: ResponseStatus) -> String {
        switch status {
        case .accepted: return "checkmark.circle.fill"
        case .declined: return "xmark.circle.fill"
        case .tentative: return "questionmark.circle.fill"
        case .needsAction, .unknown: return "circle"
        }
    }
}
