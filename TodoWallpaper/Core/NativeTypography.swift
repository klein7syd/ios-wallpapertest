import Foundation
import CoreText
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

enum NativeTypography {
    static func font(family: WallpaperFont, weight: WallpaperWeight, size: CGFloat) -> CTFont {
        let native: CTFont
        #if canImport(UIKit)
        let w = UIFont.Weight(rawValue: CGFloat(weight.trait))
        let base = family == .monospaced ? UIFont.monospacedSystemFont(ofSize: size, weight: w) : UIFont.systemFont(ofSize: size, weight: w)
        if family == .serif, let descriptor = base.fontDescriptor.withDesign(.serif) {
            native = UIFont(descriptor: descriptor, size: size) as CTFont
        } else { native = base as CTFont }
        #else
        let w = NSFont.Weight(rawValue: CGFloat(weight.trait))
        let base = family == .monospaced ? NSFont.monospacedSystemFont(ofSize: size, weight: w) : NSFont.systemFont(ofSize: size, weight: w)
        if family == .serif, let descriptor = base.fontDescriptor.withDesign(.serif), let font = NSFont(descriptor: descriptor, size: size) {
            native = font as CTFont
        } else { native = base as CTFont }
        #endif
        // Named concrete CJK fallback weights prevent a Latin-only weight change.
        // PingFang has no separate bold face: bold reasonably falls back to semibold.
        guard family != .serif else { return native }
        let suffix: String
        switch weight { case .light: suffix = "Light"; case .regular: suffix = "Regular"; case .medium: suffix = "Medium"; case .semibold, .bold: suffix = "Semibold" }
        let cjk = CTFontCreateWithName(("PingFangSC-" + suffix) as CFString, size, nil)
        var cascade = [CTFontCopyFontDescriptor(cjk)]
        if let existing = CTFontCopyAttribute(native, kCTFontCascadeListAttribute) as? [CTFontDescriptor] { cascade += existing }
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(native), [kCTFontCascadeListAttribute: cascade] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }
}
