import Foundation

// MARK: - Errors

enum SlideshowError: LocalizedError {
    case noImages
    case invalidTransitionDuration
    case unreadableImage(URL)
    case ffmpegNotFound
    case ffmpegFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noImages:
            return "Add at least one image."
        case .invalidTransitionDuration:
            return "The transition must be longer than zero and shorter than the image duration."
        case .unreadableImage(let url):
            return "Could not read image \(url.lastPathComponent)."
        case .ffmpegNotFound:
            return "FFmpeg was not found. Bundle it with the app or install it with Homebrew."
        case .ffmpegFailed(let log):
            return log.isEmpty ? "FFmpeg failed without an error message." : "FFmpeg failed: \(log)"
        case .cancelled:
            return "Export cancelled."
        }
    }
}

// MARK: - Plan

struct ExportPlan {
    /// Images already converted to PNG by `ImageNormalizer`, in slideshow order.
    var imageFiles: [URL]
    var settings: SlideshowSettings
    var audio: AudioTrackSettings
    var outputURL: URL
}

// MARK: - Builder

/// Turns a slideshow description into FFmpeg arguments.
///
/// Timeline maths (N images, each shown for `d` seconds, transition `t` seconds):
/// - Each still is fed in for `d + t` seconds so it can overlap its neighbour.
/// - Transition k (1-based) starts at `k * d`.
/// - Total length is `N * d + t` (or `N * d` for hard cuts).
enum FFmpegCommandBuilder {

    static func usesTransitions(_ settings: SlideshowSettings, imageCount: Int) -> Bool {
        settings.transition != .cut && imageCount > 1
    }

    static func totalDuration(imageCount: Int, settings s: SlideshowSettings) -> Double {
        let n = Double(imageCount)
        guard usesTransitions(s, imageCount: imageCount) else { return n * s.imageDuration }
        return n * s.imageDuration + s.transitionDuration
    }

    static func validate(_ s: SlideshowSettings, imageCount: Int) throws {
        guard imageCount > 0 else { throw SlideshowError.noImages }
        guard s.imageDuration > 0 else { throw SlideshowError.invalidTransitionDuration }
        if usesTransitions(s, imageCount: imageCount) {
            guard s.transitionDuration > 0, s.transitionDuration < s.imageDuration else {
                throw SlideshowError.invalidTransitionDuration
            }
        }
    }

    static func arguments(for plan: ExportPlan) throws -> [String] {
        let s = plan.settings
        let n = plan.imageFiles.count
        try validate(s, imageCount: n)

        let transitions = usesTransitions(s, imageCount: n)
        let total = totalDuration(imageCount: n, settings: s)
        let clipLength = s.imageDuration + (transitions ? s.transitionDuration : 0)
        let (width, height) = s.resolution.size
        let fps = s.frameRate

        var args = ["-hide_banner", "-loglevel", "error", "-y"]

        // Inputs: one looping still per image, then the optional music track.
        for file in plan.imageFiles {
            args += ["-loop", "1", "-framerate", "\(fps)", "-t", f(clipLength), "-i", file.path]
        }
        let audioIndex: Int? = plan.audio.url == nil ? nil : n
        if let music = plan.audio.url {
            if plan.audio.loop { args += ["-stream_loop", "-1"] }
            args += ["-i", music.path]
        }

        // Video graph: normalise every still, then join them.
        var graph: [String] = []
        for i in 0..<n {
            let fit = fitFilter(s.fitMode, width: width, height: height)
            graph.append("[\(i):v]\(fit),fps=\(fps),setsar=1,format=yuv420p,settb=AVTB,setpts=PTS-STARTPTS[v\(i)]")
        }

        let videoLabel: String
        if n == 1 {
            videoLabel = "v0"
        } else if transitions, let name = s.transition.xfadeName {
            var previous = "v0"
            for k in 1..<n {
                let out = (k == n - 1) ? "vout" : "x\(k)"
                graph.append("[\(previous)][v\(k)]xfade=transition=\(name):duration=\(f(s.transitionDuration)):offset=\(f(Double(k) * s.imageDuration))[\(out)]")
                previous = out
            }
            videoLabel = "vout"
        } else {
            let inputs = (0..<n).map { "[v\($0)]" }.joined()
            graph.append("\(inputs)concat=n=\(n):v=1:a=0[vout]")
            videoLabel = "vout"
        }

        // Audio: volume, fade-out, pad with silence, then trim to the video length.
        var audioLabel: String?
        if let index = audioIndex {
            var filters = ["volume=\(f(plan.audio.volume))"]
            let fade = min(max(plan.audio.fadeOutSeconds, 0), total)
            if fade > 0 {
                filters.append("afade=t=out:st=\(f(total - fade)):d=\(f(fade))")
            }
            filters += ["apad", "atrim=0:\(f(total))", "asetpts=PTS-STARTPTS"]
            graph.append("[\(index):a]" + filters.joined(separator: ",") + "[aout]")
            audioLabel = "aout"
        }

        args += ["-filter_complex", graph.joined(separator: ";")]
        args += ["-map", "[\(videoLabel)]"]
        if audioLabel != nil { args += ["-map", "[aout]"] }

        args += videoEncoderArguments(s)
        args += ["-pix_fmt", "yuv420p", "-r", "\(fps)"]
        if audioLabel != nil { args += ["-c:a", "aac", "-b:a", "192k"] }
        args += [
            "-t", f(total),
            "-movflags", "+faststart",
            "-progress", "pipe:1", "-nostats",
            plan.outputURL.path
        ]
        return args
    }

    // MARK: Helpers

    static func fitFilter(_ mode: FitMode, width: Int, height: Int) -> String {
        switch mode {
        case .fit:
            return "scale=\(width):\(height):force_original_aspect_ratio=decrease,pad=\(width):\(height):(ow-iw)/2:(oh-ih)/2:color=black"
        case .fill:
            return "scale=\(width):\(height):force_original_aspect_ratio=increase,crop=\(width):\(height)"
        case .stretch:
            return "scale=\(width):\(height)"
        }
    }

    /// Uses the hardware encoder on macOS when enabled; falls back to software x264/x265.
    static func videoEncoderArguments(_ s: SlideshowSettings) -> [String] {
        switch (s.codec, s.useHardwareEncoder) {
        case (.h264, true):
            return ["-c:v", "h264_videotoolbox", "-q:v", "\(s.quality.videoToolboxQuality)", "-allow_sw", "1"]
        case (.h264, false):
            return ["-c:v", "libx264", "-preset", "medium", "-crf", "\(s.quality.x264CRF)"]
        case (.hevc, true):
            return ["-c:v", "hevc_videotoolbox", "-q:v", "\(s.quality.videoToolboxQuality)", "-allow_sw", "1", "-tag:v", "hvc1"]
        case (.hevc, false):
            return ["-c:v", "libx265", "-crf", "\(s.quality.x265CRF)", "-tag:v", "hvc1"]
        }
    }

    private static func f(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
