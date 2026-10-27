# AGENTS.md — Todo Wallpaper 交接记忆

给任何接手本仓库的 AI 读的长期记忆。**先读本文件，再读 `docs/STATE.md`。**
一次任务结束后，把新结论写回 `docs/STATE.md`，不要只留在对话里。

## 项目是什么

- 原生 iOS 应用：SwiftUI，主 App + Widget 扩展。
- Bundle：`org.todowallpaper.app` / `org.todowallpaper.app.widget`，App Group `group.org.todowallpaper.app`。
- 产品：待办清单壁纸。没有 PWA、WebView、云端同步、AI。
- 当前 **0.5.1 / build 1029**，代码提交 `9210e85`；`d63dd87` 是它的证据记录提交（仅文档，`[skip ci]`）。
- 仓库：https://github.com/klein7syd/ios-wallpapertest （public）

## 开发者的真实环境（很重要，别搞错）

- 只有 **Windows 电脑 + iPhone**，**没有 Mac**，不写代码，靠 AI 操作，需要一步一步的操作说明。
- **免费 Apple 开发者账号**，不是 99 美元年费账号：签名 7 天过期，重签重装是常态，不是故障。
- 编译在 **GitHub Actions `macos-26`**（Xcode 26.6 / iOS SDK 26.5 / arm64 / 最低 iOS 17.0），public 仓库免费。
- CI 出的是**未签名 IPA**；签名和装机在 **Windows 本地**用 iPASide（zsign 内核）走 USB 完成。
- 不要建议买 Mac、租云 Mac、或上 App Store —— 与现状不符，会浪费对方时间。

## 红线

- 不在仓库里放证书、profile、p12、设备 UDID、签名产物。仓库只有源码。
- **编译通过 ≠ 真机通过**。`docs/VALIDATION.json` 记录了哪些只是编译/模拟器验证。
- 不许假装验证过真机。没装到手机上就写 `not_verified`。
- 不改写历史验证结论；新证据只追加。
- 版本号与 `CURRENT_PROJECT_VERSION` 必须一起改，不要手改产物。

## 网络（这台机器特有，最容易卡住）

- 直连 GitHub 不通，必须先开代理（系统代理 `127.0.0.1:7897`）。
- Git 的 schannel 后端在本机会报 `SEC_E_NO_CREDENTIALS`（0x8009030e），**必须换 OpenSSL 后端**：

```powershell
$env:HTTPS_PROXY="http://127.0.0.1:7897"; $env:HTTP_PROXY="http://127.0.0.1:7897"
git -c http.sslBackend=openssl pull --ff-only
```

- 如果 clone / push 卡住或报 `RPC failed`，再加 `-c http.version=HTTP/1.1`。当初 Codex 在这台机器上就是这样克隆成功的（它的放行规则里记着）。

## 入口脚本（都在 `native-tools/`）

- `build-product.sh` —— CI 里的正式构建入口，只能在 macOS 跑。
- `check-native.sh` / `check-ios-ui.sh` / `check-ui-structure.py` —— 源码与 UI 结构校验。
- `verify_product_ipa.py` —— 产物校验。
- 具体参数以脚本内注释和 `.github/workflows/*.yml` 为准，不要凭记忆编参数。

## 记忆文件

- `AGENTS.md`（本文件）—— 不常变的约定与环境事实。
- `docs/STATE.md` —— 当前版本、已验证/未验证、下一步。**每次任务结束更新。**
- `docs/VALIDATION.json` —— 历史验证证据，只追加。
- `docs/DEVICE-TEST.md`、`TodoWallpaper/DEVICE-TEST.md` —— 真机测试步骤。

## 接棒协议（每个会话都必须遵守）

上下文会耗尽，文件不会。**不要靠对话记忆接棒，靠这三步。**

**会话开始：**
1. 读本文件（自动加载）和 `docs/STATE.md`。
2. 跑 `git log --oneline -10` 和 `git status`，看清当前在哪。
3. **先复述**「当前版本 / 已验证 / 未验证 / 下一步」给用户确认，再动手。

**会话结束（或上下文快满时）：**
1. 更新 `docs/STATE.md`：这次做了什么、验证到哪一步、下一步是什么。
2. 提交，commit message 写清「为什么」，不只写「改了什么」。
3. 打一个检查点标签：`git tag checkpoint-YYYYMMDD-HHMM`。

**禁止（会造成不可恢复的损失）：**
- 禁止 `git push --force` / `--force-with-lease` 到 main。
- 禁止 `git reset --hard` 到没有 tag 或 bundle 兜底的提交。
- 禁止删除分支、删除 tag、改写已推送的历史。
- 破坏性操作前必须先打 tag，并在回复里说明「这一步可以用 X 回退」。
