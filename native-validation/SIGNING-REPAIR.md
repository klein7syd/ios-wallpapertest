# 构建 5 签名修复 R1

这是同一个 0.0.2 / 构建 5 App，未签名 IPA 字节未变；仅修复 Windows 签名脚本及安装前校验。手机现有 App 和原计数请保留。

## 现在操作

1. 将完整 R1 ZIP 解压到新文件夹；保持 iPASide 使用原签名账号、已登录，USB 连接并解锁 iPhone。暂停普通自动刷新，关闭 iPASide 窗口，避免同时签名。
2. 双击 Install-WidgetProbe.cmd。首行应显示 Signing repair: 0.0.2-build5-signing-r1。脚本复用原 iPASide，不更换其安装目录里的程序。
3. 脚本会在签名前先嵌入两份 profile，再签名。只有主 App 与 Widget 的权限、资源文件、代码哈希全部检查通过，才会尝试覆盖安装。
4. 看到 INSTALL SERVICE SUCCEEDED 后再打开手机 App，核对旧计数保留、共享待办可读，然后按 DEVICE-TEST.md 添加/操作 Widget。App 仍显示构建 5，这是签名修复，不是新 App 构建。
5. 如仍报错，保留现有 App，发送控制台报错。不要卸载或改为删除 Widget 扩展。

## 原因和验证边界

用户上次安装时，设备拒绝 Widget 的资源签名（0xe8008017）。原脚本的身份/权限检查没有覆盖资源封装完整性，已补上。

官方 zsign v1.1.2 修复过同类多 profile 问题：扩展 profile 在 CodeResources 封装之后才被写入。R1 不依赖升级 iPASide，而是在签名前先嵌入最终 profile，让旧工具再次写入时字节保持一致。

已用真实构建 5 IPA 和人工测试证书/profile 实际运行：v1.1.1 原流程检测到扩展 profile 属于封装后新增文件；预先嵌入后通过；v1.1.2 原流程也通过。人为修改 profile、可执行代码或资源哈希均会被新校验拦住。这些测试不代表 Apple 账号签名、Windows 实机或 iPhone 安装通过；R1 仍需本次设备反馈。

原始未签名 IPA SHA256：54d62cade526e589e8c9f416914e502383674b0ba9aef4af1c614eab92fee96c。
参考：https://github.com/zhlynn/zsign/releases/tag/v1.1.2
