// MARK: - 根视图：登录 ⇄ 主界面（5 Tab）

import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        if app.loggedIn {
            MainTabView()
        } else {
            LoginView()
        }
    }
}

// MARK: 登录

struct LoginView: View {
    @EnvironmentObject var app: AppState
    @State private var server = UserDefaults.standard.string(forKey: "server.url")
        ?? "http://192.168.1.7:5299"
    @State private var user = UserDefaults.standard.string(forKey: "login.user") ?? ""
    @State private var pass = ""
    @State private var busy = false
    @State private var err = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器") {
                    TextField("http://服务器IP:5299", text: $server)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section("账号") {
                    TextField("用户名", text: $user)
                        .textInputAutocapitalization(.never)
                    SecureField("密码", text: $pass)
                }
                if !err.isEmpty {
                    Section { Text(err).foregroundStyle(.red).font(.footnote) }
                }
                Section {
                    Button {
                        login()
                    } label: {
                        if busy { ProgressView().frame(maxWidth: .infinity) }
                        else { Text("登  录").frame(maxWidth: .infinity).bold() }
                    }
                    .disabled(busy || user.isEmpty || pass.isEmpty)
                }
                Section {
                    Text("内网明文 http 部署时，iOS 允许连接（App 已放开 ATS）。首次登录请使用管理员分配的账号。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("MYD-IVMS")
        }
    }

    private func login() {
        busy = true; err = ""
        Task {
            defer { busy = false }
            do {
                let trimmed = server.trimmingCharacters(in: .whitespaces)
                    .hasPrefix("http") ? server.trimmingCharacters(in: .whitespaces)
                    : "http://" + server.trimmingCharacters(in: .whitespaces)
                guard let url = URL(string: trimmed) else { throw ApiError.server("服务器地址无效") }
                _ = try await ApiClient.shared.login(server: url, username: user, password: pass)
                UserDefaults.standard.set(user, forKey: "login.user")
                app.loggedIn = true
                await app.bootstrap()
            } catch {
                err = error.localizedDescription
            }
        }
    }
}

// MARK: 主界面：预览 / 回放 / 报警 / 地图 / 我的

struct MainTabView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        TabView {
            LiveTab()
                .tabItem { Label("预览", systemImage: "video.fill") }
            PlaybackTab()
                .tabItem { Label("回放", systemImage: "backward.end.fill") }
            AlarmsTab()
                .tabItem { Label("报警", systemImage: "bell.fill") }
                .badge(app.unreadAlarms)
            MapTab()
                .tabItem { Label("地图", systemImage: "map.fill") }
            MoreTab()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
        .tint(.blue)
    }
}

// MARK: 我的（占位：登出 / 服务器信息）

struct MoreTab: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        NavigationStack {
            Form {
                Section("设备概览") {
                    LabeledContent("接入设备", value: "\(app.devices.count) 台")
                    LabeledContent("在线", value: "\(app.devices.filter { $0.online != false }.count) 台")
                }
                Section {
                    Button("刷新设备与通道") { Task { await app.bootstrap() } }
                    Button("退出登录", role: .destructive) {
                        ApiClient.shared.logout()
                        app.loggedIn = false
                        app.stopEventStream()
                    }
                }
                Section("关于") {
                    LabeledContent("版本", value: "1.1.0 (iOS)")
                    LabeledContent("服务器", value: UserDefaults.standard.string(forKey: "server.url") ?? "-")
                }
            }
            .navigationTitle("我的")
        }
    }
}
