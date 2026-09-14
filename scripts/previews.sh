#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
xcrun swiftc -parse-as-library -O -swift-version 5 -I "$BIN/AudioCore.build" Sources/ASMEUL/SoundLibrary.swift Tests/PreviewRender.swift "$BIN/AudioCore.build/Engine.mm.o" -framework CoreAudio -framework Accelerate -framework AVFoundation -framework Foundation -lc++ -o "$BIN/soundscape-preview"
"$BIN/soundscape-preview" "$BIN/ASMEUL_ASMEUL.bundle" "$PWD/previews"
