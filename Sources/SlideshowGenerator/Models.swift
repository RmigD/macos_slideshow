import Foundation

// MARK: - Supported file types

enum FileTypes {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "tif", "tiff", "heic", "heif"]
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "ogg"]

    static func isImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    static func isAudio(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }
}

// MARK: - Images

struct SlideImage: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let creationDate: Date

    var name: String { url.lastPathComponent }
}

enum SortKey {
    case name
    case date
}

// MARK: - Slideshow settings

enum FitMode: String, CaseIterable, Identifiable {
    case fit, fill, stretch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fit: return "Fit"
        case .fill: return "Fill"
        case .stretch: return "Stretch"
        }
    }
}

enum TransitionType: String, CaseIterable, Identifiable {
    case cut, fade, dissolve, slideLeft, slideRight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cut: return "None (cut)"
        case .fade: return "Fade"
        case .dissolve: return "Dissolve"
        case .slideLeft: return "Slide left"
        case .slideRight: return "Slide right"
        }
    }

    /// FFmpeg `xfade` transition name. `nil` means a hard cut, which uses `concat` instead.
    var xfadeName: String? {
        switch self {
        case .cut: return nil
        case .fade: return "fade"
        case .dissolve: return "dissolve"
        case .slideLeft: return "slideleft"
        case .slideRight: return "slideright"
        }
    }
}

enum Resolution: String, CaseIterable, Identifiable {
    case hd720, hd1080, uhd4k

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hd720: return "720p"
        case .hd1080: return "1080p"
        case .uhd4k: return "4K"
        }
    }

    var size: (width: Int, height: Int) {
        switch self {
        case .hd720: return (1280, 720)
        case .hd1080: return (1920, 1080)
        case .uhd4k: return (3840, 2160)
        }
    }
}

enum VideoCodec: String, CaseIterable, Identifiable {
    case h264, hevc

    var id: String { rawValue }

    var label: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC"
        }
    }
}

enum QualityPreset: String, CaseIterable, Identifiable {
    case high, balanced, small

    var id: String { rawValue }

    var label: String {
        switch self {
        case .high: return "High"
        case .balanced: return "Balanced"
        case .small: return "Small file"
        }
    }

    var x264CRF: Int {
        switch self {
        case .high: return 18
        case .balanced: return 23
        case .small: return 28
        }
    }

    var x265CRF: Int {
        switch self {
        case .high: return 22
        case .balanced: return 26
        case .small: return 30
        }
    }

    /// VideoToolbox `-q:v` value (1–100, higher is better quality).
    var videoToolboxQuality: Int {
        switch self {
        case .high: return 80
        case .balanced: return 60
        case .small: return 40
        }
    }
}

struct SlideshowSettings: Equatable {
    var imageDuration: Double = 4
    var transition: TransitionType = .fade
    var transitionDuration: Double = 1
    var fitMode: FitMode = .fit
    var resolution: Resolution = .hd1080
    var frameRate: Int = 30
    var codec: VideoCodec = .h264
    var quality: QualityPreset = .balanced
    var useHardwareEncoder = true
}

// MARK: - Music

struct AudioTrackSettings: Equatable {
    var url: URL?
    var volume: Double = 1.0
    var fadeOutSeconds: Double = 2.0
    var loop = false
}
