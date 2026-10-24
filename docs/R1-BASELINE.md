# 阶段 A：R1 基线

已验证版本标识：`0.0.2-build5-signing-r1`。
原始测试 Bundle ID：`org.todowallpaper.nativeinstallprobe`。

用户在本轮正式指令中确认：SwiftUI 启动、计数、本地保存、覆盖安装、WidgetKit、App Intents、App Groups 和 R1 签名修复均已通过其 iPhone 实测。此次不重新研究或宣称这些结果来自新设备测试。

原始源码来自公开仓库 `klein7syd/klein7syd.github.io` 的提交 `a5c8890f00437a3a36247421da0f9dc65e25b01c`。28 个原提交文件都存在，迁移前逐个检查 Git blob 哈希并全部匹配。原始工程直接提交 `.xcodeproj/project.pbxproj` 与共享 Scheme，没有依赖 XcodeGen。工作区遗留的旧 `project.yml` 不在成功版本提交中，没有迁移。

`native-validation/` 下 App、Widget、Shared、Xcode 工程、Windows 启动脚本、R1 签名/资源验证脚本均保持原文件内容。原 Actions YAML 原样保存在 `native-validation/original-workflow/native-probe.yml`；新仓库使用 `.github/workflows/r1-baseline.yml`，只调整仓库分支触发与 Artifact 名称。

源提交中的 verification.json、README、DEVICE-TEST.md 是历史记录，部分项目仍写“待反馈”；本文件记录用户最新确认，不伪造或改写历史日志。原证据日志仅含人工测试身份和临时路径，不含真实设备信息。来源文件清单与哈希见 `r1-source-manifest.json`。

本仓库重新编译仍会使用 Actions 本仓库的流水号作为 CI 构建号，区别于用户已验证的原构建 5。此次复编是迁移完整性验证；不要求卸载或覆盖手机中已成功的原测试 App。原 R1 测试包与正式产品分开保留。

已排除 IPA、签名输出、profile、私钥、本机缓存、下载认证链接和设备标识。根目录 .gitignore 防止这些本地文件进入后续提交。Public 源码可能被复制、缓存，后续设为 Private 不能撤回已公开内容。

阶段 A 已读取真实日志并通过：

- 提交：1d002b7ee6659914f5280a346973f196a1bb060f。
- Actions：https://github.com/klein7syd/ios-wallpapertest/actions/runs/40105083399。
- Job 120904990760：success；日志含 BUILD SUCCEEDED，IPA 结构检查 passed。
- 本仓库复编流水号/构建号为 1，不与用户原先已验证构建 5 混淆；不要求重做真机能力验证。
- 独立保留分支：r1-baseline-0.0.2-build5-signing-r1，指向上述基线提交。

阶段 A 成功后开始阶段 B，正式 Bundle ID 选用 org.todowallpaper.app，与测试 App 并存。
