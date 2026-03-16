# 构建和安装指南

## 环境要求

- Android Studio Arctic Fox 或更高版本
- JDK 11 或更高版本
- Android SDK (API 24-34)
- Gradle 8.2+

## 方法一：使用 Android Studio（推荐）

### 1. 打开项目
```
1. 启动 Android Studio
2. File -> Open
3. 选择 D:\Projects\music 目录
4. 等待 Gradle 同步完成
```

### 2. 同步依赖
```
1. 点击顶部工具栏的 "Sync Project with Gradle Files" 按钮
2. 或者 File -> Sync Project with Gradle Files
3. 等待同步完成（首次可能需要下载依赖）
```

### 3. 连接设备
```
方式1: 真机
- 开启 USB 调试
- 连接到电脑
- 在 Android Studio 顶部选择设备

方式2: 模拟器
- Tools -> Device Manager
- 创建或启动模拟器
```

### 4. 运行应用
```
1. 点击顶部工具栏的绿色 "Run" 按钮
2. 或按快捷键 Shift + F10
3. 选择目标设备
4. 等待安装完成
```

## 方法二：使用命令行

### 1. 检查 Java 环境
```bash
java -version
# 应该显示 Java 11 或更高版本
```

### 2. 设置环境变量（如果需要）
```bash
# Windows
set JAVA_HOME=C:\Program Files\Java\jdk-11
set ANDROID_HOME=C:\Users\YourName\AppData\Local\Android\Sdk

# 或在系统环境变量中设置
```

### 3. 清理项目
```bash
cd D:\Projects\music
gradlew.bat clean
```

### 4. 构建项目
```bash
# 构建 Debug 版本
gradlew.bat assembleDebug

# 构建 Release 版本
gradlew.bat assembleRelease
```

### 5. 安装到设备
```bash
# 确保设备已连接
adb devices

# 安装 Debug 版本
gradlew.bat installDebug

# 或手动安装
adb install app/build/outputs/apk/debug/app-debug.apk
```

## 方法三：直接使用 ADB

### 1. 构建 APK（使用 Android Studio）
```
Build -> Build Bundle(s) / APK(s) -> Build APK(s)
```

### 2. 找到 APK 文件
```
位置: app/build/outputs/apk/debug/app-debug.apk
```

### 3. 安装到设备
```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

## 常见问题

### Q1: Gradle 同步失败
```
解决方案:
1. 检查网络连接
2. File -> Invalidate Caches / Restart
3. 删除 .gradle 文件夹后重新同步
4. 检查 gradle-wrapper.properties 配置
```

### Q2: 依赖下载失败
```
解决方案:
1. 配置国内镜像源（阿里云、腾讯云）
2. 在 build.gradle 中添加:
   repositories {
       maven { url 'https://maven.aliyun.com/repository/public/' }
       maven { url 'https://maven.aliyun.com/repository/google/' }
   }
```

### Q3: 编译错误
```
解决方案:
1. Build -> Clean Project
2. Build -> Rebuild Project
3. 检查 JDK 版本
4. 更新 Android Studio 和 Gradle 插件
```

### Q4: 设备未识别
```
解决方案:
1. 检查 USB 调试是否开启
2. 安装设备驱动
3. 更换 USB 线或端口
4. 运行 adb kill-server && adb start-server
```

### Q5: 安装失败
```
解决方案:
1. 卸载旧版本应用
2. 检查设备存储空间
3. 检查应用签名
4. 使用 adb install -r 强制重新安装
```

## 构建配置

### Debug 版本
```
- 包名: com.music.player
- 签名: Debug 签名
- 混淆: 关闭
- 日志: 完整
```

### Release 版本
```
- 包名: com.music.player
- 签名: 需要配置 Release 签名
- 混淆: 开启（ProGuard）
- 日志: 最小化
```

## 签名配置（Release）

### 1. 生成签名文件
```bash
keytool -genkey -v -keystore music-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias music
```

### 2. 配置 build.gradle
```gradle
android {
    signingConfigs {
        release {
            storeFile file('music-release.jks')
            storePassword 'your_password'
            keyAlias 'music'
            keyPassword 'your_password'
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.release
        }
    }
}
```

## 性能优化

### 1. 启用并行构建
```gradle
# gradle.properties
org.gradle.parallel=true
org.gradle.caching=true
org.gradle.jvmargs=-Xmx2048m
```

### 2. 使用增量编译
```gradle
android {
    compileOptions {
        incremental true
    }
}
```

## 测试

### 运行单元测试
```bash
gradlew.bat test
```

### 运行 UI 测试
```bash
gradlew.bat connectedAndroidTest
```

## 日志查看

### 使用 Logcat
```bash
# 查看所有日志
adb logcat

# 过滤应用日志
adb logcat | grep "MusicPlayer"

# 清空日志
adb logcat -c
```

### 使用 Android Studio
```
View -> Tool Windows -> Logcat
```

## 调试

### 1. 断点调试
```
1. 在代码行号左侧点击设置断点
2. 点击 Debug 按钮（虫子图标）
3. 应用会在断点处暂停
```

### 2. 网络调试
```
1. 使用 OkHttp Logging Interceptor
2. 查看 Logcat 中的网络请求日志
3. 使用 Charles 或 Fiddler 抓包
```

## 发布准备

### 1. 更新版本号
```gradle
// app/build.gradle
android {
    defaultConfig {
        versionCode 2
        versionName "1.1.0"
    }
}
```

### 2. 生成 Release APK
```bash
gradlew.bat assembleRelease
```

### 3. 测试 Release 版本
```
1. 安装 Release APK
2. 完整测试所有功能
3. 检查性能和稳定性
```

## 快速命令参考

```bash
# 清理
gradlew.bat clean

# 构建 Debug
gradlew.bat assembleDebug

# 构建 Release
gradlew.bat assembleRelease

# 安装 Debug
gradlew.bat installDebug

# 卸载
adb uninstall com.music.player

# 查看设备
adb devices

# 查看日志
adb logcat

# 重启 ADB
adb kill-server && adb start-server
```

---

**提示**: 首次构建可能需要较长时间下载依赖，请耐心等待。建议使用 Android Studio 进行开发，体验更好。
