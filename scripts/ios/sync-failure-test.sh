#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$ROOT/build/sync-failure-tests"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcrun swiftc -D SYNC_FAILURE_STANDALONE \
  "$ROOT/ios/JapaneseSyntaxCoach/Networking/APIClient.swift" \
  "$ROOT/ios/JapaneseSyntaxCoach/Learning/LearningSyncFailure.swift" \
  "$ROOT/ios/JapaneseSyntaxCoachTests/LearningSyncFailureTests.swift" \
  -o "$ROOT/build/sync-failure-tests/tests"
"$ROOT/build/sync-failure-tests/tests"
