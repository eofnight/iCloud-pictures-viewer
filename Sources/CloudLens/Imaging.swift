import AppKit
import ImageIO
import CryptoKit

struct ImageEdits {
    static func rotate(_ image: NSImage) -> NSImage {
        let size = NSSize(width: image.size.height, height: image.size.width)
        return NSImage(size: size, flipped: false) { _ in
            let transform = NSAffineTransform()
            transform.translateX(by: 0, yBy: size.height)
            transform.rotate(byDegrees: -90)
            transform.concat()
            image.draw(in: NSRect(origin: .zero, size: image.size))
            return true
        }
    }
    static func crop(_ image: NSImage, normalized rect: CGRect) -> NSImage? {
        let bounds = rect.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard bounds.width > 0.001, bounds.height > 0.001 else { return nil }
        let source = CGRect(x: bounds.minX * image.size.width, y: (1-bounds.maxY) * image.size.height, width: bounds.width * image.size.width, height: bounds.height * image.size.height)
        return NSImage(size: source.size, flipped: false) { _ in
            image.draw(in: CGRect(origin: .zero, size: source.size), from: source, operation: .copy, fraction: 1)
            return true
        }
    }
}

actor ThumbnailCache {
    static let shared = ThumbnailCache()
    private let directory: URL
    private let coordinateReads: Bool
    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("CloudLens/Thumbnails", isDirectory: true), coordinateReads: Bool = true) {
        self.directory = directory
        self.coordinateReads = coordinateReads
    }
    private var generation = 0
    func clear() throws {
        generation += 1
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    func size() -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
    private func target(_ url: URL, pixels: Int) -> URL {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let signature = "\(url.path)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(values?.fileSize ?? 0)|\(pixels)"
        let key = SHA256.hash(data: Data(signature.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key).appendingPathExtension("jpg")
    }
    func cachedPreview(_ url: URL) -> NSImage? { NSImage(contentsOf: target(url, pixels: 2048)) }
    func prepare(_ url: URL, includePreview: Bool = true) async throws -> Bool {
        let version = generation
        try await CloudFiles.ensureDownloaded(url)
        try Task.checkCancellation()
        guard version == generation else { throw CancellationError() }
        guard thumbnail(url) != nil else { return false }
        return !includePreview || render(url, pixels: 2048) != nil
    }
    func thumbnail(_ url: URL) -> NSImage? {
        render(url, pixels: 320)
    }
    private func render(_ url: URL, pixels: Int) -> NSImage? {
        let target = target(url, pixels: pixels)
        if let cached = NSImage(contentsOf: target) { return cached }
        let cloud = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if cloud?.isUbiquitousItem == true && cloud?.ubiquitousItemDownloadingStatus == .notDownloaded { return nil }
        var error: NSError?
        var result: NSImage?
        let read: (URL) -> Void = { coordinated in
            guard let source = CGImageSourceCreateWithURL(coordinated as CFURL, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: pixels] as CFDictionary) else { return }
            let bitmap = NSBitmapImageRep(cgImage: cg)
            do {
                try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
                guard let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return }
                try data.write(to: target, options: .atomic)
                result = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            } catch { result = nil }
        }
        if coordinateReads {
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error, byAccessor: read)
        } else {
            read(url)
        }
        return result
    }
}

enum CloudFiles {
    static func ensureDownloaded(_ url: URL) async throws {
        try Task.checkCancellation()
        var values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        guard values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus == .notDownloaded else { return }
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
        for _ in 0..<120 {
            try Task.checkCancellation()
            values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if values.ubiquitousItemDownloadingStatus == .current || values.ubiquitousItemDownloadingStatus == .downloaded { return }
            try await Task.sleep(for: .seconds(1))
        }
        throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "iCloud 下載逾時，請確認網路後重新整理。"])
    }
}
