#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$ROOT/build/word-token-tests"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcrun swiftc -D WORD_TOKEN_STANDALONE \
  "$ROOT/ios/JapaneseSyntaxCoach/Learning/WordToken.swift" \
  "$ROOT/ios/JapaneseSyntaxCoach/Learning/WordTokenReadings.swift" \
  "$ROOT/ios/JapaneseSyntaxCoachTests/WordTokenTests.swift" \
  -o "$ROOT/build/word-token-tests/tests"
"$ROOT/build/word-token-tests/tests"
