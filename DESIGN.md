# 设计系统说明（大厂级 UI/UX）

本项目的视觉语言对齐 Apple Music / Spotify 等大厂音乐应用，并与原 Android 项目（`/Users/wangweijie/projects/android/music`）的 `Theme.MusicPlayer.*` 配色同源。

## 设计原则

1. **沉浸优先**：暗色主题默认纯黑背景，让封面与内容成为视觉主体；全屏播放页 / 歌单详情页使用封面模糊作为氛围背景。
2. **文字层级**：Apple 语义文字色（`#F5F5F7` / `#A1A1A6` / `#6E6E73`），大标题紧字距、粗字重，次级信息弱化。
3. **玻璃质感**：表面统一半透明填充 + 1px 细线（hairline），不做廉价投影。
4. **动效克制**：120–320ms 缓动，按压微缩反馈、页面淡入上浮、歌词滚动缓动，速度与质感平衡。
5. **组件一致性**：全部 UI 走 `lib/widgets/glass.dart` 设计系统组件，不散落裸样式。

## 设计令牌（Design Tokens）

`lib/core/theme/design_tokens.dart`

| 令牌 | 说明 |
| --- | --- |
| `AppBrand.red` | 品牌红 `#FF2D55`（收藏红心、渐变） |
| `DarkPalette` / `LightPalette` | 暗/亮主题基础色板（背景、表面、文字、细线、玻璃） |
| `TypeScale` | 字号 + 字重（11–28pt） |
| `Space` | 4pt 网格间距 |
| `RadiusToken` | 圆角（8–28 + 胶囊） |
| `ShadowToken` | 统一卡片/封面阴影 |
| `Motion` | 动效时长与曲线 |

## 主题

`lib/core/theme/app_theme.dart` 提供 5 套主题（与 Android 版同名同源）：

| 主题 | 强调色 | 背景 |
| --- | --- | --- |
| 暗黑（默认） | 白 | 纯黑 |
| 明亮 | `#FF2D55` | iOS 分组灰 `#F2F2F7` |
| 日落 | `#FF756C` | `#101217` |
| 海洋 | `#59CDEB` | `#09141A` |
| 石墨 | `#C3F26A` | `#0D100C` |

主题通过 `ThemeExtension<GlassTokens>` 提供玻璃填充 / 细线 / 抬升表面等令牌，组件统一取用。

## 组件库

`lib/widgets/glass.dart`：

- `GPressScale`：按压缩放反馈基座
- `GAppBar` / `GButton` / `GIconButton` / `GListTile` / `GChoiceChip` / `GSegmented` / `GSurface` / `GProgressBar` / `GLoading` / `GEmptyState`
- `pageTitleStyle` / `SectionHeader` / `glassFill` / `glassHairline`

所有组件基于 `GestureDetector`，**不使用 MouseRegion / RawScrollbar / Slider**，规避 macOS Flutter 鼠标断言卡死问题（保留 `scripts/patch_flutter_mouse_tracker.sh` 兼容性）。

## 页面

| 页面 | 设计要点 |
| --- | --- |
| 主框架 `home_shell.dart` | 232px 侧边栏：Logo + 搜索 + 导航 + 我的歌单 + 用户脚部；窄屏底部导航 |
| 首页 `home_view.dart` | 时间问候 + 今日电台（品牌渐变卡）+ 快捷入口 + 正在流行（排名角标横滑）+ 精选歌单 |
| 搜索 `search_view.dart` | 分段控件（单曲/歌手/歌单）+ 多源切换 + 历史/热词胶囊 |
| 播放页 `player_view.dart` | 封面模糊氛围背景 + 旋转唱片 + 歌词居中高亮 + 宽/窄双布局 |
| 迷你播放栏 `mini_player.dart` | 封面 + 白底播放圆钮 + 音量/队列 + 底部细进度 |
| 歌单详情 `playlist_detail_view.dart` | 模糊封面沉浸头部 + 播放全部 + 歌曲列表 |
| 发现 / 资料库 / 个人中心 / 设置 / 工具 | 统一走组件库，随主题自动升级 |

## 后端约定

所有数据与播放接口均走自有后端 `https://api.751152.xyz/`（`lib/core/config/app_config.dart`），不接入任何第三方客户端直连。
