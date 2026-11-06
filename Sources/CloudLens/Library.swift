import ImageIO

import SwiftUI
import UniformTypeIdentifiers

struct Entry: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    var id: URL { url }
}
@MainActor final class Library: ObservableObject {
    @Published var folder: URL?
    @Published var entries: [Entry] = []
    @Published var selected: URL?
    @Published var image: NSImage?
    @Published var original: NSImage?
    @Published var busy = false
    @Published var message: String?
    @Published var cacheLabel = ""
    @Published var cacheEpoch = UUID()
    @Published private(set) var root: URL?
    @Published var albums: [Entry] = []
    @Published var cacheProgress = ""
    @Published var cachedURLs: Set<URL> = []
    @Published var isPrefetching = false
    private var prefetchTask: Task<Void, Never>?
    private var prefetchID = UUID()
    private var scoped = false
    private var loadTask: Task<Void, Never>?
    init() {
        guard let data = UserDefaults.standard.data(forKey: "folderBookmark") else { return }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale) { open(url, remember: stale) }
    }
    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "開啟資料夾"; panel.canDownloadUbiquitousContents = true
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }
    func open(_ url: URL, remember: Bool = true) {
        stopPrefetch()
        loadTask?.cancel()
        if scoped { root?.stopAccessingSecurityScopedResource() }
        root = url; scoped = url.startAccessingSecurityScopedResource()
        if remember, let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) { UserDefaults.standard.set(data, forKey: "folderBookmark") }
        albums = ((try? Self.readEntries(url)) ?? []).filter { $0.isDirectory }
        browse(url)
    }
    func closePreview() {
        loadTask?.cancel(); selected = nil; image = nil; original = nil; busy = false
    }
    nonisolated static func readEntries(_ url: URL) throws -> [Entry] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .contentTypeKey], options: [.skipsHiddenFiles]).compactMap { item in
            let v = try item.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey, .isSymbolicLinkKey])
            guard v.isSymbolicLink != true else { return nil }
            guard v.isDirectory == true || v.contentType?.conforms(to: .image) == true else { return nil }
            return Entry(url: item, isDirectory: v.isDirectory == true)
        }.sorted { a, b in a.isDirectory != b.isDirectory ? a.isDirectory : a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending }
    }
    func browse(_ url: URL) {
        stopPrefetch()
        entries = []
        loadTask?.cancel(); busy = false; folder = url; selected = nil; image = nil; original = nil
        do {
            entries = try Self.readEntries(url)
            if url == root { albums = entries.filter { $0.isDirectory } }
            prefetchPhotos()
        } catch { message = error.localizedDescription }
    }
    var canGoUp: Bool { folder != nil && folder != root }
    func up() { if canGoUp, let folder { browse(folder.deletingLastPathComponent()) } }
    func select(_ entry: Entry) {
        if entry.isDirectory { browse(entry.url); return }
        loadTask?.cancel(); selected = entry.url; image = nil; original = nil; busy = true
        loadTask = Task {
            do {
                if let preview = await ThumbnailCache.shared.cachedPreview(entry.url) {
                    try Task.checkCancellation()
                    image = preview
                }
                try await CloudFiles.ensureDownloaded(entry.url)
                let loaded = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                    var result: NSImage?
                    var error: NSError?
                    NSFileCoordinator().coordinate(readingItemAt: entry.url, options: [], error: &error) { url in
                        if let source = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 16000] as CFDictionary) { result = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }
                    }
                    return result
                }.value
                try Task.checkCancellation()
                guard selected == entry.url else { return }
                image = loaded; original = loaded; busy = false
                if loaded == nil { message = "無法讀取圖片，請確認檔案已從 iCloud 下載且格式受支援。" }
            } catch is CancellationError { } catch { busy = false; message = error.localizedDescription }
        }
    }
    func move(_ delta: Int) {
        let photos = entries.filter { !$0.isDirectory }
        guard !photos.isEmpty else { return }
        let index = photos.firstIndex { $0.url == selected } ?? 0
        select(photos[max(0, min(photos.count-1, index+delta))])
    }
    func save() {
        guard let image else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = (selected?.deletingPathExtension().lastPathComponent ?? "Image") + "-edited.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            var coordinationError: NSError?; var writeError: Error?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
                do { try data.write(to: target, options: .atomic) } catch { writeError = error }
            }
            if let error = writeError ?? coordinationError { throw error }
        } catch { message = error.localizedDescription }
    }
    func stopPrefetch() {
        prefetchID = UUID()
        prefetchTask?.cancel(); prefetchTask = nil
        isPrefetching = false; cacheProgress = ""
    }
    func prefetchPhotos() {
        let photos = entries.filter { !$0.isDirectory }
        guard !photos.isEmpty else { return }
        let id = UUID(); prefetchID = id
        isPrefetching = true
        cacheProgress = "預覽快取 0 / \(photos.count)"
        prefetchTask = Task {
            var failed = 0
            for (index, photo) in photos.enumerated() {
                do {
                    try Task.checkCancellation()
                    let ready = try await ThumbnailCache.shared.prepare(photo.url)
                    try Task.checkCancellation()
                    guard prefetchID == id else { return }
                    if ready { cachedURLs.insert(photo.url) } else { failed += 1 }
                } catch is CancellationError { return }
                catch {
                    guard prefetchID == id, !Task.isCancelled else { return }
                    failed += 1
                }
                cacheProgress = "預覽快取 \(index + 1) / \(photos.count)" + (failed > 0 ? " · \(failed) 張失敗" : "")
            }
            guard prefetchID == id else { return }
            isPrefetching = false
            cacheProgress = failed == 0 ? "\(photos.count) 張預覽已快取" : "快取完成 · \(failed) 張失敗，可重新整理重試"
        }
    }
    func clearCache() {
        stopPrefetch()
        Task {
            do {
                try await ThumbnailCache.shared.clear()
                cachedURLs.removeAll(); cacheEpoch = UUID(); cacheLabel = "快取已清除"
            } catch { message = error.localizedDescription }
        }
    }
    func cacheSize() { Task { let bytes = await ThumbnailCache.shared.size(); cacheLabel = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) } }
}
