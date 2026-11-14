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
if ! swiftc=$(xcrun --sdk macosx --find swiftc) || ! sdk=$(xcrun --sdk macosx --show-sdk-path); then
    echo "error: unable to find Swift compiler or macOS SDK in DEVELOPER_DIR=$DEVELOPER_DIR" >&2
    exit 1
fi
build="$root/.build/auth-signout-offline-runner"
mkdir -p "$build/tmp" "$build/module-cache"
export TMPDIR="$build/tmp" CLANG_MODULE_CACHE_PATH="$build/module-cache"
echo "Compiling fake Supabase module and real AuthSessionStore (not XCTest)..."
"$swiftc" -sdk "$sdk" -module-cache-path "$build/module-cache" \
    -D AUTH_SIGNOUT_OFFLINE_TEST -parse-as-library -emit-module -emit-object \
    -module-name Supabase ios/JapaneseSyntaxCoachTests/AuthSignOutOfflineSupabase.swift \
    -emit-module-path "$build/Supabase.swiftmodule" -o "$build/Supabase.o"
"$swiftc" -sdk "$sdk" -module-cache-path "$build/module-cache" \
    -D AUTH_SIGNOUT_OFFLINE_TEST -I "$build" \
    ios/JapaneseSyntaxCoach/Auth/AuthSessionStore.swift \
    ios/JapaneseSyntaxCoachTests/AuthSignOutOfflineTests.swift "$build/Supabase.o" \
    -o "$build/auth-signout-offline-tests"
echo "Running standalone signOut offline tests..."
exec "$build/auth-signout-offline-tests"
