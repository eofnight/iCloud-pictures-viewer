import AppKit
@main struct ImagingChecks {
    static func main() async throws {
        let image = NSImage(size: NSSize(width: 120, height: 80), flipped: false) { rect in NSColor.red.setFill(); rect.fill(); return true }
        let rotated = ImageEdits.rotate(image)
        precondition(rotated.size == NSSize(width: 80, height: 120))
        precondition(ImageEdits.crop(image, normalized: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))?.size == NSSize(width: 60, height: 40))
        precondition(ImageEdits.crop(image, normalized: .zero) == nil)
        precondition(ImageEdits.crop(image, normalized: CGRect(x: -1, y: -1, width: 3, height: 3))?.size == image.size)
        precondition(rotated.tiffRepresentation != nil)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let source = temporary.appendingPathComponent("photo.png")
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: source)
        let cache = ThumbnailCache(directory: temporary.appendingPathComponent("cache"), coordinateReads: false)
        let prepared = try await cache.prepare(source)
        precondition(prepared)
        let preview = await cache.cachedPreview(source)
        precondition(preview != nil)
        let contents = try FileManager.default.contentsOfDirectory(atPath: temporary.appendingPathComponent("cache").path)
        precondition(contents.count == 2)
        try await cache.clear()
        let size = await cache.size()
        precondition(size == 0)
        precondition(FileManager.default.fileExists(atPath: source.path))
        let invalid = temporary.appendingPathComponent("bad.png")
        try Data("invalid".utf8).write(to: invalid)
        let badResult = try await cache.prepare(invalid)
        precondition(!badResult)
        let task = Task { try await cache.prepare(source) }
        task.cancel()
        do { _ = try await task.value; preconditionFailure("Cancelled work must stop") }
        catch is CancellationError { }
        print("All 12 imaging and cache checks passed")
    }
}
