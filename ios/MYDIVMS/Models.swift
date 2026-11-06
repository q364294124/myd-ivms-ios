// MARK: - 数据模型（与服务端 API 契约一一对应，2026-11-05）
// 命名对齐服务端 JSON（camelCase），解码用默认策略即可。

import Foundation

// MARK: 登录

struct LoginRequest: Encodable {
    let username: String
    let password: String
    /// 双端版本门禁（2026-11-04）：服务端要求上报 1.1.0
    let clientVersion = "1.1.0"
}

struct LoginResponse: Decodable {
    let token: String
    let username: String
    let role: String
    let displayName: String?
    let permissions: [String]
    let isAdmin: Bool
}

// MARK: 设备与通道

struct DeviceDto: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let ip: String
    /// hik / gb / onvif / proxy
    let protocol_: String?
    /// cvr（纯存储）不参与预览/回放树
    let devClass: String?
    let channelCount: Int
    let channelsCsv: String?
    let online: Bool?
    let sdkOnline: Bool?

    var isGb: Bool { (protocol_ ?? "").lowercased() == "gb" }
    var isCvr: Bool { (devClass ?? "").lowercased() == "cvr" }

    enum CodingKeys: String, CodingKey {
        case id, name, ip, devClass, channelCount, channelsCsv, online, sdkOnline
        case protocol_ = "protocol"
    }

    /// 通道号清单（channelsCsv 优先，回退 1..channelCount）
    var channels: [Int] {
        if let csv = channelsCsv, !csv.isEmpty {
            return csv.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { $0 > 0 }
        }
        return Array(1...max(1, channelCount))
    }
}

/// 通道名映射：GET /api/osd/names → { "devId": { "ch": "name" } }
typealias ChannelNames = [String: [String: String]]

// MARK: 报警

struct AlarmDto: Decodable, Identifiable {
    let id: Int64
    let time: String
    let deviceId: Int
    let channel: Int
    let type: String
    let detail: String?
    let imageUrl: String?
    let deviceName: String?
    let handled: Bool?
}

// MARK: 录像（SDK 与 GB 两种口径）

struct RecordingFile: Identifiable, Decodable {
    let name: String
    let start: Date
    let end: Date
    var id: String { "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)" }
}

// MARK: 平面图

struct MapFloorDto: Decodable, Identifiable, Equatable {
    let id: Int
    let name: String
    let sort: Int
    let markers: Int
    let imageUrl: String
}

struct MapMarkerDto: Decodable, Identifiable, Equatable {
    let id: Int
    let deviceId: Int
    let channel: Int
    let deviceName: String
    let name: String
    let online: Bool
    let x: Double      // 图片宽度百分比 0~100
    let y: Double
}

// MARK: 云台

struct PtzRequest: Encodable {
    let command: String     // Stop/Up/Down/Left/Right/UpLeft/UpRight/DownLeft/DownRight/ZoomIn/ZoomOut
    let speed: Int          // 1~7
    var preset: Int?
}

// MARK: 服务端错误体 { error: "..." }

struct ApiErrorBody: Decodable { let error: String }
