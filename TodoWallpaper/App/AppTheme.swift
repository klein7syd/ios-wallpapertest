// Target Membership：仅App。界面主题不写入小组件与壁纸导出设置。
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark, blueDots
    static let key = "app.interfaceTheme"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        case .blueDots: return "白底蓝色波点"
        }
    }
    var scheme: ColorScheme? {
        switch self { case .system: return nil; case .dark: return .dark; default: return .light }
    }
}
struct AppThemeBackground: View {
    @AppStorage(AppTheme.key) private var theme = AppTheme.system.rawValue
    var body: some View {
        if theme == AppTheme.blueDots.rawValue {
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                for row in 0...Int(size.height / 28) {
                    for column in 0...Int(size.width / 28) {
                        let x = CGFloat(column) * 28 + (row.isMultiple(of: 2) ? 7 : 21)
                        let rect = CGRect(x: x, y: CGFloat(row) * 28 + 7, width: 4, height: 4)
                        context.fill(Path(ellipseIn: rect), with: .color(.blue.opacity(0.18)))
                    }
                }
            }.accessibilityHidden(true).allowsHitTesting(false).ignoresSafeArea()
        } else {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        }
    }
}
