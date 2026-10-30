import Foundation

// Target Membership：App + Widget；纯值请求与缓存键也由 macOS 原生检查执行。
struct PhotoAnalysisRequest: Codable, Equatable, Sendable {
    let photoName: String
    let crop: PhotoCrop
    let opacity: Double
    let darkBackground: Bool
    let canvasAspect: Double

    init(photoName: String, crop: PhotoCrop = PhotoCrop(), opacity: Double = 1,
         darkBackground: Bool = false, canvasAspect: Double = 1) {
        self.photoName = photoName; self.crop = crop; self.opacity = opacity
        self.darkBackground = opacity == 1 ? false : darkBackground
        self.canvasAspect = canvasAspect
    }
    func validate() throws {
        guard WidgetPhotoReference.isValid(photoName), opacity.isFinite, (0...1).contains(opacity),
              canvasAspect.isFinite, canvasAspect > 0, canvasAspect <= 100 else { throw AppearanceError.invalidStyle }
        try crop.validate()
    }
    var cacheID: String {
        let values = [crop.zoom, crop.panX, crop.panY, opacity, canvasAspect]
            .map { String(($0 == 0 ? 0.0 : $0).bitPattern, radix: 16) }.joined(separator: "-")
        return photoName + "." + values + (opacity < 1 && darkBackground ? ".dark" : ".light")
    }
}

extension WidgetAppearance {
    func analysisRequest(photoName: String, canvasAspect: Double, darkBackground: Bool) -> PhotoAnalysisRequest {
        PhotoAnalysisRequest(photoName: photoName, crop: photoCrop, opacity: photoOpacity,
            darkBackground: darkBackground, canvasAspect: canvasAspect)
    }
}
