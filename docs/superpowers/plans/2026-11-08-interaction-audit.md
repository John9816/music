# Android Interaction Audit Implementation Plan

> **For agentic workers:** Use systematic-debugging and verification-before-completion. Independent fixes follow dispatching-parallel-agents; run Flutter commands sequentially through the primary agent.

**Goal:** 按用户要求彻底检查现有音乐 App 的页面交互、动画渲染、排版、按钮、控件与点击反馈，修复可复现问题并提供实际可操作的验证版本。

**Architecture:** 保留现有 Flutter 设计与数据接口。先验证共用控件契约，再分别检查播放器、歌曲菜单及各页面；修复限定在实际发现的问题，使用行为回归与运行截图验证。

**Tech Stack:** Flutter / Dart，widget tests，Android emulator / ADB。

**Spec:** 用户 2026-11-08 指令“我建议你彻底检查一遍”，以及已有 TuneFreeNext 对齐方向。

## Global Constraints

- 保留生产包 com.music.player 与已有数据，调试版本使用 com.music.player.debug。
- 不修改账户、收藏或歌单数据，不执行真实删除、兑换或下载清理。
- 不发布新的正式版本；先交付修复和模拟器验收。
- 原有 macOS 调查文档及其他未提交文件保持不变。
- 测试小屏 320×640、常规手机 390×844、横屏 844×390，以及文字倍率 1 / 2，深浅主题与减弱动态效果。
- Flutter 测试、构建逐个运行，避免工具锁竞争；模拟器只由主代理操作。

## Task 1: 共用控件与触控反馈

Files: lib/widgets/glass.dart，lib/widgets/responsive_button.dart，lib/core/theme/platform_motion.dart；test/interaction_controls_test.dart，test/platform_motion_test.dart。

- [x] 快速点按、取消、禁用与加载态加入回归，验证有效操作仅发生一次。
- [x] 已接受的快速点击保留短暂可见反馈，取消后恢复且不执行回调。保留 Flutter 手势竞争机制，不要求原始指针按下后首个 16ms 内就反馈，以免滚动时误触发。
- [x] 修复共用按压状态、热区与禁用显示；触摸模式不显示键盘焦点框。
- [x] GPageHeader 窄屏大字下换行，资料库和个人页图标与标题垂直居中；播放器进度与歌词手势有回归。
- [ ] 嵌套歌曲行/歌手/更多按钮的所有组合逐一真机复测（本轮仅覆盖菜单入口与既有自动化）。

## Task 2: 播放器与转场

Files: lib/features/player/player_view.dart，mini_player.dart，queue_view.dart；test/player_interaction_test.dart，player_responsive_layout_test.dart，mobile_performance_regression_test.dart。

- [x] 自动化覆盖播放器入口、下拉取消/关闭、歌词与进度手势、队列重复打开；模拟器实测队列、返回、短拖回弹和长拖关闭。
- [x] 对音量误提交、旧音质弹层操作新歌曲、弹层大字溢出等问题保存失败测试后修复。
- [x] 保留已有播放器手势模型，通过手势回归；未将未测量的逐帧平滑程度或真机帧率标为已验证。
- [x] 动画监听器生命周期、后台页面重建、封面解码尺寸、暂停/减弱动态效果下的动画均有自动化验证。

## Task 3: 歌曲菜单与二级页面

Files: lib/widgets/song_action_menu.dart，lib/features/profile，lib/features/playlists，lib/features/settings；相关现有测试及新的行为测试。

- [x] 菜单重复打开、关闭重开、边界、键盘避让、减弱动态效果及转场监听器加入自动化；模拟器实测菜单锚点与返回。
- [x] 歌曲收藏和添加歌单操作增加异步保护、错误后恢复；音质和睡眠定时弹层支持小屏/横屏大字滚动。
- [x] 修复歌单导入标题溢出、定时器到期回调丢失，保存对应回归。
- [ ] 用户歌单登录会话变化、批量删除/清空历史失败反馈、存储加载失败进一步实测。本轮不执行真实破坏性操作，静态疑点不作为确认缺陷。

## Task 4: 全页面与运行验收

- [x] 模拟器检查首页、发现、搜索、资料库、个人、设置、专辑详情、播放器、队列与歌曲菜单；歌单及其他布局状态由自动化补充。
- [x] 完成改动审阅及独立复核，修复减弱动态效果遗漏与主推文字对比度问题。
- [x] 全量 466 项测试、22 项视觉测试通过；最后标题对齐调整后 33 项相关测试通过，最终 analyze 无问题。
- [x] 构建并安装 com.music.player.debug，最终安装时间 2026-11-08 11:05:02；正式包未替换。
- [x] 前后截图、测试日志、最终进程错误日志和检查记录已保存，详情见 ../research/2026-11-08-interaction-design-audit.md。

## Visual direction — user clarification

用户补充：主要问题是整个设计缺少质感。以现有音乐内容和参考 App 的克制陈列为依据，整合视觉基础并实际验证。

- 首页以真实主推封面作为唯一醒目区域，文字置于有足够对比度的底部渐层，主操作单独留出位置；大字时允许高度增长。
- 手机主标题 27/600、宽屏 28/600，区块标题 20/600，内容文字按歌曲列表和说明层级设置。中文沿用系统字体，避免额外字体混搭。
- 中性浅底 #F7F8FA、白色表面 #FFFFFF、正文 #202126、次级 #737780；暗色背景 #101113、抬升 #1B1D21。用户主题色继续保留，仅用于主操作和选中态。
- 全局 20px 外边距、区块 28px 节奏；封面 10px，功能表面 16–20px，弹层 24px 圆角。
- 底栏统一图标23px、文字10.5px，避免图标和选中标签同时过重；播放器以主播放键和专辑图为重心。
- 快速点按提供短暂可见反馈，滚动/取消不执行操作。动画遵循用户减弱动态效果设置。
- 以模拟器真实数据截图、深浅主题和布局测试验收，不能以静态分析代替视觉评价。
