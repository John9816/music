# macOS 1.1.46 分发故障调查与修复

日期：2026-09-13。调查基线：`3c61cf5`，`1.1.46+57`，Flutter 3.44.8 / Dart 3.12.2。

## 已确认的直接原因

正式 DMG 中应用的资源签名已失效。Xcode 在 Flutter 构建结束时为应用做了 ad-hoc 签名，CI 随后把 `duckmusic-ios-helper` 写入 `Contents/Resources`，没有再次签名便制作并发布 DMG。系统校验看到的应用内容与签名封存内容不一致。

这与缺少 Developer ID / Apple 公证是两个相关但不同的问题：重新封存可以修复资源完整性；面向普通用户的正式分发还必须完成可信签名、公证与 Gatekeeper 验收。

## 线上产物证据

正式 Release：<https://github.com/John9816/music/releases/tag/flutter-v1.1.46>，发布于 `2026-09-11T13:53:53Z`，非 draft、非 prerelease。Release 原说明明确承认未使用 Developer ID 签名和公证。

核验对象为 `DuckMusic-Flutter-v1.1.46-macOS-arm64.dmg`，47,346,915 bytes。完整下载的 SHA-256 与 GitHub API 提供的 digest 完全一致：

```text
a7305021c050f4ed570077b0cef6add1fc68b7c6f2045307f9d66540142fa481
```

下载放在隔离临时目录，只读挂载，没有修改用户安装或原始构建产物。

| 检查 | 实际结果 |
| --- | --- |
| `shasum -a 256` | 与 GitHub digest 精确匹配 |
| `hdiutil verify` | DMG checksum VALID |
| `.app` 的 `codesign --verify --deep --strict` | exit 1，资源 seal 失效，明确指出新增 helper |
| `codesign --display --verbose=4` | `Signature=adhoc`、`TeamIdentifier=not set` |
| 主程序架构 | `x86_64 arm64` universal |
| helper 架构 | `arm64` |
| Info.plist | bundle ID `com.751152.duckMusic`，版本 `1.1.46`，构建 `57` |

关键原始错误：

```text
7511.app: a sealed resource is missing or invalid
file added: 7511.app/Contents/Resources/duckmusic-ios-helper
```

同一工作区新构建、尚未加入 helper 的 `build/macos/Build/Products/Release/7511.app` 则通过了完整资源签名校验：

```text
7511.app: valid on disk
7511.app: satisfies its Designated Requirement
```

因此有产物级证据支持“构建后写入 helper 破坏资源 seal”，不是仅由文档推测。正确的 DMG 校验和不能替代应用资源签名校验。

原安装包的 `spctl` 在沙箱中返回 `internal error in Code Signing subsystem`；升级执行请求被中断。`stapler validate` 在受限环境也未得到可信验收结果。这些错误不作为真实 Gatekeeper 判决或 staple 状态的证据；本次可信结论来自完整下载、只读挂载和实际 `codesign` 输出。

## 历史与代码边界

- `b714291`（2026-08-13，`ci: publish unsigned macOS release artifacts`）移除了证书导入、最终签名、`codesign` 验证、公证和 staple，只留下 `hdiutil verify`。
- 基线工作流在 `flutter build macos` 之后调用 `scripts/build_ios_helper.sh`，向已封存的应用增加文件。
- Xcode Release 配置使用 `CODE_SIGN_IDENTITY = "-"`，所以“未签名发布”的实际产物带有已失效的 ad-hoc 资源签名。
- `scripts/build_ios_helper.sh` 只编译和设置可执行权限。运行时仍从 `Contents/Resources/duckmusic-ios-helper` 寻找助手，本次保留该路径及脚本接口。

## Hardened Runtime 的额外实测

恢复正式签名时发现 standalone Dart AOT helper 需要单独的内存映射权限。对相同线上 helper 的隔离副本，始终使用临时 ad-hoc 身份，不读取钥匙串或调用设备安装；执行的命令为 `audit-unknown-command --json`，正常行为是返回 `code=unknown` 的 JSON 与 exit 2。

| 隔离副本签名参数 | 执行结果 |
| --- | --- |
| 原 Release.entitlements，不加 Hardened Runtime | 正常 JSON，exit 2 |
| 原 Release.entitlements + Hardened Runtime | 系统终止，exit 137；签名校验仍有效 |
| 原权限 + `allow-jit` + Hardened Runtime | 仍被终止，exit 137 |
| `allow-unsigned-executable-memory` + Hardened Runtime | 正常 JSON，exit 2 |
| 仓库最终 Helper.entitlements（仅上述内存例外）+ Hardened Runtime | 正常 JSON，exit 2 |

因此新增 `macos/Runner/Helper.entitlements`，仅用于 helper。主应用继续使用原 `Release.entitlements`。这没有关闭 Gatekeeper、关闭 Hardened Runtime 或扩大主应用权限。`allow-unsigned-executable-memory` 是助手进程的安全例外，不能据此给所有框架或主应用添加同一权限。

## 实现

- `scripts/configure_macos_signing.sh`：正式构建先校验六项凭据是否存在，要求 Developer ID Application，将证书与公证凭据放入本次 CI 的独立临时钥匙串。仅报告字段名和成功状态，不打印真实值；失败和任务结束时清理。
- `scripts/verify_macos_app.sh`：验证 bundle ID、版本、构建号、helper 可执行性，以及应用内所有 Mach-O 是否包含目标架构。封存后严格验证 app 与 helper；正式模式还检查 Apple Developer ID 证书要求、Team ID、Hardened Runtime 和安全时间戳。
- `scripts/package_macos.sh`：先验证输入，再创建私有副本；显式签署所有 Mach-O、嵌套 framework / bundle，最后签署外层应用。应用公证 `Accepted` 并 staple 后制作 DMG，再签名、公证、staple、Gatekeeper 评估。只读挂载后复验应用，卸载成功才输出最终资产。
- 公证命令非零退出、超时或状态不为 `Accepted` 时，保留命令退出码、合法 submission UUID、Apple 状态；日志可用时输出 `statusSummary` 与 `issues`，不输出凭据，不放宽门禁。
- 工作流恢复正式发布签名与公证，缺配置即失败。正式文件名保持 `DuckMusic-Flutter-v<version>-macOS-arm64|x64.dmg`；非正式手动构建使用明确的 `-development.dmg` 后缀。
- `RELEASE.md` 同步说明正式分发要求、开发包用途、helper 权限和故障诊断，移除以绕过系统校验作为正式验收方式的说明。

## 验证与限制

最初 13 项脚本行为测试已先观察失败，再运行通过。真实 macOS 集成检查随后发现 `lipo -verify_arch` 的参数位置必须位于输入文件之后，已增加原生回归并修正。当前专项文件共 16 项，包含原生 Mach-O 检查、编译真实 helper 后以 Hardened Runtime 签名并执行的测试；macOS 原生的两项在其他系统上跳过。最终全量 Flutter 测试由主代理串行执行，避免共享原生构建缓存的并发竞争。

在真实线上坏包的私有副本上运行新打包脚本，27 个 Mach-O 全部通过目标架构检查；签名后 `.app` 与 helper 均报告 `valid on disk` / `satisfies its Designated Requirement`，原“新增 helper”错误消失。这验证了资源 seal 的修复。最初在沙箱内继续制作 DMG 时，`hdiutil create` 被系统设备访问限制阻止；完整本地 DMG 验收由主代理在获准环境中继续执行。

已通过 Bash 语法检查、Helper.entitlements 的 plist 检查、工作流 YAML 解析和 Dart 格式化。主代理已确认本机没有有效 Developer ID 签名身份，因此未执行真实生产证书签名或向 Apple 提交公证；受控命令测试不等同于 Apple 信任验证。正式 CI 必须实际通过本次恢复的门禁后才能发布。

本地修复与验收阶段未修改版本、提交或推送、创建标签、替换已发布资产或修改用户安装。正式修复发布应递增版本与构建号，保留既有 `1.1.46` 标签不可复用。

## 最终本机验收补充

主代理已串行完成最终完整测试：366 项通过、0 失败、0 跳过，包含本文件对应的全部 16 项测试。最终 macOS Release 重建后，在 Apple M1 Pro 上实际完成 development DMG 制作、只读挂载与 27 个 Mach-O / app / helper 完整性验证，并从该 DMG 复制出的应用成功启动业务界面。

本次增量 Xcode 构建还出现了旧外层资源 seal 引用新 App.framework 的情况；框架单独验证有效，外层签名陈旧。最终打包流程的由内到外重新签名同样消除了该问题，原始 Xcode 构建目录没有被当作交付物。

沙箱外对最终开发 app 的真实 `spctl --assess` 为 `rejected`（exit 3），该包仍是 ad-hoc 签名、无 Team ID、未公证。这个结果明确区分了已修复的内容完整性与尚未通过的 Apple 信任门禁。两个诊断挂载均已卸载，下载原包与本地开发产物保留。完整命令、DMG SHA-256、其他平台编译及截图结果见 [综合验收报告](2026-09-13-production-readiness-verification.md)。
