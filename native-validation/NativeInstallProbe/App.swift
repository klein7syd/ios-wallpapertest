import SwiftUI
import WidgetKit

@main
struct NativeInstallProbeApp: App {
    var body: some Scene {
        WindowGroup { ProbeView() }
    }
}

struct ProbeView: View {
    // Keep the build-1 key and standard container unchanged for upgrade testing.
    @AppStorage("nativeProbe.counter.v1") private var counter = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var shared: SharedProbeState?
    @State private var storageError: String?
    @State private var draftTitle = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("原生安装验证") {
                    Text("SwiftUI 已运行")
                    LabeledContent("版本", value: "0.0.2 · 构建 \(build)")
                    Text("源码 ID：org.todowallpaper.nativeinstallprobe")
                    Text("实际 ID：\(Bundle.main.bundleIdentifier ?? "未知")")
                        .textSelection(.enabled)
                }
                Section("保存与覆盖更新验证") {
                    Text("计数：\(counter)")
                    Button("计数 +1") { if counter < Int.max { counter += 1 } }
                    Text("退出重开及同标识覆盖安装后，核对计数是否保留。")
                }
                Section("共享待办 · App Groups") {
                    if let shared {
                        Text(shared.title)
                        LabeledContent("状态", value: shared.isCompleted ? "已完成" : "未完成")
                        Button(shared.isCompleted ? "恢复待办" : "完成待办") {
                            mutate { try SharedProbeStore().setCompleted(!shared.isCompleted, source: "app") }
                        }
                        TextField("测试待办内容", text: $draftTitle)
                        Button("保存待办文字") {
                            mutate { try SharedProbeStore().rename(draftTitle) }
                        }
                        LabeledContent("共享修订", value: String(shared.revision))
                        LabeledContent("最后写入", value: shared.lastWriter)
                        LabeledContent("Widget 操作次数", value: String(shared.widgetActions))
                        Text("共享存储 ID：\(shared.storeID)")
                            .font(.caption).textSelection(.enabled)
                    }
                    if let storageError {
                        Text("共享容器不可用：\(storageError)").foregroundStyle(.red)
                        Text("这通常需要核对主 App 与扩展的签名权限；没有退回到各自本地存储。")
                            .font(.caption)
                    }
                    Button("重新读取共享数据") { loadShared() }
                }
                Section("Widget 验证") {
                    Text("主屏幕添加“原生能力验证”小组件。点击任务圆圈，应在主屏幕直接完成或恢复。")
                    Text("App Group：\(SharedProbeStore.groupID)").font(.caption).textSelection(.enabled)
                    Button("请求刷新小组件") {
                        loadShared()
                        WidgetCenter.shared.reloadTimelines(ofKind: ProbeConstants.widgetKind)
                    }
                    Text("刷新由系统调度。返回 App 时会重新读取共享文件；主屏幕操作是否唤起 App 需实机核对。")
                        .font(.caption)
                }
            }
            .navigationTitle("原生安装测试")
            .onAppear { loadShared() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { loadShared() }
            }
        }
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知"
    }

    private func loadShared() {
        do {
            let value = try SharedProbeStore().read()
            shared = value
            draftTitle = value.title
            storageError = nil
        } catch {
            shared = nil
            storageError = error.localizedDescription
        }
    }

    private func mutate(_ operation: () throws -> SharedProbeState) {
        do {
            let value = try operation()
            shared = value
            draftTitle = value.title
            storageError = nil
            WidgetCenter.shared.reloadTimelines(ofKind: ProbeConstants.widgetKind)
        } catch {
            storageError = error.localizedDescription
        }
    }
}
