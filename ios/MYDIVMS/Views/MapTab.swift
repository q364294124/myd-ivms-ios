// MARK: - 厂区平面图 Tab：平面图列表 → 图片 + 点位（点击直接看该通道实时画面）
// 点位坐标是图片百分比（0~100），与图片显示尺寸无关 —— 用 GeometryProject 换算。

import SwiftUI

struct MapTab: View {
    @State private var floors: [MapFloorDto] = []
    @State private var sel: MapFloorDto?
    @State private var image: UIImage?
    @State private var markers: [MapMarkerDto] = []
    @State private var loading = false
    @State private var err = ""
    @State private var liveFor: MapMarkerDto?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if floors.count > 1 { floorPicker }
                stage
            }
            .navigationTitle("厂区平面图")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await loadFloors() }
            .onAppear { Task { await loadFloors() } }
            .sheet(item: $liveFor) { m in
                MarkerLiveSheet(m: m)
                    .presentationDetents([.large])
            }
        }
    }

    private var floorPicker: some View {
        Picker("平面图", selection: Binding(
            get: { sel?.id ?? 0 },
            set: { nid in sel = floors.first(where: { $0.id == nid }) })) {
            ForEach(floors) { f in Text(f.name).tag(f.id) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 6)
        .onChange(of: sel) { f in if let f { Task { await loadFloor(f) } } }
    }

    private var stage: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(markersOverlay(geo: geo, imageSize: image.size))
                } else if loading {
                    ProgressView("加载平面图…")
                } else {
                    // iOS 16 无 ContentUnavailableView，用简易占位（17+ 可换回）
                    VStack(spacing: 10) {
                        Image(systemName: "map").font(.largeTitle).foregroundStyle(.secondary)
                        Text(err.isEmpty ? "还没有平面图" : err).font(.footnote).foregroundStyle(.secondary)
                        Text("在 Web 端「地图」页上传后这里会显示").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
    }

    /// 点位层：按图片实际绘制矩形（scaledToFit 的居中留边）定位
    private func markersOverlay(geo: GeometryProxy, imageSize: CGSize) -> some View {
        let scale = min(geo.size.width / imageSize.width, geo.size.height / imageSize.height)
        let dw = imageSize.width * scale, dh = imageSize.height * scale
        let ox = (geo.size.width - dw) / 2, oy = (geo.size.height - dh) / 2
        return ForEach(markers) { m in
            VStack(spacing: 2) {
                Circle()
                    .fill(m.online ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                Text("\(m.deviceName) · \(m.name)")
                    .font(.caption2).lineLimit(1)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white)
            }
            .position(x: ox + m.x / 100 * dw, y: oy + m.y / 100 * dh)
            .onTapGesture { liveFor = m }
        }
    }

    private func loadFloors() async {
        loading = true; err = ""
        defer { loading = false }
        do {
            floors = try await ApiClient.shared.mapFloors()
            if sel == nil || !floors.contains(where: { $0.id == sel?.id }) { sel = floors.first }
            if let sel { await loadFloor(sel) }
        } catch { err = error.localizedDescription }
    }

    private func loadFloor(_ f: MapFloorDto) async {
        do {
            async let img = ApiClient.shared.mapImage(f.imageUrl)
            async let mk = ApiClient.shared.mapMarkers(floorId: f.id)
            image = try await img
            markers = try await mk
        } catch { err = error.localizedDescription; image = nil; markers = [] }
    }
}

// MARK: 点位 → 实时画面（半屏播放 + 云台）

struct MarkerLiveSheet: View {
    @Environment(\.dismiss) private var dismiss
    let m: MapMarkerDto

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlayerView(url: ApiClient.shared.liveFlvUrl(deviceId: m.deviceId, channel: m.channel)) {}
                    .aspectRatio(16 / 9, contentMode: .fit)
                PtzPad(deviceId: m.deviceId, channel: m.channel, title: "\(m.deviceName) · \(m.name)")
                Spacer()
            }
            .navigationTitle("\(m.deviceName) · \(m.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}
