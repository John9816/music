# 音乐播放器 Android App

这是一个基于 Android 的音乐播放器应用，使用 Kotlin 开发。

## 功能特性

- 每日推荐歌曲
- 热门歌单浏览
- 歌曲搜索
- 在线播放
- 音乐接口来自 daohangv2 项目

## 技术栈

- Kotlin
- MVVM 架构
- Retrofit (网络请求)
- LiveData & ViewModel
- ExoPlayer (音频播放)
- Glide (图片加载)
- Material Design

## 音乐 API

使用以下音乐 API：
- 网易云音乐 API: http://mc.alger.fun/
- GDStudio 音乐 API（备用）: https://music-api.gdstudio.xyz/api.php
- 歌词 API（备用）: https://node.api.xfabe.com/

## 如何运行

1. 使用 Android Studio 打开项目
2. 等待 Gradle 同步完成
3. 连接 Android 设备或启动模拟器
4. 点击运行按钮

## 最低要求

- Android SDK 24 (Android 7.0)
- 目标 SDK 34 (Android 14)

## 登录不掉线验证

1. 登录后等待 1–2 小时，期间进入“我的/收藏/历史/歌单”等需要登录的页面多次刷新。
2. 若升级后首次仍出现“未登录/需要重新登录”，退出并重新登录一次（旧版本可能未保存 refresh_token）。

## 项目结构

```
app/
├── src/main/
│   ├── java/com/music/player/
│   │   ├── data/
│   │   │   ├── api/          # API 接口定义
│   │   │   ├── model/        # 数据模型
│   │   │   └── repository/   # 数据仓库
│   │   ├── ui/
│   │   │   ├── adapter/      # RecyclerView 适配器
│   │   │   └── viewmodel/    # ViewModel
│   │   └── MainActivity.kt   # 主界面
│   ├── res/                  # 资源文件
│   └── AndroidManifest.xml
```

## 注意事项

- 需要网络权限
- 音乐 URL 可能需要定期更新
- 登录使用 Supabase，access_token 会过期；已支持 refresh_token 自动续期（升级后可能需要重新登录一次）
- 建议在真机上测试音频播放功能
