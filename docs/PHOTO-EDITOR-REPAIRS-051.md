# 0.5.1 — 照片、排版与交互修复

安装身份保持 `org.todowallpaper.app` / `.widget` / `group.org.todowallpaper.app`。沿用 R1 脚本，直接覆盖安装，勿卸载。

## 修改

- 小组件背景由 TimelineProvider 预先解码、裁剪为尺寸受限的位图（最长边不超过 768px，每张最多约 2.25MiB 解码数据），移交时间线后释放源图解码缓存。扩展视图使用 entry 中的位图，不再在 body 中读取共享文件。相册时间线从八张改为今天/明天两张，并于下一个本地午夜请求下一对。系统仍可延迟更新。
- 旧路径会把较大的源照片和未来多张图片带入组件绘制；这是照片模式失效/旧画面/闪烁的高风险来源。当前没有用户设备的崩溃或内存日志，因此不把内存问题宣称为已证实的唯一根因。真实桌面须重新验收。
- 滑条使用原生 UISlider 直接跟手，由 CADisplayLink 合并为每显示帧最多一次模型提交。触控期间不写外观文件、不请求 Widget 刷新；结束后再延迟保存。原有标准节点、吸附、数字输入与一组撤销保留。字体和文字测量有界缓存；撤销历史只在可撤销状态变化时发布，避免每次采样重复刷新整页。
- 标记新增本地图片，使用原生 PhotosPicker；去除原始元数据，最长边 512px PNG，保留透明通道。共享 App Group 保存生成名称，壁纸原生高清渲染、待办、Widget 共用，旧文件留给备份与撤销。单项优先于当前页面默认。图片可保留/变淡/替换自定义 Emoji/细线完成圆；不会强制加图形勾。
- “标记点按后效果”与“文字点按后效果”均有可见标题；壁纸仍只展示静态标记，没有伪点按行为。
- 行距归入文字页（关于 → 高级编辑选项开启后显示），范围 0–40。最小行距不再给大号组件强加双行和额外四点留白；可显式选择自动、单行、最多两行。文字与标记自身高度仍是防重叠底线。未完成数量开关移入内容页，不改变旧位置或存储值。
- 标题先保留完整字形高度再安排顶部留白，并显式固定文字自身高度，防止上边距挤掉标题。人工检查 build1028 截图进一步定位外层定高 frame 默认垂直居中造成第二次偏移；改用显式 topLeading，并要求各留白的标题墨迹与零留白相差不超过 1%。
- 已知实色面板按对比度校正黑底黑字等不可读选择，不改用户保存的颜色，保留有意设置的不透明度；照片/半透明背景增加轻微文字阴影。壁纸不透明面板也保护对比度，透光面板文字加入轻影，预览和 PNG 使用同一绘制代码。
- Emoji/图片标记使用有界原生彩色位图并对 iOS 18+ Image 指定 fullColor accented rendering，避免 Canvas 在系统着色模式下一律单色。主屏幕最终合成仍由 iOS 控制。

## 玻璃背景的证据边界

开关移至主题最顶部，并将旧 ultraThinMaterial 请求替换为 iOS 26 公开 `glassEffect(.clear, in:)`，较旧系统保留材质回退。保留旧设置键。

Apple 官方文档明确：系统透明/着色外观会进入 accented 模式，移除组件背景，换成系统玻璃/着色。这不能证明第三方 App 在默认图标模式下能得到电池组件的同等桌面透视。这个开关是实验实现，默认/深色图标模式的最终效果待真实 iPhone 截图验证；不使用私有 API、伪造主屏幕截图或承诺成功。

官方依据：
- https://developer.apple.com/documentation/widgetkit/optimizing-your-widget-for-accented-rendering-mode-and-liquid-glass
- https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- https://developer.apple.com/documentation/widgetkit/displaying-the-right-widget-background

## 兼容

TodoMarker 仅增加可选 imageName；WidgetAppearance 仅增加可选 maximumTitleLines。旧 JSON、草稿、任务 ID、顺序、完成状态、照片引用、单项 Emoji、App Intents 与文件迁移维持。旧版 App 不应覆盖降级读取新 image 枚举；请保留现有备份，不卸载升级。新版本可直接读取旧版数据。

## 验证状态

最终交付 **0.5.1 / 1029**，源码提交 `9210e85a78e5cf3a67a64fc4002a3dd58731f6ed`。

- [GitHub Actions 40481159418](https://github.com/klein7syd/ios-wallpapertest/actions/runs/40481159418)：success，主 App 与 Widget ARM64 真机目标、macOS 原生持久化/迁移/PNG、iOS26.5 Simulator 均通过；Swift 源码警告 0。
- 126 项结构/保护检查；54 组小尺寸 Emoji 原生栅格；30 张 Dynamic Type/尺寸矩阵；实际图片标记 1890×4096 PNG。
- 最终标题 0/12/24 留白的彩色墨迹像素均为 **9267**；人工核对最终截图确认本组标题没有底部裁切。1028 曾通过宽松断言但人工发现残余裁切，已在 1029 修正并收紧断言。
- 照片背景下字体/标题/完成状态产生四组不同像素；预生成图片小/中/大分别为 340×340、728×340、728×764，最大解码数据 2,224,768 bytes。图片标记原生颜色像素 1944；亮色系统黑底黑字修正后的白色文字像素 3422。
- 600 次模拟滑条采样合为一个手动触发的显示帧提交；这是合并机制检查，不能代表真机 FPS。手势与撤销的 CPU 耗时同样不等于用户触控体验。
- 最终 IPA 通过未签名 ARM64 App+Widget 结构检查，双方 App Intent `openAppWhenRun=false`；四个 R1 Windows 文件与原始源码匹配。
- GitHub artifact `12723845598`，ZIP SHA256 `76cb462fa98dbc24bc6b496c26fe5a16e0398e95278f2c37730157be0a944a99`；IPA SHA256 `859f138eb86cc372db0055ee5951a86cf0137569909c798e25b13687ace7b03c`。
- 本轮四次 CI：1026 新 PNG 测试抛错断言编译失败；1027 原生/模拟器通过、旧打包版本断言失败；1028 CI 成功但人工发现标题裁切；1029 修正并全部通过。没有把失败/人工发现问题的构建当作最终交付。

新版本 **Windows 签名、安装、真实桌面照片更新/闪烁、玻璃与手势流畅度仍待用户验收**。保留正常备份，直接覆盖安装，不卸载。
