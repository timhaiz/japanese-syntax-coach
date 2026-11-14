#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SIMULATOR_ID="510E97CE-798B-4D14-A2A6-0792B8551502"
XCODEGEN="$ROOT/build/tools/XcodeGen/.build/release/xcodegen"
SPEC="$ROOT/scripts/ios/local-auth-project.yml"
PROJECT_DIR="$ROOT/build/auth-local-project-$(date +%Y%m%d-%H%M%S)-$$"
DERIVED_DATA="$ROOT/build/auth-local-derived-$(date +%Y%m%d-%H%M%S)-$$"
RESULT_BUNDLE="$ROOT/build/auth-local-sdk-$(date +%Y%m%d-%H%M%S)-$$.xcresult"

: "${LOCAL_AUTH_LAB_URL:?LOCAL_AUTH_LAB_URL is required}"
: "${LOCAL_AUTH_LAB_ANON_KEY:?LOCAL_AUTH_LAB_ANON_KEY is required}"
[[ -x "$XCODEGEN" ]] || { printf 'xcodegen executable is missing\n' >&2; exit 1; }
[[ -f "$SPEC" ]] || { printf 'isolated XcodeGen spec is missing\n' >&2; exit 1; }

TEST_FILTER=(-only-testing:JapaneseSyntaxCoachTests/LocalAuthLabTests)
EXPECTED_TESTS=2
if [[ "${1:-}" == "--all" ]]; then
  TEST_FILTER=(-only-testing:JapaneseSyntaxCoachTests)
  EXPECTED_TESTS=143
fi

cd "$ROOT"
mkdir -p "$PROJECT_DIR"
"$XCODEGEN" --spec "$SPEC" --project-root ios --project "$PROJECT_DIR" >/dev/null
ln -s "$ROOT/ios/JapaneseSyntaxCoach" "$PROJECT_DIR/JapaneseSyntaxCoach"
ln -s "$ROOT/ios/JapaneseSyntaxCoachTests" "$PROJECT_DIR/JapaneseSyntaxCoachTests"

TEST_RUNNER_LOCAL_AUTH_LAB_URL="$LOCAL_AUTH_LAB_URL" \
TEST_RUNNER_LOCAL_AUTH_LAB_ANON_KEY="$LOCAL_AUTH_LAB_ANON_KEY" \
DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild -quiet test \
  -project "$PROJECT_DIR/JapaneseSyntaxCoach.xcodeproj" \
  -scheme JapaneseSyntaxCoach \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE" \
  "${TEST_FILTER[@]}" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO

DEVELOPER_DIR="$DEVELOPER_DIR" xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" | EXPECTED_TESTS="$EXPECTED_TESTS" node -e '
let input = "";
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  const result = JSON.parse(input);
  const expected = Number(process.env.EXPECTED_TESTS);
  if (result.passedTests !== expected || result.failedTests !== 0 || result.skippedTests !== 0) {
    console.error(`SDK Auth tests did not execute ${expected} passing tests without skips.`);
    process.exitCode = 1;
  } else console.log(`SDK Auth tests: ${expected} passed, 0 failed, 0 skipped.`);
});'
printf 'SDK auth result bundle: %s\n' "$RESULT_BUNDLE"
