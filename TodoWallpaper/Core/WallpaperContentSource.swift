// Target Membership：App + Widget；纯数据适配，不写入待办仓库。
import Foundation

enum WallpaperContentSource {
    case todo([TodoItem]), lianxin(LianxinPublication)
    var items: [TodoItem] {
        switch self {
        case .todo(let items): return items
        case .lianxin(let content):
            return [TodoItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
                title: content.shareText, marker: TodoMarker(kind: .none), isCompleted: false,
                createdAt: .distantPast, updatedAt: .distantPast)]
        }
    }
}
extension LianxinPublication {
    var shareText: String { text + "\n—— " + idol + " · " + contentLabel }
}
