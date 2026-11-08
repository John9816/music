# 播放音频身份与歌词一致性

日期：2026-11-08。配套后端仓库：`/Users/wangweijie/projects/idea/website-backend`；后端设计和实现记录见其 `docs/superpowers/` 下的同日 music-reliability 文档。

## 本轮行为

- 解析播放地址时同时读取 `actualSource`、`actualId`、`lyricMatch` 和实际时长。收藏、歌单、队列仍保留原始歌曲身份。
- 同步歌词使用实际录音身份；明确未验证的录音、跨源但没有实际 ID 的旧响应不加载同步歌词。兼容未提供新字段的同源旧响应。
- 播放取词拒绝明确 `official:false` 的备用歌词，避免文本匹配返回另一录音的歌词。缺少该字段的旧接口保持兼容；不会人为生成逐字时间戳。
- 音频请求和下载请求使用实际音源请求头；缓存文件按实际录音身份区分，并保存身份旁文件。下载清单保存同样的身份；无法确认身份的旧离线文件不套用原曲同步歌词。
- 下载请求标记 `prefetch=true`，避免把下载操作记为播放历史。
- 播放器与系统媒体信息使用音频实际时长；恢复、清空、播放失败和销毁时清理已解析信息。已经失效的歌词请求不能回写当前状态。

## 验证与复查

- 最终 `flutter test --no-pub --reporter expanded`：534 项通过。
- 最终 `flutter analyze --no-pub`：无问题。
- `git diff --check`：通过。
- 独立审查发现清空后残留旧音频时长；已用清空、恢复、加载失败、失败后迟到歌词 4 个行为回归复现并修复，修复复审通过。
- 配套后端 `mvn -q clean verify`：403 项通过，0 失败/错误/跳过。

测试使用已有的 `build/qa/tunefree-alignment-2026-11-07/tool-bin` 包装器与 CommandLineTools 环境，没有修改系统 Xcode 许可。最终日志及 `verification-summary.json` 位于 `build/qa/music-reliability-2026-11-08/`。

本轮尚未打包新版 APK、进行 Android 真机回归、提交、推送或部署。之前的两个 macOS 研究文档改动不属于本任务，已保留。
