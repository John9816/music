# DuckMusic 音乐产品基准审计

## 结论

当前原型模仿了音乐产品的表面视觉，但没有落实生产级产品最重要的四个结构：高密度可比较的曲目列表、可持续的播放上下文、明确的响应式重排，以及可验证的状态系统。

“纯黑 + 全部玻璃卡片 + 大 Hero”不能作为产品基线。成熟桌面音乐产品使用少量实体 surface、内容架（shelf）和行级操作，让用户在浏览、比较、播放和回到队列之间保持连续。

## 参考产品观察

### Spotify Web

- 左侧固定“音乐库”导航，提供创建歌单和播客入口。
- 顶栏提供 Home、全局搜索、Browse 以及账户/安装等工具。
- 主体由多个横向内容架组成，每个架有“显示全部”，卡片和曲目行都有独立播放入口。
- 底部固定 Now Playing dock，包含曲目身份、收藏、shuffle/repeat、上一首/播放/下一首、进度、音量、队列和 Now Playing 视图。
- 即使未登录，播放器结构仍然完整；禁用态和注册提示被明确分层。

### Apple Music Web

- 左侧导航收敛为 Search、Home、New、Radio，账户和“在音乐中打开”是独立动作。
- “新发现”首屏用少量双列 Banner carousel 承担编辑推荐，其余内容使用高密度歌曲列表。
- 歌曲行同时提供播放、歌曲名、艺人和更多菜单；列表比大卡片更适合快速比较。
- 播放控制和营销提示位于内容底部的独立层，避免干扰内容层级。
- 主要内容使用实体深灰 surface 和细微分隔，不给每个区块都加玻璃描边和强阴影。

## 当前 DuckMusic 的差距

- `DESIGN.md` 将“纯黑背景、统一半透明填充 + hairline”写成总原则，但没有 surface 层级、hover/focus 规则或内容密度规则。
- `DESIGN.md` 的首页描述是问候、今日电台、快捷入口、热门横滑和精选歌单；当前代码的主入口实际是 `HomeShell` 中的 `DiscoverView`，显示每日推荐、最新专辑和主推内容。两者不能同时作为 Figma 的 source of truth。
- `lib/features/home/home_view.dart` 仅有两个横滑架和两个快捷卡片，没有 Recent/Continue Listening、section-level See all 或高密度 song rows。
- Figma 规格允许“component-like frames”和“neutral image placeholder”。这不足以证明组件可复用，也无法检查真实封面裁切、文本长度和 hover/playing 状态。
- 文档写品牌红 `#FF2D55`，实际 `AppBrand.red` 和暗色主题 primary 为品牌绿 `#2FD365`。需要先确定代码为唯一真源，或同步修正文档。

## 推荐生产基线

### 桌面 Shell

- 画布：`1440 x 900`。
- 左栏：`240px` 固定；窗口缩窄到 `1100px` 时收为 `64px` icon rail。
- 顶栏：`64px`，包含返回/前进、全局搜索和账户动作。
- 内容：12 列或最大 `1200px`，左右 gutter `24/32px`；不要让内容随着窗口无限放大。
- 播放 dock：`72px` 固定在底部；歌词/队列常驻面板从右侧展开，宽度 `360-420px`。

### 首页信息层级

1. Greeting + Continue Listening/Recent 的高密度曲目列表（行高约 `64px`）。
2. 一组 2-up 编辑推荐 Banner，承担有限的 Hero 叙事。
3. 5-up 推荐歌曲或艺人 shelf。
4. 5-up 歌单/专辑 shelf，均提供“显示全部”。

今日电台可以保留，但不应占据首屏一半，也不应与搜索、资料库并列为两个大按钮。

### 颜色与表面

- 背景：`#0F0F0F`。
- Surface：`#181818`；Raised：`#242424`。
- Primary：`#2FD365`，只用于播放、选中、进度和成功反馈。
- 文本：`#F5F5F7 / #A1A1A6 / #6E6E73`。
- 禁止每个卡片都使用渐变、强阴影和大圆角。图片可以有 `8px` 圆角；交互控件优先 `6-8px`。

### 必须建成真正组件的状态

- `SongRow`: default / hover / playing / selected / downloaded / disabled。
- `Card`: default / hover / focus。
- `NavItem`: default / hover / selected / focus。
- `MiniPlayer`: empty / loading / playing / error。
- `Search`: idle / focused / typed / results / no-results。
- `Button`: filled / tonal / ghost / disabled。
- 全部图标动作提供 tooltip 和可访问名称；焦点环和最小 `44px` 命中区域可见。

### 核心播放流

`Home song row play -> MiniPlayer -> full Player -> Lyrics/Queue -> favorite/add to playlist -> Library`

队列行必须能移除或重排；收藏、加入歌单、下载等异步操作必须有提交中、成功和失败反馈。播放器至少展示暂无播放、缓冲中、播放中、暂停、播放错误、无歌词和空队列。

## Figma 验收清单

- 重复的 SongRow、NavItem、MiniPlayer 是真正 component instances，能够 swap，而不是复制的 frame。
- 颜色、间距、字号由 variables/styles 绑定；修改一个 token 能影响所有实例。
- Core Flow 至少覆盖会话恢复/登录、首页、搜索空态、搜索结果、详情、播放器、收藏/加入歌单、资料库和设置。
- 每个核心区块至少有成功、loading、empty、error、提交中五类状态。
- 在 `1440/1100/768/390` 四个宽度检查无裁切、水平溢出或底部播放器遮挡；移动端必须重排为底部四 Tab，不是把桌面画布压窄。
