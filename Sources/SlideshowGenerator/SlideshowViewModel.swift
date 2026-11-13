import Foundation
import SwiftUI
import AppKit

enum ExportStatus: Equatable {
    case idle
    case preparing
    case running(progress: Double, eta: TimeInterval?)
    case finished(URL)
    case failed(String)
    case cancelled

    var isBusy: Bool {
        switch self {
        case .preparing, .running: return true
        default: return false
        }
    }
}

@MainActor
final class SlideshowViewModel: ObservableObject {
    @Published var images: [SlideImage] = []
    @Published var selection = Set<SlideImage.ID>()
    @Published var settings = SlideshowSettings()
    @Published var audio = AudioTrackSettings()
    @Published var status: ExportStatus = .idle
    @Published var openFolderWhenDone = true

    private let exporter = FFmpegExporter()

    var estimatedDuration: Double {
        FFmpegCommandBuilder.totalDuration(imageCount: images.count, settings: settings)
    }

    /// A user-facing problem with the current settings, or nil when the export can run.
    var validationMessage: String? {
        guard !images.isEmpty else { return nil }
        do {
            try FFmpegCommandBuilder.validate(settings, imageCount: images.count)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Images

    func addImages(_ urls: [URL]) {
        var seen = Set(images.map(\.url))
        for url in urls where FileTypes.isImage(url) && !seen.contains(url) {
            seen.insert(url)
            images.append(SlideImage(url: url, creationDate: FileInfo.creationDate(of: url)))
        }
    }

    func removeSelected() {
        images.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }

    func delete(at offsets: IndexSet) {
        images.remove(atOffsets: offsets)
    }

    func move(from offsets: IndexSet, to destination: Int) {
        images.move(fromOffsets: offsets, toOffset: destination)
    }

    func sort(by key: SortKey) {
        switch key {
        case .name:
            images.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .date:
            images.sort { $0.creationDate < $1.creationDate }
        }
    }

    // MARK: Music

    func setAudio(_ url: URL) {
        guard FileTypes.isAudio(url) else { return }
        audio.url = url
    }

    // MARK: Export

    func export(to outputURL: URL) {
        guard !images.isEmpty, !status.isBusy else { return }
        guard let ffmpeg = FFmpegLocator.executableURL() else {
            status = .failed(SlideshowError.ffmpegNotFound.localizedDescription)
            return
        }

        status = .preparing
        let sources = images.map(\.url)
        let settings = self.settings
        let audio = self.audio
        let total = estimatedDuration
        let openWhenDone = openFolderWhenDone

        Task {
            let workDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("SlideshowGenerator-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

                let frames = try await Task.detached(priority: .userInitiated) {
                    try ImageNormalizer.prepare(urls: sources, into: workDir)
                }.value

                let plan = ExportPlan(imageFiles: frames, settings: settings, audio: audio, outputURL: outputURL)
                let arguments = try FFmpegCommandBuilder.arguments(for: plan)

                self.status = .running(progress: 0, eta: nil)
                self.exporter.start(
                    executable: ffmpeg,
                    arguments: arguments,
                    outputURL: outputURL,
                    totalDuration: total,
                    progress: { fraction, eta in
                        Task { @MainActor in self.status = .running(progress: fraction, eta: eta) }
                    },
                    completion: { result in
                        Task { @MainActor in
                            try? FileManager.default.removeItem(at: workDir)
                            self.finish(result, openWhenDone: openWhenDone)
                        }
                    }
                )
            } catch {
                try? FileManager.default.removeItem(at: workDir)
                status = .failed(error.localizedDescription)
            }
        }
    }

    func cancelExport() {
        exporter.cancel()
    }

    private func finish(_ result: Result<URL, SlideshowError>, openWhenDone: Bool) {
        switch result {
        case .success(let url):
            status = .finished(url)
            if openWhenDone {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        case .failure(.cancelled):
            status = .cancelled
        case .failure(let error):
            status = .failed(error.localizedDescription)
        }
    }
}
