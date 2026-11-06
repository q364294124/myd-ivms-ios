// MARK: - 云台摇杆（8 向按压 + 松开停 + 变倍），走 POST /api/devices/{id}/ptz?channel=

import SwiftUI

struct PtzPad: View {
    @Environment(\.dismiss) private var dismiss
    let deviceId: Int
    let channel: Int
    let title: String
    @State private var speed = 4
    @State private var busy = false
    @State private var err = ""

    var body: some View {
        VStack(spacing: 14) {
            Text(title).font(.headline).lineLimit(1)
            Text("按住转动 · 松开停止 · 速度 \(speed)").font(.caption).foregroundStyle(.secondary)
            ZStack {
                Circle().fill(.quaternary).frame(width: 190, height: 190)
                VStack(spacing: 46) {
                    joystickRow("Up", "UpLeft", "UpRight")
                    HStack(spacing: 46) {
                        pressBtn("Left", "arrow.left")
                        zoomBtns
                        pressBtn("Right", "arrow.right")
                    }
                    joystickRow("Down", "DownLeft", "DownRight")
                }
            }
            HStack {
                ForEach(1...7, id: \.self) { s in
                    Button("\(s)") { speed = s }
                        .buttonStyle(.bordered)
                        .tint(speed == s ? .blue : .secondary)
                }
            }
            if !err.isEmpty { Text(err).font(.caption).foregroundStyle(.red) }
        }
        .padding()
    }

    /// 中间两个变倍按钮放 HStack 里撑位
    private var zoomBtns: some View {
        HStack(spacing: 10) {
            pressBtn("ZoomIn", "plus.magnifyingglass")
            pressBtn("ZoomOut", "minus.magnifyingglass")
        }
    }

    private func joystickRow(_ up: String, _ left: String, _ right: String) -> some View {
        HStack(spacing: 46) {
            pressBtn(left, diagonalIcon(left))
            pressBtn(up, verticalIcon(up))
            pressBtn(right, diagonalIcon(right))
        }
    }

    private func verticalIcon(_ cmd: String) -> String { cmd == "Up" ? "arrow.up" : "arrow.down" }
    private func diagonalIcon(_ cmd: String) -> String {
        switch cmd {
        case "UpLeft": "arrow.up.left"; case "UpRight": "arrow.up.right"
        case "DownLeft": "arrow.down.left"; default: "arrow.down.right"
        }
    }

    private func pressBtn(_ cmd: String, _ icon: String) -> some View {
        Image(systemName: icon)
            .font(.title2)
            .frame(width: 48, height: 48)
            .background(.thinMaterial, in: Circle())
            // 按下发方向、松开发 Stop —— 监控云台的标准手感
            .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
                Task { await send(pressing ? cmd : "Stop") }
            }, perform: {})
    }

    private func send(_ command: String) {
        busy = true; err = ""
        Task {
            defer { busy = false }
            do { try await ApiClient.shared.ptz(deviceId: deviceId, channel: channel, command: command, speed: speed) }
            catch { err = error.localizedDescription }
        }
    }
}
