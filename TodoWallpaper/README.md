# Todo Wallpaper · SwiftUI

最低 iOS 17。版本 **0.3.0 / D1+D2**，CI build number 为 1000 + 正式工作流 run number。稳定标识 `org.todowallpaper.app`；嵌入扩展 `org.todowallpaper.app.widget`；组 `group.org.todowallpaper.app`。

## 工程结构

- `Core/`：阶段 C 的版本化待办、稳定 UUID、进程锁/原子写入/备份、一次性 App Groups 迁移保护。未修改。
- `Shared/`、`Widget/`：已验收的真实交互式 Widget、App Intent 与共享存储。未修改。
- `App/`：已验收列表及编辑页，SwiftUI 原生 TabView 新增独立“壁纸”页；仅增加入口、关于说明与相册添加权限说明。
- `Wallpaper/WallpaperSettings.swift`：共享布局/裁剪/样式/尺寸模型。
- `Wallpaper/WallpaperRenderer.swift`：Core Graphics + Core Text + Core Image 原生渲染，同一引擎用于实时预览与目标像素 PNG。
- `Wallpaper/WallpaperDraftStore.swift`：私有壁纸草稿、原照片、显式缓存清理。与待办数据分离。
- `Wallpaper/WallpaperEditorModel.swift`、`WallpaperEditorView.swift`：异步渲染、PhotosPicker、分组原生控件、相册保存及系统分享。
- `Tests/`：生产持久化/迁移检查和 macOS 生产渲染器执行检查。仅测试程序使用合成待办和图案。
- `TodoWallpaper.xcodeproj`：真实工程及共享 Scheme；由 `../native-tools/generate_product_project.py` 确定性生成。

云端仅编译未签名 ARM64 真机 IPA，不处理 Apple Account 或用户照片。Windows 签名脚本和资源/CodeDirectory 验证原样沿用阶段 C 的 R1 适配版本。

[完整技术说明](../docs/STAGE-D1-D2.md) · [真实结果](../docs/VALIDATION.json) · [设备验收](DEVICE-TEST.md)

实际交付 **0.3.0 / 1005**，[Actions 40115769912](https://github.com/klein7syd/ios-wallpapertest/actions/runs/40115769912) 成功。原生渲染样图已检查，未将 macOS 输出视为 iPhone 验收。IPA 与 Widget 未签名，需用包内 R1 Windows 脚本签名覆盖安装，之后反馈。
