# KNOWN_ISSUES

## a. 本轮处理结论

本轮请求涉及的已确认代码缺陷均已修复并移入历史踩坑。编译、原生检查、模拟器、签名安装与真机验收是不同证据，最后两项仍待用户设备验证。

- **静态壁纸完成态：已确认无需修改。** `WallpaperGeometry.glyphKey` 与 `check-ui-structure.py` 明确要求静态装饰不应用旧完成视觉效果；保留该设计，不采用旧问题列表中恢复删除线/降透明度的建议。
- **壁纸可读色：按要求保留。** `WallpaperRenderer.effectiveTextColor` 仍调用 `TextLegibility.readable`，本轮没有修改该函数或其调用行为。
- **微调视觉跳变：未复现，需真机。** 216 个生产布局中心/边界场景验证可见移动不超过一个导出像素；已修复连续点按的撤销分组，未凭存储中心值变化推断画面跳变，也未加大步进。
- **旧壁纸阴影：绘制与控件已不存在，无需恢复或再次删除。** 本轮仅清理 `drawText` 死参数和过时注释，持久化兼容字段保留。

## b. 真机未验证

- 三个锚点、负边距与 WidgetKit content margins 的真实贴边效果。
- 真实 accented/vibrant 模式下的阴影/蒙层禁用，以及不同照片上三档阴影、黑/白/粉字的肉眼观感。共享渲染器覆盖锁屏 family 门禁，但扩展当前只注册主屏小/中/大规格。
- 调裁剪、透明度后的约 0.5 秒自动数值刷新、大图流畅度、内存峰值与真实触摸帧率。
- Photos 完整权限、iCloud 网络失败、取消按钮、批量导入的真实体验及长期图库回收。
- 双指系统中断、连续微调撤销和系统地区/日历/时区设置切换后的显示。
- 相册跨日后的实际 Widget 刷新、免费账号签名、覆盖安装及数据保留。

## c. 系统限制与保守行为

- 主屏组件背景由系统合成，公开 `.glassEffect` 不保证默认图标模式呈现电池组件同款透明效果。
- `policy = .after(...)` 只请求系统刷新，不保证准点；App 挂起时缺失分析先回退基础值 0.4，重新打开后补算。
- 导出的壁纸是静态图片，圆环不可点击；不绕过沙盒更换系统壁纸。
- 免费 Apple 账号签名通常七天过期，需沿既有流程重签覆盖。
- 图片被备份、撤销或禁用相册引用时继续保留；最近十分钟文件不删。任一权威文件或恢复归档损坏时整轮 GC 跳过，宁可少删。

## d. 历史踩坑（现象 → 根因 → 修复位置 → 不要改回去的原因）

1. 用户选色不生效 → 小组件按底色强制替换颜色 → `TodoWidgetContent.safeColor` 直接采用所选颜色 → 不得恢复小组件自动黑白改色；壁纸的既有保护另行保留。
2. 鲜艳取色报错并锁住撤销 → P3 越界分量直接解释为 sRGB → `StyleColorControl` / `WallpaperColor.sRGB` 先转换色域再夹取 → 不得只截断原色域数值或移除合法范围校验。
3. 分隔线糊粗 → 容器整体加阴影 → `TodoWidgetContent` 逐文字/标记加阴影，行 overlay 画分隔线 → 不得把分隔线套回阴影容器。
4. 强度切换无效 → 未向文字传 intensity → `readableText` 与调用方统一传强度 → 不得固定 `.standard`。
5. 日期不跟随完成效果 → 日期独立颜色/透明度 → `TodoWidgetContent.title` 共用 rowColor/rowFade → 保持标题与日期一致。
6. 相册蒙层恒定或与构图不符 → 选图单次原图分析、旧键不含上下文 → `TodoStore` / `PhotoAnalysisService` 整相册串行处理，按 crop/opacity/底色/实际比例存原始统计 → 不得退回仅按图片名缓存建议值。
7. 控件上下跳 → 条件插入颜色控件 → `MarkerEditors` 保持控件并 disabled → 避免调节时重排工具区。
8. 面板慢拖被吸回中心 → 每帧位移清零后仍吸附 → `WallpaperLiveCanvas` 增量路径不吸附 → 保留连续跟手，不能用阈值吞掉小位移。
9. 大片阴影与整体压暗破坏照片 → 整块效果过强 → `ScrimView` 局部蒙层与逐内容配方 → 不恢复整块大半径阴影或固定遮罩。
10. 旧文字描边发虚 → 多方向文字叠加/位图描边 → 共享层改用配方阴影 → 不恢复模拟描边。
11. 无控件的 header.topInset 仍影响位置 → 旧字段参与布局 → `WidgetHeaderLayout.titleY = 0`，统一 edgeInset → 旧字段仅解码兼容。
12. 旧壁纸文字阴影遗留 → 绘制早已删除但签名/注释残留 → `WallpaperRenderer.drawText` 删除 dead shadow 参数，Geometry 清注释 → 不重新绘制旧阴影，保留旧文件解码能力。
13. 标记与文字观感不同 → 标记未套配方 → `TodoWidgetContent.mark` 加同配方/强度/门禁 → 保留 MarkerBitmapCache 和完成逻辑。
14. 负 edgeInset 扩大蒙层 → 使用 abs → `ReadableRules.coverHeight` 只计 max(0, extraInset) → 负边距不得增加顶/底覆盖，居中偏移方向保留。
15. 白蒙层自动强度反向 → 复用黑蒙层建议值 → `ReadableRules.scrim` 按当前文字深浅运行时映射 → 新分析只存亮度/对比度，旧 suggestedScrim 只兼容解码。
16. 居中偏移固定 ±40 → 不知道自然文字高度 → `ReadableRules.insetRange`、共享 WidgetContentLayout 与几何 Preference → 滑条、setter、切换锚点和渲染必须共用边界。
17. 异常数值锁住撤销/存储错误被隐藏 → 校验失败无修正、错误混用 → `TodoStore.setAppearance` 规范化重试并返回接收结果，存储错误实际 IO 成功才清除 → 不吞掉失败撤销或未来版本保护。
18. Widget 长生命周期读旧分析 → 内存无失效边界 → Provider 起始清缓存、entry 携快照，缺失登记原子请求交 App 补算 → 不依赖可被其他尺寸清掉的全局缓存渲染 entry。
19. 大图分析卡主线程 → Task 继承 MainActor 且解码原图 → `PhotoAnalysisService` utility 串行 ImageIO128/CG32，结束400ms去抖及删除版本保护 → 不在 body/Widget 同步分析或每图 detached 并发。
20. 相册一张失败全部中断且残留文件 → 原图请求、无事务 → `AlbumReader` 目标1536逐张网络请求，单张计数跳过，全失败/过半/取消回滚，`WidgetPhotoStore` 名称日志和提交 → 不删除已持久化外观的图片，不恢复原图整批驻留。
21. App Group 图片只增不减 → 无跨编辑器保留集合 → `PhotoAssetMaintenance` 与共享 photo actor 保留当前、任务、两个撤销栈及备份，十分钟保护、失败整体跳过、清理孤立分析 → 不仅凭当前预览决定删除。
22. todos 重复读取 → 迁移已 load，调用方再次 load → `TodoRepositorySnapshot` 供 App reload/Provider 复用 → 保留锁与回执，不改为跨事务长期缓存。
23. 日期标签反复创建格式器 → 计算属性分配 → `TodoSchedule` 两种格式缓存、NSLock、系统通知失效，locale/calendar autoupdatingCurrent，应用默认时区 → 保持旧文本和浮动日期组件不变。
24. 双指一个取消丢掉全部操作 → 共享 cancelled 标志且无业务依据 → `PhotoMotionView` 记录正常结束，只在全取消回滚，最后结束提交一次 → 不恢复连坐或逐帧发布。
25. 连续微调需多次撤销 → 点按绕过交互分组 → `coalescingContext` 显式 begin/end 合并500ms同键点按 → 保留一个导出像素，不让旧计时器截断新手势。
26. 交接脚本空跑也 PASS → Bash 分列后再判断分隔符，跳过全部真实行 → `tools/check_handoff.py` 严格表格、路径、声明、覆盖及逐项非零计数，18个工具回归接 CI → 不硬编码成功数或只测试正例。
27. 布局变化造成像素回归失败 → 真实 native 渲染门禁有像素断言 → 对应 `Tests/` 同步验证实际生产行为 → 不放宽/删除断言换取通过。

## 连心首版范围与待验收

- 支持用户自填 HTTPS Chat Completions 兼容接口，非连续聊天；只有点击生成才请求。未使用用户真实密钥进行付费调用。
- 发布的是当前一张话语卡片，不含自动定时生成、历史收藏或多角色切换。修改底图/生成新句不会悄悄改已发布组件，需再次点击发布。
- 长文可在输出编辑框缩至200字；小号/锁屏组件显示空间有限，圆形以名字与心形呈现。壁纸布局有截断时阻止保存。
- 真机仍需验证第三方 API、钥匙串重签访问、Photos/iCloud、桌面/锁屏五种尺寸和系统刷新时机。AI 创作标识随输出保留。

## 本轮逐项换行
小组件固定行高和自动单行已改为内容测量与逐项预算；末项可缩行，仍无法放下一行时停止。列表最多3行和壁纸CoreText行数上限均保持既有设计；真机字体回退与系统组件边距仍需验收。
