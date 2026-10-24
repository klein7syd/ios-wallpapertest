# 原生能力验证 0.0.2

本次 IPA 是未签名真机包。主 App 与 Widget 编译/打包通过，不表示 Windows 签名、安装或 Widget 功能已经通过。

## Windows 安装

1. 在旧 App 中记下计数值，截一张图；不要卸载。退出后台保存已经由用户确认通过。
2. 将本测试包完整解压到一个文件夹。连接并解锁 iPhone；在 iPASide 选择上次签名使用的同一 Apple Account，确认已登录，然后关闭 iPASide 窗口，避免同时签名。
3. 测试期间暂停 iPASide 普通自动刷新，避免普通流程用旧 IPA 或移除扩展的方式覆盖此测试包。此能力测试包的自动刷新尚未验证。
4. 双击 Install-WidgetProbe.cmd。脚本复用电脑上已安装的 iPASide Python/设备驱动/登录状态，保留设备上原 App 的实际 ID，为主 App 和 Widget 分别申请 profile、关联同一个 App Group，再本地签名覆盖安装。它不会要求把密码、私钥上传到 GitHub。
5. 遇到错误，保留 App，发送报错。不要改用“删除扩展”绕过。本脚本尚未在你的 Windows 上实测；界面报告 SIGNING TOOL SUCCEEDED 与 INSTALL SERVICE SUCCEEDED 是两个不同结果，后者也不代表 Widget 功能通过。

源码主 Bundle ID 始终是 org.todowallpaper.nativeinstallprobe。iPASide 可能已在旧版实际 ID 后附加团队后缀；脚本读取已装旧 App 并沿用该实际 ID。扩展实际 ID 是主 App 实际 ID + .widget，共享组在原 group ID 后附同一团队后缀。App 现在显示实际 ID，便于核对。

本地结果放在 widget-probe-local-output/local-result.json；signed-package-verification.json 检查两份 profile 和两份 Mach-O entitlement。签名文件、profile、私钥不应发到公共仓库。只需反馈测试结果或错误截图。

## 真机清单（按顺序）

- [ ] 覆盖后仍只有原来的一个 App 图标；版本显示 0.0.2、新构建号；原计数值完全保留。
- [ ] App 显示共享待办而不是红色“共享容器不可用”；记下共享存储 ID 和修订号。
- [ ] 把任务改成“真机 Widget 测试”，点保存，退出重开，文字保留。
- [ ] 长按主屏幕 → 编辑/添加小组件 → 搜索“原生能力验证”，添加小号或中号；显示相同文字与修订号。
- [ ] 划掉主 App 后，留在主屏幕，点小组件任务圆圈；状态变成已完成，并且没有跳转主 App。
- [ ] 打开主 App，确认已完成、“最后写入”为 widget、Widget 操作次数增加、共享存储 ID 不变。
- [ ] 回主屏幕再次点任务恢复；再打开 App 核对未完成。
- [ ] 在 App 完成/恢复一次，回主屏幕查看 Widget 同步；必要时点 App 内“请求刷新小组件”，记录实际延迟。
- [ ] 再次运行同一安装脚本覆盖当前包；原计数、任务文字、完成状态、共享存储 ID 均保留。这只能验证重装同一构建；后续更高构建覆盖仍需实测。

## 诊断与范围

- 找不到小组件：先打开 App 一次，再去组件库找；仍不存在时提供安装日志。不能据此直接判断 WidgetKit 不支持免费账号。
- 两端出现共享容器错误：权限未获准/被签名工具改写时会明确失败，不会各自用私有存储伪装共享成功。
- 能显示但点击打不开状态：核对 Widget 是否仍旧构建、扩展是否保留、App Intent 日志/权限。先反馈，不要卸载或清数据。
- Widget 刷新由 iOS 调度，不保证后台每秒刷新。普通点击组件空白处会打开 App；本次验证的是任务按钮点击。
- 当前只有一条测试待办；没有加入完整待办管理、壁纸、Liquid Glass 美化、AI 或 PWA。
- 尚未实测：含扩展包在 Windows 的签名安装、App Groups 共享、主屏幕 App Intent、覆盖数据保留、此包自动刷新。逐项收到设备反馈后更新记录。
