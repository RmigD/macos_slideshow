import Foundation

// MARK: - Locating FFmpeg

enum FFmpegLocator {
    /// Prefers the copy bundled inside the app, then common Homebrew install paths.
    static func executableURL() -> URL? {
        let fm = FileManager.default
        if let bundled = Bundle.main.url(forResource: "ffmpeg", withExtension: nil),
           fm.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        return ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
            .map { URL(fileURLWithPath: $0) }
            .first { fm.isExecutableFile(atPath: $0.path) }
    }
}

// MARK: - Running FFmpeg

/// Runs one FFmpeg encode, streams progress from `-progress pipe:1`, and supports cancellation.
/// Callbacks are delivered on the main queue.
final class FFmpegExporter {
    private var process: Process?
    private var wasCancelled = false
    private let stderrLock = NSLock()
    private var stderrData = Data()

    func start(executable: URL,
               arguments: [String],
               outputURL: URL,
               totalDuration: Double,
               progress: @escaping (_ fraction: Double, _ eta: TimeInterval?) -> Void,
               completion: @escaping (Result<URL, SlideshowError>) -> Void) {

        let proc = Process()
        proc.executableURL = executable
        proc.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardOutput = stdout
        proc.standardError = stderr

        process = proc
        wasCancelled = false
        stderrLock.lock(); stderrData = Data(); stderrLock.unlock()
        let startedAt = Date()

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("out_time_us=") {
                guard totalDuration > 0,
                      let micros = Double(line.dropFirst("out_time_us=".count)) else { continue }
                let fraction = min(max(micros / 1_000_000 / totalDuration, 0), 1)
                let elapsed = Date().timeIntervalSince(startedAt)
                let eta: TimeInterval? = fraction > 0.01 ? elapsed * (1 - fraction) / fraction : nil
                DispatchQueue.main.async { progress(fraction, eta) }
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { [self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stderrLock.lock(); stderrData.append(data); stderrLock.unlock()
        }

        proc.terminationHandler = { [self] finished in
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            let remaining = stderr.fileHandleForReading.readDataToEndOfFile()
            stderrLock.lock(); stderrData.append(remaining); let log = String(decoding: stderrData, as: UTF8.self); stderrLock.unlock()
            let cancelled = wasCancelled

            DispatchQueue.main.async {
                if cancelled {
                    try? FileManager.default.removeItem(at: outputURL)
                    completion(.failure(.cancelled))
                } else if finished.terminationStatus == 0 {
                    completion(.success(outputURL))
                } else {
                    completion(.failure(.ffmpegFailed(log.trimmingCharacters(in: .whitespacesAndNewlines))))
                }
            }
        }

        do {
            try proc.run()
        } catch {
            completion(.failure(.ffmpegFailed(error.localizedDescription)))
        }
    }

    func cancel() {
        wasCancelled = true
        process?.terminate()
    }
}
