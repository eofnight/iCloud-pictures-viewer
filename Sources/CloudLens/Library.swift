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
    private var root: URL?
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
        loadTask?.cancel()
        if scoped { root?.stopAccessingSecurityScopedResource() }
        root = url; scoped = url.startAccessingSecurityScopedResource()
        if remember, let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) { UserDefaults.standard.set(data, forKey: "folderBookmark") }
        browse(url)
    }
    func browse(_ url: URL) {
        loadTask?.cancel(); busy = false; folder = url; selected = nil; image = nil; original = nil
        do {
            entries = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .contentTypeKey], options: [.skipsHiddenFiles]).compactMap { item in
                let v = try item.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
                guard v.isDirectory == true || v.contentType?.conforms(to: .image) == true else { return nil }
                return Entry(url: item, isDirectory: v.isDirectory == true)
            }.sorted { a, b in a.isDirectory != b.isDirectory ? a.isDirectory : a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending }
        } catch { message = error.localizedDescription }
    }
    var canGoUp: Bool { folder != nil && folder != root }
    func up() { if canGoUp, let folder { browse(folder.deletingLastPathComponent()) } }
    func select(_ entry: Entry) {
        if entry.isDirectory { browse(entry.url); return }
        loadTask?.cancel(); selected = entry.url; image = nil; original = nil; busy = true
        loadTask = Task {
            do {
                let cloud = try entry.url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
                if cloud.isUbiquitousItem == true && cloud.ubiquitousItemDownloadingStatus == .notDownloaded {
                    try FileManager.default.startDownloadingUbiquitousItem(at: entry.url)
                    for _ in 0..<120 {
                        try Task.checkCancellation()
                        let v = try entry.url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                        if v.ubiquitousItemDownloadingStatus != .notDownloaded { break }
                        try await Task.sleep(for: .seconds(1))
                    }
                }
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
    func clearCache() { Task { do { try await ThumbnailCache.shared.clear(); cacheEpoch = UUID(); cacheLabel = "快取已清除" } catch { message = error.localizedDescription } } }
    func cacheSize() { Task { let bytes = await ThumbnailCache.shared.size(); cacheLabel = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) } }
}
