#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/tests
xcrun clang++ -framework Accelerate -std=c++17 -O2 -Wall -Wextra -fsanitize=undefined Tests/DSPTests.cpp -o .build/tests/dsp-tests
.build/tests/dsp-tests
xcrun clang++ -framework Accelerate -std=c++17 -O2 -Wall -Wextra -fsanitize=undefined Tests/SoundscapeTests.cpp -o .build/tests/soundscape-tests
.build/tests/soundscape-tests
xcrun clang++ -framework Accelerate -std=c++17 -O2 -Wall -Wextra -fsanitize=undefined Tests/BinauralTests.cpp -o .build/tests/binaural-tests
.build/tests/binaural-tests
xcrun swiftc Sources/ASMEUL/AudioSources.swift Tests/AudioSourceTests.swift -o .build/tests/audio-source-tests
.build/tests/audio-source-tests
xcrun clang++ -framework Accelerate -std=c++17 -fobjc-arc -O2 -Wall -Wextra -fsanitize=undefined Tests/AudioRoutingTests.mm -framework Foundation -framework CoreAudio -o .build/tests/audio-routing-tests
.build/tests/audio-routing-tests
xcrun swiftc -parse-as-library -O Sources/ASMEUL/AnimationClock.swift Sources/ASMEUL/AudioMeter.swift Sources/ASMEUL/EnvironmentImageStore.swift Tests/RenderingTests.swift -o .build/tests/rendering-tests
.build/tests/rendering-tests "$PWD/Sources/ASMEUL/Resources"
