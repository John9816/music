# 依赖问题修复指南

## 问题描述
```
Could not find io.github.jan-tennert.supabase:auth-kt
```

## 已修复的内容

### 1. 更新 Supabase 版本
```gradle
// 从 2.0.0 更新到 2.6.0（更稳定的版本）
implementation platform('io.github.jan-tennert.supabase:bom:2.6.0')
```

### 2. 添加必要的 Ktor 依赖
```gradle
implementation 'io.ktor:ktor-client-android:2.3.12'
implementation 'io.ktor:ktor-client-core:2.3.12'
implementation 'io.ktor:ktor-utils:2.3.12'
```

### 3. 添加 JitPack 仓库
```gradle
// settings.gradle
repositories {
    google()
    mavenCentral()
    maven { url 'https://jitpack.io' }
}
```

## 现在请执行以下步骤

### 在 Android Studio 中：

1. **同步项目**
   - 点击顶部的 "Sync Now" 提示
   - 或者 File → Sync Project with Gradle Files
   - 等待同步完成（可能需要几分钟下载依赖）

2. **清理项目**
   - Build → Clean Project
   - 等待清理完成

3. **重新构建**
   - Build → Rebuild Project
   - 等待构建完成

4. **运行应用**
   - 点击绿色的 Run 按钮
   - 或按 Shift + F10

## 如果仍然有问题

### 方案 1: 清除 Gradle 缓存
```
1. 关闭 Android Studio
2. 删除以下目录:
   - D:\Projects\music\.gradle
   - C:\Users\你的用户名\.gradle\caches
3. 重新打开 Android Studio
4. 等待 Gradle 重新下载依赖
```

### 方案 2: 使用国内镜像（如果下载慢）

在 `settings.gradle` 中添加阿里云镜像：

```gradle
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        // 阿里云镜像（优先）
        maven { url 'https://maven.aliyun.com/repository/public/' }
        maven { url 'https://maven.aliyun.com/repository/google/' }
        maven { url 'https://maven.aliyun.com/repository/jcenter/' }

        // 官方仓库（备用）
        google()
        mavenCentral()
        maven { url 'https://jitpack.io' }
    }
}
```

### 方案 3: 检查网络连接

如果在公司网络或使用代理：

1. **配置代理**（如果需要）
   - File → Settings → Appearance & Behavior → System Settings → HTTP Proxy
   - 配置代理服务器

2. **检查防火墙**
   - 确保 Android Studio 可以访问外网
   - 允许 Gradle 下载依赖

### 方案 4: 手动指定版本（备用方案）

如果 BOM 版本仍有问题，可以手动指定每个依赖的版本：

```gradle
// 替换 app/build.gradle 中的 Supabase 依赖
dependencies {
    // Supabase - 手动指定版本
    implementation 'io.github.jan-tennert.supabase:postgrest-kt:2.6.0'
    implementation 'io.github.jan-tennert.supabase:auth-kt:2.6.0'
    implementation 'io.github.jan-tennert.supabase:realtime-kt:2.6.0'
    implementation 'io.ktor:ktor-client-android:2.3.12'
    implementation 'io.ktor:ktor-client-core:2.3.12'
    implementation 'io.ktor:ktor-utils:2.3.12'

    // Kotlin Serialization
    implementation 'org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3'
}
```

## 验证修复

构建成功后，你应该看到：

```
BUILD SUCCESSFUL in Xs
```

如果看到这个消息，说明依赖问题已解决！

## 常见错误和解决方案

### 错误 1: "Could not resolve..."
```
解决: 检查网络连接，清除 Gradle 缓存
```

### 错误 2: "Duplicate class found"
```
解决: 检查是否有重复的依赖，移除冲突的库
```

### 错误 3: "Unsupported class file major version"
```
解决: 更新 JDK 版本到 11 或更高
```

### 错误 4: "Failed to transform..."
```
解决:
1. Build → Clean Project
2. File → Invalidate Caches / Restart
3. 重新构建
```

## 依赖版本说明

当前使用的版本：

| 库 | 版本 | 说明 |
|---|---|---|
| Supabase BOM | 2.6.0 | 统一管理 Supabase 依赖版本 |
| Ktor Client | 2.3.12 | HTTP 客户端，Supabase 依赖 |
| Kotlin Serialization | 1.6.3 | JSON 序列化 |
| Kotlin | 1.9.20 | Kotlin 语言版本 |
| Gradle | 8.2 | 构建工具 |

## 下一步

依赖问题解决后：

1. ✅ 同步成功
2. ✅ 构建成功
3. → 运行应用
4. → 测试登录功能
5. → 测试音乐播放

---

**提示**: 首次同步可能需要 5-10 分钟下载所有依赖，请耐心等待。
