#!/bin/bash
# One-time developer step: downloads a macOS FFmpeg build and verifies its SHA-256
# before it can be bundled. End users never run this.
#
# Usage:
#   FFMPEG_URL=https://example.com/ffmpeg.zip \
#   FFMPEG_SHA256=<expected sha256 of the zip> \
#   ./Scripts/fetch-ffmpeg.sh
#
# Output: ThirdParty/ffmpeg (a single, self-contained arm64 or x86_64 binary).
set -euo pipefail

: "${FFMPEG_URL:?Set FFMPEG_URL to a static macOS FFmpeg zip you trust}"
: "${FFMPEG_SHA256:?Set FFMPEG_SHA256 to the zip's expected SHA-256}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

curl -fsSL "$FFMPEG_URL" -o "$WORK/ffmpeg.zip"

ACTUAL="$(shasum -a 256 "$WORK/ffmpeg.zip" | awk '{print $1}')"
if [ "$ACTUAL" != "$FFMPEG_SHA256" ]; then
  echo "SHA-256 mismatch: expected $FFMPEG_SHA256, got $ACTUAL" >&2
  exit 1
fi

unzip -q "$WORK/ffmpeg.zip" -d "$WORK/unpacked"
BIN="$(find "$WORK/unpacked" -type f -name ffmpeg | head -n 1)"
[ -n "$BIN" ] || { echo "No ffmpeg binary found in archive" >&2; exit 1; }

# The app runs on both Apple Silicon and Intel, so the bundled binary must
# contain both architectures (a universal binary, built with `lipo -create`).
ARCHS="$(lipo -archs "$BIN" 2>/dev/null || file -b "$BIN")"
for arch in arm64 x86_64; do
  case "$ARCHS" in
    *"$arch"*) ;;
    *) echo "Warning: binary lacks $arch (found: $ARCHS). Intel or Apple Silicon Macs will fail." >&2 ;;
  esac
done

# Confirm the encoders the app needs are present.
ENCODERS="$("$BIN" -hide_banner -encoders 2>/dev/null || true)"
for enc in h264_videotoolbox hevc_videotoolbox libx264 libx265; do
  case "$ENCODERS" in
    *" $enc "*) ;;
    *) echo "Warning: encoder $enc missing from this build" >&2 ;;
  esac
done

mkdir -p "$ROOT/ThirdParty"
cp "$BIN" "$ROOT/ThirdParty/ffmpeg"
chmod +x "$ROOT/ThirdParty/ffmpeg"
echo "Saved verified FFmpeg to $ROOT/ThirdParty/ffmpeg"
"$ROOT/ThirdParty/ffmpeg" -version | head -n 1
