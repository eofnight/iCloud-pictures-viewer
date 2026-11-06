import AppKit
@main struct ImagingChecks {
    static func main() {
        let image = NSImage(size: NSSize(width: 120, height: 80), flipped: false) { rect in NSColor.red.setFill(); rect.fill(); return true }
        let rotated = ImageEdits.rotate(image)
        precondition(rotated.size == NSSize(width: 80, height: 120))
        precondition(ImageEdits.crop(image, normalized: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))?.size == NSSize(width: 60, height: 40))
        precondition(ImageEdits.crop(image, normalized: .zero) == nil)
        precondition(ImageEdits.crop(image, normalized: CGRect(x: -1, y: -1, width: 3, height: 3))?.size == image.size)
        precondition(rotated.tiffRepresentation != nil)
        print("All 5 imaging checks passed")
    }
}
