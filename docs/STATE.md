# STATE — 当前状态

最后更新：2026-10-27

## 版本

- 交付版本 **0.5.1 / build 1029**，代码提交 `9210e85`，CI run `40481159418`。
- 仓库 HEAD `540e02a`（接棒记忆文件提交）；它之前是 `d63dd87`，即 0.5.1 的证据记录提交（只改文档，`[skip ci]`）。
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

## 下一步候选

1. 把 0.5.1 的真机验收结论逐项落定，补进 `docs/VALIDATION.json`（现在只写了“验收了”，缺逐项证据）。
2. 把标签 `codex-final-0.5.1` 推到 GitHub，让“Codex 最后一版”在云端也能定位。
3. 开始下一轮迭代：等用户指定要做哪个功能、或修哪个真机问题。
