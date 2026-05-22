import Foundation

/// イベント参加者を表す Value Object。
/// Google Calendar API の `attendees[]` 1 件分に相当。
/// `email` を実質 id として扱い、Hashable で Set 重複排除を可能にする。
struct Attendee: Equatable, Hashable {
    let email: String
    let displayName: String?
    let responseStatus: ResponseStatus

    /// 表示用名前。displayName 優先、無ければ email を返す。
    var displayLabel: String {
        if let name = displayName, !name.isEmpty { return name }
        return email
    }
}

/// 参加可否ステータス。Google API の `responseStatus` 文字列に対応。
/// 値：accepted / declined / tentative / needsAction / unknown。
enum ResponseStatus: String, Equatable {
    case accepted
    case declined
    case tentative
    case needsAction
    case unknown

    /// API 文字列から enum を解決する。nil / 未知値は `.unknown`。
    static func from(apiString: String?) -> ResponseStatus {
        guard let s = apiString else { return .unknown }
        return ResponseStatus(rawValue: s) ?? .unknown
    }
}
