#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SIMULATOR_ID="510E97CE-798B-4D14-A2A6-0792B8551502"
PROJECT_DIR="$ROOT/build/auth-ui-project"
RESULT_BUNDLE="$ROOT/build/auth-ui-$(date +%Y%m%d-%H%M%S).xcresult"
XCODEGEN="$ROOT/build/tools/XcodeGen/.build/release/xcodegen"

cd "$ROOT"
"$XCODEGEN" --spec ios/project.yml --project-root ios --project "$PROJECT_DIR"
for source_dir in JapaneseSyntaxCoach JapaneseSyntaxCoachTests JapaneseSyntaxCoachUITests; do
  if [[ ! -e "$PROJECT_DIR/$source_dir" ]]; then
    ln -s "$ROOT/ios/$source_dir" "$PROJECT_DIR/$source_dir"
  fi
done

DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild -quiet test \
  -project "$PROJECT_DIR/JapaneseSyntaxCoach.xcodeproj" \
  -scheme JapaneseSyntaxCoachUITests \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath "$ROOT/build/auth-ui-derived-data" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -only-testing:JapaneseSyntaxCoachUITests/AuthInteractionUITests \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  SUPABASE_URL= \
  SUPABASE_ANON_KEY= \
  CODE_SIGNING_ALLOWED=NO

printf 'UI test result bundle: %s\n' "$RESULT_BUNDLE"
