# 产品验收报告

日期：2026-07-18

## 当前结论

当前版本达到“可进入真机内测 / Beta 验收”的工程门槛，但还不是可直接正式发布的合格产品。

原因：
- 自动化构建、单测、lint、release 混淆构建均已通过。
- 机器上没有 `adb`，未能执行真机安装、真实播放链路、后台播放和长时间稳定性验证。
- 当前 release 产物是 unsigned APK，缺少正式签名配置，不能作为正式发布包。
- release lint 仍有 158 个 warning，主要是性能、资源、可访问性和国际化问题；其中 `InsecureBaseConfiguration` 是有意允许第三方音乐媒体流明文地址的产品取舍。

## 已执行验证

| 项目 | 命令 / 检查 | 结果 |
| --- | --- | --- |
| Debug 构建 | `.\gradlew.bat assembleDebug` | 通过 |
| 单元测试 | `.\gradlew.bat testDebugUnitTest` | 通过 |
| 完整检查 | `.\gradlew.bat check` | 通过 |
| Release lint | `.\gradlew.bat lintRelease` | 通过，0 errors / 158 warnings |
| Release 构建 | `.\gradlew.bat assembleRelease` | 通过 |
| APK 产物 | `app/build/outputs/apk/release/app-release-unsigned.apk` | 生成成功，约 3.19 MB |
| 设备连接 | `where.exe adb` | 当前环境未找到 adb |

单测结果：
- Debug Unit Test：6 tests / 0 failures / 0 errors
- Release Unit Test：6 tests / 0 failures / 0 errors

## 本次修复

- 修复移动网络播放音质策略：移动网络质量现在作为上限，不会把用户较低的首选音质自动升高。
- 保留 `addPlayHistory(song: Song)` 兼容签名，并显式抑制当前后端记录播放历史导致的未使用参数警告。
- 将 `ShimmerView` 从字符串反射式 `ObjectAnimator` 改为 `ValueAnimator` 回调，规避 release 混淆后的动画风险。
- 简化 `PlaybackService` 中过时的 SDK 判断。
- 在 manifest 中接入 `network_security_config.xml`，让已有网络安全策略实际生效。
- 对有意导出的 `PlaybackService` 添加 lint 标注，避免误判为未解释的导出服务。

## 主要剩余风险

### P0：正式发布阻塞

1. Release APK 未签名
   - 当前产物：`app-release-unsigned.apk`
   - 需要配置 `keystore.properties` 后生成正式签名包。

2. 未完成真机验收
   - 当前机器无 `adb`，无法安装启动 APK 或跑 UI smoke test。
   - 必须至少覆盖一台 Android 8-10 和一台 Android 13-14 设备。

### P1：发布前建议处理

1. 明文流量基础配置
   - 文件：`app/src/main/res/xml/network_security_config.xml`
   - 当前策略：自有 API 域名强制 HTTPS，但基础配置允许 cleartext，以兼容第三方音乐媒体 URL。
   - 建议：如果可以确认播放 URL 全部 HTTPS，改成默认禁止明文，只对白名单媒体域名放行。

2. release lint 仍有 158 warnings
   - 主要类别：`UnusedResources`、`Overdraw`、`RtlSymmetry`、`HardcodedText`、`ClickableViewAccessibility`、`TooDeepLayout`。
   - 当前不阻塞构建，但会影响体积、性能、可访问性和国际化质量。

3. 应用内更新权限
   - manifest 申请了 `REQUEST_INSTALL_PACKAGES`，代码中用于自更新安装 APK。
   - 如果目标发布渠道不允许应用内下载安装包更新，需要移除或按渠道拆分。

## 真机回归清单

### 安装启动

- 安装 release 签名包。
- 首次启动进入登录页，无闪退。
- 切后台再恢复，无白屏、无重复启动页面。
- 深色模式和浅色模式分别启动一次。

### 登录链路

- 使用有效账号登录成功。
- 错误密码显示明确错误。
- token 过期后能刷新或提示重新登录。
- 退出登录后回到登录页，返回键不能回到已登录页面。

### 播放链路

- 搜索歌曲并播放。
- 播放 / 暂停 / 下一首 / 上一首可用。
- 拖动进度条后位置正确。
- 弱网下有加载状态，不闪退。
- 播放失败时有错误提示，并可切换音质重试。
- 熄屏后继续播放。
- 通知栏媒体控制可播放 / 暂停 / 切歌。
- 耳机或蓝牙媒体键可控制播放。

### 歌单和用户数据

- 收藏歌曲后刷新仍存在。
- 取消收藏后列表同步更新。
- 播放历史产生记录。
- 删除单条历史和清空历史生效。
- 创建歌单、导入歌单、删除歌单生效。
- 向歌单添加和移除歌曲生效。

### 下载和更新

- 下载歌曲成功后能在下载页看到。
- 删除下载项后文件和 UI 同步。
- 检查更新不会阻塞主流程。
- 下载的更新 APK 签名校验不通过时拒绝安装。

### 稳定性

- 连续播放 30 分钟无崩溃。
- 快速连续切歌 20 次无卡死。
- 断网后恢复网络，搜索和播放能恢复。
- 后台播放 10 分钟后回前台，播放状态一致。

## 发布判定

当前判定：Beta 可验收。

正式发布前必须完成：
- 配置 release 签名并生成 signed APK / AAB。
- 至少一轮真机完整回归。
- 明确 `InsecureBaseConfiguration` 是否接受。
- 根据发布渠道确认 `REQUEST_INSTALL_PACKAGES` 是否允许。
