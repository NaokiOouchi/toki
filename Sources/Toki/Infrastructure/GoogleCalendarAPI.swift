import CoreGraphics
import Foundation

/// Google Calendar API クライアント。
/// 今日の event を全 calendar 横断で取得することに特化する。
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

    /// 1 つの calendar から event を取得する。
    /// 401（token 失効）のときのみ getValidAccessToken() で 1 回 retry。
    /// それ以外の non-2xx は log + 空配列。network error も log + 空配列。
    private func fetchEvents(in cal: GoogleAPICalendar,
                             timeMin: String, timeMax: String,
                             token initialToken: String) async -> [GoogleAPIEvent] {
        let encodedId = cal.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cal.id
        let urlStr = "\(Self.baseURL)/calendars/\(encodedId)/events?timeMin=\(timeMin)&timeMax=\(timeMax)&singleEvents=true&orderBy=startTime&maxResults=250"
        guard let url = URL(string: urlStr) else { return [] }

        var token = initialToken
        // attempt=0: 初回, attempt=1: 401 直後の retry。
        for attempt in 0..<2 {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            do {
                let (data, response) = try await session.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

                if statusCode == 401 && attempt == 0 {
                    // token 失効: 新 token で 1 回だけ retry
                    do {
                        token = try await oauth.getValidAccessToken()
                        continue
                    } catch {
                        print("GoogleCalendarAPI fetchEvents: 401 refresh failed: \(error)")
                        return []
                    }
                }
                if !(200...299).contains(statusCode) {
                    print("GoogleCalendarAPI fetchEvents: status \(statusCode) for calendar \(cal.id)")
                    return []
                }
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let items = json["items"] as? [[String: Any]] else { return [] }
                return items.compactMap { Self.parseEvent($0, calendar: cal) }
            } catch {
                print("GoogleCalendarAPI fetchEvents network error: \(error)")
                return []
            }
        }
        return []
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
