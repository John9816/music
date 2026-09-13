# 搜索响应式与分页恢复实现记录

日期：2026-09-13。对应 `2026-09-13-production-readiness.md` Task 3，以及设计规范 Section C。

## 修改范围

- `lib/features/search/search_view.dart`
- 新增 `test/search_resilience_test.dart`
- 本报告

未修改 shell、播放器、资料库、设置、Glass 组件或其他测试文件。未新增依赖，未提交、推送或发布。

## 实现与接口决策

- 用搜索页的 `LayoutBuilder` 实际宽度决定展示，不再依据整个窗口宽度决定请求或结果类型。
- 显式增加“综合”范围。首次布局宽度至少 720 px 时默认综合，较窄时默认单曲；此后只由用户操作切换范围。所有尺寸都可切换综合、单曲、歌手、专辑、歌单。缩放窗口不会重新解释结果或修改待完成请求的范围。
- `_page` 保留已成功显示的页；`_retryPage` 单独记录失败目标页。错误后继续显示旧结果和说明，重试请求原失败页。综合下一页全部为空时保留最后有效页、禁用继续向后翻页。
- 类型切换栏在局部宽度不足或文字放大时允许横向滚动。来源行与分页按局部宽度展示；歌单网格列数、卡片高度与综合歌单区高度按可用宽度和字体缩放计算。
- 初始搜索骨架在普通布局的结果区域内可滚动，并提供“正在搜索”语义标签；不改变 Glass 骨架组件，也不增高外层容器。
- 可用高度小于字体缩放后的 480 px 时，搜索头、范围、来源、结果和分页共用一个纵向滚动区。内层有限分页列表使用 `shrinkWrap` 并关闭内层滚动，避免固定头或固定页脚挤出内容。输入框保持挂载，范围和来源没有隐藏。
- 保持 `SearchView(initialQuery:)`、原有 `MusicApi` 请求类型、offset/limit 换算和每页 30 条不变。仅增加可选 `focusNode` 供 shell 搜索快捷键使用；该节点由调用方持有，本页不主动获取焦点或销毁它。
- 保留已有的请求版本、关键词、范围与来源校验，旧响应不能覆盖新查询。

## 行为回归与 RED 证据

测试通过真实 `MusicApi`/`ApiClient` 路径，使用受控 HTTP 客户端提供响应并记录实际 endpoint、source、pageSize、type、page；未用源代码字符串检查替代行为验证。

1. 综合满页后下一页为空：修复前丢失第一页内容/页码；修复后保留有效页并停止继续请求空页。
2. 第二页失败后重试：修复前重试第一页，无法显示第二页歌曲；修复后请求序列为 1、2、2，旧结果和失败页说明均可见。
3. 1280 px 窗口内仅 390 px 的搜索内容：修复前未出现可点击的窄屏类型控件；修复后按局部宽度请求单曲并提供可用分页。
4. 综合歌手结果完成后缩到 390 px：修复前歌手消失；修复后保留结果和关键词，不发起新请求。
5. 单独歌手搜索扩到 1280 px 后翻页：修复前发出四种请求；修复后只发 ARTIST 第二页请求。
6. 综合请求等待期间缩窗：修复前响应按新宽度被错误解释；修复后维持原请求范围。
7. 320 px 内容宽、2 倍文字的歌单网格：修复前底部溢出 31 px；修复后标题可见且没有布局异常。
8. 2 倍文字的综合歌单卡片：修复前底部溢出 35 px；修复后无布局异常。
9. 1280×800 窗口内 1017.6×700 搜索区域：`enterText('abcd')` 后首帧、debounce 完成后的受控等待帧、成功响应分别检查。修复前首帧骨架底部溢出 64 px；修复后各阶段无异常。
10. 812×375 横屏、1.5 倍文字、仅 230 px 内容高：修复前固定搜索头底部溢出 52 px；修复后实际滚动访问类型、来源、输入框、结果和分页，无布局异常。

## 验证结果

- `flutter test --no-pub test/search_resilience_test.dart --reporter expanded`：10 项通过。
- `flutter test --no-pub test/widget_test.dart --name 'search' --reporter expanded`：4 项通过，覆盖桌面点击区域、各平台搜索文字、四类型分页、来源切换。
- `flutter analyze --no-pub lib/features/search/search_view.dart test/search_resilience_test.dart`：No issues found。
- `dart format lib/features/search/search_view.dart test/search_resilience_test.dart`：最后一次检查 0 个文件变化。
- `git diff --check -- lib/features/search/search_view.dart test/search_resilience_test.dart`：无错误。

已有搜索用例曾在两个 Flutter 测试命令并发启动时遇到 `build/native_assets/macos/objective_c.dylib` 临时缺失的签名错误；单独重跑同一命令后 4 项全部通过。后续验证已顺序执行，避免共享 native assets 构建目录竞争。

## 验证边界

本任务验证受控网络响应和 Flutter widget 行为，未据此声称真实后端服务、各平台真机或系统输入法已经验收。完整测试套件、平台构建、shell 实际布局与截图由主代理集成验证；本任务没有运行全套测试或修改发布配置。
