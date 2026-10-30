# KNOWN_ISSUES

## a. 已知未修复（现象 → 涉及位置 → 根因 → 建议）

1. **壁纸"包含已完成"无视觉区分** — `Wallpaper/WallpaperRenderer.swift:drawContent`：`completed: false` 写死，标题与日期没套完成效果。建议把 `item.isCompleted` 传进 `drawText` 的 `strike` 与透明度。
3. **孤立图片无回收** — `App/WidgetPhotoStore.swift:importPhoto/importMarker` 只写不删；`Wallpaper/WallpaperDraftStore.swift:cleanExpired` 只清草稿，App Group 的 `WidgetPhotos/`、`MarkerImages/` 无清理。
4. **`todos-v1.json` 重复读取** — `Core/TodoSharedStorage.swift:TodoMigration.prepare` 与 `App/TodoStore.swift:reload` 各 `load()` 一次；`Widget/TodoWallpaperWidget.swift:TodoWidgetProvider.read` 同样两次。
5. **相册导入整张读入且单张失败即中断** — `App/WidgetAlbumPicker.swift:AlbumReader.prepare`：用 `requestImageDataAndOrientation` 取原图，任一 `throw` 直接退出，已写入文件不回滚。
6. **`TodoSchedule.label` 每次新建 `DateFormatter`** — `Core/TodoSchedule.swift:label`（计算属性）。
7. **双指连坐回滚** — `App/PhotoMotionView.swift:finish`：任一识别器 `.cancelled` 会把整次交互回滚到 `initialCrop`。
12. **壁纸 `drawText` 的 `shadow` 参数已成死参数** — `Wallpaper/WallpaperRenderer.swift:drawText` 签名仍保留 `shadow: CGColor? = nil`，但 `setShadow` 已删除、无人再传值。
13. **壁纸微调步进过小、从边缘会跳变** — `Wallpaper/WallpaperEditorView.swift:nudge`：按 `layout.panel.midX / 390` 重算再叠 `dx / size.width`（约 0.2pt），且未包在 `interaction.begin/end` 里；`panelX` 被夹在 0…1 但 `midX` 只能落在 0.46…0.54，从边缘点一次会跳。

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
14. **标记视图没有阴影** → 标记与文字在同一行时视觉不一致 → 第1组已给标记本身添加同配方阴影，并保留着色/锁屏禁用门禁，见 e 部分。
12. **测试里的像素断言随布局变化失败** → CI 有 render 检查 → 改布局后同步更新 `Tests/`。

## e. 第1组已修复（编译与真机证据分别记录）

- 负边距曾通过 `abs` 扩大顶部/底部蒙层；现在负增量按 0 计，正增量仍扩展覆盖。
- 原 a8：黑/白蒙层在渲染时根据原始亮度、对比度和当前文字深浅重算；旧 `suggestedScrim` 仅解码兼容，新缓存不写它。
- 原 a11：标记本身与文字共用阴影及效果策略；真实 accented/vibrant 与锁屏 family 均禁用效果；摘要重复阴影已移除。
- P3 颜色先真正转换到 sRGB，再夹取分量，不再把原色域数值直接解释为 sRGB。
- 居中偏移范围由自然文字高度与画布高度动态确定，滑条、setter、锚点切换和渲染共用规则；历史顶部/底部 -40 值仍能加载。
- 原 a14：`setAppearance` 对数值做规范化后重试并返回结果，成功立即清除校验错误；存储/未来版本错误须实际 IO 成功才清除。撤销检查接收结果，失败可重试。
- 新增纯 Core 规则/历史数据检查及 iOS 原生颜色、像素、样式保护与撤销检查；源码检查不构成真机验收证据。

## f. 第2组图片分析管线修复（本组原生/编译证据另记）

- 原 a2：裁剪、缩放、透明度与有效明暗曾只改变显示、不重算 → 缺统一生命周期调度 → TodoStore 结束交互后 400ms 去抖，PhotoAnalysisService 按完整上下文重算整个相册 → 不要恢复选图单次分析或 body 内工作。
- 原 a9：历史/缺失分析回退固定基础值 → 旧键不包含显示上下文且无补算闭环 → Provider 登记实际比例原子请求，App 启动/前台/公开通知串行补算，缺失时仍安全回退基础值 0.4 → 不要在 Widget 内同步计算。
- 原 a10：Widget 长生命周期内存结果陈旧 → 缺失效入口 → 每次 Provider 起始清内存并将结果快照放入 entry → 不要依赖可被另一尺寸清空的全局缓存渲染已准备 entry。
- 原 a15：选大图在 MainActor 解码并分析 → Task 继承视图隔离 → 统一 utility 串行队列只读取 1536px 已导入文件并用 ImageIO 降到 128px，再纯 CG 合成一次 32×32 → 不要重新引入 UIImage(data:) 原图分析或每图 detached 并发。
- 新增原子 AnalysisCache 三锚点封套与 AnalysisRequests 队列，解决 defaults 异步可见性；旧 defaults 不复用，只清理兼容。内存短锁、独立文件锁和删除版本防止卡主线程或删除后复活；坏/未来缓存封套安全回退。
- 单图失败不阻断分析批次；导入本身的单张失败回滚、原图读取与图片回收仍属第3组，尚未在此组修复。
