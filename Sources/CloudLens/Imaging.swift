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
    private let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("CloudLens/Thumbnails", isDirectory: true)
        func clear() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    func size() -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
    func thumbnail(_ url: URL) -> NSImage? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let signature = "\(url.path)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(values?.fileSize ?? 0)"
        let key = SHA256.hash(data: Data(signature.utf8)).map { String(format: "%02x", $0) }.joined()
        let target = directory.appendingPathComponent(key).appendingPathExtension("jpg")
        if let cached = NSImage(contentsOf: target) { return cached }
        // Do not download entire cloud libraries merely to fill the grid.
        let cloud = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if cloud?.isUbiquitousItem == true && cloud?.ubiquitousItemDownloadingStatus == .notDownloaded { return nil }
        var error: NSError?
        var result: NSImage?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { coordinated in
            guard let source = CGImageSourceCreateWithURL(coordinated as CFURL, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 320] as CFDictionary) else { return }
            let bitmap = NSBitmapImageRep(cgImage: cg)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])?.write(to: target, options: .atomic)
            result = NSImage(cgImage: cg, size: .zero)
        }
        return result
    }
}
