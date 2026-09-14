#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/tests
xcrun clang++ -std=c++17 -O2 -Wall -Wextra Tests/AudioPerformanceTests.cpp -framework Accelerate -o .build/tests/audio-performance-tests
.build/tests/audio-performance-tests
xcrun clang++ -std=c++17 -O1 -g -fsanitize=address,undefined Tests/SoundLifetimeTests.cpp -framework Accelerate -o .build/tests/sound-lifetime-tests
.build/tests/sound-lifetime-tests
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
xcrun swiftc -parse-as-library -O -swift-version 5 -I "$BIN/AudioCore.build" Sources/ASMEUL/SoundLibrary.swift Tests/SoundLoadingTests.swift "$BIN/AudioCore.build/Engine.mm.o" -framework CoreAudio -framework Accelerate -framework AVFoundation -framework Foundation -lc++ -o .build/tests/sound-loading-tests
.build/tests/sound-loading-tests "$BIN/Hollow_Hollow.bundle"
