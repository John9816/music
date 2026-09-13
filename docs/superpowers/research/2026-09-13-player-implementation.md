# 播放器布局与操作验证

日期：2026-09-13。对应生产可用性计划 Task 4 与设计 D 节。

## 实现结果

- `player_view.dart` 按实际约束选择布局。窄屏竖排保留播放控制，工具不足一行时分成两组；横屏使用封面/歌词与控制双栏。封面舞台和控制区在高度不足时独立滚动。
- 主要按钮与音质入口最小 44 px。字号放大时预留歌曲信息与歌词标题的自然高度，切换歌词不会移动播放按钮。旋转时复用页面与控制子树，保留歌词页和控件状态。
- 播放、收藏、播放方式、歌词、睡眠、队列等操作补齐中文标签；语义名称、选中/启用状态与点击动作位于同一按钮节点。随机播放的辅助功能点击已验证能切回关闭状态。
- `mini_player.dart` 按自身宽度选择桌面或紧凑布局。桌面中栏使用剩余空间，时间文字保持单行；重要按钮至少 44 px，Android 为 48 px。减弱动态效果时直接更新栏内容。
- 桌面迷你栏复用 `GProgressBar`，移除重复拖动实现，继承拖动、键盘与辅助功能时间描述。桌面进度目标默认 28 px，触摸平台为 44 px。手机纯展示进度仍为 3 px。
- 新增 `MiniPlayer.desktopHeight(BuildContext context)` 供主框架统一避让播放栏。默认桌面 80 px、Android 宽栏 100 px、iOS 宽栏 96 px，大字号必要时继续增高。主代理已将停靠面板的 bottom 接入此接口。

## 失败证据

先新增 `test/player_responsive_layout_test.dart` 再修改实现。首次运行原有生产代码时，初始 9 项测试全部失败，其中可稳定复现：

| 场景 | 观察到的失败 |
| --- | --- |
| 320×700，1×/1.5×字号 | 工具栏向右溢出 22 px |
| 812×375，1×字号 | 封面舞台向下溢出 122 px |
| 812×375，1.5×字号 | 向下溢出 126 px |
| 320×430，1.5×字号 | 向下溢出 71 px |
| 1080 px 桌面迷你栏，1.5×字号 | 向右溢出 16 px，时间换行造成向下溢出 30 px |
| 1280 px 窗口中的 720/320 px 迷你栏 | 仍误用固定宽度桌面栏并溢出 |

后续专项检查同样先观察失败再修正：随机播放的具名语义节点没有 tap 动作；桌面迷你栏没有“播放进度”操作入口；从竖屏歌词页旋转到横屏后，页面位置从 1 回到 0。

## 最终验证

```sh
flutter analyze --no-pub lib/features/player/player_view.dart lib/features/player/mini_player.dart test/player_responsive_layout_test.dart
```

结果：`No issues found!`，退出码 0。

```sh
flutter test --no-pub test/player_responsive_layout_test.dart --reporter expanded
```

结果：新增 13 项全部通过。覆盖 320×700、812×375、1.5×字号、320×430 低高度滚动、旋转保留歌词页、主要按钮点击及辅助功能动作、局部约束迷你栏，以及 macOS/Android/iOS 宽栏进度点击后从 `2:00` 通过右方向键前进到 `2:05`。

```sh
flutter test --no-pub test/player_responsive_layout_test.dart test/player_interaction_test.dart test/design_system_regression_test.dart test/mobile_performance_regression_test.dart test/widget_test.dart --reporter expanded
```

结果：最终 101 项全部通过，退出码 0。包括已有 320×568、375×667、390×844、430×932 全屏布局、280/320 px 迷你栏 2×字号、歌词滚动与跟随、队列、下拉收起、减弱动态效果和曲目来源切换测试。

`git diff --check` 对本任务代码无空白错误。

## 变更范围与交接

本任务仅修改 `lib/features/player/player_view.dart`、`lib/features/player/mini_player.dart`，新增本报告与 `test/player_responsive_layout_test.dart`。未修改 `desktop_player_panel.dart`、播放器控制器、已有测试、依赖、发布配置或版本，未提交或推送。

以上是 Flutter 布局和交互回归证据。原生音频、投放设备、真实屏幕阅读器与平台安装包仍由主代理的集成和设备验收覆盖。
