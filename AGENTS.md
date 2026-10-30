# AGENTS.md

## 项目一句话
原生 iOS 待办壁纸应用：主 App 里管理待办并编辑壁纸，主屏幕小组件直接完成待办，壁纸导出为 PNG。

## 技术栈与版本
- SwiftUI + WidgetKit + AppIntents + EventKit + PhotosUI + CoreText/CoreGraphics，无第三方依赖。
- 最低 iOS 17.0（`generate_product_project.py` 里 `IPHONEOS_DEPLOYMENT_TARGET=17.0`）。
- 编译器与 SDK 以 CI 为准：Xcode 26.6 / iOS SDK 26.5 / arm64（见构建日志 `toolchain.txt`、`platform.txt`）。
- iOS 26 API：`WidgetGlassBackground` 里用 `#available(iOS 26.0, *)` 判断后调用 `.glassEffect(.clear, in:)`，否则回落 `.ultraThinMaterial`。

## Target 与目录
- Target：`TodoWallpaper`（App）、`TodoWallpaperWidget`（扩展）。工程文件由 `native-tools/generate_product_project.py` 生成。
- 目录：`App/`（页面与编辑器，仅 App）、`Core/`（模型与存储，双 Target）、`Shared/`（小组件共用视图，双 Target）、`Widget/`（Widget bundle）、`Wallpaper/`（壁纸子系统，仅 App）、`Tests/`（多数为独立 macOS 原生可执行检查；只有 NativeUIProbe 在 TODO_UI_CHECKS 的 Simulator Debug App 中编译）。
- App Group：`TodoWidgetConstants.originalGroupID = "group.org.todowallpaper.app"`，定义在 `Core/TodoSharedStorage.swift`。

## 构建 / CI / 打包
- CI：`.github/workflows/todo-wallpaper.yml`，`runs-on: macos-26`，入口 `bash native-tools/build-product.sh`，产物上传为 Actions Artifact（含 `TodoWallpaper-unsigned.ipa`）。
- 签名不在 CI 做：产物是未签名 IPA，用户在 Windows 上用 iPASide（zsign）签名，脚本在 `native-tools/windows/`（`Install-TodoWallpaper.cmd` → `Install-TodoWallpaper.ps1` → `sign_todo_wallpaper.py` → `verify_ipa.py`）。
- 安装：USB 连 iPhone，用同一 Apple 账号覆盖安装，不卸载旧版；免费账号签名 7 天过期，重签是常态。
- 版本号：`native-tools/product-version.json` 的 `version`；构建号 = 1000 + GitHub run number。

## 编码约定（从源码归纳）
- 注释：既有源码保留原注释，新增注释/文档用中文、变量名用英文；用户可见文案全部中文。
- 命名：类型 UpperCamelCase，函数与变量 lowerCamelCase；常量集中在各类型的 `static let`。
- 只用官方 API，不使用私有 API；不可用的系统能力在 README/KNOWN_ISSUES 里写明限制，不伪造。
- Target Membership 在文档与新增文件注释里标注（Core/Shared 双 Target，其余单 Target）。
- 不使用已弃用 API：颜色用 `foregroundStyle`，不用 `foregroundColor`。
- 单元/渲染检查放在 `Tests/`，由 `native-tools/check-*.sh` 在 macOS 上执行；`native-tools/check-ui-structure.py` 可在 Windows 直接跑。

## 改代码前必须知道的约束
1. 编译通过 ≠ 真机通过；`docs/VALIDATION.json` 记录的是历史证据，不要用编译结果冒充真机结论。
2. 用户没 Mac：所有真机验证都要先出 Windows 包再让用户装。
3. 文字颜色不要再用 `TextLegibility.readable` 改写（壁纸渲染除外），否则用户选了颜色却看不到变化。
4. 阴影只加在文字与标记本身，不要套在包含分隔线的容器上，否则线会被糊粗；着色模式与锁屏 family 统一禁用阴影和蒙层。
5. 可读性强度的倍率要同时传给蒙层和阴影，`readableText` 有 `intensity` 参数，不传就是 `.standard`。
6. 行分隔线画在行的 overlay 上、不参与布局；不要改成分隔视图，否则行距会不均。
7. `header.topInset` 已不参与布局（`WidgetHeaderLayout.titleY = 0`），位置由 `readableEdgeInset` 控制。
8. 颜色先通过 CoreGraphics 从 P3 转换到 sRGB，再 clamp 到 0…1；`setAppearance` 会重试规范化数值并返回是否接收，撤销须检查返回值。
9. 拖动面板时不能在增量路径里做吸附（每帧位移只有 1~2pt，会被反复吸回中心）。
10. 分析上下文含图片名、crop、透明度、实际画布比例与有效底色（opacity=1 共用明暗）；结果与缺失请求为 App Group 原子文件。主 App utility 串行分析，Widget 只读/登记缺失；每次 Provider 起始清内存且 entry 携分析快照，body 仅读内存或快照。
11. CI 的 render 检查带像素断言，改布局/字体/颜色会让断言失败，需要同步更新 Tests。
12. 调试页入口在 `#if DEBUG` 内，不要放到正式版。

## 本轮维护入口
- `tools/check_handoff.sh` 调用标准库 Python 检查器，五项均输出“检查了 N 条”，零条失败；`tools/test_check_handoff.py` 的正/负向回归已接入 native 门禁。引用检查不替代编译或常量值语义审查。
- 照片/标记生产导入统一 `WidgetPhotoStore.shared`；相册事务在外观落盘后才提交。回收须保留当前、任务、两个编辑器撤销和备份引用，十分钟新文件/导入中/加载失败不删。
- App reload/Widget Provider 使用 `TodoRepositorySnapshot`，不二次 load，也不做跨事务文档缓存。
- 日期缓存跟随地区/日历并在系统通知后重建默认时区；照片组合手势全取消才回滚；微调的 begin/end 合并连点，仍为一个导出像素。

## 连心入口
用户明确要求新增底栏业务入口，现为五页。连心私有资料与钥匙串不可写入组件；仅用户明确发布的 LianxinPublication 可进入 App Group。连心壁纸使用独立草稿目录，保留原待办/壁纸/组件行为。
