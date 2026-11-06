// MARK: - 实时预览 Tab：左（手机为底部抽屉）设备树 + 右（主区）宫格播放
// 手机竖屏：宫格占满，设备树从底部 sheet 拉出（比左右分栏更适合手指）。
// 云台：选中格是 GB/海康通道时右上角遥控器按钮进入。

import SwiftUI

struct LiveTab: View {
    @EnvironmentObject var app: AppState
    /// 宫格绑定：槽位 → (设备, 通道)
    @State private var slots: [Slot?] = Array(repeating: nil, count: 4)
    @State private var layout = 1                      // 1 / 4 宫格
    @State private var showTree = false
    @State private var ptzTarget: Slot?
    @State private var selIndex = 0

    struct Slot: Equatable, Identifiable {
        var id: String { "\(deviceId):\(channel)" }
        let deviceId: Int; let channel: Int; var title: String
    }

    private var visibleSlots: [Slot?] { Array(slots.prefix(layout * layout)) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                grid
                toolbar
            }
            .navigationTitle("实时预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showTree = true } label: { Image(systemName: "list.bullet") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("\(layout)x\(layout)") {
                        ForEach([1, 4], id: \.self) { n in
                            Button("\(n)x\(n)") { layout = n; if slots.count < n * n { slots += Array(repeating: nil, count: n * n - slots.count) } }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let t = selSlot, let dev = app.devices.first(where: { $0.id == t.deviceId }), !dev.isCvr {
                        Button { ptzTarget = t } label: { Image(systemName: "gamecontroller") }
                    }
                }
            }
            .sheet(isPresented: $showTree) {
                DeviceTreeSheet(pick: { dev, ch in
                    place(dev, ch)
                    showTree = false
                })
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $ptzTarget) { t in
                PtzPad(deviceId: t.deviceId, channel: t.channel, title: t.title)
                    .presentationDetents([.height(360)])
            }
        }
    }

    private var selSlot: Slot? { slots[selIndex] }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: layout), spacing: 2) {
            ForEach(0..<visibleSlots.count, id: \.self) { i in
                let s = visibleSlots[i]
                PlayerCell(
                    title: s?.title ?? "空",
                    subtitle: s.flatMap { t in
                        let d = app.devices.first { $0.id == t.deviceId }
                        return d.map { $0.isGb ? "GB · 点按选中" : "SDK · 点按选中" }
                    } ?? "点设备树放置",
                    url: s.map { ApiClient.shared.liveFlvUrl(deviceId: $0.deviceId, channel: $0.channel) }
                )
                .aspectRatio(16 / 9, contentMode: .fit)
                .onTapGesture { selIndex = i }
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(selIndex == i ? .blue : .clear, lineWidth: 2)
                )
                .contextMenu {
                    Button("清空此格", role: .destructive) { slots[i] = nil }
                }
            }
        }
        .background(.black)
    }

    private var toolbar: some View {
        HStack {
            Button { slots = Array(repeating: nil, count: slots.count) } label: {
                Image(systemName: "xmark.circle")
            }
            Spacer()
            Text("\(visibleSlots.compactMap(\.self).count)/\(layout * layout) 路").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func place(_ dev: DeviceDto, _ ch: Int) {
        slots[selIndex] = Slot(deviceId: dev.id, channel: ch, title: app.channelTitle(dev.id, ch))
        // 自动顺移到下一格（铺墙习惯与 WPF 端一致）
        if let next = (0..<visibleSlots.count).first(where: { slots[$0] == nil }) { selIndex = next }
    }
}

// MARK: 设备树（sheet）：在线分组 → 设备 → 通道

struct DeviceTreeSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    let pick: (DeviceDto, Int) -> Void
    @State private var q = ""
    @State private var expanded: Set<Int> = []

    private var filtered: [(DeviceDto, [Int])] {
        app.devices
            .filter { !$0.isCvr }
            .compactMap { d -> (DeviceDto, [Int])? in
                let chs = d.channels.filter {
                    q.isEmpty || d.name.localizedCaseInsensitiveContains(q)
                        || app.channelTitle(d.id, $0).localizedCaseInsensitiveContains(q)
                }
                return chs.isEmpty ? nil : (d, chs)
            }
            .sorted { ($0.0.online == true ? 0 : 1, $0.0.id) < ($1.0.online == true ? 0 : 1, $1.0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered, id: \.0.id) { (d, chs) in
                    DisclosureGroup(isExpanded: Binding(
                        get: { expanded.contains(d.id) || filtered.count == 1 },
                        set: { if $0 { expanded.insert(d.id) } else { expanded.remove(d.id) } })) {
                        ForEach(chs, id: \.self) { ch in
                            Button {
                                pick(d, ch)
                            } label: {
                                HStack {
                                    Text(app.channelTitle(d.id, ch)).lineLimit(1)
                                    Spacer()
                                    if d.isGb { Text("GB").font(.caption2).foregroundStyle(.orange) }
                                    if d.online == false { Text("设备离线").font(.caption2).foregroundStyle(.red) }
                                    Image(systemName: "play.circle").foregroundStyle(.blue)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Circle().fill(d.online == false ? .gray : .green).frame(width: 8, height: 8)
                            Text(d.name).bold()
                            Spacer()
                            Text("\(chs.count) 通道").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $q, prompt: "搜索设备 / 通道")
            .navigationTitle("选择通道")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .refreshable { await app.refreshDevices() }
        }
    }
}
