# DuckMusic 第三轮细节调整

日期：2026-11-07。用户同意全部五项建议：缩短手机歌单封面、收起单曲删除、区分封面加载状态、首页两块内容独立加载、统一次级页面。

## 实现与检查范围

- 两类手机歌单使用较短的封面区域，标题仍按实际文字高度布局；桌面结构保留。
- 歌单/喜欢/历史的单曲移除进入歌曲菜单，并按来源显示确认；批量管理保留。取消喜欢成功后只更新仍在播放的同来源、同 ID 歌曲。
- 首页推荐和专辑分别管理请求、缓存和错误，先完成的部分先显示；局部重试只请求失败部分，刷新保留已有内容和滚动位置。
- 歌单目录使用方形封面和统一的 20dp 留白；搜索框根据文字自然增高；下载列表修正重复缩进；多歌手面板可滚动并适配大字体。
- 封面的缺图、加载和失败有不同表现，失败支持重试；缓存与真实解码验证记录在下方。

所有新增功能在本地调试版验证，不发布、不提交、不推送。真实账号的歌单/喜欢/历史/下载删除均未用于破坏性测试；相关测试使用假 API 或临时目录。

## 验证记录

证据目录：`build/qa/tunefree-refinement-2026-11-07/`。`before/` 保留上一轮 35 张截图。

- 歌曲菜单及大字体/横屏相关第一轮 17 项通过：`library-green.log`。
- 喜欢状态回归先重现当前歌曲未清除的错误，另外歌曲和同 ID 不同来源不会被清除：`favorite-red.log`；修复后完整个人歌单测试 17 项通过：`library-final.log`。
- 首页 16 项通过：`secondary-home-green.log`（该次合并运行的两个次级页面测试异步问题随后单独修正）。
- 次级页面 4 项通过：`secondary-green.log`，包括真实临时下载文件删除；搜索裁字回归由 `search-red.log` 独立重现。
- 当前已有页面截图检查 21 项通过：`visual-tests.log`；新增首页局部加载/失败截图 1 项通过：`partial-visual.log`。
- 最终全量测试 **425 项通过**：`full-tests.log`；`dart analyze lib test` 输出 **No issues found**：`analyze.log`；`git diff --check` 通过。最终导出并保存 44 张页面截图至 `after/`。
- 封面、图片缓存及请求策略共 **22 项通过**：`focused-final.log`。真实受控 HTTP 与图片解码覆盖 503→重试成功、损坏 PNG→重试成功、旧图刷新失败保留、小图与晚订阅者缓存、两个真实详情页横竖屏重试点击。
- 小图缓存与动画原格式缓存均先重现失败：`small-cache-red.log`、`animated-cache-red.log`。修复后所有格式共享一致的尺寸缓存键；小图和 GIF/WebP 保留原字节与格式，不放大、不转码动画；双帧 GIF 的字节和帧数由回归测试确认。静态大图仍按比例限制尺寸。

## 构建、安装与运行

- 构建成功：`build-apk.log`。APK 为 `build/app/outputs/flutter-apk/app-debug.apk`，165,162,102 字节，SHA-256 `bf3ead91946baa0faa81a15732f43a478c2d3d3c81388c94cc101ae50252cb15`。
- 已通过 REA 安装到 `emulator-5554`，使用 `--replace`；安装证据 `ev_f826d4b76c17b41ea83a0e721ff9a9bdf5fdebc515b5bf097a605c8cea46bf32`。没有卸载操作，启动后原账号与两个歌单仍在。
- 包检查为 `com.music.player.debug`，`1.1.46-debug (57)`；设备记录更新时间 `2026-11-07 17:17:19`。包证据 `ev_2de15b4498dc48f39eab070724b0a2bf70f13a6157a77366c2505b90c7e53cf0`。
- 实际检查首页、歌单目录、314 首歌曲的个人歌单、歌曲菜单与空下载页。截图及 REA 记录保存在 `live-home-ready`、`live-directory`、`live-owned-ready`、`live-owned-menu`、`live-downloads` 对应目录/JSON；菜单显示“从歌单移除”，未执行真实删除。
- 播放 `ありがとう・・・ / KOKIA` 后进入后台并熄屏。初始媒体进度 563ms；电源状态为 `Asleep` 时进度 37,562ms，仍为 `PLAYING`；唤醒回到播放页显示 `01:41`。下一首切换至 `泪的告白 / 司南`，页面显示 `00:07` 且继续播放。随后暂停，媒体状态为 `PAUSED`、进度 40,501ms。见 `media-*.txt`、`power-locked.txt`、`live-player-resumed` 与 `live-next`。
- 本次运行 PID 始终为 `22781`，按该 PID 过滤的 AndroidRuntime/Flutter 错误与 libc fatal 日志为空：`runtime-errors.log`。这是一次短时调试版模拟器检查，不能推断不同机型、长时间后台或生产包的偶发闪退已解决。
- 最终返回首页，音乐暂停；本轮未调整主题设置，仍沿用跟随系统的配置。真实下载为空，下载删除行为由临时文件测试覆盖。

## Onevra 适用性

工作期间用户询问 https://oneo-me.github.io/onevra/ 能否用于本项目。已直接读取官网和官方仓库 README，分别保存为 `onevra-page.html`、`onevra-readme.md`。

Onevra 是 Go / MyGo 的桌面组件库，官网列出 macOS、Windows、Linux。当前 DuckMusic 使用 Flutter / Dart，因此无法直接把它当作 Flutter 或安卓控件依赖接入。可以参考它的视觉风格，在现有 Flutter 组件中实现；本轮没有添加 Onevra 依赖或更换框架。

官方 README 标明项目 MIT，改编的 MyGo 控件与 Lucide 图标保留各自上游许可。若后续实际移植源码或资源，应保留相应声明；本轮没有复制这些代码或资源。

## 原安卓闪退边界

本轮主要处理界面和数据加载体验。原生产 APK 的通知图标资源调查见 `2026-11-07-tunefree-control-alignment.md` 与对应 `notification-finding.md`。短时模拟器检查不能证明频繁闪退已修复。
