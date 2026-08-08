# DuckMusic Desktop iOS Sideload Design

## Goal

为 DuckMusic 的 macOS 和 Windows 桌面版增加一个 iOS 安装中心：桌面端从 ECS 获取未签名 IPA，使用用户自己的 Apple 账号和本机签名材料完成签名、安装和到期前刷新。ECS 不接收 Apple ID 密码、验证码、私钥或登录会话。

## Hard Constraints

- iOS App 本身不负责签名、替换或续签自己。
- 公共用户仍受 Apple 个人团队的有效期、设备数量和 App 数量限制。
- 续签必须在 IPA 过期前由桌面端完成；iPhone 需要通过 USB 或受信任的 Wi-Fi 可见。
- ECS 只托管构建产物和版本元数据，不执行代签、不保存用户 Apple 凭据。
- 普通用户通过 DuckMusic DMG/EXE 使用本地签名助手，不把完整 Xcode 作为默认前置条件。Xcode 只用于发布构建和 macOS 备用诊断路径；Windows 使用经过许可证审核的本地 AltServer 类引擎或明确提示需要 Mac 签名节点。

## Scope

### In scope

1. ECS 版本清单和 IPA 下载接口，包含版本、构建号、SHA-256、最低 iOS 版本和构建时间。
2. DuckMusic macOS/Windows 桌面端的 iOS 安装中心界面。
3. 本地 Apple 账号状态、已配对设备、签名有效期和最近一次任务结果的展示。
4. 桌面端定时检查，在签名剩余时间不足时提醒并尝试刷新。
5. 本地安全存储和日志脱敏。
6. 无真实 Apple 账号时的诊断模式和可测试的模拟服务。

### Out of scope

- ECS 代管 Apple ID、2FA 验证码、开发证书私钥或共享企业证书。
- 绕过 iOS 验证、伪造描述文件、利用特定系统漏洞或公共证书池。
- 仅靠网页或 iOS 快捷指令完成签名。
- App Store/TestFlight 正式发布流水线；该流程继续按 `RELEASE.md` 独立维护。

## Architecture

### ECS

ECS 发布 `ios/latest.json` 和版本化 IPA。清单使用 HTTPS，并包含 `version`、`buildNumber`、`downloadUrl`、`sha256`、`minimumOsVersion` 和 `publishedAt`。桌面端下载到临时目录后先校验哈希，再交给本地签名适配器。IPA 下载地址不包含 Apple 凭据，构建产物按版本不可变。

### Shared Flutter layer

新增 `IosSideloadController`、`IosSideloadService` 和模型类型，负责版本获取、状态机、任务进度、错误分类和刷新调度。平台专属代码通过现有 Flutter platform channel 约定暴露 `prepareAccount`、`listDevices`、`install`、`refresh`、`status` 和 `cancel` 操作。

### macOS adapter

通过随 DuckMusic 分发的本地 Helper 进程调用 `security`、`plutil`、`codesign` 和 `xcrun devicectl`。Helper 读取 Xcode 已生成的本机描述文件和 Apple Development 身份，临时 IPA、profile 和导出的 app 在任务结束后删除；当前实现不替用户向 Apple 申请新描述文件，因此刷新不会凭空延长同一 profile 的到期时间。适配器必须返回结构化错误，例如 `helperMissing`、`xcodeMissing`、`deviceUntrusted`、`developerModeRequired`、`profileExpired` 和 `installFailed`。

### Windows adapter

检测 Apple Devices/iTunes、Bonjour 和可用的本地 AltServer 类服务。第一版优先支持“本机服务已安装”的模式：Flutter UI 负责发现、配置和显示状态，签名和设备安装由本机服务执行。AltStore 官方公开仓库提供的 AltServer 源码面向 macOS 且采用 AGPLv3，不能假定存在可直接嵌入 DuckMusic 的官方 Windows 源码；Windows 引擎必须单独完成来源和许可证审核。缺少服务或 Apple 驱动时，界面提供明确的安装指引，不上传 Apple 账号到 ECS，也不把未验证的第三方证书作为后备。

## User Flow

1. 用户在桌面端打开“iOS 安装中心”。
2. 桌面端拉取 ECS 清单并显示当前版本、哈希和构建时间。
3. 用户在本机完成 Apple 账号准备，桌面端显示账号团队和可用设备，不把密码发送到 ECS。
4. 用户连接并信任 iPhone；若系统要求，开启开发者模式。
5. 用户点击“安装”或“刷新”，桌面端下载、校验、签名并安装。
6. 任务完成后保存本地状态和预计过期时间。
7. 常驻任务每天检查一次；剩余时间小于 24 小时时执行刷新，失败则通知用户并提供诊断信息。

## Security and Privacy

- ECS API 只使用公开构建元数据和短期下载令牌。
- Apple 凭据只进入平台安全存储；日志中禁止输出账号、token、私钥、profile 内容和完整路径。
- 临时签名文件使用随机目录，任务结束时清理；清理失败只记录文件数量，不记录内容。
- 所有下载验证 HTTPS、SHA-256 和版本号；哈希不匹配立即终止任务。
- Windows 本地服务通信限定为 localhost，并使用一次性随机挑战防止任意本地进程触发签名。

## Failure Handling

- ECS 不可用：保留上一次已校验版本，禁止使用未校验 IPA。
- 设备不可见：显示 USB/Wi-Fi、信任状态和驱动检查项。
- 签名过期：明确提示需要重新安装，不能伪装成自动续签成功。
- Apple 账号需要 2FA：暂停任务，等待用户在本机完成验证。
- Windows 服务缺失：进入诊断页，不自动下载未经审计的证书或执行远程脚本。

## Testing

- Dart 单元测试覆盖清单解析、SHA-256 校验、剩余时间阈值、任务状态机和错误映射。
- Platform channel 测试覆盖成功、取消、设备不可见、profile 过期和驱动缺失。
- macOS/Windows 手工验收使用测试设备验证首次安装、重复刷新、网络中断和过期恢复。
- 没有 Apple 账号或 iPhone 的 CI 只运行模拟适配器，不声称真实 IPA 签名成功。

## Acceptance Criteria

- macOS/Windows 桌面端能显示 ECS 上的已校验 iOS 版本。
- 无凭据或无设备时，界面给出可执行诊断，而不是显示成功。
- 真实签名任务的 Apple 凭据不出现在 ECS 请求和日志中。
- 刷新调度在剩余时间不足时触发一次且可取消，不会并发执行多个签名任务。
- 所有新增 Dart 测试通过；平台构建在缺少本机签名工具时能失败并给出明确原因。
