# Todo Wallpaper · 原生 iOS

Windows + iPhone，GitHub Actions macOS 编译，iPASide 本地签名安装。Public 仓库仅含非敏感源码与构建配置，不保存账号、私钥、profile 或设备信息，不自动创建公开 Release。

## 已验收基线

- 阶段 A：`native-validation/` 独立保留原始 `0.0.2-build5-signing-r1`，Bundle ID `org.todowallpaper.nativeinstallprobe`。原文件哈希、来源及独立分支见 [R1 记录](docs/R1-BASELINE.md)。
- 阶段 B：正式 App 待办 CRUD、完成/恢复、排序、本地持久化及原生底部导航，用户真实 iPhone 验收通过。
- 阶段 C：`0.2.0 / 1002`，小中大小组件、App Intents、App Groups 和同步，用户真实 iPhone 验收通过，见 [阶段 C](docs/STAGE-C.md)。

## 当前交付 · D1 + D2

正式源码在 `TodoWallpaper/`，版本 **0.3.0**。标识不变：`org.todowallpaper.app` / `org.todowallpaper.app.widget` / `group.org.todowallpaper.app`。

新增 SwiftUI 壁纸页、PhotosPicker、缩放/拖动裁剪、真实待办排版、玻璃面板连续调节、设备尺寸/自定义尺寸、原生 PNG 高清渲染、相册保存、系统分享及单份本地草稿。预览不保存相册。保留阶段 C 全部存储/迁移/小组件代码和 R1 签名流程。

[正式 App Actions](https://github.com/klein7syd/ios-wallpapertest/actions/workflows/todo-wallpaper.yml) 生成包含 App + Widget 的**未签名真机 IPA**和 Windows 安装脚本。实际结果见 [验证记录](docs/VALIDATION.json)；代码、CI、Windows 签名、安装和真机功能分别记录。

- [技术实现及限制](docs/STAGE-D1-D2.md)
- [Windows 安装与 iPhone 验收](TodoWallpaper/DEVICE-TEST.md)
- [正式工程结构](TodoWallpaper/README.md)

壁纸为静态快照，手动通过系统设置使用；壁纸玻璃独立渲染，不宣称复制系统 Liquid Glass 或后台自动更换壁纸。D1+D2 等待真机验收，D3+D4、AI 和翻译均未开发。

工作流按路径触发，只进行必要构建；文档性结果提交使用 `[skip ci]`。公开源码可能被复制或缓存，后续改 Private 无法撤回已公开的信息。
