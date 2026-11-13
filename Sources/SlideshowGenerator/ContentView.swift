import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @StateObject private var model = SlideshowViewModel()
    @StateObject private var previewer = AudioPreviewer()
    @State private var showingImageImporter = false
    @State private var showingAudioImporter = false

    var body: some View {
        HSplitView {
            imagePane
                .frame(minWidth: 320, idealWidth: 380)
            settingsPane
                .frame(minWidth: 320, idealWidth: 360)
        }
        .frame(minWidth: 760, minHeight: 560)
        .fileImporter(isPresented: $showingImageImporter,
                      allowedContentTypes: [.image],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.addImages(urls) }
        }
        .fileImporter(isPresented: $showingAudioImporter,
                      allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { model.setAudio(url) }
        }
    }

    // MARK: Image pane

    private var imagePane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { showingImageImporter = true } label: {
                    Label("Add Images", systemImage: "plus")
                }
                Button { model.removeSelected() } label: {
                    Label("Remove", systemImage: "trash")
                }
                .disabled(model.selection.isEmpty)

                Menu("Sort") {
                    Button("By Filename") { model.sort(by: .name) }
                    Button("By Date") { model.sort(by: .date) }
                }
                .fixedSize()

                Spacer()
                Text("\(model.images.count) images")
                    .foregroundStyle(.secondary)
            }
            .padding([.horizontal, .top])

            List(selection: $model.selection) {
                ForEach(model.images) { image in
                    ImageRow(image: image)
                        .tag(image.id)
                }
                .onMove { model.move(from: $0, to: $1) }
                .onDelete { model.delete(at: $0) }
            }
            .overlay {
                if model.images.isEmpty {
                    ContentUnavailableView("Drop images here",
                                           systemImage: "photo.on.rectangle",
                                           description: Text("JPEG, PNG, WebP, TIFF or HEIC"))
                }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                loadFileURLs(from: providers) { urls in model.addImages(urls) }
                return true
            }
            .onDeleteCommand { model.removeSelected() }
        }
    }

    // MARK: Settings pane

    private var settingsPane: some View {
        Form {
            Section("Timing") {
                Stepper(value: $model.settings.imageDuration, in: 0.5...30, step: 0.5) {
                    Text("Image duration: \(String(format: "%.1f", model.settings.imageDuration)) s")
                }

                Picker("Transition", selection: $model.settings.transition) {
                    ForEach(TransitionType.allCases) { Text($0.label).tag($0) }
                }

                if model.settings.transition != .cut {
                    Stepper(value: $model.settings.transitionDuration, in: 0.1...5, step: 0.1) {
                        Text("Transition: \(String(format: "%.1f", model.settings.transitionDuration)) s")
                    }
                }

                Picker("Fit", selection: $model.settings.fitMode) {
                    ForEach(FitMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                if let message = model.validationMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            Section("Video") {
                Picker("Resolution", selection: $model.settings.resolution) {
                    ForEach(Resolution.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Frame rate", selection: $model.settings.frameRate) {
                    ForEach([24, 25, 30, 50, 60], id: \.self) { Text("\($0) fps").tag($0) }
                }

                Picker("Codec", selection: $model.settings.codec) {
                    ForEach(VideoCodec.allCases) { Text($0.label).tag($0) }
                }

                Picker("Quality", selection: $model.settings.quality) {
                    ForEach(QualityPreset.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Toggle("Use hardware encoder", isOn: $model.settings.useHardwareEncoder)
            }

            Section("Music") {
                LabeledContent("File") {
                    Text(model.audio.url?.lastPathComponent ?? "None")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack {
                    Button("Choose…") { showingAudioImporter = true }
                    Button(previewer.isPlaying ? "Stop" : "Preview") {
                        if let url = model.audio.url {
                            previewer.toggle(url: url, volume: model.audio.volume)
                        }
                    }
                    .disabled(model.audio.url == nil)
                    Button("Remove") {
                        previewer.stop()
                        model.audio = AudioTrackSettings()
                    }
                    .disabled(model.audio.url == nil)
                }

                LabeledContent("Volume") {
                    Slider(value: $model.audio.volume, in: 0...1.5)
                        .frame(maxWidth: 200)
                }

                Stepper(value: $model.audio.fadeOutSeconds, in: 0...10, step: 0.5) {
                    Text("Fade-out: \(String(format: "%.1f", model.audio.fadeOutSeconds)) s")
                }

                Toggle("Loop if shorter than slideshow", isOn: $model.audio.loop)

                Text("Drop an audio file here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                loadFileURLs(from: providers) { urls in
                    if let url = urls.first { model.setAudio(url) }
                }
                return true
            }

            Section("Export") {
                LabeledContent("Estimated length") {
                    Text(formatDuration(model.estimatedDuration))
                }

                Toggle("Open folder when finished", isOn: $model.openFolderWhenDone)

                statusView

                HStack {
                    if model.status.isBusy {
                        Button("Cancel", role: .cancel) { model.cancelExport() }
                    }
                    Spacer()
                    Button {
                        chooseDestinationAndExport()
                    } label: {
                        Label("Export MP4…", systemImage: "square.and.arrow.up")
                    }
                    .keyboardShortcut("e", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.images.isEmpty || model.status.isBusy || model.validationMessage != nil)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.status {
        case .idle:
            EmptyView()
        case .preparing:
            ProgressView("Preparing images…")
        case .running(let progress, let eta):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                Text(progressText(progress, eta))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .finished(let url):
            Label("Exported \(url.lastPathComponent)", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .failed(let message):
            Text(message)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        case .cancelled:
            Text("Export cancelled")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private func chooseDestinationAndExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "Slideshow.mp4"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.export(to: url)
    }

    private func progressText(_ progress: Double, _ eta: TimeInterval?) -> String {
        let percent = Int(progress * 100)
        guard let eta else { return "\(percent)% · estimating time…" }
        return "\(percent)% · about \(formatDuration(eta)) remaining"
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Row

private struct ImageRow: View {
    let image: SlideImage
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(width: 64, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(image.name).lineLimit(1)
                Text(image.creationDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: image.id) {
            thumbnail = Thumbnailer.image(for: image.url)
        }
    }
}

// MARK: - Drop helper

/// Loads file URLs from drag-and-drop providers and hands them back on the main queue.
private func loadFileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    for provider in providers where provider.canLoadObject(ofClass: URL.self) {
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async { completion([url]) }
        }
    }
}
