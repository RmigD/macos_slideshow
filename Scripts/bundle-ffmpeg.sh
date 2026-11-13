#!/bin/bash
# Copies FFmpeg into the app's Resources folder and signs it, so the app
# works out of the box on any Mac.
#
# Xcode "Run Script" build phase (after "Copy Bundle Resources"):
#   "${SRCROOT}/Scripts/bundle-ffmpeg.sh" "${SRCROOT}/ThirdParty/ffmpeg"
set -euo pipefail

SRC="${1:?usage: bundle-ffmpeg.sh /path/to/ffmpeg}"
DEST="${BUILT_PRODUCTS_DIR:?must run inside Xcode}/${CONTENTS_FOLDER_PATH:?}/Resources"

mkdir -p "$DEST"
cp "$SRC" "$DEST/ffmpeg"
chmod +x "$DEST/ffmpeg"

# Embedded executables must carry the app's signature with the hardened runtime,
# or notarization and Gatekeeper will reject the app.
if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp \
    --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$DEST/ffmpeg"
fi
echo "Bundled ffmpeg into $DEST"
