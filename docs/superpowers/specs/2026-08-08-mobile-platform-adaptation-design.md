# 移动端平台自适应 UI/UX 与动效设计

## 背景

当前 Flutter 应用已经有 iOS/Android 的页面转场和基础安全区处理，但移动端主要通过宽度阈值压缩桌面组件。结果是：导航层级、底部播放器、触控反馈、页面切换和系统返回虽然“能用”，但不像同一个成熟的移动端产品。

本设计先处理移动端公共壳层和动效基础，再让播放器和内容页逐步接入。第一阶段不重写业务页面、不改变 API 或播放状态模型。

## 目标

- 在 iOS 和 Android 上保持一致的信息架构，同时遵循各自的导航与触感习惯。
- 让底部导航、页面切换、系统返回和底部播放器形成稳定的移动端层级。
- 统一安全区、触控尺寸、键盘避让和横竖屏下的可见性规则。
- 建立可复用的平台动效和反馈组件，后续页面不再各自硬编码动画。
- 支持系统“减少动态效果”设置，关闭非必要动画但保留状态变化和导航可理解性。

## 非目标

- 不在第一阶段重做首页内容卡片、搜索结果、歌单详情或播放器业务逻辑。
- 不把 Flutter 页面改写为 SwiftUI，也不维护两套独立的 iOS/Android 页面树。
- 不引入新的动画依赖；优先复用 Flutter SDK、现有 `GPressScale`、`Motion` 令牌和 Provider 状态。
- 不修改网络协议、播放队列、缓存和登录流程。

## 平台原则

### 共同结构

- 移动端固定为四个一级入口：`首页`、`发现`、`搜索`、`我的`。
- 每个入口保留独立的嵌套导航栈；切换 Tab 不销毁页面，返回只处理当前 Tab 的栈。
- 底部导航、MiniPlayer 和页面内容按同一条垂直安全区链布局，MiniPlayer 不覆盖底部导航或系统手势区域。
- 所有可交互元素至少 44 logical px；Android 的主要操作目标扩展到 48 logical px，图标视觉尺寸不随之放大。

### iOS

- 一级导航保留轻量标签栏和选中态，不模拟 Android 的 FAB 或强烈涟漪。
- 页面进入使用 Cupertino 风格横向推入；返回支持边缘右滑，取消手势时页面回到原位。
- 点击反馈以透明度、轻微缩放和 `HapticFeedback.selectionClick` 为主，不使用明显的水波纹。
- 弹层优先使用带安全区的圆角底部面板，操作列表使用 iOS 语义的分组间距和拖拽手柄。

### Android

- 一级导航保留 Material 3 风格的选中指示和触摸反馈。
- 页面进入使用预测返回兼容的 Material 转场；系统返回优先弹出当前 Tab 内层页面。
- 主要点击提供轻量涟漪或缩放反馈，并在导航、播放和 Tab 切换等关键动作提供短触感。
- 弹层继续使用 Material bottom sheet，最大高度、键盘避让和系统导航栏颜色由公共组件统一处理。

## 组件与边界

### `HomeShell`

继续负责一级导航、嵌套导航栈、MiniPlayer 宿主和平台返回协调。移动端布局拆出明确的 `_MobileScaffold`，桌面侧栏分支保持不变。

移动端 Scaffold 的层级固定为：

1. `Expanded` 内容区，包含当前 Tab 的嵌套 Navigator。
2. MiniPlayer（有播放内容时显示）。
3. 安全区内的移动 BottomNav。

Tab 切换只改变内容区的活动状态，不影响 MiniPlayer 和 BottomNav 的几何位置。切换时保留页面状态，并使用平台对应的短转场。

### `PlatformMotion`

在 `lib/widgets` 增加小型平台动效工具，统一以下能力：

- `pageTransition`：iOS 横向推入，Android 预测返回兼容转场。
- `tabSwitch`：当前内容轻微淡入并沿平台方向位移，持续时间来自 `Motion.fast` 或 `Motion.normal`。
- `pressFeedback`：复用 `GPressScale` 的语义和键盘支持，按平台决定缩放与透明度表现。
- `reduceMotion`：读取 `MediaQuery.disableAnimations`，将非必要动画时长设为零。

工具只包装动画，不持有业务状态；页面状态仍由 `HomeShell` 和现有控制器管理。

### `MiniPlayer`

第一阶段只调整宿主布局和进出动画：

- 移动端保持稳定高度，不因歌曲标题、错误提示或按钮状态改变而推动 BottomNav。
- 从无播放到有播放使用由下向上的短进入动画；关闭或播放队列打开使用反向动画。
- iOS 使用透明度 + 上移，Android 使用透明度 + 上移并保留轻量按压反馈。
- 所有内容继续遵守底部 `SafeArea`，横屏窄高场景优先保证播放、暂停和展开入口可见。

## 动画状态与数据流

```
用户点击 Tab
  -> HomeShell 更新活动索引
  -> 当前 Tab Navigator 保留其栈
  -> PlatformMotion 播放短转场
  -> MiniPlayer / BottomNav 保持几何稳定

系统返回
  -> 当前 Tab Navigator 尝试 pop
  -> 有内页：只退出内页
  -> 无内页：回到首页
  -> 首页根页：交给平台系统退出行为
```

动画只依赖 `activeTab`、Navigator 栈状态和 `MediaQuery.disableAnimations`。不把网络加载、播放进度或登录请求绑定到页面转场，避免异步状态导致动画重启。

## 错误与边界处理

- SafeArea、键盘和横屏尺寸变化只影响布局约束，不重置导航栈或播放状态。
- 页面加载失败时显示原有错误状态，错误出现/消失不改变 MiniPlayer 和 BottomNav 的位置。
- 快速连续点击 Tab 时只保留最后一次目标状态，不能叠加多个转场或重复创建 Navigator。
- 系统关闭动画时，所有转场仍在同一帧完成，页面不能短暂透明或显示错误 Tab。
- 触控目标扩展不能覆盖相邻操作；点击区域和 Semantics 标签保持一一对应。

## 实现范围

第一阶段主要修改：

- `lib/features/home/home_shell.dart`：拆分移动 Scaffold，统一内容、MiniPlayer、BottomNav 和返回处理。
- `lib/widgets/glass.dart` 或新增 `lib/widgets/platform_motion.dart`：抽取平台反馈与动画入口，保留现有公共组件行为。
- `lib/features/player/mini_player.dart`：接入移动宿主的稳定高度和进入/退出动画。
- `lib/app.dart`：只在需要时补充平台安全区或系统导航栏语义，不改变全局主题颜色。
- `test/widget_test.dart` 及必要的独立 widget 测试：覆盖平台、尺寸、返回、Tab 切换和减少动态效果。

桌面侧栏、桌面播放器和业务 API 不在本阶段改动。

## 测试方案

- 在 `320x568`、`375x667`、`390x844`、`430x932` 下分别使用 Android 和 iOS theme pump 移动壳层。
- 断言 BottomNav、MiniPlayer 和主要页面控件不溢出、不被安全区裁切，主要按钮保持最小点击尺寸。
- 测试四个 Tab 切换后页面状态保持，当前 Tab 的二级页面由系统返回正确退出。
- 测试 iOS 边缘右滑、Android 系统返回和根页退出行为。
- 测试 `disableAnimations: true` 时转场立即完成且没有异常透明状态。
- 测试 MiniPlayer 出现、消失和打开详情时 BottomNav 的位置稳定。
- 运行完整 Flutter 测试、`flutter analyze` 和格式检查。

## 分阶段交付

1. 第一阶段：移动壳层、平台动效、返回、安全区、MiniPlayer 宿主和回归测试。
2. 第二阶段：全屏播放器的 iOS/Android 控件密度、歌词切换和手势动画。
3. 第三阶段：首页、搜索、歌单和弹层的移动间距、空状态和加载动效统一。

## 验收标准

- iOS 和 Android 的一级导航结构一致，但返回、按压、转场和弹层符合平台习惯。
- 任何支持的移动尺寸下，内容、MiniPlayer、BottomNav 和系统手势区不重叠。
- Tab 切换、页面 push/pop、MiniPlayer 出现/消失都有可预期的短动效；减少动态效果时不闪烁。
- 快速操作不会重复 push 页面、丢失 Tab 状态或让播放器位置跳动。
- 第一阶段测试在 Android/iOS 两套 theme 和所有目标尺寸下通过。
