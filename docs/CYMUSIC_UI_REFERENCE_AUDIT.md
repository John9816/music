# Cymusic UI Reference Audit

## 结论

`gyc-12/Cymusic` 值得参考，但不适合直接移植代码。它是 React Native / Expo / TypeScript 项目，本地项目是原生 Android XML + Kotlin。正确做法是借鉴它的信息架构、视觉层级和播放体验，把本地界面从「装饰型首页」改成「内容优先的音乐工具」。

## Cymusic 值得借鉴的点

1. 底部结构清晰

   Cymusic 使用 4 个一级 Tab：`Songs`、`Radio`、`Favorites`、`Search`。每个 Tab 都是明确的任务入口，底部 Tab 常驻，当前位置用高亮色和图标状态表达。

2. 播放器一直可达

   `FloatingPlayer` 悬浮在 TabBar 上方，显示封面、歌名、播放/暂停、下一首和进度条。用户在任何主页面都能快速回到播放状态，不需要先理解当前页面层级。

3. 列表是主内容

   歌曲、榜单、收藏、搜索结果都以列表为核心。页面顶部只保留标题、搜索框或少量操作，减少不必要的卡片堆叠。

4. 播放页沉浸但控制区稳定

   播放页使用专辑封面/背景色建立氛围，但标题、进度、主控、音量、歌词/循环/队列入口的位置稳定。沉浸感没有牺牲可操作性。

5. 设置页按任务分组

   设置页是分组列表：应用信息、音频设置、自定义音源。每组内是行项目，右侧放当前值或进入箭头，扫描效率高。

## 本地项目当前主要不适点

1. 首页层级过重

   `fragment_discover.xml` 顶部有 Hero、最新专辑、周热、推荐摘要、每日推荐列表，多层 Card 和分割线同时出现。首屏注意力被装饰和栏目标题分散，用户很难立刻进入听歌动作。

2. 搜索/曲库入口混杂

   `fragment_library.xml` 的 Tab 文案是曲库，但主要内容是搜索面板和搜索结果。底部菜单里 `nav_library` 使用搜索图标，会让「我的音乐/曲库」和「搜索」的心智模型混在一起。

3. Mini Player 已接近 Cymusic，但信息密度还不够顺

   `activity_main.xml` 的 `miniPlayer` 已有封面、标题、播放/暂停、队列和进度环。问题是它缺少歌手/来源等次级信息，进度环也比横向细进度条更难一眼判断播放进度。

4. 播放页控制区像底部控制卡片

   `bottom_sheet_now_playing.xml` 把进度、音质、收藏、播放控制集中在 `controlsBar` Card 内。功能完整，但视觉上更像工具面板，不如 Cymusic 的「封面 - 曲目信息 - 进度 - 主控 - 次级操作」自然。

5. 圆角和卡片感偏重

   `dimens.xml` 里 radius 从 `14dp` 到 `36dp`，多个页面又套 `MaterialCardView`。音乐播放器可以有质感，但现在很多信息块都像独立容器，页面整体呼吸感被切碎。

## 建议改版方向

### P0: 先修信息架构

- 底部 Tab 建议调整为：`发现`、`搜索`、`歌单`、`我的`。
- `nav_library` 如果继续承载搜索，就改名为 `搜索` 并使用搜索图标；如果要做真正曲库，就把搜索框降级成顶部入口，主内容改为本地音乐、下载、收藏、最近播放。
- 每个 Tab 只解决一个一级任务，避免在同屏塞多个业务目标。

### P1: 让首页内容优先

- `发现` 首页首屏建议保留：
  - 顶部标题/搜索入口
  - 1 个主推荐区
  - 1 个歌曲列表
- 删除或折叠过重的 Hero 文案、摘要 Chip、重复说明性副标题。
- 最新专辑和周热可以作为横向模块，但不应同时挤占首屏主要高度。

### P1: 重做 Mini Player 手感

- 改成 Cymusic 类似的横向悬浮条：封面 40-44dp、两行文本、播放/暂停、下一首、底部 2dp 进度条。
- 保留队列入口，但可以放进更多菜单或长按菜单，避免主控区过拥挤。
- Mini Player 和 BottomNav 之间保持 8dp 间距，列表底部 padding 要覆盖 Mini Player + BottomNav 总高度。

### P2: 播放页改成固定节奏

- 页面节奏建议为：
  - 顶部关闭条/返回
  - 大封面或歌词区
  - 歌名 + 歌手 + 更多
  - 进度条 + 时间
  - 上一首 / 播放暂停 / 下一首
  - 次级操作：歌词、循环、队列、音质
- `btnAudioQuality` 不建议放在进度条上方作为首个控件，音质是次级操作，应弱化到更多菜单或底部次级栏。

### P2: 统一视觉语气

- 主色继续用 `#FF2D55` 可以，音乐产品辨识度够强。
- Surface 层级减少到 2 层：页面背景 + 列表/浮层。避免页面里多个大 Card 互相嵌套。
- 列表项保持 48-56dp 封面、主标题 16sp、歌手 13-14sp、更多按钮 48dp 点击区域。

## 推荐落地顺序

1. 修改底部 Tab 命名和图标，先解决入口认知问题。
2. 简化 `fragment_discover.xml`，把首屏改成标题 + 搜索入口 + 推荐列表。
3. 调整 `miniPlayer` 为横向进度条样式，增加歌手副标题。
4. 调整播放页控制区，把音质/收藏/队列降级为次级操作，突出主播放控制。
5. 最后再处理颜色、圆角、动效和暗色主题细节。

## 参考文件

- Cymusic: `src/app/(tabs)/_layout.tsx`
- Cymusic: `src/components/FloatingPlayer.tsx`
- Cymusic: `src/app/player.tsx`
- 本地项目: `app/src/main/res/layout/activity_main.xml`
- 本地项目: `app/src/main/res/layout/fragment_discover.xml`
- 本地项目: `app/src/main/res/layout/fragment_library.xml`
- 本地项目: `app/src/main/res/layout/bottom_sheet_now_playing.xml`
