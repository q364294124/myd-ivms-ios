// MARK: - API 客户端（JWT 鉴权 + 全端点 + SSE 事件流）
// 对齐服务端 2026-11-05 契约：
//   · 登录必须带 clientVersion:"1.1.0"（双端版本门禁）；
//   · 视频流 URL 走 access_token 查询串（Program.cs 白名单，浏览器/<img>/播放器同约定）；
//   · SDK 回放时间 = UTC "yyyy-MM-ddTHH:mm:ss"（toISO 无 Z，服务端解析后按本地语义用，
//     与 Web 端 toISOString().slice(0,19) 完全一致）；GB 录像/回放时间 = 本地时间。

import Foundation
import UIKit

final class ApiClient {
    static let shared = ApiClient()

    private(set) var baseURL = URL(string: "http://192.168.1.7:5299")!
    private(set) var token: String?
    private(set) var permissions: Set<String> = []
    private(set) var isAdmin = false

    private let session: URLSession
    private let decoder = JSONDecoder()

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 120
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
    }

    // MARK: 登录态

    var isLoggedIn: Bool { token != nil }

    func configure(baseURL: URL, token: String, permissions: [String], isAdmin: Bool) {
        self.baseURL = baseURL
        self.token = token
        self.permissions = Set(permissions)
        self.isAdmin = isAdmin
        Self.persist(baseURL: baseURL, token: token, permissions: permissions, isAdmin: isAdmin)
    }

    func restore() -> Bool {
        guard let raw = UserDefaults.standard.string(forKey: "server.url"),
              let t = UserDefaults.standard.string(forKey: "server.token") else { return false }
        guard let url = URL(string: raw), url.scheme?.hasPrefix("http") == true else { return false }
        baseURL = url
        token = t
        permissions = Set(UserDefaults.standard.stringArray(forKey: "server.perms") ?? [])
        isAdmin = UserDefaults.standard.bool(forKey: "server.isAdmin")
        return true
    }

    private static func persist(baseURL: URL, token: String, permissions: [String], isAdmin: Bool) {
        let d = UserDefaults.standard
        d.set(baseURL.absoluteString, forKey: "server.url")
        d.set(token, forKey: "server.token")
        d.set(permissions, forKey: "server.perms")
        d.set(isAdmin, forKey: "server.isAdmin")
    }

    func logout() {
        token = nil
        permissions = []
        UserDefaults.standard.removeObject(forKey: "server.token")
    }

    func hasPerm(_ p: String) -> Bool { isAdmin || permissions.contains(p) }

    // MARK: 底层请求

    private func request(_ path: String, method: String = "GET", body: Data? = nil,
                         query: [URLQueryItem] = []) throws -> URLRequest {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }

    private func send<T: Decodable>(_ type: T.Type, _ req: URLRequest) async throws -> T {
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ApiError.network("非 HTTP 响应") }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { logout(); throw ApiError.unauthorized }
            if let err = try? decoder.decode(ApiErrorBody.self, from: data) {
                throw ApiError.server(err.error)
            }
            throw ApiError.server("HTTP \(http.statusCode)")
        }
        return try decoder.decode(T.self, from: data)
    }

    private func get<T: Decodable>(_ type: T.Type, _ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(type, request(path, query: query))
    }

    private func post<T: Decodable>(_ type: T.Type, _ path: String, _ body: some Encodable,
                                    query: [URLQueryItem] = []) async throws -> T {
        try await send(type, request(path, method: "POST", body: try JSONEncoder().encode(body), query: query))
    }

    // MARK: 认证

    func login(server: URL, username: String, password: String) async throws -> LoginResponse {
        baseURL = server
        let resp = try await post(LoginResponse.self, "api/auth/login",
                                  LoginRequest(username: username, password: password))
        configure(baseURL: server, token: resp.token, permissions: resp.permissions, isAdmin: resp.isAdmin)
        return resp
    }

    // MARK: 设备与通道

    func devices() async throws -> [DeviceDto] { try await get([DeviceDto].self, "api/devices") }

    func channelNames() async throws -> ChannelNames { try await get(ChannelNames.self, "api/osd/names") }

    // MARK: 流地址（播放器直接用；access_token 查询串与服务端白名单约定一致）

    func liveFlvUrl(deviceId: Int, channel: Int, sub: Int = 1) -> URL {
        URL(string: "\(baseURL)/api/live/\(deviceId)/\(channel)/ps.flv?sub=\(sub)&access_token=\(token!)")!
    }

    /// SDK 回放起播 → FLV 地址
    func sdkPlaybackStart(deviceId: Int, channel: Int, start: Date, end: Date, sub: Int = 1) async throws -> URL {
        struct StartResp: Decodable { let httpFlvUrl: String }
        struct StartReq: Encodable { let startTime: String; let endTime: String; let subStream: Int }
        let f = ISO8601_utc.string(from: start), e = ISO8601_utc.string(from: end)
        let r = try await post(StartResp.self, "api/playback/\(deviceId)/\(channel)/start",
                               StartReq(startTime: f, endTime: e, subStream: sub))
        guard let url = URL(string: r.httpFlvUrl) else { throw ApiError.server("回放地址无效") }
        return url
    }

    func sdkPlaybackStop(deviceId: Int, channel: Int) async {
        _ = try? try? await send(Empty.self,
                            request("api/playback/\(deviceId)/\(channel)/stop", method: "POST",
                                    body: Data("{}".utf8)))
    }

    func sdkPlaybackFiles(deviceId: Int, channel: Int, day: Date) async throws -> [RecordingFile] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        struct RawFile: Decodable { let start: String; let end: String; let name: String? }
        let raw = try await get([RawFile].self, "api/playback/\(deviceId)/\(channel)/files", query: [
            .init(name: "start", value: ISO8601_utc.string(from: dayStart)),
            .init(name: "end", value: ISO8601_utc.string(from: dayEnd)),
        ])
        return raw.compactMap { f in
            guard let s = parseUtc(f.start), let e = parseUtc(f.end) else { return nil }
            return RecordingFile(name: f.name ?? "", start: s, end: e)
        }
    }

    // MARK: GB28181 录像（本地时间口径）

    func gbRecords(deviceId: Int, channel: Int, day: Date) async throws -> [RecordingFile] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        struct RawSeg: Decodable { let start: String; let end: String; let name: String? }
        let raw = try await get([RawSeg].self, "api/gb/records", query: [
            .init(name: "deviceId", value: String(deviceId)),
            .init(name: "channel", value: String(channel)),
            .init(name: "start", value: localFmt.string(from: dayStart)),
            .init(name: "end", value: localFmt.string(from: dayEnd)),
        ])
        return raw.compactMap { f in
            guard let s = parseLocal(f.start), let e = parseLocal(f.end) else { return nil }
            return RecordingFile(name: f.name ?? "", start: s, end: e)
        }
    }

    func gbPlaybackFlvUrl(deviceId: Int, channel: Int, start: Date, end: Date) -> URL {
        URL(string: "\(baseURL)/api/gb/playback/\(deviceId)/\(channel)/ps.flv"
            + "?start=\(localFmt.string(from: start).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)"
            + "&end=\(localFmt.string(from: end).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)"
            + "&access_token=\(token!)")!
    }

    // MARK: 报警

    func alarmHistory(count: Int = 100) async throws -> [AlarmDto] {
        try await get([AlarmDto].self, "api/alarms/history", query: [.init(name: "count", value: String(count))])
    }

    // MARK: 云台

    func ptz(deviceId: Int, channel: Int, command: String, speed: Int = 4, preset: Int? = nil) async throws {
        let body = PtzRequest(command: command, speed: speed, preset: preset)
        _ = try await post(Empty.self, "api/devices/\(deviceId)/ptz", body,
                           query: [.init(name: "channel", value: String(channel))])
    }

    // MARK: 平面图

    func mapFloors() async throws -> [MapFloorDto] { try await get([MapFloorDto].self, "api/map/floors") }

    func mapMarkers(floorId: Int) async throws -> [MapMarkerDto] {
        try await get([MapMarkerDto].self, "api/map/floors/\(floorId)/markers")
    }

    func mapImage(_ imageUrl: String) async throws -> UIImage {
        var req = URLRequest(url: URL(string: imageUrl.hasPrefix("http")
            ? imageUrl : "\(baseURL)\(imageUrl)?access_token=\(token!)")!)
        req.setValue("Bearer \(token ?? "")", forHTTPHeaderField: "Authorization")
        let (data, _) = try await session.data(for: req)
        guard let img = UIImage(data: data) else { throw ApiError.server("平面图图片解码失败") }
        return img
    }

    // MARK: 事件流（SSE：GET /api/events/stream，data: {...} 行）

    /// 长连接读 SSE。返回的 AsyncThrowingStream 在任务取消时结束。
    /// 事件体形如 {"type":"alarm",...} / {"topic":"devices",...}，这里原样透传 JSON 给上层宽松解析。
    func eventStream() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let token else { throw ApiError.unauthorized }
                    var req = URLRequest(url: baseURL.appendingPathComponent("api/events/stream"))
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    req.timeoutInterval = .infinity
                    let (bytes, resp) = try await session.bytes(for: req)
                    guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                        throw ApiError.server("事件流连接失败")
                    }
                    for try await line in bytes.lines {
                        if line.hasPrefix(":") { continue }               // 心跳注释
                        if line.hasPrefix("data:") {
                            // 服务端只发 data: 行（无 event: 名），事件类型在 JSON 的 source 字段里
                            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            if !payload.isEmpty { continuation.yield(payload) }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: 时间格式（两套口径，勿混）

    /// SDK 回放口径：UTC 无 Z（与 Web toISOString().slice(0,19) 一致）
    private let ISO8601_utc: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// GB 口径：本地时间 yyyy-MM-ddTHH:mm:ss（服务端 DateTime 直接按本地解析）
    private let localFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func parseUtc(_ s: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; f.timeZone = TimeZone(identifier: "UTC"); f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
    private func parseLocal(_ s: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; f.timeZone = .current; f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }
}

/// 占位类型（不关心响应体的请求复用）
struct Empty: Codable {}

enum ApiError: LocalizedError {
    case network(String), unauthorized, server(String)

    var errorDescription: String? {
        switch self {
        case .network(let m): return "网络错误：\(m)"
        case .unauthorized: return "登录已过期，请重新登录"
        case .server(let m): return m
        }
    }
}

