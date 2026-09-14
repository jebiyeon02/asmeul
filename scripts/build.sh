#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
# Sign outside the file-provider folder: Finder metadata can race codesign there.
ASMEUL_STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/asmeul-build.XXXXXX")"
trap 'rm -rf "$ASMEUL_STAGE_DIR"' EXIT
APP="$ASMEUL_STAGE_DIR/ASMEUL.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/ASMEUL" "$APP/Contents/MacOS/ASMEUL"
# Bundle resources are explicitly resolved in SoundLibrary.
mkdir -p "$APP/Contents/Resources"
cp -R "$BIN/ASMEUL_ASMEUL.bundle" "$APP/Contents/Resources/"
cp Assets/ASMEUL.icns "$APP/Contents/Resources/ASMEUL.icns"
cp Distribution/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
# Remove the obsolete generated jazz asset from incremental build output.
rm -f "$APP/Contents/Resources/ASMEUL_ASMEUL.bundle/radio-jazz.wav"
ASMEUL_BUNDLE_ID="${ASMEUL_BUNDLE_ID:-studio.asmeul}"
ASMEUL_VERSION="${ASMEUL_VERSION:-1.0}"
ASMEUL_BUILD_NUMBER="${ASMEUL_BUILD_NUMBER:-9}"
if [[ ! "$ASMEUL_BUNDLE_ID" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]]; then
  printf '%s\n' "Invalid bundle ID: $ASMEUL_BUNDLE_ID" >&2
  exit 1
fi
if [[ ! "$ASMEUL_VERSION" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
  printf '%s\n' "Invalid marketing version: $ASMEUL_VERSION" >&2
  exit 1
fi
if [[ ! "$ASMEUL_BUILD_NUMBER" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
  printf '%s\n' "Invalid build number: $ASMEUL_BUILD_NUMBER" >&2
  exit 1
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>${ASMEUL_BUNDLE_ID}</string>
<key>CFBundleName</key><string>ASMEUL</string>
<key>CFBundleDisplayName</key><string>아스믈</string>
<key>CFBundleExecutable</key><string>ASMEUL</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>ASMEUL.icns</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleDevelopmentRegion</key><string>ko</string>
<key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
<key>CFBundleShortVersionString</key><string>${ASMEUL_VERSION}</string>
<key>CFBundleVersion</key><string>${ASMEUL_BUILD_NUMBER}</string>
<key>LSApplicationCategoryType</key><string>public.app-category.music</string>
<key>LSMinimumSystemVersion</key><string>14.4</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAudioCaptureUsageDescription</key><string>재생 중인 소리에 공간 효과를 입히기 위해 시스템 오디오 접근이 필요합니다. 오디오를 녹음하거나 저장하지 않습니다.</string>
</dict></plist>
PLIST
xattr -cr "$APP"
ASMEUL_CODE_SIGN_IDENTITY="${ASMEUL_SIGN_IDENTITY:--}"
if [[ "$ASMEUL_CODE_SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - --timestamp=none "$APP"
else
  # Developer ID distribution requires the hardened runtime and a trusted
  # timestamp. The notary service rejects ad-hoc or untimestamped builds.
  codesign --force --sign "$ASMEUL_CODE_SIGN_IDENTITY" --options runtime --timestamp "$APP"
fi
codesign --verify --deep --strict "$APP"
mkdir -p "$PWD/build"
rm -f "$PWD/ASMEUL-macOS-arm64.zip"
ditto -c -k --norsrc --keepParent "$APP" "$PWD/ASMEUL-macOS-arm64.zip"

if [[ -n "${ASMEUL_NOTARY_PROFILE:-}" ]]; then
  if [[ "$ASMEUL_CODE_SIGN_IDENTITY" == "-" ]]; then
    printf '%s\n' "ASMEUL_NOTARY_PROFILE requires a Developer ID Application signing identity." >&2
    exit 1
  fi
  xcrun notarytool submit "$PWD/ASMEUL-macOS-arm64.zip" \
    --keychain-profile "$ASMEUL_NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  # A notarization ticket cannot be stapled to a ZIP. Recreate it from the
  # stapled app so recipients also pass Gatekeeper while offline.
  rm -f "$PWD/ASMEUL-macOS-arm64.zip"
  ditto -c -k --norsrc --keepParent "$APP" "$PWD/ASMEUL-macOS-arm64.zip"
fi
rm -rf "$PWD/build/ASMEUL.app"
ditto --norsrc "$APP" "$PWD/build/ASMEUL.app"
xattr -cr "$PWD/build/ASMEUL.app"
# macOS may reattach the provenance attribute while ditto copies the app into
# the workspace. It is metadata, not part of the signed bundle, and codesign
# rejects it as a resource fork on subsequent rebuilds.
xattr -dr com.apple.provenance "$PWD/build/ASMEUL.app" 2>/dev/null || true
codesign --verify --deep --strict "$PWD/build/ASMEUL.app"
if [[ -n "${ASMEUL_NOTARY_PROFILE:-}" ]]; then
  spctl --assess --type execute --verbose=2 "$PWD/build/ASMEUL.app"
fi
printf '%s\n' "$PWD/build/ASMEUL.app"
