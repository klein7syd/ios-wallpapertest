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
// PhotoKit 可提前或多次回调；取消与 requestID 返回的竞态必须只恢复一次 continuation。
private final class AlbumImageRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UIImage, Error>?
    private var requestID: PHImageRequestID?
    private var finished = false
    private var cancelled = false
    func image(_ asset: PHAsset) async throws -> UIImage {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { next in
                lock.lock()
                if cancelled { lock.unlock(); next.resume(throwing: CancellationError()); return }
                continuation = next; lock.unlock()
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat; options.resizeMode = .exact
                options.isNetworkAccessAllowed = true; options.version = .current
                let id = PHImageManager.default().requestImage(for: asset,
                    targetSize: CGSize(width: 1536, height: 1536), contentMode: .aspectFit, options: options) { [self] image, info in
                    if (info?[PHImageCancelledKey] as? Bool) == true { complete(.failure(CancellationError())); return }
                    if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                    if let image { complete(.success(image)) }
                    else { complete(.failure((info?[PHImageErrorKey] as? Error) ?? AlbumError.unreadable)) }
                }
                lock.lock(); requestID = id; let shouldCancel = cancelled; lock.unlock()
                if shouldCancel { PHImageManager.default().cancelImageRequest(id) }
            }
        } onCancel: { self.cancel() }
    }
    private func complete(_ result: Result<UIImage, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true; let next = continuation; continuation = nil; lock.unlock()
        next?.resume(with: result)
    }
    private func cancel() {
        lock.lock(); cancelled = true; let id = requestID; lock.unlock()
        complete(.failure(CancellationError()))
        if let id { PHImageManager.default().cancelImageRequest(id) }
    }
}
private struct PreparedAlbum: Sendable {
    let transactionID: UUID
    let rotation: WidgetAlbumRotation
    let skipped: Int
}
private actor AlbumReader {
    private let photos = WidgetPhotoStore.shared
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
    func prepare(_ album: PhotoAlbumRow, progress: @escaping @Sendable (Int, Int) -> Void) async throws -> PreparedAlbum {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized,
              let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [album.id], options: nil).firstObject else { throw AlbumError.permission }
        let options = PHFetchOptions(); options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 60
        let assets = PHAsset.fetchAssets(in: collection, options: options)
        guard assets.count > 0 else { throw AlbumError.missing }
        let transaction = try await photos.beginBatch()
        var state = PhotoImportProgress(total: assets.count)
        do {
            for index in 0..<assets.count {
                try Task.checkCancellation()
                do {
                    let name = try await importAsset(assets.object(at: index), transaction: transaction)
                    state.succeeded(name)
                } catch is CancellationError { throw CancellationError() }
                catch { state.skipped() }
                progress(index + 1, assets.count)
            }
            try Task.checkCancellation()
            try state.validateResult()
            return PreparedAlbum(transactionID: transaction,
                rotation: WidgetAlbumRotation(title: album.title, photos: state.names, anchor: .now), skipped: state.failed)
        } catch {
            await photos.rollbackBatch(transaction)
            throw error
        }
    }
    private func importAsset(_ asset: PHAsset, transaction: UUID) async throws -> String {
        let image = try await AlbumImageRequest().image(asset)
        try Task.checkCancellation()
        let data = try autoreleasepool {
            guard let data = image.jpegData(compressionQuality: 0.95) else { throw AlbumError.unreadable }
            return data
        }
        return try await photos.importPhoto(data, transactionID: transaction)
    }
    func commit(_ album: PreparedAlbum) async throws { try await photos.commitBatch(album.transactionID) }
    func rollback(_ album: PreparedAlbum) async { await photos.rollbackBatch(album.transactionID) }
    }
}
struct WidgetAlbumPicker: View {
    let onSelect: (WidgetAlbumRotation, Int) throws -> Void
    let onCommitted: () -> Void
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
            var prepared: PreparedAlbum?
            var published = false
            do {
                let result = try await reader.prepare(album) { current, total in
                    Task { @MainActor in progress = "\(current) / \(total) 张" }
                }
                prepared = result
                try Task.checkCancellation()
                try onSelect(result.rotation, result.skipped)
                // 外观已原子落盘后，即使页面退出也不得回滚其引用的照片。
                published = true
                try await reader.commit(result)
                onCommitted(); dismiss()
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
            if !published, let prepared { await reader.rollback(prepared) }
            preparing = false
        }
    }
}
