# Android 音乐播放器项目说明

## 项目概述

已成功创建一个完整的 Android 音乐播放器项目，可以直接在 Android Studio 中打开和运行。

## 项目位置

`D:\Projects\music`

## 如何在 Android Studio 中打开

1. 启动 Android Studio
2. 选择 "Open an Existing Project"
3. 导航到 `D:\Projects\music` 目录
4. 点击 "OK" 打开项目
5. 等待 Gradle 同步完成（首次打开需要下载依赖）

## 项目架构

### MVVM 架构模式
- **Model**: 数据模型和业务逻辑
- **View**: Activity 和 XML 布局
- **ViewModel**: 连接 View 和 Model

### 目录结构

```
music/
├── app/
│   ├── src/main/
│   │   ├── java/com/music/player/
│   │   │   ├── data/
│   │   │   │   ├── api/
│   │   │   │   │   ├── MusicApiService.kt      # API 接口定义
│   │   │   │   │   └── RetrofitClient.kt       # Retrofit 配置
│   │   │   │   ├── model/
│   │   │   │   │   └── Models.kt               # 数据模型
│   │   │   │   └── repository/
│   │   │   │       └── MusicRepository.kt      # 数据仓库
│   │   │   ├── ui/
│   │   │   │   ├── adapter/
│   │   │   │   │   └── SongAdapter.kt          # 歌曲列表适配器
│   │   │   │   └── viewmodel/
│   │   │   │       └── MusicViewModel.kt       # ViewModel
│   │   │   └── MainActivity.kt                 # 主界面
│   │   ├── res/
│   │   │   ├── layout/
│   │   │   │   ├── activity_main.xml           # 主界面布局
│   │   │   │   └── item_song.xml               # 歌曲列表项布局
│   │   │   ├── values/
│   │   │   │   ├── colors.xml
│   │   │   │   ├── strings.xml
│   │   │   │   └── themes.xml
│   │   │   └── drawable/
│   │   └── AndroidManifest.xml
│   ├── build.gradle                            # App 级别配置
│   └── proguard-rules.pro
├── gradle/
│   └── wrapper/
│       └── gradle-wrapper.properties
├── build.gradle                                # 项目级别配置
├── settings.gradle
├── gradle.properties
├── gradlew
├── gradlew.bat
├── .gitignore
└── README.md
```

## 核心功能

### 1. 每日推荐
- 自动加载网易云音乐每日推荐歌曲
- 显示歌曲列表

### 2. 搜索功能
- 支持关键词搜索歌曲
- 实时显示搜索结果

### 3. 音乐播放
- 点击歌曲开始播放
- 显示当前播放歌曲信息
- 播放/暂停控制

## 使用的音乐 API

### 网易云音乐 API
- **基础 URL**: `http://mc.alger.fun/`
- **接口**:
  - `/api/recommend/songs` - 每日推荐
  - `/api/top/playlist` - 热门歌单
  - `/api/playlist/detail` - 歌单详情
  - `/api/cloudsearch` - 搜索歌曲
  - `/api/song/detail` - 歌曲详情
  - `/api/song/url/v1` - 获取播放地址
  - `/api/lyric` - 获取歌词

### GDStudio 音乐 API
- **基础 URL**: `https://music-api.gdstudio.xyz/`
- **用途**: 备用获取音乐播放 URL

### 歌词 API
- **基础 URL**: `https://node.api.xfabe.com/`
- **用途**: 备用获取歌词

## 技术栈

### 核心库
- **Kotlin**: 主要开发语言
- **AndroidX**: Android Jetpack 组件
- **Material Design**: UI 设计规范

### 网络请求
- **Retrofit 2.9.0**: HTTP 客户端
- **Gson**: JSON 解析
- **OkHttp**: 网络拦截器

### 异步处理
- **Kotlin Coroutines**: 协程支持
- **LiveData**: 数据观察
- **ViewModel**: 生命周期管理

### 音频播放
- **Media3 ExoPlayer**: 音频播放引擎

### 图片加载
- **Glide 4.16.0**: 图片加载和缓存

## 系统要求

- **最低 SDK**: 24 (Android 7.0)
- **目标 SDK**: 34 (Android 14)
- **编译 SDK**: 34
- **Gradle**: 8.2
- **Kotlin**: 1.9.20
- **Android Gradle Plugin**: 8.2.0

## 运行步骤

1. **打开项目**
   - 在 Android Studio 中打开 `D:\Projects\music`

2. **等待同步**
   - Gradle 会自动下载依赖（首次需要几分钟）

3. **配置设备**
   - 连接 Android 设备（需开启 USB 调试）
   - 或启动 Android 模拟器（推荐 API 24+）

4. **运行应用**
   - 点击工具栏的运行按钮（绿色三角形）
   - 或使用快捷键 Shift + F10

## 权限说明

应用需要以下权限：
- `INTERNET`: 访问网络获取音乐数据
- `ACCESS_NETWORK_STATE`: 检查网络状态
- `FOREGROUND_SERVICE`: 前台服务（用于后台播放）
- `FOREGROUND_SERVICE_MEDIA_PLAYBACK`: 媒体播放服务

## 注意事项

1. **网络连接**: 应用需要网络连接才能获取音乐数据
2. **API 稳定性**: 第三方音乐 API 可能不稳定，如遇问题可更换 API
3. **真机测试**: 建议在真机上测试音频播放功能
4. **HTTP 流量**: 已启用 `usesCleartextTraffic` 支持 HTTP 请求

## 后续优化建议

1. **音频播放器增强**
   - 实现完整的播放控制（上一曲、下一曲、进度条）
   - 添加播放列表管理
   - 支持后台播放和通知栏控制

2. **UI 优化**
   - 添加专辑封面显示
   - 实现歌词显示功能
   - 优化界面动画效果

3. **功能扩展**
   - 添加收藏功能
   - 播放历史记录
   - 多音乐平台支持（QQ 音乐、酷我音乐）
   - 本地音乐扫描

4. **性能优化**
   - 添加音乐缓存
   - 优化网络请求
   - 实现分页加载

## 故障排除

### Gradle 同步失败
- 检查网络连接
- 尝试使用 VPN
- 修改 Gradle 镜像源

### 编译错误
- 确保 JDK 版本正确（推荐 JDK 17）
- 清理项目：Build -> Clean Project
- 重新构建：Build -> Rebuild Project

### 运行时错误
- 检查网络权限
- 查看 Logcat 日志
- 确认 API 可访问性

## 联系与支持

如有问题，请检查：
1. Android Studio 版本（推荐最新稳定版）
2. Gradle 配置是否正确
3. 网络连接是否正常
4. API 服务是否可用
