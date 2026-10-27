import SwiftUI
import Photos
import UIKit

private struct PhotoAlbumRow: Identifiable, Sendable {
    let id: String
    let title: String
    let count: Int
}
private enum AlbumError: LocalizedError {
    case permission, missing, unreadable
    var errorDescription: String? {
        switch self {
        case .permission: return "选择相册需要照片的完整访问权限；有限访问仍可使用单张照片选择。"
        case .missing: return "相册没有可读取的照片，或已被删除。"
        case .unreadable: return "有照片暂时无法读取，请检查 iCloud 下载与网络后重试。"
        }
    }
}
private actor AlbumReader {
    private let photos = WidgetPhotoStore()
    func albums() async throws -> [PhotoAlbumRow] {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized else { throw AlbumError.permission }
        var seen = Set<String>(), result: [PhotoAlbumRow] = []
        let groups = [PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil),
            PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumFavorites, options: nil),
            PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)]
        let options = PHFetchOptions(); options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        for group in groups {
            for index in 0..<group.count {
                let collection = group.object(at: index)
                guard seen.insert(collection.localIdentifier).inserted else { continue }
                let count = PHAsset.fetchAssets(in: collection, options: options).count
                if count > 0 { result.append(PhotoAlbumRow(id: collection.localIdentifier,
                    title: String((collection.localizedTitle ?? "相册").prefix(100)), count: count)) }
            }
        }
        return result
    }
    func prepare(_ album: PhotoAlbumRow, progress: @escaping @Sendable (Int, Int) -> Void) async throws -> WidgetAlbumRotation {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized,
              let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [album.id], options: nil).firstObject else { throw AlbumError.permission }
        let options = PHFetchOptions(); options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 60
        let assets = PHAsset.fetchAssets(in: collection, options: options)
        guard assets.count > 0 else { throw AlbumError.missing }
        var names: [String] = []
        for index in 0..<assets.count {
            try Task.checkCancellation()
            let asset = assets.object(at: index)
            let data: Data = try await withCheckedThrowingContinuation { continuation in
                let request = PHImageRequestOptions(); request.deliveryMode = .highQualityFormat
                request.isNetworkAccessAllowed = true; request.version = .current
                PHImageManager.default().requestImageDataAndOrientation(for: asset, options: request) { data, _, _, info in
                    if let data { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: (info?[PHImageErrorKey] as? Error) ?? AlbumError.unreadable) }
                }
            }
            try Task.checkCancellation()
            names.append(try await photos.importPhoto(data))
            progress(index + 1, assets.count)
        }
        return WidgetAlbumRotation(title: album.title, photos: names, anchor: .now)
    }
}
struct WidgetAlbumPicker: View {
    let onSelect: (WidgetAlbumRotation) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [PhotoAlbumRow] = []
    @State private var error: String?
    @State private var loading = true
    @State private var preparing = false
    @State private var progress = ""
    @State private var task: Task<Void, Never>?
    private let reader = AlbumReader()
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if loading { ProgressView("正在读取相册…") }
                    if let error {
                        Text(error).foregroundStyle(.red)
                        Button("打开系统设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    }
                    ForEach(rows) { album in
                        Button { select(album) } label: {
                            HStack { Text(album.title); Spacer(); Text("\(album.count) 张").foregroundStyle(.secondary) }
                        }.disabled(preparing)
                    }
                } footer: {
                    Text("每个相册最多使用最近 60 张照片，仅在本机处理。按本地日期每日轮换；系统可能延后刷新。相册新增照片后，在这里重新选择以同步。")
                }
                if preparing { Section { ProgressView(progress) } }
            }
            .navigationTitle("每日换图相册").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { task?.cancel(); dismiss() } } }
            .task {
                do { rows = try await reader.albums() } catch { self.error = error.localizedDescription }
                loading = false
            }
            .onDisappear { task?.cancel() }
        }
    }
    private func select(_ album: PhotoAlbumRow) {
        preparing = true; error = nil; progress = "准备照片…"
        task = Task {
            do {
                let result = try await reader.prepare(album) { current, total in
                    Task { @MainActor in progress = "\(current) / \(total) 张" }
                }
                try Task.checkCancellation(); onSelect(result); dismiss()
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
            preparing = false
        }
    }
}
