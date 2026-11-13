import Foundation
import ImageIO
import AppKit

/// Converts every source image to an upright PNG in a work directory.
///
/// Doing this in ImageIO means HEIC, WebP and TIFF work regardless of the FFmpeg build,
/// and EXIF rotation from phone photos is applied before the frames reach FFmpeg.
enum ImageNormalizer {

    static func prepare(urls: [URL], into directory: URL) throws -> [URL] {
        var result: [URL] = []
        for (index, source) in urls.enumerated() {
            let name = String(format: "frame_%05d.png", index)
            let destination = directory.appendingPathComponent(name)
            try convertToPNG(source: source, destination: destination)
            result.append(destination)
        }
        return result
    }

    private static func convertToPNG(source: URL, destination: URL) throws {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else {
            throw SlideshowError.unreadableImage(source)
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 1
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 1

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // applies EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: max(width, height)
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary),
              let output = CGImageDestinationCreateWithURL(destination as CFURL, "public.png" as CFString, 1, nil)
        else {
            throw SlideshowError.unreadableImage(source)
        }

        CGImageDestinationAddImage(output, image, nil)
        guard CGImageDestinationFinalize(output) else {
            throw SlideshowError.unreadableImage(source)
        }
    }
}

/// Small, fast thumbnails for the image list.
enum Thumbnailer {
    static func image(for url: URL, maxSide: Int = 160) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: .zero)
    }
}

enum FileInfo {
    static func creationDate(of url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.creationDateKey])
        return values?.creationDate ?? .distantPast
    }
}
