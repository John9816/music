# DuckMusic 打包与发布指南

本文档是 DuckMusic Flutter 客户端的发布操作手册，供开发者和 AI 执行发版时使用。

当前发布方式：

- Android、macOS、Windows：推送 `flutter-v*` Git 标签后，由 GitHub Actions 构建并上传到 GitHub Release。
- iOS：在 macOS 上构建 IPA，再通过 App Store Connect 上传和审核。
- `.github/workflows/flutter-release.yml` 是自动发布流程的实现，`pubspec.yaml` 是版本号的唯一来源。

## 1. 发布速查

Android 老用户直升 ECS 的固定链路：

1. `pubspec.yaml` 同时递增版本号和构建号，且 `applicationId` 保持 `com.music.player`。
2. 推送代码到 `flutter-migration`，再推送匹配的 `flutter-v<version>` 标签。
3. GitHub Actions 从 Secrets 恢复历史正式证书，并校验证书 SHA-256 为 `c6821dcc9ac2395eb9a810f1b9ff250a3a7186ab899fdd8de772d852cf542a72`。
4. Android 签名构建和校验成功后，独立任务立即将 APK 和 `latest.json` 上传至 ECS `/opt/website/updates`，不等待 macOS 或 Windows；多平台 GitHub Release 继续单独生成。
5. 最后从 `https://api.751152.xyz/updates/latest.json` 和其中的 `downloadUrl` 回读校验版本、构建号与 APK 哈希。任何一步失败都不能手工上传 debug 签名 APK。

正式发布 `1.2.0`、构建号 `12` 的标准流程：

```bash
# 1. 将 pubspec.yaml 修改为：version: 1.2.0+12
flutter pub get
flutter analyze
flutter test

# 2. 提交并先推送代码
git add pubspec.yaml pubspec.lock
git commit -m "chore: release Flutter 1.2.0"
git push origin main

# 3. 标签必须与 pubspec.yaml 中 + 之前的版本完全匹配
git tag -a flutter-v1.2.0 -m "DuckMusic Flutter 1.2.0"
git push origin flutter-v1.2.0
```

随后在 GitHub 的 `Actions` 页面观察 **Flutter multi-platform release**。所有任务成功后，同一条 GitHub Release 应包含：

```text
DuckMusic-Flutter-v1.2.0-Android-universal.apk
DuckMusic-Flutter-v1.2.0-macOS-arm64.dmg
DuckMusic-Flutter-v1.2.0-macOS-x64.dmg
DuckMusic-Flutter-v1.2.0-Windows-x64-setup.exe
```

iOS 不会由该标签自动上传，参见“iOS 上架”章节。

## 2. 版本规则

版本只修改 `pubspec.yaml`：

```yaml
version: 1.2.0+12
```

- `1.2.0` 是面向用户的版本号，即 build name。
- `12` 是商店和系统识别的内部构建号，即 build number，必须为正整数。
- GitHub 发布标签只使用用户版本号：`flutter-v1.2.0`，不包含 `+12`。

各平台映射如下：

| 平台 | 用户版本 | 内部构建号 |
| --- | --- | --- |
| Android | `versionName` | `versionCode` |
| iOS | `CFBundleShortVersionString` | `CFBundleVersion` |
| macOS | `CFBundleShortVersionString` | `CFBundleVersion` |
| Windows | Flutter 应用版本及安装器 `AppVersion` | Flutter 构建号 |

版本递增建议：

- 修复问题：`1.2.0` -> `1.2.1`
- 向后兼容的新功能：`1.2.0` -> `1.3.0`
- 不兼容的大改动：`1.2.0` -> `2.0.0`
- 每次提交到商店或正式发布都递增构建号，例如 `1.2.0+12` -> `1.2.1+13`。

注意：

- 不要手动修改 `android/local.properties`、`ios/Flutter/Generated.xcconfig`、`macos/Flutter/ephemeral/*` 等生成文件。
- 正式标签必须严格等于 `flutter-v<用户版本>`，否则 CI 会立即失败。
- 已发布的标签不要删除后复用。工作流失败时可在 GitHub 重新运行；如果标签对应的代码需要改变，请提升版本并创建新标签。
- 应用内更新依赖 `APP_VERSION`、`flutter-v` 标签前缀和 `DuckMusic-Flutter-` 资产名前缀，不要随意改变命名。

当前应用标识：

- Android application ID：`com.music.player`
- iOS/macOS bundle ID：`com.751152.duckMusic`

应用标识决定系统和商店是否将安装包识别为同一个应用。除非明确进行应用迁移，否则不要修改。

## 3. 首次配置 GitHub 发布环境

仓库的 `Settings > Secrets and variables > Actions` 中需要配置以下内容。任何证书、私钥和密码都不能提交到仓库、Issue、日志或文档。

### 3.1 Android 签名

正式标签要求以下 Repository secrets 全部存在：

```text
ANDROID_KEYSTORE_BASE64
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
ANDROID_SIGNING_CERT_SHA256
```

首次创建上传密钥的示例：

```bash
keytool -genkeypair -v \
  -keystore upload-keystore.jks \
  -alias upload \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000

keytool -list -v -keystore upload-keystore.jks -alias upload
base64 -i upload-keystore.jks | tr -d '\n' | pbcopy
```

将最后一条命令复制的单行内容保存为 `ANDROID_KEYSTORE_BASE64`，将 `SHA256` 指纹保存为 `ANDROID_SIGNING_CERT_SHA256`。正式发版后必须永久备份该 keystore 及密码；丢失或更换密钥会导致现有 Android 用户无法覆盖升级。

本地正式签名时，在 `android/key.properties` 中配置：

```properties
storeFile=../upload-keystore.jks
storePassword=<store password>
keyAlias=upload
keyPassword=<key password>
```

并将密钥放在 `android/upload-keystore.jks`。这两个路径已被 `.gitignore` 忽略，提交前仍需用 `git status` 再确认一次。

### 3.2 macOS 签名与公证

正式标签要求：

```text
MACOS_CERTIFICATE_BASE64
MACOS_CERTIFICATE_PASSWORD
MACOS_SIGNING_IDENTITY
MACOS_NOTARIZATION_APPLE_ID
MACOS_NOTARIZATION_PASSWORD
APPLE_TEAM_ID
```

- 从钥匙串导出 Developer ID Application 证书及私钥为 `.p12`，再执行 `base64 -i certificate.p12 | tr -d '\n' | pbcopy` 得到 `MACOS_CERTIFICATE_BASE64`。
- `MACOS_SIGNING_IDENTITY` 使用证书的完整名称，可通过 `security find-identity -v -p codesigning` 查询。
- `MACOS_NOTARIZATION_PASSWORD` 应使用 Apple ID 的 app-specific password，不要使用 Apple ID 登录密码。
- `APPLE_TEAM_ID` 是 Apple Developer Team ID。

CI 会依次完成 app 签名、DMG 制作、Apple 公证和 staple 校验。缺少其中任意正式发布凭据时，标签构建会失败。

### 3.3 Windows 签名

建议配置：

```text
WINDOWS_CERTIFICATE_BASE64
WINDOWS_CERTIFICATE_PASSWORD
```

将代码签名 `.pfx` 证书编码为单行 Base64 后存入 `WINDOWS_CERTIFICATE_BASE64`。CI 会同时签名 `duck_music.exe` 和最终安装器。Windows 凭据暂时不是标签发布的硬性条件，但未签名产物会显示“未知发布者”，并更容易触发 SmartScreen。

### 3.4 iOS App Store ID

应用在 App Store Connect 创建后，把纯数字 Apple ID 保存为 Repository variable：

```text
IOS_APP_STORE_ID=1234567890
```

不要填写 bundle ID。CI 会把该值编译进所有平台，用于 iOS 应用内检查更新。

## 4. 发布前检查

在创建标签前完成：

```bash
flutter doctor -v
flutter pub get
flutter analyze
flutter test
git status --short
```

人工确认：

- `pubspec.yaml` 的版本号符合本次发布计划，构建号高于已提交到商店的构建号。
- 版本变更和功能代码已经提交，准备打标签的 commit 是预期 commit。
- 更新说明不包含密钥、用户数据或内部地址。
- Android 使用历史版本相同的签名密钥。
- iOS/macOS 的证书、描述文件和协议状态有效。
- 至少在本次涉及的平台上完成一次 release 模式冒烟测试。

## 5. GitHub Actions 自动发布

工作流有两种触发方式：

1. 推送 `flutter-v*` 标签：正式发布。CI 校验、构建、签名、公证，并创建 GitHub Release。
2. 在 Actions 页面手动运行 `workflow_dispatch`：只做验证构建并上传 workflow artifacts，不创建 GitHub Release。没有配置凭据时，Android 可能使用 debug key，macOS/Windows 可能未签名，因此这些 artifacts 只能用于内部测试。

正式发布时，`validate` job 会从 `pubspec.yaml` 读取版本，并要求：

```text
标签 flutter-v1.2.0 <=> pubspec version 1.2.0+12
```

构建期间还会自动注入：

```text
APP_VERSION=<用户版本>
UPDATE_REPOSITORY=<当前 GitHub owner/repo>
IOS_APP_STORE_ID=<GitHub Actions variable>
```

这些值关系到应用内更新。手工构建正式包时也必须注入相同参数。

## 6. 本地打包

以下示例在项目根目录执行：

```bash
VERSION=1.2.0
BUILD_NUMBER=12
UPDATE_REPOSITORY=owner/repository
IOS_APP_STORE_ID=1234567890
```

将 `owner/repository` 和 App Store ID 替换为真实值。

### 6.1 Android APK 与 AAB

GitHub Release 使用 universal APK：

```bash
flutter build apk --release \
  --build-name="$VERSION" \
  --build-number="$BUILD_NUMBER" \
  --dart-define="APP_VERSION=$VERSION" \
  --dart-define="UPDATE_REPOSITORY=$UPDATE_REPOSITORY" \
  --dart-define="IOS_APP_STORE_ID=$IOS_APP_STORE_ID"
```

产物：`build/app/outputs/flutter-apk/app-release.apk`。

如需上传 Google Play，构建 AAB：

```bash
flutter build appbundle --release \
  --build-name="$VERSION" \
  --build-number="$BUILD_NUMBER" \
  --dart-define="APP_VERSION=$VERSION" \
  --dart-define="UPDATE_REPOSITORY=$UPDATE_REPOSITORY" \
  --dart-define="IOS_APP_STORE_ID=$IOS_APP_STORE_ID"
```

产物：`build/app/outputs/bundle/release/app-release.aab`。本地不存在 `android/key.properties` 时，当前工程会退回 debug key；这种包可以安装测试，但不能作为正式更新发布。

### 6.2 macOS APP

必须在 macOS 上执行：

```bash
flutter build macos --release \
  --build-name="$VERSION" \
  --build-number="$BUILD_NUMBER" \
  --dart-define="APP_VERSION=$VERSION" \
  --dart-define="UPDATE_REPOSITORY=$UPDATE_REPOSITORY" \
  --dart-define="IOS_APP_STORE_ID=$IOS_APP_STORE_ID"
```

产物：`build/macos/Build/Products/Release/duck_music.app`。对外分发还必须进行 Developer ID 签名、公证并制作 DMG，优先使用 CI 完成，不要直接发布未公证的 `.app`。

### 6.3 Windows EXE 安装器

必须在安装了 Visual Studio Desktop development with C++ 和 Inno Setup 6 的 Windows 环境执行：

```powershell
$VERSION = "1.2.0"
$BUILD_NUMBER = "12"
$UPDATE_REPOSITORY = "owner/repository"
$IOS_APP_STORE_ID = "1234567890"

flutter build windows --release `
  --build-name="$VERSION" `
  --build-number="$BUILD_NUMBER" `
  --dart-define="APP_VERSION=$VERSION" `
  --dart-define="UPDATE_REPOSITORY=$UPDATE_REPOSITORY" `
  --dart-define="IOS_APP_STORE_ID=$IOS_APP_STORE_ID"

& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" `
  "/DMyAppVersion=$VERSION" `
  "windows\installer.iss"
```

应用目录为 `build\windows\x64\runner\Release\`，安装器位于 `windows\dist\`。对外发布前应使用受信任的 Authenticode 证书签名。

## 7. iOS 上架

iOS 不允许应用自行下载 IPA 更新，发布必须经过 App Store Connect。

首次准备：

- App Store Connect 中创建 bundle ID 为 `com.751152.duckMusic` 的应用。
- Xcode 登录有权限的 Apple Developer 账号。
- 打开 `ios/Runner.xcworkspace`，检查 Runner target 的 Team、Bundle Identifier 和 Signing & Capabilities。
- 确认 App Store Connect 的协议、税务和银行信息没有阻塞提交。

构建 IPA：

```bash
flutter build ipa --release \
  --build-name="$VERSION" \
  --build-number="$BUILD_NUMBER" \
  --dart-define="APP_VERSION=$VERSION" \
  --dart-define="UPDATE_REPOSITORY=$UPDATE_REPOSITORY" \
  --dart-define="IOS_APP_STORE_ID=$IOS_APP_STORE_ID"
```

典型产物：

```text
build/ios/archive/Runner.xcarchive
build/ios/ipa/*.ipa
```

上传与发布：

1. 使用 Apple Transporter 上传 `build/ios/ipa/*.ipa`，或在 Xcode Organizer 中打开 archive 后选择 **Distribute App > App Store Connect > Upload**。
2. 等待 App Store Connect 完成构建处理。
3. 在对应版本中选择该 build，填写版本说明、截图、隐私与审核信息。
4. 提交审核；审核通过后按计划手动或自动发布。
5. 发布后从中国区 App Store 页面确认版本可见，并验证应用内“检查更新”。

如果 App Store 提示 build 已使用，保持用户版本不变并递增 `+构建号` 后重新构建。例如 `1.2.0+12` 改为 `1.2.0+13`。

## 8. 发布后验收

- GitHub Release 不是 draft 或 prerelease，标签和四个资产名都正确。
- Android APK 可覆盖安装旧版，且签名证书 SHA-256 与历史版本一致。
- Apple Silicon 和 Intel macOS 分别下载匹配的 DMG，Gatekeeper 不提示包已损坏或身份不明。
- Windows 安装器显示预期发布者，可安装、启动、覆盖升级和卸载。
- iOS App Store 页面展示新版本，旧版应用能跳转更新。
- 四个平台“关于/设置”中的版本正确，应用内更新不会重复提示当前版本。
- 核心路径完成冒烟测试：启动、网络请求、播放、后台播放、设置持久化和更新入口。

发现严重问题时不要覆盖旧标签或替换同名资产。停止分发后修复代码，提升 patch 版本和构建号，再按完整流程发布。

## 9. 常见问题

### 标签校验失败

确认标签没有包含构建号，且大小写、前缀完全一致：

```text
正确：pubspec 1.2.0+12，标签 flutter-v1.2.0
错误：flutter-v1.2.0+12、v1.2.0、flutter-v1.2.1
```

### Android signing certificate mismatch

CI 计算出的 APK 证书指纹与 `ANDROID_SIGNING_CERT_SHA256` 不同。确认 Base64 内容、alias 和 SHA-256 都来自同一个历史 keystore，不要通过替换指纹来掩盖误用密钥。

### macOS 公证失败

检查 Developer ID Application 证书是否过期、签名 identity 是否完整、app-specific password 是否有效，以及 Apple Developer 协议是否待接受。查看 `notarytool` 对应 job 的原始错误再处理。

### Windows 用户看到未知发布者

说明没有配置 Windows 证书或签名步骤失败。检查两个 `WINDOWS_*` secrets，并在 CI 日志中确认主程序和安装器的 `signtool` 步骤均成功。

### 应用检查不到 GitHub 新版本

依次检查 Release 是否为非 draft、非 prerelease，标签是否以 `flutter-v` 开头，资产是否以 `DuckMusic-Flutter-` 开头，以及构建时的 `UPDATE_REPOSITORY` 是否指向实际仓库。

## 10. AI 执行约束

AI 协助发版时应遵守：

- 先读取本文件、`pubspec.yaml`、`.github/workflows/flutter-release.yml` 和 `windows/installer.iss`，以仓库当前配置为准。
- 可以修改版本、运行检查、准备命令和核对产物；没有用户明确授权时，不创建或推送 Git 标签，不上传商店，不创建 GitHub Release。
- 不读取、打印、提交或猜测真实密码、私钥和签名文件内容。
- 修改版本时只改 `pubspec.yaml`，除非平台配置已经明确脱离 Flutter 的版本映射。
- 发版前报告目标版本、构建号、目标 commit、目标标签和预计产物；发版后报告 CI 结果及实际资产。
- 遇到签名、商店账号、协议或审核问题时保留原始错误信息，并让有权限的账号所有者处理，不能用临时证书冒充正式发布。
