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
        let calendars = try await fetchCalendarIds(token: token)
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

    /// ユーザーの calendar list を取得し、calendar.id 配列を返す。
    private func fetchCalendarIds(token: String) async throws -> [String] {
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
        return items.compactMap { $0["id"] as? String }
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
}
