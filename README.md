# 柒伍壹壹音乐 · Flutter 跨平台版

一套 Flutter 代码覆盖 **iOS / Android / macOS / Windows** 四端。

## 项目结构

```
DuckMusic/
├── lib/          ← 四端共享 Dart 代码（UI、播放、网络、逻辑）
├── ios/          ← iOS Runner 壳（Xcode 工程：ios/Runner.xcworkspace）
├── macos/        ← macOS Runner 壳（Xcode 工程：macos/Runner.xcworkspace）
├── android/      ← Android Runner 壳
├── windows/      ← Windows Runner 壳
├── test/         ← 单元测试
├── scripts/      ← 工具脚本（如 Flutter SDK 鼠标补丁）
├── pubspec.yaml  ← 共享依赖声明
└── analysis_options.yaml
```

## 运行

确保 Flutter SDK 已安装并执行过 `flutter doctor`。

```bash
# macOS（开发主力）
flutter run -d macos

# iOS（需 Xcode + 开发者证书）
flutter run -d ios

# Android
flutter run -d android

# Windows（需 Visual Studio 工具链）
flutter run -d windows
```

## Xcode 相关

工程根目录是 Flutter 项目，不是 Xcode 工程。需要 Xcode 做原生配置（如签名、权限）时，请打开：

- **macOS 配置** → `macos/Runner.xcworkspace`
- **iOS 配置** → `ios/Runner.xcworkspace`

日常开发建议直接用 `flutter run`，无需手动打开 Xcode。

## macOS 鼠标卡死补丁

Flutter 的 macOS debug 模式下有一个已知 Bug：`MouseTracker._deviceUpdatePhase` 的防重入断言会在鼠标 hover 触发重建时崩溃。运行前请执行一次：

```bash
bash scripts/patch_flutter_mouse_tracker.sh
```

`flutter upgrade` 后需要重新执行。

## 后端 API

默认后端地址：`https://api.751152.xyz/`（配置在 `lib/core/config/app_config.dart`）。

## 四端在线更新

设置页会根据当前平台检查和安装更新：

- Android：下载 universal APK，并交给系统安装器更新。
- macOS：按 Apple Silicon / Intel 下载对应 DMG，并打开系统安装界面。
- Windows：下载 Inno Setup EXE，并打开系统安装器。
- iOS：查询 App Store 线上版本并跳转 App Store。Apple 不允许应用自行下载 IPA 更新。

Flutter 四端版本使用 `flutter-v*` 标签和 `DuckMusic-Flutter-*` 资产名，与仓库中原生 Android 应用的 `v*` Release 完全隔离。发布工作流位于 `.github/workflows/flutter-release.yml`。

Android 保留原生正式版的应用身份 `com.music.player`。首个 Flutter 迁移版本从 `1.1.27+38` 开始，并必须复用原生版的永久签名证书；满足这三个条件后，已安装 `1.1.26(37)` 的老用户可以直接覆盖升级。iOS/macOS 保持各自的 `com.751152.duckMusic` Bundle ID，Windows 保持固定安装器 AppId。

老版线上正式 APK 的签名证书 SHA-256 为 `c6821dcc9ac2395eb9a810f1b9ff250a3a7186ab899fdd8de772d852cf542a72`。该公开指纹已固定在 CI 发布门禁中；私钥只从 GitHub Actions Secrets 读取。

### 发布版本

完整的版本规则、首次签名配置、四端打包命令、上传步骤和验收清单见 [RELEASE.md](RELEASE.md)。

1. 修改 `pubspec.yaml` 中的 `version: x.y.z+build`；Android 的 build 必须始终大于已发布的 versionCode。
2. 提交并推送代码。
3. 创建并推送完全匹配的标签 `flutter-vx.y.z`。
4. Actions 通过分析、测试、签名和公证后，将 Android APK、两种 macOS DMG、Windows EXE 上传到同一条 GitHub Release，并更新老版 Android 客户端读取的 ECS `latest.json`。

客户端构建时，工作流会自动注入当前仓库、应用版本和 `IOS_APP_STORE_ID`。手工构建可使用：

```bash
flutter build apk --release \
  --dart-define=APP_VERSION=1.2.0 \
  --dart-define=UPDATE_REPOSITORY=owner/repository \
  --dart-define=IOS_APP_STORE_ID=123456789
```

### GitHub 配置

Android Release 必须配置这些 Secrets，且后续版本必须始终使用同一签名证书：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_SIGNING_CERT_SHA256`

macOS Release 必须配置 Developer ID 签名和 Apple 公证信息：

- `MACOS_CERTIFICATE_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `MACOS_SIGNING_IDENTITY`
- `MACOS_NOTARIZATION_APPLE_ID`
- `MACOS_NOTARIZATION_PASSWORD`
- `APPLE_TEAM_ID`

Windows 建议配置 `WINDOWS_CERTIFICATE_BASE64` 和 `WINDOWS_CERTIFICATE_PASSWORD`，工作流会对主程序和安装器做 Authenticode 签名。没有证书仍可构建，但 Windows SmartScreen 可能显示未知发布者。

iOS 上架后，在 GitHub Actions Variables 中设置 `IOS_APP_STORE_ID`。iOS 新版本仍需通过 Xcode / App Store Connect 上传审核；审核发布后，应用内检查会自动识别线上版本。

## 设计与 UI/UX

项目已按大厂级设计系统重构（Apple Music 风格），详见 [DESIGN.md](DESIGN.md)：

- 设计令牌 + 5 套主题（暗黑 / 明亮 / 日落 / 海洋 / 石墨）
- 统一组件库（玻璃表面、胶囊按钮、分段控件、进度条等）
- 沉浸式播放页（封面模糊背景 + 旋转唱片 + 歌词）、歌单详情模糊头部
- 参考原 Android 项目配色与 TuneFreeNext 的简洁界面风格
