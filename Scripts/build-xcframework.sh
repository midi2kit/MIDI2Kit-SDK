#!/bin/bash
#
# build-xcframework.sh
# Builds XCFrameworks for MIDI2Kit modules
#
# Usage:
#   ./Scripts/build-xcframework.sh          # Build all modules
#   ./Scripts/build-xcframework.sh MIDI2Core # Build single module
#

set -e

# All modules to build
ALL_MODULES=("MIDI2Core" "MIDI2Transport" "MIDI2CI" "MIDI2PE" "MIDI2Client")

# If a specific module is requested
if [ -n "$1" ]; then
    MODULES=("$1")
else
    MODULES=("${ALL_MODULES[@]}")
fi

BUILD_DIR="$(pwd)/build"
OUTPUT_DIR="$(pwd)/dist"

echo "🧹 Cleaning..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# Function to build a single module
build_module() {
    local MODULE=$1
    local SCHEME="${MODULE}Dynamic"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 Building $MODULE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local MODULE_BUILD="$BUILD_DIR/$MODULE"
    mkdir -p "$MODULE_BUILD"

    echo "  📱 iOS..."
    xcodebuild build \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination "generic/platform=iOS" \
        -derivedDataPath "$MODULE_BUILD/ios" \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        SKIP_INSTALL=NO \
        -quiet 2>&1 | grep -E "^error:" || true

    echo "  📱 iOS Simulator..."
    xcodebuild build \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination "generic/platform=iOS Simulator" \
        -derivedDataPath "$MODULE_BUILD/ios-sim" \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        SKIP_INSTALL=NO \
        -quiet 2>&1 | grep -E "^error:" || true

    echo "  💻 macOS..."
    xcodebuild build \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination "generic/platform=macOS" \
        -derivedDataPath "$MODULE_BUILD/macos" \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        SKIP_INSTALL=NO \
        -quiet 2>&1 | grep -E "^error:" || true

    # Find frameworks
    local IOS_FW=$(find "$MODULE_BUILD/ios" -path "*Release-iphoneos*PackageFrameworks*" -name "${SCHEME}.framework" -type d 2>/dev/null | head -1)
    local IOS_SIM_FW=$(find "$MODULE_BUILD/ios-sim" -path "*Release-iphonesimulator*PackageFrameworks*" -name "${SCHEME}.framework" -type d 2>/dev/null | head -1)
    local MACOS_FW=$(find "$MODULE_BUILD/macos" -path "*Release*PackageFrameworks*" -name "${SCHEME}.framework" -type d 2>/dev/null | head -1)

    # Fallback to Debug
    [ -z "$IOS_FW" ] && IOS_FW=$(find "$MODULE_BUILD/ios" -path "*Debug-iphoneos*PackageFrameworks*" -name "${SCHEME}.framework" -type d 2>/dev/null | head -1)
    [ -z "$IOS_SIM_FW" ] && IOS_SIM_FW=$(find "$MODULE_BUILD/ios-sim" -path "*Debug-iphonesimulator*PackageFrameworks*" -name "${SCHEME}.framework" -type d 2>/dev/null | head -1)
    [ -z "$MACOS_FW" ] && MACOS_FW=$(find "$MODULE_BUILD/macos" -path "*Debug*PackageFrameworks*" -name "${SCHEME}.framework" -type d 2>/dev/null | head -1)

    # Rename frameworks from ${SCHEME}.framework to ${MODULE}.framework
    echo "  🔄 Renaming frameworks..."

    # Cross-platform sed in-place edit
    sed_inplace() {
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "$@"
        else
            sed -i "$@"
        fi
    }

    # PlistBuddy helper with Set/Add fallback
    plist_set() {
        local KEY=$1
        local VALUE=$2
        local PLIST=$3
        /usr/libexec/PlistBuddy -c "Set :${KEY} ${VALUE}" "$PLIST" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add :${KEY} string ${VALUE}" "$PLIST" 2>/dev/null || \
        echo "    ⚠️ Warning: Failed to set ${KEY} in Info.plist"
    }

    rename_framework() {
        local FW_PATH=$1
        if [ -z "$FW_PATH" ] || [ ! -d "$FW_PATH" ]; then
            return 0
        fi

        local FW_DIR=$(dirname "$FW_PATH")
        local NEW_FW_PATH="$FW_DIR/${MODULE}.framework"

        # Rename framework directory
        if ! mv "$FW_PATH" "$NEW_FW_PATH" 2>/dev/null; then
            echo "    ❌ Error: Failed to rename framework directory"
            return 1
        fi

        # Update modulemap (if exists)
        local MODULEMAP="$NEW_FW_PATH/Modules/module.modulemap"
        if [ -f "$MODULEMAP" ]; then
            sed_inplace "s/framework module ${SCHEME}/framework module ${MODULE}/g; s/${SCHEME}.h/${MODULE}.h/g" "$MODULEMAP"
        fi

        # Rename umbrella header (if exists)
        local OLD_HEADER="$NEW_FW_PATH/Headers/${SCHEME}.h"
        local NEW_HEADER="$NEW_FW_PATH/Headers/${MODULE}.h"
        if [ -f "$OLD_HEADER" ]; then
            if ! mv "$OLD_HEADER" "$NEW_HEADER" 2>/dev/null; then
                echo "    ⚠️ Warning: Failed to rename umbrella header"
            fi
        fi

        # Update Info.plist bundle name
        local PLIST="$NEW_FW_PATH/Info.plist"
        if [ -f "$PLIST" ]; then
            plist_set "CFBundleName" "${MODULE}" "$PLIST"
            plist_set "CFBundleExecutable" "${MODULE}" "$PLIST"
        fi

        # Rename binary (if exists)
        local OLD_BINARY="$NEW_FW_PATH/${SCHEME}"
        local NEW_BINARY="$NEW_FW_PATH/${MODULE}"
        if [ -f "$OLD_BINARY" ]; then
            if ! mv "$OLD_BINARY" "$NEW_BINARY" 2>/dev/null; then
                echo "    ❌ Error: Failed to rename binary"
                return 1
            fi
        fi

        echo "$NEW_FW_PATH"
    }

    IOS_FW=$(rename_framework "$IOS_FW")
    IOS_SIM_FW=$(rename_framework "$IOS_SIM_FW")
    MACOS_FW=$(rename_framework "$MACOS_FW")

    # Build XCFramework
    local ARGS=""
    [ -n "$IOS_FW" ] && [ -d "$IOS_FW" ] && ARGS="$ARGS -framework $IOS_FW"
    [ -n "$IOS_SIM_FW" ] && [ -d "$IOS_SIM_FW" ] && ARGS="$ARGS -framework $IOS_SIM_FW"
    [ -n "$MACOS_FW" ] && [ -d "$MACOS_FW" ] && ARGS="$ARGS -framework $MACOS_FW"

    if [ -n "$ARGS" ]; then
        echo "  📦 Creating XCFramework..."
        xcodebuild -create-xcframework $ARGS -output "$OUTPUT_DIR/${MODULE}.xcframework" 2>/dev/null

        echo "  🗜️ Creating ZIP..."
        cd "$OUTPUT_DIR"
        zip -r -q "${MODULE}.xcframework.zip" "${MODULE}.xcframework"
        cd - > /dev/null

        local CHECKSUM=$(swift package compute-checksum "$OUTPUT_DIR/${MODULE}.xcframework.zip")

        echo "  ✅ $MODULE complete"
        echo "     Checksum: $CHECKSUM"
    else
        echo "  ❌ $MODULE failed - no frameworks found"
    fi
}

# Build each module
for MODULE in "${MODULES[@]}"; do
    build_module "$MODULE"
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Build Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📍 Output: $OUTPUT_DIR/"
echo ""
ls -lh "$OUTPUT_DIR"/*.xcframework.zip 2>/dev/null || echo "No ZIP files created"
echo ""
echo "📝 Checksums for Package.swift:"
echo ""
for zip in "$OUTPUT_DIR"/*.xcframework.zip; do
    if [ -f "$zip" ]; then
        NAME=$(basename "$zip" .xcframework.zip)
        CHECKSUM=$(swift package compute-checksum "$zip")
        echo ".binaryTarget("
        echo "    name: \"$NAME\","
        echo "    url: \"https://github.com/hakaru/MIDI2Kit/releases/download/v1.0.0/$NAME.xcframework.zip\","
        echo "    checksum: \"$CHECKSUM\""
        echo "),"
        echo ""
    fi
done
