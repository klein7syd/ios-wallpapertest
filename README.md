# Todo Wallpaper · 原生 iOS

Windows + iPhone，GitHub Actions macOS 编译，iPASide 本地签名安装。仓库保持 Public，不保存账号、私钥、profile 或设备信息。

## R1 基线（阶段 A 已通过）

`native-validation/` 保存原生测试工程，Bundle ID `org.todowallpaper.nativeinstallprobe`。28 个原文件逐个校验 Git blob 哈希。用户已确认 `0.0.2-build5-signing-r1` 原生安装、持久化/覆盖更新、WidgetKit、App Intents、App Groups 和 R1 签名流程通过。

迁移后的[基线 Actions](https://github.com/klein7syd/ios-wallpapertest/actions/runs/40105083399) 实际构建成功。基线独立分支 `r1-baseline-0.0.2-build5-signing-r1` 保留，不被正式产品覆盖。详见 [基线记录](docs/R1-BASELINE.md)。

## 正式 App（阶段 B）

`TodoWallpaper/`，Bundle ID **org.todowallpaper.app**，版本 **0.1.0**，构建号从 1001 开始。支持新增、编辑、删除、拖动排序、完成/恢复和本地持久化；原生 SwiftUI 底部导航。与测试 App 并存。

[正式 App Actions](https://github.com/klein7syd/ios-wallpapertest/actions/runs/40105646210) 已真实构建成功，生产存储代码的自动化检查通过。交付 **0.1.0／构建 1001**，ARM64 iOS 真机未签名 IPA 已生成并独立检查。用户于 2026-10-24 反馈“验收完成”，并认可原生底栏与简洁页面。阶段 B 按用户整体真机验收记为通过；未提供逐项设备日志，后续保持当前原生、简洁的设计方向。安装步骤与验收：[DEVICE-TEST.md](TodoWallpaper/DEVICE-TEST.md)。

正式 App 的 Widget、壁纸、AI 与视觉完善留待后续阶段。`native-tools/` 保存正式工程生成/编译工具；两条工作流按路径分别触发，避免重复构建。不会自动创建公开 Release。

公开源码可能被复制、缓存；后续改为 Private 无法撤回过去已公开的信息。
