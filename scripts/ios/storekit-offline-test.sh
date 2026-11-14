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
    echo "error: unable to find the Swift compiler or macOS SDK in DEVELOPER_DIR=$DEVELOPER_DIR" >&2
    exit 1
fi
build="$root/.build/storekit-offline-runner"
mkdir -p "$build/tmp" "$build/module-cache"
export TMPDIR="$build/tmp" CLANG_MODULE_CACHE_PATH="$build/module-cache"
echo "Compiling standalone StoreKit offline tests (not XCTest)..."
"$swiftc" -sdk "$sdk" -module-cache-path "$build/module-cache" \
    -D STOREKIT_FINISH_OFFLINE_TEST \
    ios/JapaneseSyntaxCoach/Billing/PendingTransactionQueue.swift \
    ios/JapaneseSyntaxCoach/Billing/StoreKitProductProvider.swift \
    ios/JapaneseSyntaxCoach/StoreKitManager.swift \
    ios/JapaneseSyntaxCoachTests/StoreKitFinishOfflineTests.swift \
    -o "$build/storekit-offline-tests"
echo "Running standalone StoreKit offline tests..."
exec "$build/storekit-offline-tests"
