# 阶段 C：正式 Widget 与共享存储

状态：本版编译与自动化检查通过，尚未得到本版真机反馈，不能标记完成或开始阶段 D。

- App：org.todowallpaper.app；原安装身份保持。
- Widget：org.todowallpaper.app.widget。
- App Group：group.org.todowallpaper.app。
- 版本：0.2.0；构建号继续沿用正式工作流 1000 + run_number。
- 原 native-validation/ 和 R1 基线分支不修改。

## 数据安全

Core/TodoSharedStorage.swift 解析签名时写入两端 Info.plist 的真实共享组，保留阶段 B 的 private 目录常量。TodoMigration 在共享目录持迁移锁，仓储在读写时持原 R1 同类 BSD 文件锁。原私有文件不删除；复制原始 JSON 字节，验证 schema、UUID 唯一性、内容、顺序和完成状态。复制后才原子写入共享就绪标记与私有迁移确认。

Widget 先检查就绪标记，且仓储 requiresExistingFile 为 true，避免先启动的 Widget 生成空文件。重复/中断迁移优先验证现有共享文件；已迁移但共享数据缺失时停止，不导回陈旧副本。签名组变化会被私有迁移确认检测并阻止。未来 schema 与损坏文档均不静默重建。

真正损坏且有可验证备份时，用户可确认恢复：先保留损坏文件，再复制备份。已迁移后只使用共享备份，禁止从旧私有副本回退。迁移未完成时可恢复旧文件的有效备份后重试。原始文件、备份和迁移快照均留在设备，不出现在构建/仓库中。

自动化检查覆盖原存储行为、逐字节迁移、状态/排序/ID 保留、Widget 首次访问门禁、重复/中断迁移、换组及主文件缺失保护、3 个独立进程并发写入，以及迁移前后备份恢复。它们使用临时合成数据，不代表设备迁移已通过。

## Widget 与签名

小、中、大号，优先未完成任务，保留一条完成项供恢复；空间不足时显示剩余数量。Widget 的 Button(intent:) 设置具体任务 UUID 的目标状态，openAppWhenRun=false。所有操作更新同一 JSON；系统回到 App 时重新读取；App 变化及 Intent 都请求时间线刷新。系统刷新预算仍适用。

native-tools/windows/ 是 R1 脚本的正式 App 适配副本：只调整产品/组标识、Info.plist 键和文件名。两份 profile 预嵌入、资源封装/代码哈希验证及本机 iPASide 调用不重写；原 R1 文件保留。签名脚本读取设备上既有正式 App ID，账号不匹配则停止，不卸载或新建身份绕过。

本机安装与验收见 TodoWallpaper/DEVICE-TEST.md。云端只产生未签名 IPA，无 Apple 凭据/私钥/profile/设备信息。

## 实际构建记录

- 日期（用户时区）：2026-10-25。
- 代码提交：922cc61a9bc1f2dce4c38ba0227f421ea1acc211。
- Actions：https://github.com/klein7syd/ios-wallpapertest/actions/runs/40111874272。
- Job 120925108096：success；日志 BUILD SUCCEEDED。
- 原 CRUD/保存检查及逐字节迁移、标记门禁、中断/重复迁移、错组/缺失文件保护、三个进程写入和备份恢复检查均实际运行 PASS。使用的是临时合成文件，未访问真实 iPhone 数据。
- 版本 0.2.0，构建 1002；实际 IPA 包含主 App 与 PlugIns/TodoWallpaperWidget.appex，均为 ARM64 iOS device、无 profile、无代码签名。
- 两目标均包含 SetTodoCompletionIntent 元数据且 openAppWhenRun=false；这不能代替真机“不打开 App”的操作验证。
- IPA SHA256：e4b7a5e4146bcec3aecc539ac22fe6641dc2c0d2bd90c0288680c97dfedc6396。
- 本阶段只运行一次 macOS 构建；记录更新跳过 CI。原 R1 基线未改动。
- 待反馈：Windows 适配签名与安装、iPhone 原待办迁移、Widget 显示/操作/同步、重启与再次覆盖保留。
