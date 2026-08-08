# DuckMusic TVBox 源切换设计

本仓库的实现与后端设计说明见：

`/Users/wangweijie/projects/idea/website-backend/docs/superpowers/specs/2026-08-07-duckmusic-tvbox-source-switching-design.md`

客户端只从 ECS 获取启用源目录，影视配置、目录、详情和播放解析直接请求当前源；客户端不执行第三方 `spider` JAR，只支持标准 CMS JSON API。源选择按源 id 持久化，历史按 `sourceId + videoId` 隔离，播放继续复用现有安全媒体地址校验和投屏链路。
