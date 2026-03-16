# 获取 Supabase API Key 指南

## 问题原因

你在 daohangv2 项目中可以登录，但在音乐项目中提示"账号密码错误"，这是因为：

1. **API Key 不正确** - 我使用的是占位符 key，不是真实的 anon key
2. **需要从 Supabase Dashboard 获取真实的 key**

## 解决方案

### 步骤 1: 登录 Supabase Dashboard

1. 访问 https://supabase.com
2. 登录你的账号
3. 选择项目：`vtvzpdupygvtytunrpdw`

### 步骤 2: 获取 API Keys

1. 点击左侧菜单的 **Settings**（设置）
2. 点击 **API**
3. 找到 **Project API keys** 部分
4. 复制 **anon public** key（这是一个很长的字符串，以 `eyJ` 开头）

### 步骤 3: 更新代码

打开文件：`app/src/main/java/com/music/player/data/auth/SupabaseClient.kt`

找到这一行：
```kotlin
private const val SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ0dnpwZHVweWd2dHl0dW5ycGR3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzU3MjU2MDAsImV4cCI6MjA1MTMwMTYwMH0.placeholder_signature_here"
```

替换为你从 Dashboard 复制的真实 key：
```kotlin
private const val SUPABASE_ANON_KEY = "你复制的真实key"
```

### 步骤 4: 重新运行

1. 保存文件
2. 在 Android Studio 中点击 **Run**
3. 尝试登录

## 验证 Key 是否正确

真实的 Supabase anon key 应该：
- 以 `eyJ` 开头
- 包含三个部分，用 `.` 分隔
- 长度约 200-300 个字符
- 看起来像这样：`eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ0dnpwZHVweWd2dHl0dW5ycGR3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzU3MjU2MDAsImV4cCI6MjA1MTMwMTYwMH0.真实的签名部分`

## 临时解决方案（如果无法访问 Dashboard）

如果你无法访问 Supabase Dashboard，可以：

### 方案 1: 从 daohangv2 项目获取

虽然 daohangv2 项目中显示的是 `sb_publishable_DWdy6_bOXKnHO5aKG7cM0A__mo-PjT8`，但这可能不是真实的 JWT token。

让我帮你从浏览器中获取：

1. 打开 daohangv2 项目的网页
2. 按 F12 打开开发者工具
3. 切换到 **Network** 标签
4. 登录账号
5. 查找发送到 `supabase.co` 的请求
6. 查看请求头中的 `apikey` 字段
7. 复制这个 key

### 方案 2: 使用环境变量

如果 daohangv2 使用了环境变量，检查：
- `.env` 文件
- `.env.local` 文件
- 环境变量配置

查找类似这样的配置：
```
VITE_SUPABASE_URL=https://vtvzpdupygvtytunrpdw.supabase.co
VITE_SUPABASE_ANON_KEY=真实的key
```

## 测试登录

更新 key 后，使用以下账号测试：

```
邮箱: 你在 daohangv2 中使用的邮箱
密码: 你在 daohangv2 中使用的密码
```

## 调试信息

如果仍然失败，查看 Logcat 日志：

1. 在 Android Studio 中打开 **Logcat**
2. 过滤 `SupabaseClient`
3. 查看请求和响应信息
4. 截图发给我，我会帮你分析

## 常见错误

### 错误 1: "Invalid API key"
```
原因: API key 不正确或已过期
解决: 从 Dashboard 重新获取 key
```

### 错误 2: "Invalid login credentials"
```
原因: 账号或密码错误，或账号未验证
解决:
1. 确认密码正确
2. 检查 Supabase Dashboard 中的用户状态
3. 如果账号未验证，在 Dashboard 中手动验证
```

### 错误 3: "Network error"
```
原因: 网络连接问题
解决: 检查网络连接，确保可以访问 supabase.co
```

## 下一步

获取并更新正确的 API key 后：

1. ✅ 重新运行应用
2. ✅ 使用 daohangv2 的账号登录
3. ✅ 应该可以成功登录了

---

**重要提示**: API key 是敏感信息，不要分享给他人或提交到公开的代码仓库。
