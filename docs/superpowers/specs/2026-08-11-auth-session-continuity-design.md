# DuckMusic 认证会话连续性设计

## 背景

DuckMusic 从原生 Android 1.1.26 升级为 Flutter 客户端后，应用包仍保留旧版偏好数据，但两代客户端使用不同的存储文件和字段。原生版将会话写入 `auth_prefs_secure`，并兼容 `auth_prefs`、`auth_prefs_mirror`；Flutter 版只读取 `FlutterSharedPreferences` 中的 `auth_token` 和 `auth_refresh_token`。覆盖升级后 Flutter 因无法发现旧会话而要求用户重新登录。

Flutter 当前的刷新、登录恢复和退出流程也存在协议和状态缺口，可能使仍有效的会话被清除，或让界面短暂报告登录成功但实际已经退出。

## 目标

- Android 覆盖升级后自动迁移原生 1.1.26 的有效会话，无需用户重新登录。
- 会话迁移具备原子性：Flutter 新存储确认成功前不删除旧数据。
- 兼容后端当前 refresh token 字段别名和 token 旋转行为。
- 根据 access token 到期时间主动续期，降低正常使用中的 401 和掉登录概率。
- 登录、恢复、刷新和退出对外报告的状态与实际会话一致。
- 退出登录时撤销服务端 refresh token。

## 非目标

- 不延长后端 access token 或 refresh token 的有效期。
- 不改变后端 JWT 签名、设备绑定、密码或用户模型。
- 不迁移原生版与登录无关的偏好数据。
- 不为已经失效或被撤销的旧 refresh token 绕过重新登录。
- 不改变 iOS、macOS、Windows 已有 Flutter 会话的存储格式。

## 方案选择

采用“Android 原生迁移桥 + Flutter 会话生命周期修复”。迁移桥是读取 Android 旧加密偏好的唯一可靠途径；后端迁移接口仍要求客户端先取得旧 token，无法代替本地读取。只修复 Flutter 刷新逻辑则不能解决覆盖升级后的首次重新登录。

后端现有 `/api/auth/refresh` 已支持 refresh token 轮换和多种请求字段，登录响应也提供 access token、refresh token 与有效期，因此本阶段不修改后端协议。

## 组件边界

### Android 旧会话读取器

在 Android host 层增加只负责迁移的 MethodChannel。它使用与原生 1.1.26 相同的 `EncryptedSharedPreferences` 配置读取 `auth_prefs_secure`，并按旧版行为回退到 `auth_prefs` 和 `auth_prefs_mirror`。

读取结果使用结构化 Map 返回以下字段：

- `accessToken`
- `refreshToken`
- `expiresAtMs`
- `userId`

桥接层提供“读取”和“确认迁移后清理”两个独立操作。读取不会修改旧存储；只有 Flutter 已成功写入并重新读回新会话后，才调用清理操作。非 Android 平台不注册或不调用该桥。

### Flutter 会话迁移器

Flutter 启动恢复流程首先读取当前 Flutter 会话。仅当当前 access token 和 refresh token 都缺失时，才尝试旧会话迁移；任一 Flutter token 已存在都以 Flutter 会话为准，避免旧数据覆盖用户后来登录的新账号。

迁移器验证旧 access token 和 refresh token 均为非空字符串，将 token、过期时间和可用的用户 ID 写入 Flutter 存储，再读回确认。确认成功后通知 Android 清理旧认证存储，并继续正常的资料恢复或 token 刷新。

迁移器只协调数据，不直接决定 UI 登录状态。最终状态仍由认证控制器根据会话恢复结果设置。

### Flutter 认证控制器

认证控制器继续作为登录状态的唯一来源，但统一以下规则：

- 登录响应解析 refresh token 时接受 `refresh_token`、`refreshToken`、`refresh` 和 `refresh_token_value`。
- 刷新请求发送后端兼容的 snake_case 与 camelCase 字段，确保跨版本服务可识别。
- 登录和刷新响应的有效期转换为绝对时间并持久化。
- access token 已过期或接近过期时，在请求用户资料前刷新。
- refresh token 轮换成功后同时持久化新的 access token、refresh token 和到期时间。
- `login()` 只有在会话仍存在且用户资料恢复成功后返回 `true`。
- 认证失败导致会话清理时，不能被后续异步回调重新标记为已登录。

### 退出流程

退出前读取当前 refresh token，并将其放入 `/api/auth/logout` 请求体。无论网络请求是否成功，都清理本地 Flutter 会话；服务端不可用不能阻止用户在本机退出。旧 Android 存储也执行幂等清理，避免下次启动重新迁入已退出的会话。

## 数据流

```text
应用启动
  -> 读取 Flutter 会话
  -> 会话完整：检查过期时间并恢复
  -> 会话缺失且为 Android：读取旧原生会话
       -> 数据有效：写入并读回 Flutter 会话
       -> 写入确认成功：清理旧存储
       -> 写入失败：保留旧存储，本次保持未登录
  -> access token 临期或已过期：使用 refresh token 刷新
  -> 获取用户资料
  -> 资料恢复成功：发布已登录状态
  -> refresh 被拒绝或资料返回 401：清理会话并发布未登录状态
```

## 并发与错误处理

- 同一时刻只允许一个 refresh 请求；其他调用复用该结果，避免 refresh token 轮换时并发请求互相撤销。
- 网络超时、断网和 5xx 不立即视为凭据失效，不主动删除 refresh token；界面可保留会话并展示可重试状态。
- refresh 返回明确的 400/401/403 时视为 refresh token 无效，清理本地会话。
- 旧加密偏好无法解密、字段缺失或类型错误时，迁移返回“无可用会话”而不是让应用崩溃。
- 迁移写入失败时保留旧存储，以便下次启动重试。
- 清理旧存储失败不回滚已确认的新会话；后续启动因 Flutter 会话优先，也不会用旧数据覆盖。

## 安全边界

- MethodChannel 只在应用进程内暴露，不记录或输出 token。
- 迁移桥不把 token 写入临时文件、日志或异常文本。
- 旧会话成功迁移或用户退出后清理旧认证存储，减少凭据副本。
- 不接受只有 user ID 而没有完整 token 对的旧数据。
- 不因迁移而延长 token 的服务端有效期；过期会话仍走标准 refresh 或重新登录流程。

## 测试方案

### Flutter 单元测试

- 当前 Flutter 会话完整时不调用旧会话迁移。
- 迁移写入并读回成功后才清理旧存储。
- 迁移写入失败时保留旧存储并保持未登录。
- 登录和刷新解析全部 refresh token 字段别名。
- 刷新请求包含兼容字段，并持久化轮换后的 refresh token。
- access token 临期时在恢复资料前刷新。
- 用户资料恢复返回 401 后 `login()` 不得返回成功。
- 暂时网络错误不删除仍可续期的本地会话。
- logout 请求携带 refresh token，并始终清理本地会话。

### Android 测试

- 从 `auth_prefs_secure` 读取完整旧会话。
- 加密存储不可用时按顺序读取 plain 和 mirror fallback。
- 字段缺失时不返回部分会话。
- 读取操作不删除数据；显式确认后才清理三处旧存储。
- 重复清理和无旧数据场景保持幂等。

### 集成与回归验证

- 使用带原生 1.1.26 会话数据的安装状态覆盖安装 Flutter 版本，验证启动后仍为登录状态。
- 验证旧 access token 已过期但 refresh token 有效时可自动续期。
- 验证被撤销的 refresh token 会进入未登录状态，不出现登录成功假象。
- 验证退出后重启不会从旧存储重新迁入会话。
- 运行 Flutter 认证测试、Android 单元测试、静态分析和相关后端认证测试。

## 预计修改范围

- `android/app/src/main/kotlin/.../MainActivity.kt` 或同层独立迁移类：注册 MethodChannel 并读取旧认证偏好。
- `android/app/build.gradle.kts`：仅在当前 Flutter Android 模块尚未包含 AndroidX Security 时补充兼容依赖。
- `lib/core/auth/auth_controller.dart`：接入迁移、过期时间、刷新兼容和状态修复。
- `lib/core/auth/` 下的小型存储或迁移接口：隔离平台桥，便于单元测试。
- `test/core/auth/` 和 Android 对应测试目录：覆盖迁移及会话生命周期。
- 后端代码仅在现有测试暴露协议缺口时做最小修改。

## 验收标准

- Android 原生 1.1.26 的有效登录用户覆盖升级后无需重新登录。
- 已迁移的会话在应用重启、access token 轮换和正常网络波动后保持有效。
- refresh token 确认失效时可靠退出，不循环刷新或报告虚假登录成功。
- 用户主动退出后服务端 refresh token 被撤销，重启后保持退出。
- 非 Android 平台和已有 Flutter 会话不受迁移逻辑影响。
- 新增认证回归测试、Android 测试和静态分析通过。
