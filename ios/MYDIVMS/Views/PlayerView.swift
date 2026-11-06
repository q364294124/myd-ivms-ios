// MARK: - VLCKit 播放器（http-flv / PS 流，H.264+H.265 通吃）
// 为什么用 MobileVLCKit：iOS AVPlayer 不吃 http-flv 与 PS 裸流，而服务端现有出口就是
// /api/live/.../ps.flv 与 /api/gb/playback/.../ps.flv（且 GB 常见 H.265，AVPlayer 解不了）。
// VLC 拉 http-flv 延迟 1~3s，监控场景可接受；低延迟优化走 network-caching。

import SwiftUI
import MobileVLCKit

struct PlayerView: UIViewRepresentable {
    let url: URL
    /// 供外部控制暂停/停止（回放页用）
    var onFirstFrame: (() -> Void)? = nil

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        let player = VLCMediaPlayer(options: ["--network-caching=300"])
        player.drawable = container
        player.delegate = context.coordinator
        player.media = VLCMedia(url: url)
        player.play()
        context.coordinator.player = player
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // URL 变化才重建流（懒对比：VLC 不支持无缝换源）
        if context.coordinator.currentUrl != url {
            context.coordinator.currentUrl = url
            context.coordinator.firstFired = false
            let player = context.coordinator.player
            player?.stop()
            player?.media = VLCMedia(url: url)
            player?.play()
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.player?.stop()
        coordinator.player?.media = nil
        coordinator.player = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFirstFrame: onFirstFrame) }

    final class Coordinator: NSObject, VLCMediaPlayerDelegate {
        var player: VLCMediaPlayer?
        var currentUrl: URL?
        var firstFired = false
        let onFirstFrame: (() -> Void)?

        init(onFirstFrame: (() -> Void)?) { self.onFirstFrame = onFirstFrame }

        func mediaPlayerStateChanged(_ aNotification: Notification) {
            guard let p = player else { return }
            switch p.state {
            case .playing where !firstFired:
                firstFired = true
                DispatchQueue.main.async { self.onFirstFrame?() }
            case .esAdded:
                // 有些流 esAdded 先于 playing，首帧判定双保险
                if !firstFired { firstFired = true; DispatchQueue.main.async { self.onFirstFrame?() } }
            default: break
            }
        }
    }
}

// MARK: 单格（含标题与加载态），供 1/4/9 宫格复用

struct PlayerCell: View {
    let title: String
    let subtitle: String
    let url: URL?
    @State private var loading = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            if let url {
                PlayerView(url: url) { loading = false }
                    .ignoresSafeArea()
            } else {
                Text("未选中通道").foregroundStyle(.gray).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).bold().lineLimit(1)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                if loading { ProgressView("取流中…").font(.caption2).foregroundStyle(.white) }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: Rectangle())
        }
        .clipped()
        .onChange(of: url) { _ in loading = true }
    }
}
