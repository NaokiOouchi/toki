import CoreGraphics
import Foundation

/// Google Calendar API クライアント。
/// iCalUID から event detail URL（htmlLink）を取得することに特化する。
/// 認証は GoogleOAuthClient に委譲、本クラスはトークンを使った REST 呼び出しのみ。
final class GoogleCalendarAPI {
    enum APIError: Error {
        case invalidResponse
        case invalidURL
    }

    private let oauth: GoogleOAuthClient
    private let session: URLSession

    private static let baseURL = "https://www.googleapis.com/calendar/v3"

    init(oauth: GoogleOAuthClient, session: URLSession = .shared) {
        self.oauth = oauth
        self.session = session
    }

    /// 複数の iCalUID に対して各 calendar を並列検索し、htmlLink マップを返す。
    /// 該当なし / API エラーの場合は map に含めない（silent fail）。
    func fetchHTMLLinks(forICalUIDs uids: [String]) async throws -> [String: URL] {
        guard !uids.isEmpty else { return [:] }
        let token = try await oauth.getValidAccessToken()
        let calendars = try await fetchCalendars(token: token).map { $0.id }
        guard !calendars.isEmpty else { return [:] }

        return await withTaskGroup(of: (String, URL?).self) { group in
            for uid in uids {
                group.addTask {
                    let url = await self.findHTMLLink(uid: uid,
                                                      calendars: calendars,
                                                      token: token)
                    return (uid, url)
                }
            }
            var result: [String: URL] = [:]
            for await (uid, url) in group {
                if let url { result[uid] = url }
            }
            return result
        }
    }

    /// ユーザーの calendar list を取得し、id / summary / backgroundColor を含む配列を返す。
    private func fetchCalendars(token: String) async throws -> [GoogleAPICalendar] {
        guard let url = URL(string: "\(Self.baseURL)/users/me/calendarList") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await session.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            throw APIError.invalidResponse
        }
        return items.compactMap { item -> GoogleAPICalendar? in
            guard let id = item["id"] as? String else { return nil }
            let summary = (item["summary"] as? String) ?? id
            let bgHex = (item["backgroundColor"] as? String) ?? "#808080"
            return GoogleAPICalendar(id: id, summary: summary,
                                     backgroundColor: Self.cgColor(fromHex: bgHex))
        }
    }

    /// 指定 uid について全 calendar を順次試し、最初に htmlLink を返した結果を採用する。
    /// 取得失敗 / 該当なしは nil を返す。
    private func findHTMLLink(uid: String,
                              calendars: [String],
                              token: String) async -> URL? {
        for calendarId in calendars {
            if let url = await fetchHTMLLink(uid: uid,
                                             calendarId: calendarId,
                                             token: token) {
                return url
            }
        }
        return nil
    }

    /// events.list?iCalUID=<uid>&singleEvents=true を呼び、items[0].htmlLink を返す。
    /// 404 / 該当なし / パース失敗は nil 返却（silent fail）。
    private func fetchHTMLLink(uid: String,
                               calendarId: String,
                               token: String) async -> URL? {
        let encodedCalendar = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        let encodedUID = uid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? uid
        let urlStr = "\(Self.baseURL)/calendars/\(encodedCalendar)/events?iCalUID=\(encodedUID)&singleEvents=true"
        guard let url = URL(string: urlStr) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await session.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]],
                  let first = items.first,
                  let htmlLink = first["htmlLink"] as? String,
                  let resultURL = URL(string: htmlLink) else { return nil }
            return resultURL
        } catch {
            return nil
        }
    }

    /// 今日の event を全 calendar 横断で並列取得する。
    /// 各 calendar の `events.list?timeMin=...&timeMax=...&singleEvents=true&orderBy=startTime` を並列実行し、
    /// 親 calendar の summary / color を詰めて GoogleAPIEvent 配列で返す。
    /// 個別 calendar 失敗は空配列で扱う（silent fail）。
    func fetchTodayEvents(timeMin: Date, timeMax: Date) async throws -> [GoogleAPIEvent] {
        let token = try await oauth.getValidAccessToken()
        let calendars = try await fetchCalendars(token: token)
        guard !calendars.isEmpty else { return [] }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let minStr = isoFormatter.string(from: timeMin)
        let maxStr = isoFormatter.string(from: timeMax)

        return await withTaskGroup(of: [GoogleAPIEvent].self) { group in
            for cal in calendars {
                group.addTask {
                    await self.fetchEvents(in: cal, timeMin: minStr,
                                           timeMax: maxStr, token: token)
                }
            }
            var result: [GoogleAPIEvent] = []
            for await events in group { result.append(contentsOf: events) }
            return result
        }
    }

    /// 1 つの calendar から event を取得する。失敗は空配列。
    private func fetchEvents(in cal: GoogleAPICalendar,
                             timeMin: String, timeMax: String,
                             token: String) async -> [GoogleAPIEvent] {
        let encodedId = cal.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cal.id
        let urlStr = "\(Self.baseURL)/calendars/\(encodedId)/events?timeMin=\(timeMin)&timeMax=\(timeMax)&singleEvents=true&orderBy=startTime&maxResults=250"
        guard let url = URL(string: urlStr) else { return [] }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await session.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else { return [] }
            return items.compactMap { Self.parseEvent($0, calendar: cal) }
        } catch {
            return []
        }
    }

    /// event JSON を GoogleAPIEvent に変換する。必須欠落は nil。
    private static func parseEvent(_ item: [String: Any],
                                   calendar cal: GoogleAPICalendar) -> GoogleAPIEvent? {
        guard let id = item["id"] as? String,
              let iCalUID = item["iCalUID"] as? String,
              let startDict = item["start"] as? [String: Any],
              let endDict = item["end"] as? [String: Any] else { return nil }
        let summary = (item["summary"] as? String) ?? "(無題)"
        let htmlLink = (item["htmlLink"] as? String).flatMap { URL(string: $0) }
        return GoogleAPIEvent(
            id: id,
            iCalUID: iCalUID,
            summary: summary,
            start: parseEventDate(startDict),
            end: parseEventDate(endDict),
            htmlLink: htmlLink,
            calendarSummary: cal.summary,
            calendarColor: cal.backgroundColor
        )
    }

    /// `{"dateTime":"2026-05-21T10:00:00+09:00"}` or `{"date":"2026-05-21"}` を変換。
    private static func parseEventDate(_ dict: [String: Any]) -> GoogleAPIEventDate {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let dateTime = (dict["dateTime"] as? String).flatMap { isoFormatter.date(from: $0) }

        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateOnlyFormatter.timeZone = TimeZone.current
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        let date = (dict["date"] as? String).flatMap { dateOnlyFormatter.date(from: $0) }

        return GoogleAPIEventDate(dateTime: dateTime, date: date)
    }

    /// HEX 文字列（`#RRGGBB`）を CGColor に変換。失敗時は gray。
    private static func cgColor(fromHex hex: String) -> CGColor {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            return CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        }
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        return CGColor(red: r, green: g, blue: b, alpha: 1)
    }
}

/// Google Calendar API から取得した event を、Domain 変換前に保持する中間型。
struct GoogleAPIEvent {
    let id: String
    let iCalUID: String
    let summary: String
    let start: GoogleAPIEventDate
    let end: GoogleAPIEventDate
    let htmlLink: URL?
    let calendarSummary: String
    let calendarColor: CGColor
}

/// event の start / end は `dateTime`（時刻付き）または `date`（終日）のどちらか。
struct GoogleAPIEventDate {
    let dateTime: Date?
    let date: Date?
}

/// calendarList の 1 件分。id 以外に summary と背景色を保持する。
struct GoogleAPICalendar {
    let id: String
    let summary: String
    let backgroundColor: CGColor
}
