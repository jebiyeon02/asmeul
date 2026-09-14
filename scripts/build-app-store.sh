#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

ASMEUL_BUNDLE_ID="${ASMEUL_BUNDLE_ID:-studio.asmeul}"
ASMEUL_VERSION="${ASMEUL_VERSION:-1.0}"
ASMEUL_BUILD_NUMBER="${ASMEUL_BUILD_NUMBER:-1}"
ASMEUL_APP_STORE_DRY_RUN="${ASMEUL_APP_STORE_DRY_RUN:-0}"
ASMEUL_APP_STORE_SIGN_IDENTITY="${ASMEUL_APP_STORE_SIGN_IDENTITY:-Apple Distribution}"
ASMEUL_INSTALLER_SIGN_IDENTITY="${ASMEUL_INSTALLER_SIGN_IDENTITY:-3rd Party Mac Developer Installer}"
ASMEUL_TEAM_ID="${ASMEUL_TEAM_ID:-}"

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

swift build -c release
BIN="$(swift build -c release --show-bin-path)"
ASMEUL_STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/asmeul-app-store.XXXXXX")"
trap 'rm -rf "$ASMEUL_STAGE_DIR"' EXIT
APP="$ASMEUL_STAGE_DIR/ASMEUL.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/ASMEUL" "$APP/Contents/MacOS/ASMEUL"
cp -R "$BIN/ASMEUL_ASMEUL.bundle" "$APP/Contents/Resources/"
cp Assets/ASMEUL.icns "$APP/Contents/Resources/ASMEUL.icns"
cp Distribution/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
rm -f "$APP/Contents/Resources/ASMEUL_ASMEUL.bundle/radio-jazz.wav"

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
<key>ITSAppUsesNonExemptEncryption</key><false/>
<key>NSAudioCaptureUsageDescription</key><string>재생 중인 소리에 공간 효과를 입히기 위해 시스템 오디오 접근이 필요합니다. 오디오를 녹음하거나 저장하지 않습니다.</string>
</dict></plist>
PLIST

if [[ -n "${ASMEUL_PROVISIONING_PROFILE:-}" ]]; then
  if [[ ! -f "$ASMEUL_PROVISIONING_PROFILE" ]]; then
    printf '%s\n' "Provisioning profile not found: $ASMEUL_PROVISIONING_PROFILE" >&2
    exit 1
  fi
  cp "$ASMEUL_PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
  PROFILE_PLIST="$ASMEUL_STAGE_DIR/provisioning-profile.plist"
  security cms -D -i "$ASMEUL_PROVISIONING_PROFILE" > "$PROFILE_PLIST"
  PROFILE_APPLICATION_ID="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$PROFILE_PLIST")"
  PROFILE_TEAM_ID="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' "$PROFILE_PLIST")"
  if [[ "$PROFILE_APPLICATION_ID" != *".$ASMEUL_BUNDLE_ID" ]]; then
    printf '%s\n' "Provisioning profile does not match $ASMEUL_BUNDLE_ID: $PROFILE_APPLICATION_ID" >&2
    exit 1
  fi
  if [[ -n "$ASMEUL_TEAM_ID" && "$ASMEUL_TEAM_ID" != "$PROFILE_TEAM_ID" ]]; then
    printf '%s\n' "Provisioning profile team mismatch: expected $ASMEUL_TEAM_ID, got $PROFILE_TEAM_ID" >&2
    exit 1
  fi
  ASMEUL_TEAM_ID="$PROFILE_TEAM_ID"
fi

SIGNING_ENTITLEMENTS="$ASMEUL_STAGE_DIR/signing-entitlements.plist"
cp Distribution/AppStore.entitlements "$SIGNING_ENTITLEMENTS"
if [[ -n "$ASMEUL_TEAM_ID" ]]; then
  /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $ASMEUL_TEAM_ID.$ASMEUL_BUNDLE_ID" "$SIGNING_ENTITLEMENTS"
  /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $ASMEUL_TEAM_ID" "$SIGNING_ENTITLEMENTS"
fi

xattr -cr "$APP"
if [[ "$ASMEUL_APP_STORE_DRY_RUN" == "1" ]]; then
  codesign --force --sign - --timestamp=none \
    --entitlements "$SIGNING_ENTITLEMENTS" "$APP"
else
  if [[ "$(security find-identity -v -p codesigning)" != *"$ASMEUL_APP_STORE_SIGN_IDENTITY"* ]]; then
    printf '%s\n' "Missing app signing identity: $ASMEUL_APP_STORE_SIGN_IDENTITY" >&2
    exit 1
  fi
  if [[ "$(security find-identity -v)" != *"$ASMEUL_INSTALLER_SIGN_IDENTITY"* ]]; then
    printf '%s\n' "Missing installer signing identity: $ASMEUL_INSTALLER_SIGN_IDENTITY" >&2
    exit 1
  fi
  codesign --force --sign "$ASMEUL_APP_STORE_SIGN_IDENTITY" --timestamp \
    --entitlements "$SIGNING_ENTITLEMENTS" "$APP"
fi

codesign --verify --deep --strict --verbose=2 "$APP"
SIGNED_ENTITLEMENTS="$ASMEUL_STAGE_DIR/signed-entitlements.plist"
codesign -d --entitlements "$SIGNED_ENTITLEMENTS" --xml "$APP"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$SIGNED_ENTITLEMENTS")" != "true" ]]; then
  printf '%s\n' "The signed app is missing the App Sandbox entitlement." >&2
  exit 1
fi
if [[ -n "$ASMEUL_TEAM_ID" ]]; then
  if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.application-identifier' "$SIGNED_ENTITLEMENTS")" != "$ASMEUL_TEAM_ID.$ASMEUL_BUNDLE_ID" ]]; then
    printf '%s\n' "The signed app has an invalid application identifier." >&2
    exit 1
  fi
  if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.team-identifier' "$SIGNED_ENTITLEMENTS")" != "$ASMEUL_TEAM_ID" ]]; then
    printf '%s\n' "The signed app has an invalid team identifier." >&2
    exit 1
  fi
fi
plutil -lint "$APP/Contents/Info.plist" "$APP/Contents/Resources/PrivacyInfo.xcprivacy" \
  Distribution/AppStore.entitlements
test -f "$APP/Contents/Resources/ASMEUL.icns"
test -f "$APP/Contents/Resources/PrivacyInfo.xcprivacy"

mkdir -p "$PWD/build/app-store"
if [[ "$ASMEUL_APP_STORE_DRY_RUN" == "1" ]]; then
  rm -f "$PWD/build/app-store/ASMEUL-dry-run.zip"
  ditto -c -k --norsrc --keepParent "$APP" "$PWD/build/app-store/ASMEUL-dry-run.zip"
  printf '%s\n' "$PWD/build/app-store/ASMEUL-dry-run.zip"
  exit 0
fi

rm -f "$PWD/build/app-store/ASMEUL.pkg"
productbuild --component "$APP" /Applications \
  --sign "$ASMEUL_INSTALLER_SIGN_IDENTITY" "$PWD/build/app-store/ASMEUL.pkg"
pkgutil --check-signature "$PWD/build/app-store/ASMEUL.pkg"
printf '%s\n' "$PWD/build/app-store/ASMEUL.pkg"
