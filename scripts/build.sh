#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
# Sign outside the file-provider folder: Finder metadata can race codesign there.
ASMEUL_STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/asmeul-build.XXXXXX")"
trap 'rm -rf "$ASMEUL_STAGE_DIR"' EXIT
APP="$ASMEUL_STAGE_DIR/ASMEUL.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Hollow "$APP/Contents/MacOS/ASMEUL"
# Bundle resources are explicitly resolved in SoundLibrary.
mkdir -p "$APP/Contents/Resources"
cp -R .build/release/Hollow_Hollow.bundle "$APP/Contents/Resources/"
cp Assets/ASMEUL.icns "$APP/Contents/Resources/ASMEUL.icns"
# Remove the obsolete generated jazz asset from incremental build output.
rm -f "$APP/Contents/Resources/Hollow_Hollow.bundle/radio-jazz.wav"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>studio.hollow.prototype</string>
<key>CFBundleName</key><string>ASMEUL</string>
<key>CFBundleDisplayName</key><string>아스믈</string>
<key>CFBundleExecutable</key><string>ASMEUL</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>ASMEUL.icns</string>
<key>CFBundleShortVersionString</key><string>0.9.0</string>
<key>CFBundleVersion</key><string>9</string>
<key>LSMinimumSystemVersion</key><string>14.4</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAudioCaptureUsageDescription</key><string>재생 중인 소리에 공간 효과를 입히기 위해 시스템 오디오 접근이 필요합니다. 오디오를 녹음하거나 저장하지 않습니다.</string>
</dict></plist>
PLIST
xattr -cr "$APP"
codesign --force --sign "${HOLLOW_SIGN_IDENTITY:--}" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p "$PWD/build"
rm -f "$PWD/ASMEUL-macOS-arm64.zip"
ditto -c -k --norsrc --keepParent "$APP" "$PWD/ASMEUL-macOS-arm64.zip"
rm -rf "$PWD/build/ASMEUL.app"
ditto --norsrc "$APP" "$PWD/build/ASMEUL.app"
xattr -cr "$PWD/build/ASMEUL.app"
# macOS may reattach the provenance attribute while ditto copies the app into
# the workspace. It is metadata, not part of the signed bundle, and codesign
# rejects it as a resource fork on subsequent rebuilds.
xattr -dr com.apple.provenance "$PWD/build/ASMEUL.app" 2>/dev/null || true
codesign --verify --deep --strict "$PWD/build/ASMEUL.app"
printf '%s\n' "$PWD/build/ASMEUL.app"
