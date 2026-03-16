# 快速开始指南

## 项目配置

### 1. 同步 Gradle
```bash
./gradlew clean build
```

### 2. Supabase 配置
项目已配置使用 daohangv2 的 Supabase 实例：
- URL: `https://vtvzpdupygvtytunrpdw.supabase.co`
- Anon Key: 已配置在 `SupabaseClient.kt`

### 3. 运行应用
1. 连接 Android 设备或启动模拟器
2. 点击 Run 按钮或执行：
```bash
./gradlew installDebug
```

## 功能测试

### 测试登录功能
1. 启动应用
2. 输入邮箱：`test@example.com`
3. 输入密码：`123456`
4. 点击"登录"

### 测试注册功能
1. 点击"还没有账号？点击注册"
2. 输入新邮箱
3. 输入密码（至少6位）
4. 点击"注册"

### 测试音乐功能
1. 登录后自动加载每日推荐
2. 点击歌曲播放
3. 使用搜索功能查找歌曲

### 测试退出登录
1. 点击右上角菜单
2. 选择"退出登录"
3. 自动返回登录界面

## API 端点

当前使用的音乐 API：`http://mc.alger.fun/`

可用接口：
- `/api/recommend/songs` - 每日推荐
- `/api/top/playlist` - 热门歌单
- `/api/playlist/detail` - 歌单详情
- `/api/cloudsearch` - 搜索歌曲
- `/api/song/detail` - 歌曲详情
- `/api/song/url/v1` - 获取播放地址
- `/api/lyric` - 获取歌词

Supabase 请求会自动携带认证令牌（音乐 API 不需要）。

## 常见问题

### Q: 登录失败怎么办？
A: 检查网络连接，确保 Supabase 服务可访问。

### Q: 注册后无法登录？
A: 检查 Supabase 后台是否开启了邮箱验证，建议关闭以便测试。

### Q: API 请求失败？
A: 检查 RetrofitClient 的 BASE_URL 是否正确，确保音乐 API 服务可用。

### Q: 如何查看日志？
A: 使用 Logcat 过滤 `MusicPlayer` 标签查看应用日志。

## 开发建议

1. 使用 Android Studio Arctic Fox 或更高版本
2. 最低 SDK 版本：24 (Android 7.0)
3. 目标 SDK 版本：34 (Android 14)
4. 建议使用真机测试音频播放功能

## 下一步

- 查看 `OPTIMIZATION_GUIDE.md` 了解详细的优化内容
- 查看 `PROJECT_GUIDE.md` 了解项目整体架构
- 开始添加更多功能！
