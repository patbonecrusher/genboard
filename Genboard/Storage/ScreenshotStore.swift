import AppKit

/// Screenshots live as PNG files in Application Support; SwiftData stores only the file name.
enum ScreenshotStore {
    static let directory: URL = {
        let url = URL.applicationSupportDirectory.appending(path: "Genboard/Screenshots", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static let cache = NSCache<NSString, NSImage>()

    static func save(_ png: Data) -> String? {
        let name = UUID().uuidString + ".png"
        do {
            try png.write(to: directory.appending(path: name))
            return name
        } catch {
            return nil
        }
    }

    static func data(_ name: String) -> Data? {
        try? Data(contentsOf: directory.appending(path: name))
    }

    static func image(_ name: String) -> NSImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let image = NSImage(contentsOf: directory.appending(path: name)) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    static func delete(_ name: String) {
        cache.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: directory.appending(path: name))
    }
}

nonisolated enum ImageUtil {
    static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Downscales to the size Claude actually uses for vision, which also keeps token cost down.
    static func jpegForAPI(pngData: Data, maxDimension: CGFloat = 1568) -> Data? {
        guard let source = NSBitmapImageRep(data: pngData), let cgImage = source.cgImage else { return nil }
        let width = CGFloat(source.pixelsWide), height = CGFloat(source.pixelsHigh)
        let scale = min(1, maxDimension / max(width, height))
        let newWidth = Int(width * scale), newHeight = Int(height * scale)
        guard let context = CGContext(data: nil, width: newWidth, height: newHeight, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        guard let resized = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: resized).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
