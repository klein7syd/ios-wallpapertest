# Todo Wallpaper · 阶段 B

正式 Bundle ID：`org.todowallpaper.app`。版本 `0.1.0`，CI 构建号从 1001 开始。最低 iOS 17。

与 `native-validation/` 中原始 Bundle ID 的 R1 基线分开。只实现待办 CRUD、完成/恢复、手动排序、本地保存及 SwiftUI TabView/NavigationStack；其余阶段尚未加入。

- `Core/TodoItem.swift`：版本化文档、稳定 UUID 和排序规则。
- `Core/TodoRepository.swift`：持久化；目录可注入，UI 不参与文件操作。原子写入、进程锁、前一版本备份、拒绝覆盖损坏/未来数据。
- `App/TodoStore.swift`：主线程视图状态，与存储层分离。
- `App/TodoWallpaperApp.swift`：原生列表、编辑表单、底部导航及浅色/深色系统样式。
- `Tests/RepositoryChecks.swift`：直接编译生产存储代码，验证数据变化、重新实例化读回、备份及异常文件保护。
- `TodoWallpaper.xcodeproj`：已生成的真实 Xcode 工程与共享 Scheme。
- `../native-tools/generate_product_project.py`：确定性生成器，无第三方依赖，不会改写 R1 工程。

工作流只在正式工程/工具变化时运行，基线和正式工程分别构建；文档性结果更新可用 `[skip ci]` 避免重复编译。构建脚本执行存储检查后编译 ARM64 device IPA，并复用 R1 Mach-O 检查函数确认真机平台和未签名状态。

待 iPhone 反馈：[DEVICE-TEST.md](DEVICE-TEST.md)。没有 Apple 登录、私钥、profile 或设备信息进入云端工作流。

## 本次实际构建

- 版本：0.1.0；构建：1001。
- 提交：460c8945fc515d2298d0bec6892c2f136bfdab96。
- Actions：https://github.com/klein7syd/ios-wallpapertest/actions/runs/40105646210。
- Job 120906658597：success；BUILD SUCCEEDED。
- 生产 Core 代码实际编译并执行存储检查，覆盖 CRUD、Unicode、排序、重新实例化保存、备份、拒绝写入损坏/未来版本文件。
- 实际 IPA：ARM64 / iOS device / 最低 iOS 17 / org.todowallpaper.app / 未签名。
- SHA256：eb0d9d6205662cfb65d1dea1d820554805721c9d161671ed026713144dabfe80。
- 仅有未依赖 AppIntents.framework 而跳过元数据的预期工具链警告；当前正式 App 不含 App Intents，不将其视为已实现。
- 尚未通过设备验收：Windows 签名安装、触摸/键盘/排序、退出重开与重启、同构建及更高构建覆盖数据保留。

本轮共运行两次 macOS 构建（阶段 A 和 B 各一次），均成功。结果文档更新使用 [skip ci]，避免再次编译。
