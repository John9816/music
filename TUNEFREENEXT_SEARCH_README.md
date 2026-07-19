# TuneFreeNext 搜索接口抓取记录

抓取对象：模拟器内 `com.sayqz.tunefreenext`，版本 `3.1.3`。

抓取时间：2026-05-31。

## 结论

TuneFreeNext 搜索页里有三个音源：红源、橙源、绿源。当前界面证据显示红源选中时，搜索 `林俊杰` 的歌单 Tab 返回网易云音乐结果。APK 静态字符串中也能看到网易、酷我、QQ 三类 Provider：

- `package:tune_free_next/data/providers/netease/netease_provider.dart`
- `package:tune_free_next/data/providers/kuwo/kuwo_provider.dart`
- `package:tune_free_next/data/providers/qq/qq_provider.dart`

本次已经验证可以直接用 `curl` 请求成功的搜索接口有三个：

- 网易搜索：标准 JSON，推荐作为首选。
- 酷我搜索：HTTP 200 且返回结果，但响应是单引号的类 JSON，不是严格 JSON。
- 绿源/QQ 搜索：标准 JSON，和模拟器绿源歌曲 Tab 的首屏结果一致。

说明：第一版漏掉绿源，是因为只测试了 APK 字符串里最直观的 `musicu.fcg` 和 `client_music_search_songlist`，这两条直接请求失败。补测后确认绿源可用接口是 `search_for_qq_cp`。

## 网易搜索接口

### 歌曲搜索

```bash
curl.exe -L -G "https://music.163.com/api/search/get/web" ^
  --data-urlencode "s=林俊杰" ^
  --data-urlencode "type=1" ^
  --data-urlencode "offset=0" ^
  --data-urlencode "limit=5" ^
  -H "Referer: https://music.163.com/" ^
  -H "User-Agent: Mozilla/5.0"
```

已验证结果：

- HTTP 状态：`200`
- 返回大小：`3815` bytes
- `code`: `200`
- `result.songCount`: `286`
- 第一条歌曲：`Always Online`
- 第一条歌手：`林俊杰`

### 歌手搜索

```bash
curl.exe -L -G "https://music.163.com/api/search/get/web" ^
  --data-urlencode "s=林俊杰" ^
  --data-urlencode "type=100" ^
  --data-urlencode "offset=0" ^
  --data-urlencode "limit=3" ^
  -H "Referer: https://music.163.com/" ^
  -H "User-Agent: Mozilla/5.0"
```

已验证返回 `code=200`，结果里包含 `林俊杰`，`artistCount=22`。

### 专辑搜索

```bash
curl.exe -L -G "https://music.163.com/api/search/get/web" ^
  --data-urlencode "s=林俊杰" ^
  --data-urlencode "type=10" ^
  --data-urlencode "offset=0" ^
  --data-urlencode "limit=3" ^
  -H "Referer: https://music.163.com/" ^
  -H "User-Agent: Mozilla/5.0"
```

已验证返回 `code=200`，结果里包含 `交换余生`、`和自己对话`、`新地球`。

### 歌单搜索

```bash
curl.exe -L -G "https://music.163.com/api/search/get/web" ^
  --data-urlencode "s=林俊杰" ^
  --data-urlencode "type=1000" ^
  --data-urlencode "offset=0" ^
  --data-urlencode "limit=3" ^
  -H "Referer: https://music.163.com/" ^
  -H "User-Agent: Mozilla/5.0"
```

已验证返回 `code=200`，结果里包含 `听·林俊杰热门精选|过`，与模拟器界面红源歌单 Tab 的返回形态一致。

### 参数说明

| 参数 | 说明 |
| --- | --- |
| `s` | 搜索关键词 |
| `type` | 搜索类型：`1` 歌曲，`10` 专辑，`100` 歌手，`1000` 歌单 |
| `offset` | 分页偏移，从 `0` 开始 |
| `limit` | 每页数量 |

常用返回字段：

| 搜索类型 | 结果路径 | 计数字段 |
| --- | --- | --- |
| 歌曲 | `result.songs` | `result.songCount` |
| 专辑 | `result.albums` | `result.albumCount` |
| 歌手 | `result.artists` | `result.artistCount` |
| 歌单 | `result.playlists` | `result.playlistCount` |

## 酷我搜索接口

```bash
curl.exe -L -G "http://search.kuwo.cn/r.s" ^
  --data-urlencode "all=林俊杰" ^
  --data-urlencode "ft=music" ^
  --data-urlencode "client=kt" ^
  --data-urlencode "pn=0" ^
  --data-urlencode "rn=5" ^
  --data-urlencode "rformat=json" ^
  --data-urlencode "encoding=utf8" ^
  --data-urlencode "vipver=MUSIC_9.0.5.0_W1" ^
  --data-urlencode "newver=1"
```

已验证结果：

- HTTP 状态：`200`
- 返回大小：`15167` bytes
- `TOTAL`: `3600`
- 第一条歌曲：`江南`
- 第一条歌手：`林俊杰`

注意：这个接口返回内容类似 Python dict，字段使用单引号，例如 `{'TOTAL':'3600','abslist':[...]}`，不能直接当标准 JSON 解析。

参数说明：

| 参数 | 说明 |
| --- | --- |
| `all` | 搜索关键词 |
| `ft` | 搜索类型，歌曲搜索用 `music` |
| `pn` | 页码，从 `0` 开始 |
| `rn` | 每页数量 |
| `rformat` | 返回格式，填 `json` |
| `encoding` | 返回编码，填 `utf8` |

常用返回字段：

| 字段 | 说明 |
| --- | --- |
| `TOTAL` | 总结果数 |
| `abslist` | 歌曲列表 |
| `abslist[].MUSICRID` | 酷我歌曲资源 ID |
| `abslist[].SONGNAME` / `NAME` | 歌曲名 |
| `abslist[].ARTIST` | 歌手 |
| `abslist[].ALBUM` | 专辑 |
| `abslist[].DURATION` | 时长，秒 |

## 绿源 / QQ 搜索接口

模拟器切到绿源后，搜索 `林俊杰` 的歌曲 Tab 显示 `共 20860 首`，首屏包含 `Always Online`、`江南`、`修炼爱情`。可直接请求成功的 QQ 搜索接口如下：

```bash
curl.exe -L -G "https://c.y.qq.com/soso/fcgi-bin/search_for_qq_cp" ^
  --data-urlencode "g_tk=5381" ^
  --data-urlencode "uin=0" ^
  --data-urlencode "format=json" ^
  --data-urlencode "inCharset=utf-8" ^
  --data-urlencode "outCharset=utf-8" ^
  --data-urlencode "notice=0" ^
  --data-urlencode "platform=h5" ^
  --data-urlencode "needNewCode=1" ^
  --data-urlencode "w=林俊杰" ^
  --data-urlencode "zhidaqu=1" ^
  --data-urlencode "catZhida=1" ^
  --data-urlencode "t=0" ^
  --data-urlencode "flag=1" ^
  --data-urlencode "ie=utf-8" ^
  --data-urlencode "sem=1" ^
  --data-urlencode "aggr=0" ^
  --data-urlencode "perpage=5" ^
  --data-urlencode "n=5" ^
  --data-urlencode "p=1" ^
  --data-urlencode "remoteplace=txt.mqq.all" ^
  -H "Referer: https://y.qq.com/" ^
  -H "User-Agent: Mozilla/5.0"
```

已验证结果：

- HTTP 状态：`200`
- 返回大小：`4750` bytes
- `code`: `0`
- `data.song.totalnum`: `600`
- 第一条歌曲：`Always Online`
- 第一条歌手：`林俊杰`

参数说明：

| 参数 | 说明 |
| --- | --- |
| `w` | 搜索关键词 |
| `t` | 搜索类型，`0` 为歌曲 |
| `p` | 页码，从 `1` 开始 |
| `n` / `perpage` | 每页数量 |
| `remoteplace` | 搜索来源标记，歌曲可用 `txt.mqq.all` |

常用返回字段：

| 字段 | 说明 |
| --- | --- |
| `data.song.totalnum` | 歌曲总数 |
| `data.song.list` | 歌曲列表 |
| `data.song.list[].songid` | QQ 歌曲数字 ID |
| `data.song.list[].songmid` | QQ 歌曲 MID |
| `data.song.list[].songname` | 歌曲名 |
| `data.song.list[].singer[].name` | 歌手 |
| `data.song.list[].albumname` | 专辑 |
| `data.song.list[].interval` | 时长，秒 |

## 本次排除的 QQ 候选接口

APK 中能看到以下 QQ 相关端点：

- `http://c.y.qq.com/soso/fcgi-bin/client_music_search_songlist`
- `https://u.y.qq.com/cgi-bin/musicu.fcg`

本次直接 `curl` 验证结果：

- 老接口返回：`{"code":-3003,"subcode":-3003,"message":"system error"}`
- 新接口返回：`{"code":500001,...}`

因此这两条不是绿源的可直接复现搜索接口。绿源可用接口见上一节 `search_for_qq_cp`。

## 抓取过程简记

1. 通过 `adb shell pm path com.sayqz.tunefreenext` 定位 APK。
2. 拉取 `base.apk` 后确认是 Flutter 应用，主要业务字符串在 `lib/x86_64/libapp.so`。
3. 从 AOT 二进制中抽取到 `netease_provider.dart`、`kuwo_provider.dart`、`qq_provider.dart` 以及对应 URL。
4. 用模拟器 UI dump 确认 TuneFreeNext 搜索页字段：搜索输入框、音源红/橙/绿、歌曲/歌手/歌单 Tab。
5. 用本机 `curl.exe` 对候选接口逐个验证，保留 HTTP 200 且有真实搜索结果的接口。
