import Foundation
import Network

/// OAuth Loopback IP redirect を受領するための loopback HTTP server。
/// `http://localhost:<port>/callback?code=...&state=...` を 1 接続だけ待ち、
/// state を検証してから code を返す。
final class LoopbackOAuthReceiver {
    enum ReceiverError: Error {
        case bindFailed
        case missingCode
        case stateMismatch
        case malformedRequest
    }

    /// 指定ポートで listener を起動し、code を返す。
    /// 1 接続受領後に listener は自動停止する。
    /// state 検証で CSRF を防ぐ。
    func waitForCode(port: UInt16, expectedState: String) async throws -> String {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ReceiverError.bindFailed
        }
        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp, on: nwPort)
        } catch {
            throw ReceiverError.bindFailed
        }
        return try await withCheckedThrowingContinuation { continuation in
            listener.newConnectionHandler = { [weak listener] connection in
                Self.handle(connection: connection, expectedState: expectedState) { result in
                    listener?.cancel()
                    continuation.resume(with: result)
                }
                connection.start(queue: .global())
            }
            listener.start(queue: .global())
        }
    }

    /// 1 接続を処理して結果を返す。
    /// 成功時はブラウザに「接続完了」HTML を返し、エラー時は HTTP 400 を返す。
    private static func handle(connection: NWConnection,
                               expectedState: String,
                               completion: @escaping (Result<String, Error>) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
            defer { connection.cancel() }
            guard let data, let request = String(data: data, encoding: .utf8) else {
                Self.sendResponse(connection: connection, status: 400, body: "Bad Request")
                completion(.failure(ReceiverError.malformedRequest))
                return
            }
            let firstLine = request.components(separatedBy: "\r\n").first ?? ""
            guard let pathQuery = Self.extractPathQuery(from: firstLine) else {
                Self.sendResponse(connection: connection, status: 400, body: "Bad Request")
                completion(.failure(ReceiverError.malformedRequest))
                return
            }
            let params = Self.parseQuery(pathQuery)
            guard let code = params["code"] else {
                Self.sendResponse(connection: connection, status: 400, body: "Missing code")
                completion(.failure(ReceiverError.missingCode))
                return
            }
            guard params["state"] == expectedState else {
                Self.sendResponse(connection: connection, status: 400, body: "State mismatch")
                completion(.failure(ReceiverError.stateMismatch))
                return
            }
            Self.sendResponse(connection: connection,
                              status: 200,
                              body: "<html><body>Toki: 接続完了。このタブを閉じてください。</body></html>")
            completion(.success(code))
        }
    }

    /// HTTP request line（`GET /callback?... HTTP/1.1`）からクエリ部分を抽出する。
    private static func extractPathQuery(from requestLine: String) -> String? {
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        let target = parts[1]
        guard let qIndex = target.firstIndex(of: "?") else { return nil }
        return String(target[target.index(after: qIndex)...])
    }

    /// `key=value&key=value` 形式のクエリ文字列を辞書にパースする。
    /// URL エンコードは標準的な percent decode で復元。
    private static func parseQuery(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in query.components(separatedBy: "&") {
            let kv = pair.components(separatedBy: "=")
            guard kv.count == 2,
                  let key = kv[0].removingPercentEncoding,
                  let value = kv[1].removingPercentEncoding else { continue }
            result[key] = value
        }
        return result
    }

    /// HTTP レスポンスを 1 行で組み立てて送信する。
    private static func sendResponse(connection: NWConnection, status: Int, body: String) {
        let statusText = status == 200 ? "OK" : "Bad Request"
        let response = "HTTP/1.1 \(status) \(statusText)\r\n" +
                       "Content-Type: text/html; charset=utf-8\r\n" +
                       "Content-Length: \(body.utf8.count)\r\n" +
                       "Connection: close\r\n\r\n\(body)"
        connection.send(content: response.data(using: .utf8),
                        completion: .contentProcessed { _ in })
    }
}
