# 设计系统说明（大厂级 UI/UX）

本项目的视觉语言对齐 Apple Music / Spotify 等大厂音乐应用，并与原 Android 项目（`/Users/wangweijie/projects/android/music`）的 `Theme.MusicPlayer.*` 配色同源。

## 设计原则

1. **内容优先**：明暗模式使用稳定的中性表面，让封面与内容成为视觉主体；全屏播放页 / 歌单详情页可使用封面模糊作为局部氛围背景。
2. **文字层级**：Apple 语义文字色（`#F5F5F7` / `#A1A1A6` / `#6E6E73`），大标题紧字距、粗字重，次级信息弱化。
3. **玻璃质感**：表面统一半透明填充 + 1px 细线（hairline），不做廉价投影。
4. **动效克制**：120–320ms 缓动，按压微缩反馈、页面淡入上浮、歌词滚动缓动，速度与质感平衡。
5. **组件一致性**：全部 UI 走 `lib/widgets/glass.dart` 设计系统组件，不散落裸样式。

## 设计令牌（Design Tokens）

`lib/core/theme/design_tokens.dart`

| 令牌 | 说明 |
| --- | --- |
| `AppBrand.green` / `AppBrand.cueYellow` | 固定品牌绿 `#2FD365` 与提示黄 `#FFD25A`，不随用户强调色变化 |
| `DarkPalette` / `LightPalette` | 暗/亮主题基础色板（背景、表面、文字、细线、玻璃） |
| `TypeScale` | 字号 + 字重（11–28pt） |
| `Space` | 4pt 网格间距 |
| `RadiusToken` | 圆角（8–28 + 胶囊） |
| `ShadowToken` | 统一卡片/封面阴影 |
| `Motion` | 动效时长与曲线 |

## 主题

`lib/core/theme/app_theme.dart` 将明暗模式、品牌色和用户强调色分开处理。设置页保留 7 种强调色，强调色只用于按钮、进度、选中态等交互焦点；页面背景与容器使用统一中性色，不随强调色染色。

| 强调色 | 色值 | 用途 |
| --- | --- | --- |
| 律动红 | `#FF375F` | 交互强调 |
| 落日橙 | `#FF9F0A` | 交互强调 |
| 森林绿（默认） | `#30D158` | 交互强调 |
| 湖水青 | `#40C8E0` | 交互强调 |
| 天际蓝 | `#0A84FF` | 交互强调 |
| 幻夜紫 | `#BF5AF2` | 交互强调 |
| 蔷薇粉 | `#FF6482` | 交互强调 |

每种强调色都动态选择黑色或白色前景，保证主要文字对比度至少达到 WCAG AA 4.5:1。明暗模式的 surface 层级保持一致，切换强调色不会改变页面明暗或信息层级。

主题通过 `ThemeExtension<GlassTokens>` 提供玻璃填充 / 细线 / 抬升表面等令牌，组件统一取用。

## 组件库

`lib/widgets/glass.dart`：

- `GPressScale`：按压缩放反馈基座
- `GAppBar` / `GButton` / `GIconButton` / `GListTile` / `GChoiceChip` / `GSegmented` / `GSurface` / `GProgressBar` / `GLoading` / `GEmptyState`
- `pageTitleStyle` / `SectionHeader` / `glassFill` / `glassHairline`

交互组件以 `GestureDetector` 为基础。Windows / Linux 的可点击目标额外提供指针与轻量 hover，纵向滚动区域显示滚动条；macOS 保留无 `MouseRegion` / `RawScrollbar` 的兼容路径，规避已知 MouseTracker 断言（保留 `scripts/patch_flutter_mouse_tracker.sh` 兼容性）。

## 响应式断点

断点集中在 `GBreakpoints`，按布局语义使用，而不是按设备名称猜测：

| 断点 | 宽度 | 用途 |
| --- | --- | --- |
| `compact` | 600 | 手机紧凑布局 |
| `contentSplit` | 720 | 内容区双栏布局 |
| `sidebar` | 840 | 侧边栏与完整播放页分栏 |
| `desktopPlayer` | 1080 | 固定桌面播放区域 |
| `contentMax` | 1320 | 主内容最大宽度 |

## 页面

| 页面 | 设计要点 |
| --- | --- |
| 主框架 `home_shell.dart` | 232px 侧边栏：Logo + 搜索 + 导航 + 我的歌单 + 用户脚部；窄屏底部导航 |
| 首页 `discover_view.dart` | 时间问候 + 今日主推 + 最新专辑（桌面带前后导航）+ 每日推荐 |
| 搜索 `search_view.dart` | 分段控件（单曲/歌手/歌单）+ 多源切换 + 历史/热词胶囊 |
| 播放页 `player_view.dart` | 封面模糊氛围背景 + 旋转唱片 + 歌词居中高亮 + 宽/窄双布局 |
| 迷你播放栏 `mini_player.dart` | 封面 + 白底播放圆钮 + 音量/队列 + 底部细进度 |
| 歌单详情 `playlist_detail_view.dart` | 模糊封面沉浸头部 + 播放全部 + 歌曲列表 |
| 发现 / 资料库 / 个人中心 / 设置 / 工具 | 统一走组件库，随主题自动升级 |

## 后端约定

所有数据与播放接口均走自有后端 `https://api.751152.xyz/`（`lib/core/config/app_config.dart`），不接入任何第三方客户端直连。
