# MYD-IVMS iOS 原生客户端

SwiftUI 原生实现（非网页壳），播放器用 MobileVLCKit 播服务端现有 http-flv 出口（H.264/H.265 通吃），与服务端零改动对接。

## 功能（第一版，对齐安卓/WPF 端主线）

| Tab | 功能 | 对接端点 |
|---|---|---|
| 预览 | 1/4 宫格、设备树选通道（GB/SDK 通道自动区分）、云台摇杆 | `/api/devices`、`/api/live/{dev}/{ch}/ps.flv`、`/api/devices/{id}/ptz` |
| 回放 | 按天查询录像段、点段起播（GB 本地时间口径 / SDK UTC 口径自动分叉） | `/api/gb/records`、`/api/gb/playback/.../ps.flv`、`/api/playback/...` |
| 报警 | 历史列表 + 抓图缩略 + SSE 实时红点 | `/api/alarms/history`、`/api/events/stream`（SSE） |
| 地图 | 平面图查看 + 点位（点击直接开该通道实时画面 + 云台） | `/api/map/floors`、`/api/map/floors/{id}/markers` |

登录：JWT（`clientVersion: 1.1.0` 满足服务端版本门禁），token 持久化到 UserDefaults。

## 出包流程（无 Mac 也能出 ipa）

`.github/workflows/ios-build.yml`：push 触发 GitHub Actions macOS 云构建，产出**未签名 ipa** artifact。

1. 把本仓库 push 到 GitHub（任意私有仓库）
2. Actions 页签等 `ios-build` 跑完（约 8~15 分钟）
3. 下载 artifact `MYDIVMS-unsigned-ipa`

## 签名安装（拿 ipa 之后）

- **Sideloadly**（Windows 可用）：USB 连 iPhone → 拖入 ipa → 登录你的 Apple ID → 签名安装。
  免费 Apple ID 每 7 天要重签一次；付费开发者账号（$99/年）1 年有效。
- **AltStore**：手机端自签续期，适合不想连线的场景。
- **企业证书 / TestFlight**：有账号的话走常规分发。

> 未签名 ipa = 还没嵌 provisioning profile 的正常应用包，签名工具会给它注入你的证书。

## 有 Mac 时本地开发

```bash
cd ios
brew install xcodegen          # 生成 .xcodeproj（仓库不含，XcodeGen 声明式生成）
xcodegen generate
open MYDIVMS.xcodeproj         # SPM 会自动拉 MobileVLCKit，Cmd+R 即可
```

## 关键设计说明（为什么这么做）

- **MobileVLCKit 而非 AVPlayer**：服务端现有出口是 http-flv（H.264/H.265 混布），AVPlayer 不吃这两种封装；VLC 全兼容且延迟 1~3s。已放开 ATS（`NSAllowsArbitraryLoads`）支持内网 http + IP。
- **回放时间两套口径**：SDK 端点收 UTC 无 Z（与 Web `toISOString().slice(0,19)` 一致）；GB 端点收本地时间。`ApiClient` 内已封装，调用方无感。
- **XcodeGen**：Windows 上无法手维护 .xcodeproj（格式复杂且要 UUID），声明式 `project.yml` 由云端/ Mac 上生成工程文件，这是跨平台维护 Xcode 工程的标准做法。

## 二期规划（对齐安卓端后续）

- 回放拖动精确定位（PS 流不可 seek，按时刻重建流——UI 已预留 seekBar）
- 报警推送（APNs 需要证书；短期用 SSE + 本地通知替代）
- 巡检 / 门禁 / 道闸 / 大屏
- 低延迟直播（WebRTC 出口已有 `/api/live/.../rtc`，iOS 用 WebRTC.framework 对接）
