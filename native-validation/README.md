# 原生 iPhone 能力验证

当前交付：**0.0.2，构建 5**。只修改 `native-install-probe` 分支的独立 `native-validation` 工程及其 Actions 工作流；博客 main 与原 Windows 项目没有修改。

## 签名修复 R1（当前下载包）

用户报告构建 5 安装失败：Widget 扩展资源签名被设备拒绝（0xe8008017）。上一版只检查身份和权限，没有检查资源封装，不能视为签名有效。

[修复说明与操作](SIGNING-REPAIR.md)：保持同一构建 5 IPA，签名前先嵌入主 App/Widget 的最终 profile，兼容旧 zsign 的多 profile 封装顺序；增加资源/代码哈希检查。Linux 上已用真实 IPA 与人工测试身份复现旧问题、验证预嵌入修复，并测试篡改拦截。Windows R1 签名安装、覆盖数据保留、小组件功能仍待真机反馈。证据在 signing-repair-evidence/；没有重新编译 App 或变更 Bundle ID。

## 已有真机证据

构建 1：用户使用 Windows iPASide、免费 Apple Account 安装到 iPhone，截图确认 SwiftUI 启动与计数按钮正常；用户进一步确认划掉后台后计数保留。该反馈不等于构建 5 的签名/安装/小组件测试通过。

## 构建 5 的真实结果

- Actions 成功记录：https://github.com/klein7syd/klein7syd.github.io/actions/runs/40101379470
- 编译提交：9f22d99c5b6e974481f5dfe53ca6efed223f5cc4；Xcode 日志为 BUILD SUCCEEDED。
- 主 App 与 Widget 均为 ARM64 / iOS device / 最低 iOS 17，版本与构建号一致。
- IPA 实际包含 `Payload/NativeInstallProbe.app/PlugIns/NativeProbeWidget.appex`。
- 两端 Info.plist 的共享组标识一致，两个 target 配有 App Groups entitlement 源文件。
- 两端均已提取 SetProbeTaskCompletionIntent 元数据，openAppWhenRun 为 false。
- IPA 无代码签名、无 embedded.mobileprovision，不可直接安装。App Groups entitlement 源文件不等于签名已经获得授权。
- 未签名 IPA SHA256：54d62cade526e589e8c9f416914e502383674b0ba9aef4af1c614eab92fee96c。

## 这次增加的能力

保留旧计数存储键 nativeProbe.counter.v1。增加一条可改文字、可完成/恢复的共享待办。数据逻辑放在 Shared/SharedProbeStore.swift，使用 App Group 中的版本化 JSON、原子写入和跨进程文件锁；读取失败时明确报错，绝不退回各自私有存储伪装共享成功。

主 App 在重新进入前台时读取共享文件；小组件使用 Button(intent:) 完成/恢复任务。提供小号与中号 Widget。显示共享修订、写入来源、存储 ID 和实际 Bundle ID，供真机核对；刷新由系统调度，不承诺每秒后台更新。

## Windows 本地签名与覆盖安装

见 [DEVICE-TEST.md](DEVICE-TEST.md)。完整解压 Actions 测试包后，使用随包 Install-WidgetProbe.cmd。该脚本复用已安装的 iPASide engine 与登录状态，为主 App/Widget 分别配置 profile 并关联同一共享组，再通过 zsign 多 profile 模式本地签名和安装。

源码主 Bundle ID 始终为 org.todowallpaper.nativeinstallprobe。iPASide 如果已给旧 App 附团队后缀，脚本读取旧 App 的实际 ID 并沿用；扩展为该 ID + .widget。签名账号不匹配或旧 App 无法识别时停止，绝不通过卸载重装规避覆盖验证。

为何需要脚本：已检查 iPASide 官方源码树 be811fcaea8556fe5108dd25279d626fa0d56435；普通 sideload 默认 remove_extensions=True，只 provision 主 App，app_groups 在普通流程为空；单纯关闭移除扩展不足以验证两份 profile/共享组。本辅助脚本只在本机使用签名材料，不向仓库上传凭据或私钥。

该 Windows 辅助脚本尚未在用户电脑执行。即使签名工具返回成功，也要区分本地签名结构检查、设备安装服务成功、真实 Widget 功能成功。普通 iPASide 自动刷新对此测试包尚未验证，测试期间应暂停，避免旧包或移除扩展的普通签名流程覆盖此包。

## 当前尚未通过的项目

构建 5 的 Windows 签名、iPhone 覆盖安装数据保留、Widget 出现在组件库、主屏幕直接操作、App Groups 双向共享、此包自动刷新，全部待用户实测。后续更高构建覆盖共享数据保留同样需要实测。

此工程只有一条测试待办，不是完整待办产品；未加入壁纸、AI、Liquid Glass 美化或 PWA。遇到签名/组件问题请提供报错并保留原 App，不要卸载清数据。

## 构建与验证文件

`.github/workflows/native-probe.yml` 使用 macos-26，`tools/build.sh` 同时编译两目标并验证 IPA。`tools/verify_ipa.py` 检查实际 Mach-O 平台、扩展层级、版本、ID；本地签名后再检查两份 profile/签名的共享组和身份。它是结构检查，无法代替 Apple 签名信任验证和设备功能测试。`verification.json` 分阶段记录事实。
