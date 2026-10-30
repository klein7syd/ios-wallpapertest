# KNOWN_ISSUES

## a. 已知未修复（现象 → 涉及位置 → 根因 → 建议）

1. **壁纸"包含已完成"无视觉区分** — `Wallpaper/WallpaperRenderer.swift:drawContent`：`completed: false` 写死，标题与日期没套完成效果。建议把 `item.isCompleted` 传进 `drawText` 的 `strike` 与透明度。
2. **裁剪/透明度/明暗变化后不重算亮度** — `App/ImageAnalyzer.swift:analyzePhoto` 无调用点；`App/WidgetAppearanceEditor.swift` 只在选图时以 `crop: nil, opacity: 1` 调 `analyzeAllAnchors`。建议交互结束 400ms 去抖重算。
3. **孤立图片无回收** — `App/WidgetPhotoStore.swift:importPhoto/importMarker` 只写不删；`Wallpaper/WallpaperDraftStore.swift:cleanExpired` 只清草稿，App Group 的 `WidgetPhotos/`、`MarkerImages/` 无清理。
4. **`todos-v1.json` 重复读取** — `Core/TodoSharedStorage.swift:TodoMigration.prepare` 与 `App/TodoStore.swift:reload` 各 `load()` 一次；`Widget/TodoWallpaperWidget.swift:TodoWidgetProvider.read` 同样两次。
5. **相册导入整张读入且单张失败即中断** — `App/WidgetAlbumPicker.swift:AlbumReader.prepare`：用 `requestImageDataAndOrientation` 取原图，任一 `throw` 直接退出，已写入文件不回滚。
6. **`TodoSchedule.label` 每次新建 `DateFormatter`** — `Core/TodoSchedule.swift:label`（计算属性）。
7. **双指连坐回滚** — `App/PhotoMotionView.swift:finish`：任一识别器 `.cancelled` 会把整次交互回滚到 `initialCrop`。
8. **白蒙层的自动强度未区分** — `App/ImageAnalyzer.swift:suggestedScrim(meanLuma:contrast:)` 只按"越亮越强"，深色文字的白蒙层需要反向映射。
9. **轮换到未分析的那张图时回退固定值** — `Shared/AppearanceStore.swift:analysis(for:anchor:)` 命中不了缓存时，`Core/ReadableModels.swift:ReadableSettings.autoScrim` 回退 `ReadableDefaults.scrim = 0.4`。相册导入时每张都算过，只有历史数据或绕过导入路径时才会缺。
10. **Widget 进程内分析缓存不失效** — `Shared/AppearanceStore.swift:AppearanceStore.analysis` 的进程内字典在 Widget 扩展里没有失效入口。
11. **标记视图没有阴影** — `Shared/TodoWidgetContent.swift:mark` 调用 `TodoMarkerView` 时没有加 `.readableText`，标记在复杂背景上缺少托底。
12. **壁纸 `drawText` 的 `shadow` 参数已成死参数** — `Wallpaper/WallpaperRenderer.swift:drawText` 签名仍保留 `shadow: CGColor? = nil`，但 `setShadow` 已删除、无人再传值。
13. **壁纸微调步进过小、从边缘会跳变** — `Wallpaper/WallpaperEditorView.swift:nudge`：按 `layout.panel.midX / 390` 重算再叠 `dx / size.width`（约 0.2pt），且未包在 `interaction.begin/end` 里；`panelX` 被夹在 0…1 但 `midX` 只能落在 0.46…0.54，从边缘点一次会跳。
14. **`setAppearance` 校验失败仍静默丢弃** — `App/TodoStore.swift:setAppearance` 第 47 行 catch 后只设 `appearanceError` 并 `return`，本次修改不生效；`appearanceError` 要到下一次成功 `saveAppearance`（第 81 行）或 `reloadAppearance`（第 86 行）才清空。
15. **选图时的亮度分析在主线程** — `App/WidgetAppearanceEditor.swift` 的 `.onChange(of: selectedPhoto)` 里 `Task { … analyzeAllAnchors … }` 继承视图的 MainActor，解码大图并做三次 48×48 渲染都在主线程。

## b. 真机未验证

- 三个锚点下 `edgeInset` 负值能否真的贴近组件边缘（可能被 WidgetKit content margins 吃掉）。
- 着色（accented/vibrant）模式与锁屏组件下是否确实无蒙层无阴影。
- 阴影强度三档在真实壁纸上是否肉眼可区分。
- 相册轮换跨日切换是否按 `photoName(at:)` 生效。
- 免费账号签名 7 天过期后的覆盖安装与数据保留。

## c. 系统限制

- 主屏幕组件背景由系统合成，`.glassEffect` 在组件里可能不可用；不得承诺与电池组件同款透明。
- 组件刷新时机由系统调度，`policy = .after(...)` 只是请求，不保证准点。
- 导出的壁纸是静态图片，圈不可点击。
- 免费 Apple 账号签名 7 天过期，重签重装是常态。

## d. 历史踩坑（现象 → 根因 → 修复位置 → 不要改回去的原因）

1. **用户选的颜色不生效、只有日期变色** → `safeColor` 调 `TextLegibility.readable(_:on:)` 按固定底色把颜色替换成黑白；日期行继承外层颜色没走替换 → 改为 `safeColor` 直接返回所选颜色（`TodoWidgetContent`）。不要再引入按底色的强制改写。
2. **取鲜艳颜色报错并锁死撤销** → Display P3 分量 <0 或 >1，`WallpaperColor.isValid` 失败 → `StyleColorControl` 里 clamp 0…1。不要移除 clamp。
3. **分隔线被糊粗** → 阴影套在包含分隔线的整个容器上 → 阴影改为逐文字加（`readableText`），分隔线画在行 overlay。不要改回整块阴影。
4. **强度切了没反应** → `readableText` 没接 `intensity`，恒为 `.standard` → 扩展增加 `intensity` 并三处传入。
5. **日期不跟随完成效果** → 日期无颜色修饰、固定 0.75 透明度 → `title()` 统一 `rowColor` / `rowFade`。
6. **相册轮换的自动蒙层永远是 0.4** → 相册导入没调用分析 → `AlbumReader.prepare` 逐张 `analyzeAllAnchors`；移除照片时清缓存。
7. **控件上下跳** → 颜色控件按条件出现/消失 → 改为常驻 + `disabled`。
8. **面板拖不动，必须猛甩** → 每帧 `setTranslation(.zero)` 后仍做 3pt 吸附，慢速拖动被反复吸回中心 → 删除增量路径里的吸附。
9. **早期用整块大半径阴影 / 整体压暗 / 固定 0.4 蒙层** → 糊、破坏照片、无法自适应 → 已由局部 `ScrimView` + 双层配方阴影 + 图片分析取代，不要退回去。
10. **旧文字描边（多方向偏移叠文字 / 位图描边）** → 发虚、性能差、ImageRenderer 不渲染 → 全部删除，改为纯阴影方案。
11. **旧 `header.topInset` 仍在生效** → 界面上已无控件能改它，迁移也只清了部分锚点 → `WidgetHeaderLayout.titleY = 0`，位置统一由 `edgeInset` 控制。
13. **壁纸 `setShadow` 旧阴影** → 文字下方出现硬边发糊 → 已删除 `setShadow` 调用与 shadow 常量（`WallpaperRenderer`），签名参数保留但不再使用。不要重新加回去。
14. **标记视图没有阴影** → 标记与文字在同一行时视觉不一致 → 尚未修复，见 a 部分第 11 条。
12. **测试里的像素断言随布局变化失败** → CI 有 render 检查 → 改布局后同步更新 `Tests/`。
