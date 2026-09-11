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

### Android Studio 启动

1. 在 Android Studio 中安装 **Flutter** 插件及其依赖 **Dart**，然后打开包含 `pubspec.yaml` 的 **DuckMusic 根目录**。
2. 在 Settings > Languages & Frameworks > Flutter 设置 Flutter SDK。本机路径为 `/Users/wangweijie/development/flutter`，当前安装版本为 3.44.8；其他电脑填写各自的 SDK 路径。
3. 首次打开时执行 `flutter pub get`。SDK Manager 中需有 Android SDK Platform 36、Build Tools 36 和 NDK 28.2.13676358；Gradle JDK 使用 Android Studio 自带的 JBR（Gradle 9.1 需要 Java 17 或更高版本）。
4. 从 Device Manager 启动模拟器，或连接已启用 USB 调试的 Android 手机。本机已有 `Medium_Phone` 模拟器。
5. 选择共享运行配置 **DuckMusic Android**，选择 Android 设备后点击 Run。入口是 `lib/main.dart`，默认运行 debug 模式，支持热重载。

`android/` 是原生宿主，主要用于 Gradle、权限和签名设置。Flutter 日常开发使用根目录项目。`android/local.properties` 中的 `sdk.dir`、`flutter.sdk` 是每台电脑的本地路径，不提交到版本库。

本地 debug 包使用 `com.music.player.debug`，可与正式版同时安装，数据各自独立。运行 debug 不需要正式签名文件；release 构建仍需要 `android/key.properties` 和正式签名证书。

```bash
# 首次安装依赖
flutter pub get

# macOS（开发主力）
flutter run -d macos

# iOS（需 Xcode + 开发者证书）
flutter run -d ios

# Android：先获取设备 ID，再指定一个实际设备
flutter devices
flutter run -d <android-device-id>

# 本地 Android APK（build/app/outputs/flutter-apk/app-debug.apk）
flutter build apk --debug

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

### 桌面端 iOS 安装中心（实验性）

macOS 和 Windows 桌面版设置中提供“iOS 安装中心”。它从 ECS 读取 `IOS_SIDELOAD_MANIFEST_URL` 指向的清单，校验 IPA 的 SHA-256，再交给用户本机的签名助手处理。Apple ID、双重认证、证书私钥和描述文件不会上传到 ECS。

桌面端只能在签名到期前刷新用户自己的设备；免费个人签名的有效期、设备数量和 App 数量仍由 Apple 决定。ECS 不代签，也不提供共享企业证书。缺少本机签名助手时，页面会显示诊断信息，不会报告虚假的安装成功。

DMG/EXE 会内置 `duckmusic-ios-helper`。macOS 版本现在可以使用用户本机钥匙串中的 Apple Development 身份、有效描述文件和已配对设备完成 IPA 重签名及 `devicectl` 安装；Apple 账号、验证码、私钥不会传到 ECS。Windows 版本当前仍只做 Apple Devices/Bonjour 诊断，真实签名需要后续接入经过许可证审核的 Windows 本地签名服务。

macOS Helper 会读取 Xcode 生成的描述文件，因此首次配置仍需在本机 Xcode 登录 Apple 账号并让 Xcode 为 `com.751152.duckMusic` 生成个人开发描述文件。免费个人签名的有效期、设备数量和 App 数量由 Apple 决定；Helper 只能在描述文件仍有效时重新签名安装，不能凭空延长 Apple 的有效期。桌面端发布包必须使用 Developer ID 签名并公证，才能让内置 Helper 正常访问本机签名工具和设备服务。

## 设计与 UI/UX

项目已按大厂级设计系统重构（Apple Music 风格），详见 [DESIGN.md](DESIGN.md)：

- 设计令牌 + 5 套主题（暗黑 / 明亮 / 日落 / 海洋 / 石墨）
- 统一组件库（玻璃表面、胶囊按钮、分段控件、进度条等）
- 沉浸式播放页（封面模糊背景 + 旋转唱片 + 歌词）、歌单详情模糊头部
- 参考原 Android 项目配色与 TuneFreeNext 的简洁界面风格
