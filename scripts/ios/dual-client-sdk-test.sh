#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
SIMULATOR_ID=""
XCODEGEN="$ROOT/build/tools/XcodeGen/.build/release/xcodegen"
SPEC="$ROOT/scripts/ios/dual-client-project.yml"
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
PROJECT_DIR="$ROOT/build/dual-client-project-$STAMP"
DERIVED_DATA="$ROOT/build/dual-client-derived-$STAMP"
RESULT_BUNDLE="$ROOT/build/dual-client-sdk-$STAMP.xcresult"

LOCAL_DUAL_AUTH_URL="${TEST_RUNNER_LOCAL_DUAL_AUTH_URL:-${LOCAL_DUAL_AUTH_URL:-}}"
LOCAL_DUAL_WEB_URL="${TEST_RUNNER_LOCAL_DUAL_WEB_URL:-${LOCAL_DUAL_WEB_URL:-}}"
LOCAL_DUAL_ANON_KEY="${TEST_RUNNER_LOCAL_DUAL_ANON_KEY:-${LOCAL_DUAL_ANON_KEY:-}}"
LOCAL_DUAL_EMAIL="${TEST_RUNNER_LOCAL_DUAL_EMAIL:-${LOCAL_DUAL_EMAIL:-}}"
LOCAL_DUAL_PASSWORD="${TEST_RUNNER_LOCAL_DUAL_PASSWORD:-${LOCAL_DUAL_PASSWORD:-}}"
: "${LOCAL_DUAL_AUTH_URL:?LOCAL_DUAL_AUTH_URL is required}"
: "${LOCAL_DUAL_WEB_URL:?LOCAL_DUAL_WEB_URL is required}"
: "${LOCAL_DUAL_ANON_KEY:?LOCAL_DUAL_ANON_KEY is required}"
: "${LOCAL_DUAL_EMAIL:?LOCAL_DUAL_EMAIL is required}"
: "${LOCAL_DUAL_PASSWORD:?LOCAL_DUAL_PASSWORD is required}"
[[ "$LOCAL_DUAL_AUTH_URL" == "http://127.0.0.1:54351" ]] || { printf 'Auth URL must be the fixed loopback endpoint\n' >&2; exit 1; }
[[ "$LOCAL_DUAL_WEB_URL" == "http://127.0.0.1:3219" ]] || { printf 'Web URL must be the fixed loopback endpoint\n' >&2; exit 1; }
[[ -x "$XCODEGEN" ]] || { printf 'XcodeGen executable is missing\n' >&2; exit 1; }
[[ -f "$SPEC" ]] || { printf 'isolated XcodeGen spec is missing\n' >&2; exit 1; }

# Every run owns a newly created simulator; existing devices and their queues stay untouched.
cleanup_simulator() {
  if [[ -n "$SIMULATOR_ID" ]]; then
    xcrun simctl shutdown "$SIMULATOR_ID" >/dev/null 2>&1 || true
  fi
}
trap cleanup_simulator EXIT
SIMULATOR_ID="$(xcrun simctl create "JSC dual-client $STAMP" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-2)"
xcrun simctl boot "$SIMULATOR_ID"
xcrun simctl bootstatus "$SIMULATOR_ID" -b >/dev/null

cd "$ROOT"
mkdir -p "$PROJECT_DIR"
"$XCODEGEN" --spec "$SPEC" --project-root ios --project "$PROJECT_DIR" >/dev/null
ln -s "$ROOT/ios/JapaneseSyntaxCoach" "$PROJECT_DIR/JapaneseSyntaxCoach"
ln -s "$ROOT/ios/JapaneseSyntaxCoachTests" "$PROJECT_DIR/JapaneseSyntaxCoachTests"

LOCAL_DUAL_AUTH_URL="$LOCAL_DUAL_AUTH_URL" \
LOCAL_DUAL_WEB_URL="$LOCAL_DUAL_WEB_URL" \
LOCAL_DUAL_ANON_KEY="$LOCAL_DUAL_ANON_KEY" \
LOCAL_DUAL_EMAIL="$LOCAL_DUAL_EMAIL" \
LOCAL_DUAL_PASSWORD="$LOCAL_DUAL_PASSWORD" \
LOCAL_DUAL_QUESTION_MARKER="${TEST_RUNNER_LOCAL_DUAL_QUESTION_MARKER:-}" \
LOCAL_DUAL_GATE_URL="${TEST_RUNNER_LOCAL_DUAL_GATE_URL:-}" \
LOCAL_DUAL_RACE_RESULT="${TEST_RUNNER_LOCAL_DUAL_RACE_RESULT:-}" \
TEST_RUNNER_LOCAL_DUAL_AUTH_URL="$LOCAL_DUAL_AUTH_URL" \
TEST_RUNNER_LOCAL_DUAL_WEB_URL="$LOCAL_DUAL_WEB_URL" \
TEST_RUNNER_LOCAL_DUAL_ANON_KEY="$LOCAL_DUAL_ANON_KEY" \
TEST_RUNNER_LOCAL_DUAL_EMAIL="$LOCAL_DUAL_EMAIL" \
EXPECTED_TESTS="${TEST_RUNNER_EXPECTED_TESTS:-3}"
TEST_SELECTION="${TEST_RUNNER_ONLY_TEST:-JapaneseSyntaxCoachTests/DualClientLabTests/testInjectedLearningBaseURLIsUsedForSnapshotAndAnswerRequests,JapaneseSyntaxCoachTests/DualClientLabTests/testRealAnswerReplayClearsMistakeAndConflictKeepsQueue,JapaneseSyntaxCoachTests/DualClientLabTests/testRealAuthSignOutAndSessionRestore}"
IFS=',' read -r -a TESTS <<< "$TEST_SELECTION"
ONLY_TESTING_ARGS=()
for selected_test in "${TESTS[@]}"; do ONLY_TESTING_ARGS+=("-only-testing:$selected_test"); done
TEST_RUNNER_ONLY_TEST="$TEST_SELECTION" \
TEST_RUNNER_EXPECTED_TESTS="${TEST_RUNNER_EXPECTED_TESTS:-4}" \
TEST_RUNNER_LOCAL_DUAL_PASSWORD="$LOCAL_DUAL_PASSWORD" \
TEST_RUNNER_LOCAL_DUAL_QUESTION_MARKER="${TEST_RUNNER_LOCAL_DUAL_QUESTION_MARKER:-}" \
TEST_RUNNER_LOCAL_DUAL_GATE_URL="${TEST_RUNNER_LOCAL_DUAL_GATE_URL:-}" \
TEST_RUNNER_LOCAL_DUAL_RACE_RESULT="${TEST_RUNNER_LOCAL_DUAL_RACE_RESULT:-}" \
DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild -quiet test \
  -project "$PROJECT_DIR/JapaneseSyntaxCoach.xcodeproj" \
  -scheme JapaneseSyntaxCoach \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE" \
  "${ONLY_TESTING_ARGS[@]}" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO

DEVELOPER_DIR="$DEVELOPER_DIR" xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" | TEST_RUNNER_EXPECTED_TESTS="$EXPECTED_TESTS" node -e '
let input = "";
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  const result = JSON.parse(input);
  const expected = Number(process.env.TEST_RUNNER_EXPECTED_TESTS ?? "4");
  if (result.passedTests !== expected || result.failedTests !== 0 || result.skippedTests !== 0) {
    console.error(`Dual-client SDK tests did not execute ${expected} passing tests without skips.`);
    process.exitCode = 1;
  } else console.log(`SDK Dual-client tests: ${expected} passed, 0 failed, 0 skipped.`);
});'
printf 'SDK result bundle: %s\n' "$RESULT_BUNDLE"
