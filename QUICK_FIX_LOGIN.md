# 快速修复：账号密码错误问题

## 问题原因

daohangv2 可以登录，但音乐项目提示"账号密码错误"，是因为 **Supabase API Key 不正确**。

## 快速解决方案

### 方法 1: 从浏览器获取真实 Key（推荐）

1. **打开 daohangv2 网页**
   - 在浏览器中打开 daohangv2 项目

2. **打开开发者工具**
   - 按 `F12` 或右键 → 检查

3. **切换到 Network 标签**
   - 点击 Network（网络）标签

4. **登录账号**
   - 在网页中输入账号密码登录

5. **查找 Supabase 请求**
   - 在 Network 列表中找到发送到 `supabase.co` 的请求
   - 通常是 `token?grant_type=password` 或类似的请求

6. **复制 API Key**
   - 点击该请求
   - 查看 **Headers**（请求头）
   - 找到 `apikey` 字段
   - 复制这个值（一个很长的字符串）

7. **更新代码**
   - 打开 `app/src/main/java/com/music/player/data/auth/SupabaseClient.kt`
   - 找到 `SUPABASE_ANON_KEY` 这一行
   - 替换为你复制的真实 key

8. **重新运行**
   - 在 Android Studio 中点击 Run
   - 使用 daohangv2 的账号登录

### 方法 2: 从 Supabase Dashboard 获取

1. 访问 https://supabase.com
2. 登录并选择项目
3. Settings → API → Project API keys
4. 复制 **anon public** key
5. 更新代码中的 `SUPABASE_ANON_KEY`

### 方法 3: 从 daohangv2 代码中查找

检查 daohangv2 项目中是否有：
- `.env` 文件
- `.env.local` 文件
- `vite.config.ts` 中的环境变量

查找类似这样的配置：
```
VITE_SUPABASE_ANON_KEY=真实的key
```

## 代码修改位置

文件：`app/src/main/java/com/music/player/data/auth/SupabaseClient.kt`

修改前：
```kotlin
private const val SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ0dnpwZHVweWd2dHl0dW5ycGR3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzU3MjU2MDAsImV4cCI6MjA1MTMwMTYwMH0.placeholder_signature_here"
```

修改后：
```kotlin
private const val SUPABASE_ANON_KEY = "你从浏览器或Dashboard复制的真实key"
```

## 验证 Key 格式

正确的 Supabase anon key 应该：
- ✅ 以 `eyJ` 开头
- ✅ 包含三个部分，用 `.` 分隔
- ✅ 长度约 200-300 个字符
- ✅ 是一个 JWT token

错误的 key：
- ❌ `sb_publishable_xxx` （这不是 JWT token）
- ❌ 太短（少于 100 个字符）
- ❌ 包含 `placeholder` 字样

## 测试步骤

1. 更新 API key
2. 保存文件
3. 在 Android Studio 中：
   - Build → Clean Project
   - Build → Rebuild Project
   - 点击 Run
4. 使用 daohangv2 的账号登录
5. 应该可以成功登录了！

## 如果还是失败

查看 Logcat 日志：
1. Android Studio → Logcat
2. 过滤 `SupabaseClient`
3. 查看请求 URL 和响应
4. 截图发给我

## 示例：真实 Key 的样子

```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ0dnpwZHVweWd2dHl0dW5ycGR3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzU3MjU2MDAsImV4cCI6MjA1MTMwMTYwMH0.真实的签名部分很长很长
```

注意：
- 第一部分：`eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9`
- 第二部分：`eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ0dnpwZHVweWd2dHl0dW5ycGR3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzU3MjU2MDAsImV4cCI6MjA1MTMwMTYwMH0`
- 第三部分：签名（最长的部分）

---

**按照上面的方法获取真实的 API key，然后更新代码，就可以解决登录问题了！**
