#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/tests
xcrun clang++ -std=c++17 -O2 -Wall -Wextra Tests/AudioPerformanceTests.cpp -framework Accelerate -o .build/tests/audio-performance-tests
.build/tests/audio-performance-tests
# AddressSanitizer can hang before main() on macOS 26 while initializing its
# shadow memory (llvm/llvm-project#200447). Keep UBSan coverage there and allow
# ASan to be forced after the toolchain issue is fixed.
ASMEUL_LIFETIME_SANITIZERS="address,undefined"
if [[ "$(sw_vers -productVersion)" == 26.* && "${ASMEUL_FORCE_ASAN:-0}" != "1" ]]; then
  ASMEUL_LIFETIME_SANITIZERS="undefined"
  printf '%s\n' "NOTE: skipping AddressSanitizer on macOS 26; set ASMEUL_FORCE_ASAN=1 to force it."
fi
xcrun clang++ -std=c++17 -O1 -g -fsanitize="$ASMEUL_LIFETIME_SANITIZERS" Tests/SoundLifetimeTests.cpp -framework Accelerate -o .build/tests/sound-lifetime-tests
.build/tests/sound-lifetime-tests
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
# Keep assertions enabled: these verify and perform PCM ownership transfers.
xcrun swiftc -parse-as-library -Onone -swift-version 5 -I "$BIN/AudioCore.build" Sources/ASMEUL/SoundLibrary.swift Tests/SoundLoadingTests.swift "$BIN/AudioCore.build/Engine.mm.o" -framework CoreAudio -framework Accelerate -framework AVFoundation -framework Foundation -lc++ -o .build/tests/sound-loading-tests
.build/tests/sound-loading-tests "$BIN/ASMEUL_ASMEUL.bundle"
