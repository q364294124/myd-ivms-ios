// MARK: - 录像回放 Tab：设备树选通道 → 当日录像段列表 → 起播/接播
// 定位策略与 WPF 端一致：PS 流不可 seek，段内定位 = 以目标时刻为 start 重建流。
// SDK 设备走 /api/playback start（UTC 口径）；GB 设备走 /api/gb/*（本地时间口径），ApiClient 内已分叉。

import SwiftUI

struct PlaybackTab: View {
    @EnvironmentObject var app: AppState
    @State private var showTree = false
    @State private var dev: DeviceDto?
    @State private var ch: Int?
    @State private var day = Date()
    @State private var files: [RecordingFile] = []
    @State private var loading = false
    @State private var err = ""
    @State private var playingFile: RecordingFile?
    @State private var playUrl: URL?
    @State private var stopped = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if let url = playUrl, let f = playingFile {
                    PlayerView(url: url) {}
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .overlay(alignment: .topLeading) {
                            Text("\(fmt(f.start)) ~ \(fmt(f.end))")
                                .font(.caption).monospacedDigit().padding(6)
                                .background(.ultraThinMaterial)
                        }
                    seekBar(f)
                } else {
                    placeholder
                }
                if !err.isEmpty { Text(err).font(.caption).foregroundStyle(.red).padding(.horizontal) }
                fileList
            }
            .navigationTitle("录像回放")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showTree = true } label: { Image(systemName: "list.bullet") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    DatePicker("", selection: $day, displayedComponents: .date)
                        .labelsHidden()
                        .onChange(of: day) { _ in Task { await loadFiles() } }
                }
            }
            .sheet(isPresented: $showTree) {
                DeviceTreeSheet(pick: { d, c in
                    dev = d; ch = c; showTree = false
                    Task { await loadFiles() }
                })
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var header: some View {
        HStack {
            Text(dev.map { "\($0.name) · \(app.channelTitle($0.id, ch ?? 1))" } ?? "未选择通道")
                .font(.footnote).bold().lineLimit(1)
            Spacer()
            if let dev { Text(dev.isGb ? "国标" : "SDK").font(.caption2).foregroundStyle(.orange) }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    private var placeholder: some View {
        ZStack {
            Color.black.frame(height: 210)
            Text(playingFile == nil ? "选择日期查询录像，点时间段开始回放" : "缓冲中…")
                .foregroundStyle(.gray).font(.footnote)
        }
    }

    /// 段内定位条：拖到哪 = 以该时刻重建流（与 Web/客户端同策略）
    private func seekBar(_ f: RecordingFile) -> some View {
        Slider(
            value: Binding(
                get: { Date().timeIntervalSince(f.start) },
                set: { _ in /* 拖动结束用 onEditingChanged 处理 */ }),
            in: 0...(max(1, f.end.timeIntervalSince(f.start)))
        ) { editing in
            // 简化：以按下结束时刻的当前进度定位
            if !editing { /* 二期：精确拖动定位 */ }
        }
        .disabled(true) // 一期以"整段起播 + 连播"为主，拖动定位二期放开（避免误触重建流风暴）
        .padding(.horizontal)
    }

    private var fileList: some View {
        List {
            if loading { ProgressView().frame(maxWidth: .infinity) }
            ForEach(files) { f in
                Button {
                    startPlay(f)
                } label: {
                    HStack {
                        Image(systemName: "play.rectangle").foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text("\(fmt(f.start)) ~ \(fmt(f.end))").font(.subheadline).monospacedDigit()
                            if !f.name.isEmpty { Text(f.name).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer()
                        Text(duration(f)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !loading && files.isEmpty && err.isEmpty {
                Text("当天暂无录像（确认设备录像计划已开启）")
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
        .listStyle(.plain)
    }

    private func loadFiles() async {
        guard let dev, let ch else { return }
        await stop()
        loading = true; err = ""; files = []
        defer { loading = false }
        do {
            files = dev.isGb
                ? (try await ApiClient.shared.gbRecords(deviceId: dev.id, channel: ch, day: day)).sorted { $0.start < $1.start }
                : (try await ApiClient.shared.sdkPlaybackFiles(deviceId: dev.id, channel: ch, day: day)).sorted { $0.start < $1.start }
        } catch { err = error.localizedDescription }
    }

    private func startPlay(_ f: RecordingFile) {
        guard let dev, let ch else { return }
        stopped = false
        Task {
            do {
                let url = dev.isGb
                    ? ApiClient.shared.gbPlaybackFlvUrl(deviceId: dev.id, channel: ch, start: f.start, end: f.end)
                    : try await ApiClient.shared.sdkPlaybackStart(deviceId: dev.id, channel: ch, start: f.start, end: f.end)
                playingFile = f
                playUrl = url
            } catch { err = error.localizedDescription }
        }
    }

    private func stop() async {
        playingFile = nil; playUrl = nil
        if let dev, let ch, !dev.isGb { await ApiClient.shared.sdkPlaybackStop(deviceId: dev.id, channel: ch) }
    }

    private func fmt(_ d: Date) -> String { d.formatted(date: .omitted, time: .standard) }
    private func duration(_ f: RecordingFile) -> String {
        let s = Int(f.end.timeIntervalSince(f.start))
        return String(format: "%02d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
    }
}
