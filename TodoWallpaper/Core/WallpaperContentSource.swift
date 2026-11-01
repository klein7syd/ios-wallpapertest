// Target Membership：App + Widget；纯数据适配，不写入待办仓库。
import Foundation

enum WallpaperContentSource {
    case todo([TodoItem]), lianxin(LianxinPublication)
    var items: [TodoItem] {
        switch self {
        case .todo(let items): return items
        case .lianxin(let content):
            return LianxinPresentation.items(content, style: LianxinDisplayStyle())
        }
    }
}
extension LianxinPublication {
    var shareText: String { resolvedLines.map { $0.text + ($0.translation.flatMap { $0.isEmpty ? nil : "\n" + $0 } ?? "") }.joined(separator: "\n\n") + "\n—— " + idol + (signatureSubtitle.map { " · " + $0 } ?? "") + " · " + contentLabel }
}
