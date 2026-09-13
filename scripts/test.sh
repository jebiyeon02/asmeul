#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/tests
xcrun clang++ -std=c++17 -O2 -Wall -Wextra -fsanitize=undefined Tests/DSPTests.cpp -o .build/tests/dsp-tests
.build/tests/dsp-tests
xcrun clang++ -std=c++17 -O2 -Wall -Wextra -fsanitize=undefined Tests/SoundscapeTests.cpp -o .build/tests/soundscape-tests
.build/tests/soundscape-tests
xcrun clang++ -std=c++17 -O2 -Wall -Wextra -fsanitize=undefined Tests/BinauralTests.cpp -o .build/tests/binaural-tests
.build/tests/binaural-tests
