# 酷我歌曲封面模糊排查与本地修正

日期：2026-11-07。

## 结论

主要原因是后端选错封面字段。`website-backend` 的
`KuwoMusicClient.kuwoCoverUrl` 原先把 `hts_MVPIC` / `MVPIC` 排在
`web_albumpic_short` 前面，导致有专辑封面的歌曲仍返回 MV 横版缩略图。
仅有专辑封面的部分结果则直接返回 120 像素缩略图。

在模拟器上观察到《晴天》的播放页使用 MV 画面，主体封面明显模糊。
实际下载的该图片只有 324×182 像素。正方形播放器使用 `BoxFit.cover`
会继续裁切并放大这张横图。酷我提供的正确《叶惠美》专辑封面为
500×500 像素，两者不只是尺寸不同，内容本身就不同。

## 实测证据

读取项目既有登录会话后，仅以只读搜索请求抽查周杰伦、陈奕迅、
Taylor Swift 各 5 首歌曲，去重后共 15 首。未输出或持久化令牌。

- 线上聚合 API 返回 14 张 MV 缩略图，1 张 120×120 专辑缩略图。
- MV 图片实测尺寸包含 324×182、324×184、324×243、322×182、
  323×182 和 207×116。
- 酷我官方搜索响应中，这 15 首都有独立的 `web_albumpic_short` 字段。
- 按真实专辑路径将 `/star/albumcover/120/` 请求为
  `/star/albumcover/500/`，15 张图片均成功下载并解码为 500×500。
- 把 MV 文件名直接拼到专辑目录的尝试返回 404，因此修正使用真实
  专辑字段，没有按 MV 文件名推测专辑地址。

证据目录：`build/qa/kuwo-artwork-2026-11-07/`。

| 文件 | 内容 |
| --- | --- |
| `before.png` | 模拟器当时的《晴天》播放页 |
| `api-covers.json` | 聚合 API 的歌曲及封面字段；响应中 list/songs 重复，统计按歌曲 ID 去重 |
| `image-probe.json` | 原始图片实际尺寸和试探地址的响应结果 |
| `official-search-cover-fields.json` | 官方搜索提供的歌曲、MV、专辑图片字段 |
| `official-album-cover-probe.json` | 15 张正确专辑图的地址、解码尺寸和字节数 |
| `qing-tian-cover-comparison.png` | 左侧为旧 MV 图裁切至方形，右侧为真实专辑封面；不是已部署版本截图 |
| `backend-red.log` | 修正前，新增/更新测试中 6 项按预期失败 |
| `backend-green.log` | 修正后后端相关测试日志 |

## 修改范围

仅修改本地后端项目：

- `/Users/wangweijie/projects/idea/website-backend/src/main/java/com/example/website/service/music/KuwoMusicClient.java`
- `/Users/wangweijie/projects/idea/website-backend/src/test/java/com/example/website/service/music/KuwoMusicClientTests.java`

歌曲封面选择保留原有显式 `albumpic` / `pic`，将真实专辑字段移动到
MV 字段前。对选中的酷我域名、且路径严格为
`/star/albumcover/120/…` 的图片请求已实测的 500 像素版本。
保留已有大图、URL 查询参数、其他域名和缺少专辑封面时的 MV/歌手图回退。
搜索、歌单等共用映射的歌曲结果均适用，不新增逐首网络请求。

Flutter 的磁盘封面缓存最多为 512 像素，但本次问题图片原本只有
120～324 像素，主要问题发生在后端选图。正确的 500×500 图片不会被
这一缓存上限进一步缩小。本次没有改动客户端缓存或安装包。

## 验证及上线状态

使用 Temurin 21 执行：

```sh
mvn -q -Dtest=KuwoMusicClientTests,MusicServiceTests test
```

结果：KuwoMusicClientTests 24 项、MusicServiceTests 21 项，共 45 项通过，
0 失败、0 错误。后端 `git diff --check` 通过。

测试覆盖真实字段优先级、120→500、已有大图不降级、查询参数、
非酷我及伪后缀域名不改写、MV/歌手图/无图回退，以及歌单映射与搜索请求数量。

以上是首次诊断时的验证结果。随后用户明确要求发布，后端已按下方记录上线。
已经持久化了旧 MV 地址的收藏、历史和播放队列不会因为这次映射修正自动迁移，
需要重新取得歌曲元数据。
本次排查与先前 Android 闪退问题无关，不代表闪退已经解决。

## 后端生产发布

- 提交：`e79b8191c152b608bdfcec46415839c6ad3c6754`。
- 发布目录：`/opt/website/releases/20261107T111318Z-kuwo-artwork-e79b8191c152`。
- 激活时间：2026-11-07 19:14:29（Asia/Shanghai）。
- JAR SHA-256：`3feb5d424ad22894aa8dc842989d3b8b79ea2739a556bfa079e2f0287b912b71`。
- 全量后端测试 **324 项通过，0 失败、0 错误、0 跳过**；Maven 打包成功。
- 与线上 JAR 逐项哈希对比，仅 `KuwoMusicClient.class` 和 `application.yml`
  不同。后者为已在服务配置中生效的 Security 日志 INFO 默认级别，不含数据结构变更。
- 发布前数据库备份：`/opt/backups/website-before-kuwo-artwork-20261107T111258Z.sql.gz`，
  415,972 字节；已完整解压检查结束标志，SQL 原始 6,390,509 字节。
- 沿用线上前端文件和运行服务配置，原子切换 current，仅重启 API。
  激活脚本在健康检查失败时自动恢复旧版本；previous 指向
  `/opt/website/releases/20261105T171432Z-fcfaa386a4f0-fab50eee96bd`。
- 公网 API 健康、网页和网页代理接口均 HTTP 200。
- 线上重新搜索 3 位歌手各 5 首歌曲，全部 15 张封面为真实专辑路径，
  成功下载并解码为 500×500。网易、QQ 搜索同时通过。
- 已完成激活后的 15 分钟观察，最终采样时间 19:29:29。全部采样健康检查
  为 HTTP 200 / up，自动重启 0 次，应用 ERROR 日志 0 条。
  最终服务内存约 400 MiB。另记录启动期间 1 条 WARN，未出现健康检查失败。

证据：`release-build.log`、`production-jar-manifest-before.json`、`activate-backend.sh`、
`deploy.log`、`production-verification.json`、`production-monitor.jsonl`。
最后一项记录发布后的连续健康采样；App 正式包发布另行验收。
