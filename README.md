# Slideshow Generator

A lightweight native macOS app that turns images and an optional music track into an MP4 slideshow, using FFmpeg for encoding.

This repository contains **Version 1 (MVP)**. Version 2 items are listed at the end.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15 or later
- A self-contained FFmpeg build (see [Bundling FFmpeg](#bundling-ffmpeg))

## Project layout

```
SlideshowGenerator/
├── README.md
├── Sources/SlideshowGenerator/
│   ├── SlideshowGeneratorApp.swift   App entry point
│   ├── ContentView.swift             SwiftUI interface
│   ├── SlideshowViewModel.swift      App state, import/sort, export orchestration
│   ├── Models.swift                  Settings, enums, supported file types
│   ├── FFmpegCommandBuilder.swift    Builds the FFmpeg filter graph and arguments
│   ├── FFmpegExporter.swift          Runs FFmpeg, parses progress, handles cancel
│   ├── ImageProcessing.swift         HEIC/WebP/TIFF → PNG normalisation, thumbnails
│   └── AudioPreviewer.swift          Music preview playback
├── Tests/SlideshowGeneratorTests/
│   └── FFmpegCommandBuilderTests.swift
└── Scripts/
    └── bundle-ffmpeg.sh              Copies FFmpeg into the app bundle at build time
```

## Setup

1. In Xcode, choose **File → New → Project → macOS → App**, interface **SwiftUI**, language **Swift**. Name it `SlideshowGenerator`.
2. Delete the template `ContentView.swift` and `…App.swift`.
3. Drag everything in `Sources/SlideshowGenerator/` into the project target.
4. Drag `Tests/SlideshowGeneratorTests/` into a new unit-test target (File → New → Target → Unit Testing Bundle).
5. Press **⌘R** to run.

Run the tests with **⌘U**. They check timeline maths, transition offsets, music fade and trim, and loop flags without needing FFmpeg.

## Bundling FFmpeg

The app ships its own FFmpeg, so end users install nothing. You do this once on your machine.

1. Get a static macOS FFmpeg build you trust. It needs `h264_videotoolbox`, `hevc_videotoolbox`, `libx264`, `libx265` and `xfade`. Check its licence (LGPL or GPL) before you distribute the app.
2. Verify and save it. The script checks the SHA-256 and that the encoders exist:
   ```bash
   FFMPEG_URL=https://…/ffmpeg.zip FFMPEG_SHA256=<sha256> ./Scripts/fetch-ffmpeg.sh
   ```
   This writes `ThirdParty/ffmpeg`.
3. In the target's **Build Phases**, add a **Run Script** after *Copy Bundle Resources*:
   ```bash
   "${SRCROOT}/Scripts/bundle-ffmpeg.sh" "${SRCROOT}/ThirdParty/ffmpeg"
   ```
   It copies FFmpeg into `Contents/Resources` and signs it with the hardened runtime.
4. Archive and notarise the app as usual. The bundled binary must be signed, or Gatekeeper rejects it.

Architectures: the bundled FFmpeg must be universal (arm64 and x86_64), so the app runs on Apple Silicon and Intel Macs. `fetch-ffmpeg.sh` warns if it isn't. Also check that the app's Build Settings include both architectures (Any Mac). The app targets macOS 14, which covers most Intel Macs from about 2018 onward. Intel hardware encoding varies by chip; the encoder falls back to software automatically.

Lookup order at runtime: the bundled copy first, then `/opt/homebrew/bin/ffmpeg` and `/usr/local/bin/ffmpeg` as a development fallback.

Homebrew builds link to dylibs in `/opt/homebrew`, so they won't run on other Macs. Only use a self-contained build for the bundled copy.

## How it works

Image handling:
- Every image is first converted to an upright PNG in a per-export temporary folder by ImageIO. This handles HEIC, WebP and TIFF even when FFmpeg lacks them, and applies EXIF rotation from phone photos.
- Temporary files are deleted when the export finishes, fails or is cancelled.

Timeline (N images, each shown for `d` seconds, transition `t` seconds):

| Item | Value |
|---|---|
| Length of each still's input | `d + t` (or `d` for hard cuts) |
| Transition k starts at | `k × d` |
| Total duration | `N × d + t` (or `N × d` for cuts) |

Each still is normalised to the chosen resolution, frame rate, `yuv420p` and timebase before the `xfade` chain, which avoids timestamp glitches.

Fit modes:
- **Fit**: scale to fit, then pad with black bars.
- **Fill**: scale to cover, then crop.
- **Stretch**: scale to exactly the target size.

Music: volume, fade-out, silence padding if the track is short, optional looping (`-stream_loop -1`), and a trim to the exact video length.

Export: the save panel chooses the folder and filename. Progress comes from FFmpeg's `-progress pipe:1` output, and the ETA is estimated from elapsed time. Cancelling terminates FFmpeg and removes the partial file.

Encoding: hardware encoding (VideoToolbox) is on by default. Turning it off uses libx264 or libx265 with CRF values from the quality preset.

## Version 1 scope

| Feature | Status |
|---|---|
| Image import (drag and drop, file picker), ordering, removal | Done |
| Image formats: JPEG, PNG, WebP, TIFF, HEIC | Done |
| Sort by filename or date | Done |
| Global image duration | Done |
| Fit / Fill (plus Stretch) | Done |
| Music import, preview, volume, trim, fade-out, optional loop | Done |
| Transitions: fade, dissolve, slide left/right, or none | Done |
| Transition duration | Done |
| Resolution (720p, 1080p, 4K), frame rate, codec, quality preset | Done |
| Hardware-accelerated encoding | Done |
| MP4 export with progress, ETA and cancel | Done |
| Open output folder after export | Done |
| Temporary file cleanup | Done |

## Version 2 (planned)

- Live preview
- Ken Burns effect
- Per-image durations
- More transition types
- Save and load projects, with missing-file detection
- Multiple audio tracks
- Random transitions and random ordering
- Custom output profiles
- MOV container, audio codec and bitrate settings, and aspect ratio

## Known limitations

- **Sandboxing**: the app assumes it is not sandboxed. A sandboxed build must keep security-scoped bookmarks for the images and music it imports, and this is not implemented yet.
- **Memory**: each image is decoded once and written as a full-size PNG, so very large photo sets use significant disk space in the temporary folder.
- **Transparency**: transparent PNG areas become black, because the output is `yuv420p`.
- **Untested on macOS**: the FFmpeg command and timeline were verified with FFmpeg on Linux using libx264 (1920×1080, 13.000 s, H.264 + AAC). The Swift code and VideoToolbox paths have not been compiled or run on macOS yet. Run the unit tests first.
