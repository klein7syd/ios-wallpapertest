# 阶段 C：正式 Widget 与共享存储

状态：开发/构建验证中，尚未得到本版真机反馈，不能标记完成或开始阶段 D。

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


## 真机验收更新 · 2026-10-25

用户在 D1+D2 开发指令中明确确认 0.2.0 / 1002 的待办、原生导航、小中大小组件、App Intents 与共享数据同步通过真实 iPhone 验收。阶段 C 标记为通过；新版本仍需覆盖安装回归测试。
