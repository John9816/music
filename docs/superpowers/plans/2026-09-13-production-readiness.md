# DuckMusic Production Readiness Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development for bounded implementation and review. Independent file ownership permits parallel work; the main agent integrates and verifies the full application.

**Goal:** 修复 macOS 分发完整性，完成音乐核心流程在多端尺寸和输入方式下的可用性优化。

**Architecture:** 复用现有 Flutter/Provider/Glass 组件。按发布脚本、主框架、搜索、资料库、播放器与通用控件划分文件所有权。用行为回归测试约束布局、分页、状态恢复及发布门禁。

**Tech Stack:** Flutter 3.44.8, Dart 3.12.2, Xcode 26.6, Bash, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-13-production-readiness-design.md`

## Global Constraints

- 保持 Android `com.music.player` 和历史生产证书、后端协议、用户数据兼容。
- 不新增依赖，不公开发布，不修改远程凭据，不重用已发布版本/标签。
- 使用现有主题、中文界面和减弱动态效果设置。
- 各任务仅编辑自己负责文件；统一集成由主代理完成。
- 测试验证行为、输出和错误恢复，不通过搜索源文件字符串来代替测试。
- 实施开始时工作区干净且为 `flutter-migration`；本地验收完成时改动尚未提交。在此完成修改，避免复制大型原生构建缓存；此决定仅影响本地可回滚的工作区改动。

## Task 1: macOS 发布完整性与信任链

**Files:** `.github/workflows/flutter-release.yml`, `scripts/*macos*.sh`, `RELEASE.md`, macOS 专项脚本行为测试。

**Interfaces:** 保持 `scripts/build_ios_helper.sh <output>` 和已安装客户端识别的正式 DMG 文件名。正式发布签名身份由 CI secret 提供。

- [x] 核验线上 arm64 DMG 的 SHA-256、应用资源 seal、签名、架构及 Gatekeeper 结果，记录可复现证据。线上包的 Gatekeeper 检查受环境限制；最终开发包在获准环境中明确 rejected，不能作为正式分发验收。
- [x] 为打包流程的缺失身份、helper 存在性、目标架构和校验失败增加可运行的测试；使用临时目录和受控工具替身，不写用户安装。16 项通过，含 2 项真实 macOS 原生检查。
- [x] 完成 helper 写入后再签名的封包顺序；签署嵌入代码、校验应用，恢复公证和 staple，正式标签缺配置即失败。真实 Apple 公证仍是发布门禁，不计入本地通过结果。
- [x] 验证开发 DMG 内容与内含应用的签名完整性，更新发布说明，运行脚本测试与 Bash 语法校验。DMG 本体的 Developer ID 签名、公证和正式信任验证尚未执行。

## Task 2: 主框架与导航状态

**Files:** `lib/features/home/home_shell.dart`, 需要时新增同目录布局辅助类，`test/home_shell_responsive_test.dart`。

**Interfaces:** 继续使用 `MiniPlayerPanel`、`MiniPlayer.onPanelChanged`、`UserLibraryView.active`，不更改播放控制器 API。

- [x] 增加行为回归：1280 宽窗打开面板后依次缩至 900、700，内容不留幽灵占位；隐藏页不持有键盘焦点。
- [x] 统一面板宽度和占位条件，确保 560 px 主内容最小宽度；移动导航加入资料库并保留嵌套路由。
- [x] 在缓存之外更新收藏/历史激活状态，保护文本编辑快捷键并提供桌面搜索入口。
- [x] 执行主框架、导航返回与现有移动主题回归测试。额外以 sessionGeneration 区分账户更换和 token 轮换，保留同账户的页面与输入状态；15 项会话代次测试通过。

## Task 3: 搜索响应式与分页恢复

**Files:** `lib/features/search/search_view.dart`, `test/search_resilience_test.dart`。

**Interfaces:** 保持 `SearchView(initialQuery:)`、现有 MusicApi 请求类型和分页参数。不得修改其他代理的 shell 文件。

- [x] 使用受控 HTTP 响应复现满页后空页、第二页失败后重试、局部内容宽度与窗口宽度不一致。
- [x] 使用 LayoutBuilder 驱动展示，维护明确的成功页和待重试页，避免缩窗引发数据丢失。
- [x] 保留成功结果，提供可用分页和重试；错误/加载/空内容各有明确反馈。
- [x] 运行搜索专项测试和现有 widget_test 搜索用例。

## Task 4: 播放器多端布局

**Files:** `lib/features/player/player_view.dart`, `lib/features/player/mini_player.dart`, `lib/features/player/desktop_player_panel.dart`（仅确有需要）, `test/player_responsive_layout_test.dart`。

**Interfaces:** 继续使用 GProgressBar 现有参数，主代理将增加可选的语义标签与键盘能力。保持 PlayerController 和导航入口兼容。

- [x] 复现 320×700 工具栏溢出与 812×375 横屏高度不足；加入 1.5 倍文本、实际控制点击验证。
- [x] 按实际宽高调整竖屏/横屏排版；维持触摸尺寸，合理布局次级操作和可滚动内容。
- [x] 补主要按钮标签与状态描述，完善迷你栏在窄窗口的布局。
- [x] 运行播放器专项、交互及已有全屏布局测试。

## Task 5: 资料库与设置、进度控件

**Files:** `lib/features/library/library_view.dart`, `lib/features/settings/settings_components.dart`, `lib/features/settings/settings_view.dart`, `lib/widgets/glass.dart`, 对应独立测试。

**Interfaces:** 复用 UserApi、UserPlaylistLibrary 和 SongDownloadService；保持 GProgressBar 必填参数兼容。

- [x] 资料库用真实数据展示歌单、下载与登录状态；请求失败可重试，窄卡片不使用无界 Spacer。
- [x] 设置行显式接收开关状态并正确生成行操作/语义，长值与大字布局可换行。
- [x] 进度控件增加焦点、左右键与辅助功能增减动作，保留拖动体验和仅展示模式。
- [x] 运行每个故障对应测试与组件回归。

## Task 6: 集成与交付验证

**Files:** 本计划与专项验证报告。

- [x] 评审各任务实现与接口交集，消除集成冲突和未处理的高优先级问题。macOS 发布与 UI 两条独立复审均无剩余 Critical/Important 问题。
- [x] `flutter analyze`、`flutter test --no-pub`：静态检查无问题，366 项成功、0 失败、0 跳过；18 个 Dart 文件只读格式检查无改动。
- [x] 构建 macOS release，校验本地开发 DMG 与原生启动；Android debug 与 iOS unsigned release 编译通过；9 个离线场景导出并人工检查 10 张最终截图。Windows 缺少本机环境，未构建。
- [x] 在 `docs/superpowers/research/2026-09-13-production-readiness-verification.md` 报告已验证内容、实际安装包，以及仍需满足的签名/公证和真机验收条件。没有公开发布。

## 未完成的生产发布门禁

本地验收后，用户已授权推送代码并启动 GitHub Actions。本次选择在 `flutter-migration` 分支手动运行验证构建，不创建发布标签、不更新 ECS、不创建公开 Release；以下正式发布门禁保持未完成状态。

- [ ] 在有效 Developer ID / Apple 公证凭据环境中，实际通过 arm64 与 x64 的应用、DMG 签名、公证、staple 和 Gatekeeper 校验；本地开发包被 Gatekeeper 拒绝，不代表完成这一步。
- [ ] 完成全新 macOS 安装与覆盖升级、Android 历史生产签名升级、iOS 真机及 Windows 安装/升级/卸载验收。
- [ ] 递增正式版本和构建号，明确提交、标签、平台与产物，取得用户授权后再推送、上传或发布；当前仍为本地 `1.1.46+57` 开发验证产物。
