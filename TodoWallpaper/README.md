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
