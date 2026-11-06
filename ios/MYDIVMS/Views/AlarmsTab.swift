// MARK: - 报警 Tab：历史列表 + 抓图 + SSE 实时刷新红点

import SwiftUI

struct AlarmsTab: View {
    @EnvironmentObject var app: AppState
    @State private var items: [AlarmDto] = []
    @State private var loading = false
    @State private var err = ""

    var body: some View {
        NavigationStack {
            List {
                if loading && items.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                if !err.isEmpty { Text(err).font(.caption).foregroundStyle(.red) }
                ForEach(items) { a in
                    HStack(alignment: .top, spacing: 10) {
                        thumb(a)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(a.deviceName ?? "设备\(a.deviceId)") · 通道\(a.channel)")
                                .font(.subheadline).bold().lineLimit(1)
                            Text(a.detail ?? a.type).font(.caption).lineLimit(2)
                            Text(timeText(a.time)).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        }
                        Spacer()
                        if a.handled != true {
                            Circle().fill(.red).frame(width: 7, height: 7)
                        }
                    }
                    .padding(.vertical, 2)
                }
                if !loading && items.isEmpty && err.isEmpty {
                    Text("暂无报警").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            .listStyle(.plain)
            .navigationTitle("报警中心")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await load() }
            .onAppear { Task { await load() } }
            .onReceive(NotificationCenter.default.publisher(for: .newAlarm)) { _ in
                app.unreadAlarms = 0
                Task { await load() }
            }
        }
    }

    /// 抓图缩略（imageUrl 走 access_token 查询串 + Authorization 都带上）
    @ViewBuilder
    private func thumb(_ a: AlarmDto) -> some View {
        if let img = a.imageUrl, !img.isEmpty {
            AsyncImage(url: alarmImageUrl(img)) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { placeholderThumb }
            }
            .frame(width: 74, height: 56).clipped().cornerRadius(6)
        } else { placeholderThumb }
    }

    private var placeholderThumb: some View {
        ZStack { Rectangle().fill(.quaternary); Image(systemName: "camera").foregroundStyle(.secondary) }
            .frame(width: 74, height: 56).cornerRadius(6)
    }

    private func alarmImageUrl(_ p: String) -> URL? {
        // imageUrl 形如 /alarms/xxx.jpg —— 服务端静态直出（wwwroot），带 token 查询串
        let base = UserDefaults.standard.string(forKey: "server.url") ?? ""
        let path = p.hasPrefix("http") ? p : base + p
        return URL(string: path + (p.contains("?") ? "&" : "?") + "access_token=" + (UserDefaults.standard.string(forKey: "server.token") ?? ""))
    }

    private func timeText(_ s: String) -> String {
        s.replacingOccurrences(of: "T", with: " ").prefix(19).description
    }

    private func load() async {
        loading = true; err = ""
        defer { loading = false }
        do { items = try await ApiClient.shared.alarmHistory(count: 200) }
        catch { err = error.localizedDescription }
    }
}
