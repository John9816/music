# DuckMusic 多端优化与 macOS 修复验收

日期：2026-09-13。分支：`flutter-migration`；基线提交：`3c61cf5`。本报告记录推送前的本地验收结果：验收时尚未提交、推送或发布，版本为 `1.1.46+57`。用户设备为 M1；本机实测硬件为 Apple M1 Pro，架构 `arm64`。

## 结论与交付边界

已完成本轮核心音乐流程的多端布局、交互与错误恢复改造，并修复 macOS 打包后资源签名失效的发布流程。完整测试通过，三个可用平台完成本地编译，最终 macOS 开发 DMG 的内容完整性和原生启动经过实际验证。

**这不是已公开发布、已通过全部生产验收的版本。** 当前 macOS 开发包只有 ad-hoc 签名，没有 Developer ID 或 Apple 公证；真实 Gatekeeper 评估为 `rejected`（exit 3）。它仅用于本地开发验证，不能作为普通用户无需额外放行即可安装的正式包。未修改系统安全设置，未删除 quarantine，未绕过 Gatekeeper。

详细根因、线上原包证据、helper 的 Hardened Runtime 权限与发布流程见 [macOS 调查报告](2026-09-13-macos-release-repair.md)。

## 完成的产品改动

- 主框架：手机五入口包含资料库；桌面面板宽度与内容占位统一；连续缩窗保留导航栈、搜索输入和有效内容宽度；隐藏页不持有焦点；文本编辑与播放快捷键不冲突。
- 搜索：明确搜索范围，使用实际内容宽度；空下一页和失败重试保留成功结果；窗口变化与响应竞态不改变查询语义；横屏低高度可滚动访问筛选、结果和分页。
- 资料库：真实收藏、歌单和下载数据；区分未知、空、加载与失败；刷新失败保留已有数据；字符串歌单 ID 可正常打开；新建歌单防重复并管理对话框控制器生命周期。
- 会话：用稳定的 sessionGeneration 区分换账户与同账户 token 刷新；前者隔离页面数据，后者不清空进行中的输入。
- 播放与设置：小屏/横屏/大字排版；主要按钮语义与触摸目标；迷你栏按实际宽度适配；播放进度支持键盘和辅助功能；设置开关整行正确切换一次，长文案可换行。
- 发布：helper 写入后由内到外签名；检查全部 Mach-O、版本和架构；正式模式要求 Developer ID、Hardened Runtime、安全时间戳、公证、staple 和 Gatekeeper；所有门禁通过且成功卸载 DMG 后才输出正式资产。

沿用现有主题、品牌方向和后端协议，没有新增依赖；Android 正式包名和历史签名要求未改变。

## 自动化与静态检查

| 检查 | 实际结果 |
| --- | --- |
| `flutter analyze --no-pub` | No issues found |
| `flutter test --no-pub --file-reporter=json:build/qa/production-readiness/full-test-results.json` | 366 项成功，0 失败，0 跳过 |
| 18 个改动 Dart 文件的 `dart format --output=none --set-exit-if-changed` | 0 changed |
| `git diff --check` | 通过 |
| 四个相关发布脚本的 `bash -n` | 通过 |
| Helper / Release entitlements 的 `plutil -lint` | 均通过 |
| GitHub Actions YAML 解析 | 通过，macOS job 存在 |
| macOS 发布与 UI 独立复审 | 修正发现后复审，无剩余 Critical / Important 问题 |

本轮新增的 8 个测试文件共 88 项，已包含在完整 366 项结果中，不能与全量重复相加：

| 测试文件 | 数量 |
| --- | ---: |
| `auth_session_generation_test.dart` | 15 |
| `home_shell_responsive_test.dart` | 10 |
| `library_resilience_test.dart` | 9 |
| `macos_release_packaging_test.dart` | 16 |
| `player_responsive_layout_test.dart` | 13 |
| `production_controls_test.dart` | 5 |
| `production_visual_qa_test.dart` | 9 |
| `search_resilience_test.dart` | 11 |

macOS 的 16 项中包含 2 项真实原生检查，没有在本机跳过：Mach-O 架构校验，以及编译真实 Dart helper、开启 Hardened Runtime、确认签名命令成功并实际执行安全的 unknown-command 路径。受控签名/公证替身测试验证失败门禁，不代表已经通过 Apple 服务。

## 平台产物验收

### macOS / M1

最终源代码编译命令：

```sh
flutter build macos --release --no-pub --build-name=1.1.46 --build-number=57 --dart-define=APP_VERSION=1.1.46
```

退出 0，Xcode/Flutter 产物 `build/macos/Build/Products/Release/7511.app`，102.0 MB。本轮增量构建另捕捉到原始 Xcode 目录的外层签名陈旧：外层 CodeResources 时间为 15:59:48，App.framework 可执行文件及自身签名为 16:18:06；框架单独验证有效，外层验证报 `nested code is modified or invalid`。该原始目录未作为安装交付物或启动验收目标。

将其复制到 `build/qa/package-input/7511.app`，编译 helper 后运行最终打包流程：

```sh
bash scripts/build_ios_helper.sh build/qa/package-input/7511.app/Contents/Resources/duckmusic-ios-helper
bash scripts/package_macos.sh build/qa/package-input/7511.app arm64 1.1.46 57 build/qa/production-readiness/artifacts development
```

在获准环境中完成整个流程，退出 0：27 个 Mach-O 均包含 arm64；外层 app、全部嵌套代码及 helper 签名完整性通过；DMG checksum VALID；只读挂载后 app 和 helper 再验证通过；卸载成功后才生成最终文件。

开发 DMG：

```text
build/qa/production-readiness/artifacts/DuckMusic-Flutter-v1.1.46-macOS-arm64-development.dmg
大小：47,064,596 bytes
SHA-256：d5964795ff5958b8751f47c8cd701382575b4a70b17982e0d9ccfa6837ebab8a
```

随后重新只读挂载该文件，将其 app 原样复制到 `build/qa/production-readiness/native/7511.app`。复制后再运行 `verify_macos_app.sh ... development`，退出 0；helper 的 `audit-unknown-command --json` 返回预期 JSON（`code=unknown`，exit 2），未调用设备操作。

使用原生 UI 启动该副本，观察到业务界面，并通过进程路径确认运行的是 `build/qa/production-readiness/native/7511.app/Contents/MacOS/7511`。代理未输入账户、接受协议或主动更改用户业务数据。此结果证明本地 M1 Pro 原生启动，不替代带下载隔离标记的全新用户安装验收。

最终签名为 `Signature=adhoc`、`TeamIdentifier=not set`。在沙箱外真实执行：

```sh
spctl --assess --type execute --verbose=4 build/qa/production-readiness/native/7511.app
```

结果为 `rejected`，exit 3。因此资源完整性修复与 Apple 信任验证明确分开：前者已验证，后者尚未通过。开发 DMG 本体未做 Developer ID 签名或公证。

### Android

```sh
flutter build apk --debug --no-pub --target-platform android-arm64 --build-name=1.1.46 --build-number=57 --dart-define=APP_VERSION=1.1.46
```

退出 0，产物 `build/app/outputs/flutter-apk/app-debug.apk`。`aapt dump badging` 验证包名为 `com.music.player.debug`，版本 `1.1.46-debug` / `57`；`apksigner verify --print-certs` 通过，证书为 `Android Debug`。这是独立的调试包，未作为正式 APK，也未安装到设备。

本机没有 `android/key.properties`，因此未进行历史生产证书签名的 release 构建或覆盖升级验收。没有新增 debug 签名回退，也没有自动接受额外 SDK 许可证。

### iOS

```sh
flutter build ios --release --no-codesign --no-pub --build-name=1.1.46 --build-number=57 --dart-define=APP_VERSION=1.1.46
```

退出 0，产物 `build/ios/iphoneos/Runner.app`，43.3 MB。Info.plist 确认为 `com.751152.duckMusic`、版本 `1.1.46`、构建 `57`，主程序架构为 arm64。没有设备安装、provisioning 注册、签名导出或 App Store 提交；unsigned app 不是可直接交付用户的正式包。

### Windows 与工具链提示

当前 M1 macOS 主机无法原生构建 Windows；未运行 Windows CI，也未验证 EXE 安装/升级/卸载。共享 Flutter 桌面测试不代替 Windows 原生验收。

macOS/iOS 构建均提示部分插件尚不支持 Swift Package Manager，当前构建成功，依赖兼容性迁移仍需在后续 Flutter 升级时处理。本轮未为消除提示而升级依赖。

## 截图验收

在最后的字体继承修复之后重新运行：

```sh
flutter test --no-pub test/production_visual_qa_test.dart --dart-define=DUCKMUSIC_EXPORT_QA=true '--dart-define=DUCKMUSIC_QA_FONT=/System/Library/Fonts/STHeiti Light.ttc'
```

9 个离线场景通过，导出 10 张图片，均已人工检查。测试使用固定数据与本机中文字体，不访问真实账号或音乐服务。

目录：`build/qa/production-readiness/`。

| 图片 | 逻辑尺寸与检查重点 |
| --- | --- |
| `library-phone.png` | 390×844，五入口、真实状态布局与歌单列表 |
| `library-mac-compact.png` | 700×700，紧凑 macOS 标题避让与底栏 |
| `library-desktop.png` | 1440×900，侧栏、主内容、停靠歌词与迷你播放器 |
| `search-desktop.png` | 1440×900，搜索范围、来源和分类结果 |
| `search-landscape.png` | 812×375、1.5 倍文字，短横屏搜索头部 |
| `search-landscape-results.png` | 同上，滚动后结果、分页和播放器仍可访问，中文正常显示 |
| `player-phone.png` | 390×844，封面/歌词/主要控制层次 |
| `player-small-large-text.png` | 320×700、1.5 倍文字，小屏主控制及次级工具布局 |
| `player-landscape.png` | 812×375、1.5 倍文字，双栏播放器 |
| `settings-large-text.png` | 390×844、1.5 倍文字，设置文案换行及开关布局 |

以上图片没有发现溢出或测试字体方块；滚动状态与示例数据截图不能证明所有真实内容、网络状态或辅助设备均已验收。

## 正式发布前仍需完成

1. 在 CI 中提供有效 Developer ID Application 与 Apple 公证配置，实际完成 arm64/x64 应用和 DMG 的签名、公证 Accepted、staple 与 Gatekeeper 通过。不要上传私钥或密码到对话、代码或日志。
2. 在全新下载环境验证 M1 安装和覆盖升级；用 Android 历史生产签名验证升级，完成 iOS 真机与 Windows x64 原生验收。
3. 覆盖真实账号/后端、离线下载、音频切换、异常网络和真实辅助功能设备等端到端流程；本轮单元/组件测试与原生启动不替代这些检查。
4. 正式修复版本需递增版本与构建号，不能覆盖或复用线上 `1.1.46`。明确提交、标签、平台和产物并得到用户批准后才能发布。

本轮创建的两个诊断磁盘镜像挂载已卸载。原线上 DMG、诊断副本和新开发产物保留供复核；没有修改 `/Applications` 中的用户安装、远程凭据或线上 Release。
