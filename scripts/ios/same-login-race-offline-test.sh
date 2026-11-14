#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
root=$(pwd -P)
developer_dir=${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}
if [ -z "$developer_dir" ] || [ ! -x "$developer_dir/usr/bin/xcodebuild" ]; then
    echo "error: full Xcode is required; set DEVELOPER_DIR to Xcode.app/Contents/Developer" >&2
    exit 1
fi
export DEVELOPER_DIR="$developer_dir"
build="$root/.build/same-login-race-offline-runner"
mkdir -p "$build/tmp" "$build/module-cache"
export TMPDIR="$build/tmp" CLANG_MODULE_CACHE_PATH="$build/module-cache"
# Run both compilation and the test with network access denied.
exec /usr/bin/sandbox-exec -p '(version 1) (allow default) (deny network*)' /bin/sh -eu -c '
    swiftc=$(xcrun --sdk macosx --find swiftc)
    sdk=$(xcrun --sdk macosx --show-sdk-path)
    echo "Compiling real AuthSessionStore and APIClient with a fake Supabase module (not XCTest)..."
    "$swiftc" -sdk "$sdk" -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
        -D AUTH_SIGNOUT_OFFLINE_TEST -parse-as-library -emit-module -emit-object \
        -module-name Supabase ios/JapaneseSyntaxCoachTests/AuthSignOutOfflineSupabase.swift \
        -emit-module-path "$1/Supabase.swiftmodule" -o "$1/Supabase.o"
    "$swiftc" -sdk "$sdk" -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
        -D SAME_LOGIN_RACE_OFFLINE_TEST -I "$1" \
        ios/JapaneseSyntaxCoach/Auth/AuthSessionStore.swift \
        ios/JapaneseSyntaxCoach/Networking/APIClient.swift \
        ios/JapaneseSyntaxCoachTests/SameLoginRaceOfflineTests.swift "$1/Supabase.o" \
        -o "$1/same-login-race-offline-tests"
    exec "$1/same-login-race-offline-tests"
' offline-runner "$build"
