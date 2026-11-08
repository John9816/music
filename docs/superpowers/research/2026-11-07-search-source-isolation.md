# 搜索音源与首页、发现隔离

2026-11-07。用户指出搜索切换音源会同时更换首页和发现。

## 原因与修复

搜索的音源按钮原先调用 `SettingsController.setSource`，修改全局 `music_source`。主界面监听该值并重建首页、发现及资料库，造成联动。

- 新增独立保存的 `search_music_source`。旧安装第一次加载时沿用已有全局音源作为搜索初值，之后分别保存。
- 搜索按钮、请求、过期响应检查及结果详情回退音源统一改用 `searchSource`。
- 搜索歌单缺少来源字段时，在打开详情前补齐来源并固定本次来源，保证详情加载和收藏操作一致。
- 首页和发现继续使用原来的全局音源，搜索选择不会重建这两个页面。

## 验证

证据目录：`build/qa/search-source-isolation-2026-11-07/`。

- 修复前手机和桌面的隔离测试均重现全局音源被改成 `qq`：`isolation-red.log`。
- 独立偏好读取、快速切源、歌手/专辑/歌单缺少来源时的详情路由，均先复现失败：`search-red.log`。旧设置迁移先重现失败：`migration-red.log`。
- 相关测试 36 项通过：`focused.log`；最终全量 **433 项通过**：`full-tests.log`。静态分析 **No issues found**：`analyze.log`；`git diff --check` 通过。
- 构建并用 REA `--replace` 安装到 `emulator-5554`。安装证据 `ev_705f45a7a966451640d0a4447313aecc81e765a9c66a672440cbf7e538f06837`；启动成功证据 `ev_e4eaf7d31cca033d744938c8ee7a43a6cae9f2251d01cc293db6c0293bfecf09`。
- APK：`build/app/outputs/flutter-apk/app-debug.apk`，165,163,908 字节；SHA-256 `17e58b2c2b2e1f0a5384949c091f47b186e73a4d10f4e922841bb305e1aa1e11`。
- 实测先打开红源首页和发现，再去搜索选择绿源并搜索“周杰伦”，结果正常。读取两个音源偏好确认 `music_source=netease`、`search_music_source=qq`，见 `source-before.json` 和 `source-after.json`。
- 返回首页、发现后内容保留。对两页截图的主内容区域 `(0,90)-(1080,2015)` 做像素比较，前后均无差异：`page-comparison.json`。原始截图与 REA JSON 见 `home-before/after`、`discover-before/after`、`search-green`；预览为 `source-isolation-preview.png`。
- 最终停在绿源搜索结果页，音乐维持暂停。未提交、推送或发布。
