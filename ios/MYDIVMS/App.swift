// MARK: - 应用入口与全局状态（2026-11-05 iOS 原生客户端）
// 功能对齐 WPF/安卓端第一版：登录 → 设备树实时预览(VLCKit) / 录像回放 / 报警 / 平面图。

import SwiftUI

@main
struct MYDIVMSApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.dark)      // 监控场景深色优先（设置页可跟随系统）
        }
    }
}

/// 全局状态：登录态 + 设备/通道名缓存 + 报警红点 + SSE 长连接
@MainActor
final class AppState: ObservableObject {
    @Published var loggedIn = false
    @Published var devices: [DeviceDto] = []
    @Published var chanNames: ChannelNames = [:]
    @Published var unreadAlarms = 0
    @Published var connectionLost = false

    private var streamTask: Task<Void, Never>?

    init() {
        if ApiClient.shared.restore() {
            loggedIn = true
            Task { await bootstrap() }
        }
    }

    /// 登录后/启动时拉基础数据 + 挂事件流
    func bootstrap() async {
        async let devs: Void = refreshDevices()
        async let names: Void = refreshChanNames()
        _ = (devs, names)
        startEventStream()
    }

    func refreshDevices() async {
        do { devices = try await ApiClient.shared.devices() }
        catch { connectionLost = true }
    }

    func refreshChanNames() async {
        chanNames = (try? await ApiClient.shared.channelNames()) ?? [:]
    }

    func channelTitle(_ devId: Int, _ ch: Int) -> String {
        if let n = chanNames[String(devId)]?[String(ch)], !n.isEmpty { return n }
        let dev = devices.first { $0.id == devId }
        return "\(dev?.name ?? "设备") 通道\(ch)"
    }

    // MARK: 事件流（断线 5s 自动重连；报警事件推红点并刷新列表）

    func startEventStream() {
        streamTask?.cancel()
        streamTask = Task {
            while !Task.isCancelled {
                do {
                    connectionLost = false
                    for try await raw in ApiClient.shared.eventStream() {
                        guard let d = raw.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
                        // 服务端 EventStream：报警事件带 id/time/type；通知信封 source=="notice"（topic 分流）
                        if obj["source"] as? String == "notice" {
                            if (obj["topic"] as? String) == "devices" { await refreshDevices() }
                        } else if obj["id"] != nil {
                            unreadAlarms += 1
                            NotificationCenter.default.post(name: .newAlarm, object: nil)
                        }
                    }
                } catch { /* 断流，走重连 */ }
                connectionLost = true
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func stopEventStream() { streamTask?.cancel(); streamTask = nil }
}

extension Notification.Name {
    static let newAlarm = Notification.Name("myd.newAlarm")
}
