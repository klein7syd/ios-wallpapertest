# STATE — 当前状态

最后更新：2026-10-27

## 版本

- 交付版本 **0.5.1 / build 1029**，代码提交 `9210e85`，CI run `40481159418`。
- 接棒阶段的提交从 `540e02a`（Add agent handoff memory）开始，之后见 `git log --oneline`。
- `d63dd87` 是 0.5.1 的证据记录提交（只改文档，`[skip ci]`），也是「Codex 最后一版」的标签位置。
- 近期链路：0.4.2(1015) → 0.4.3(1017) → 0.4.4(1022) → 0.5.0(1025) → 0.5.1(1027/1028/1029)。

## CI 已通过（0.5.1）

- App + Widget 编译（arm64，Release，iOS device）
- 原生渲染检查、状态持久化检查、UI 结构检查
- iOS Simulator 原生 UI 渲染截图

## 真机侧情况（截至 2026-10-27）

- 0.5.1 已签名并安装到 iPhone，用户**口头**确认「装上了并且验收了」（2026-10-27，仅口头，无逐项记录）。
- **以 `docs/VALIDATION.json` 为准**：1029 的真机项仍是 `pending` / `not_verified`。不要用上面这条口头结论去改验证记录，必须等逐项证据补齐后再追加。
- 以下项目仍缺逐项证据，`VALIDATION.json` 里还是 `not_verified`，等用户补充具体表现：
  - iPhone 滚动视觉 bug 是否真的修好
  - 照片与触摸 / PhotoKit 访问
  - Widget 交互
  - App Group 迁移
  - 升级后数据保留
  - 真机 FPS、Home Screen 材质表现

## 手上的产物

- `C:\Users\32077\Downloads\TodoWallpaper-0.5.1-build1029-Windows\`
  含未签名 IPA（`TodoWallpaper-unsigned.ipa`，1.33 MB）、签名脚本、安装脚本、校验报告。
- 更早的安装包：同目录下 0.4.x / 0.5.0 各一份，作回滚备份。

## 回退点（改坏了从这里回去）

- 标签 `codex-final-0.5.1` → `d63dd87`：Codex 交付的最后一版，冻结不动。
- 标签 `checkpoint-handoff-2026-10-27` → `d63dd87`：接棒基线。
- 离线快照：`..\backups\todo-wallpaper-codex-final-0.5.1.bundle`（可用 git clone 还原）。
- 回退命令示例：`git checkout codex-final-0.5.1`，或 `git reset --hard codex-final-0.5.1`（会丢弃之后的提交，谨慎）。

## 接棒状态（2026-10-27）

已完成：

- 最新源码拉到 0.5.1（`d63dd87`），工作区干净，42 + 接棒提交。
- 记忆文件：`AGENTS.md`、`docs/STATE.md`、`docs/PRODUCT.md`、`docs/KNOWN-ISSUES.md`。
- 标签：`codex-final-0.5.1`（钉住 Codex 最后一版）、`checkpoint-handoff-2026-10-27`。
- 离线备份：`../backups/*.bundle`，已实测可用 `git clone` 还原（43 提交、123 文件、两个标签都在）。
- Windows 上可直接跑仓库自带的 126 项检查：`python native-tools/check-ui-structure.py`。

仍待完成：

- **推送到 GitHub**：本机没有 GitHub 凭据，需要在真实终端里登录一次。
- 把 `../backups` 复制到第二个物理位置（OneDrive / U 盘）。

## 下一步候选

1. 逐条确认 `docs/KNOWN-ISSUES.md` 里的 8 条真机问题：0.5.1 上哪些已经好了、哪些还在。确认后补进 `docs/VALIDATION.json`。
2. 把标签 `codex-final-0.5.1` 推到 GitHub，让「Codex 最后一版」在云端也能定位。
3. 修剩下确认还存在的问题，或补 v0.4 被跳过的快捷指令闭环。
