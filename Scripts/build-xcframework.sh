#!/bin/bash
#
# build-xcframework.sh
# Builds XCFrameworks for MIDI2Kit modules with Swift module support
#
# Usage:
#   ./Scripts/build-xcframework.sh          # Build all modules
#   ./Scripts/build-xcframework.sh MIDI2Core # Build single module
#
# Note: SPM with BUILD_LIBRARY_FOR_DISTRIBUTION=YES generates frameworks
# with complete Modules/ directory containing swiftmodule and swiftinterface
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

# Use /tmp to avoid iCloud sync issues
BUILD_DIR="/tmp/midi2kit-build"
OUTPUT_DIR="$(pwd)/dist"

echo "🧹 Cleaning..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# Function to build a single module
build_module() {
    local MODULE=$1
    local SCHEME="${MODULE}Dynamic"
    # Special case: MIDI2ClientDynamic target is MIDI2Kit, not MIDI2Client
    local TARGET_NAME="${MODULE}"
    if [ "$MODULE" = "MIDI2Client" ]; then
        TARGET_NAME="MIDI2Kit"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 Building $MODULE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local MODULE_BUILD="$BUILD_DIR/$MODULE"
    mkdir -p "$MODULE_BUILD"

    # Build for iOS Device
    echo "  📱 iOS Device..."
    xcodebuild build \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination "generic/platform=iOS" \
        -derivedDataPath "$MODULE_BUILD/ios" \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        SKIP_INSTALL=NO \
        -quiet 2>&1 | grep -E "^error:" || true

    # Build for iOS Simulator
    echo "  📱 iOS Simulator..."
    xcodebuild build \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination "generic/platform=iOS Simulator" \
        -derivedDataPath "$MODULE_BUILD/ios-sim" \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        SKIP_INSTALL=NO \
        -quiet 2>&1 | grep -E "^error:" || true

    # Build for macOS
    echo "  💻 macOS..."
    xcodebuild build \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination "generic/platform=macOS" \
        -derivedDataPath "$MODULE_BUILD/macos" \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        SKIP_INSTALL=NO \
        -quiet 2>&1 | grep -E "^error:" || true

    # Find frameworks - SPM generates SCHEME.framework (e.g., MIDI2CoreDynamic.framework)
    local IOS_FW=$(find "$MODULE_BUILD/ios" -path "*Release-iphoneos*PackageFrameworks*" -name "${SCHEME}.framework" -type d 2>/dev/null | head -1)
    local IOS_SIM_FW=$(find "$MODULE_BUILD/ios-sim" -path "*Release-iphonesimulator*PackageFrameworks*" -name "${SCHEME}.framework" -type d 2>/dev/null | head -1)
    local MACOS_FW=$(find "$MODULE_BUILD/macos" -path "*Release*PackageFrameworks*" -name "${SCHEME}.framework" -type d 2>/dev/null | head -1)

    # Find swiftmodule directories (generated alongside but not inside the framework)
    # Use TARGET_NAME because the swiftmodule is named after the target, not the module
    local IOS_SWIFTMODULE=$(find "$MODULE_BUILD/ios" -path "*Release-iphoneos*" -name "${TARGET_NAME}.swiftmodule" -type d 2>/dev/null | grep "Build/Products" | head -1)
    local IOS_SIM_SWIFTMODULE=$(find "$MODULE_BUILD/ios-sim" -path "*Release-iphonesimulator*" -name "${TARGET_NAME}.swiftmodule" -type d 2>/dev/null | grep "Build/Products" | head -1)
    local MACOS_SWIFTMODULE=$(find "$MODULE_BUILD/macos" -path "*Release*" -name "${TARGET_NAME}.swiftmodule" -type d 2>/dev/null | grep "Build/Products" | head -1)

    # Debug output
    echo "  🔍 Found frameworks:"
    [ -n "$IOS_FW" ] && echo "    📱 iOS: $IOS_FW" || echo "    📱 iOS: NOT FOUND"
    [ -n "$IOS_SIM_FW" ] && echo "    📱 iOS Sim: $IOS_SIM_FW" || echo "    📱 iOS Sim: NOT FOUND"
    [ -n "$MACOS_FW" ] && echo "    💻 macOS: $MACOS_FW" || echo "    💻 macOS: NOT FOUND"

    # Add Modules directory to frameworks
    echo "  📋 Adding Swift modules..."
    add_modules_to_framework() {
        local FW=$1
        local SWIFTMODULE=$2

        if [ -z "$FW" ] || [ ! -d "$FW" ]; then
            return 0
        fi

        # Create Modules directory
        mkdir -p "$FW/Modules/${MODULE}.swiftmodule"

        # Copy swiftmodule files
        if [ -n "$SWIFTMODULE" ] && [ -d "$SWIFTMODULE" ]; then
            cp -R "$SWIFTMODULE"/* "$FW/Modules/${MODULE}.swiftmodule/" 2>/dev/null || true
        fi

        # Create module.modulemap
        cat > "$FW/Modules/module.modulemap" << MODULEMAP
framework module ${MODULE} {
    header "${MODULE}.h"
    export *
}
MODULEMAP

        # Create umbrella header
        mkdir -p "$FW/Headers"
        cat > "$FW/Headers/${MODULE}.h" << HEADER
// ${MODULE} umbrella header
// Auto-generated for XCFramework distribution
HEADER

        # Rename binary if needed
        if [ -f "$FW/${SCHEME}" ] && [ ! -f "$FW/${MODULE}" ]; then
            mv "$FW/${SCHEME}" "$FW/${MODULE}"
        fi

        # Update Info.plist
        if [ -f "$FW/Info.plist" ]; then
            /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${MODULE}" "$FW/Info.plist" 2>/dev/null || true
            /usr/libexec/PlistBuddy -c "Set :CFBundleName ${MODULE}" "$FW/Info.plist" 2>/dev/null || true
        fi
    }

    add_modules_to_framework "$IOS_FW" "$IOS_SWIFTMODULE"
    add_modules_to_framework "$IOS_SIM_FW" "$IOS_SIM_SWIFTMODULE"
    add_modules_to_framework "$MACOS_FW" "$MACOS_SWIFTMODULE"

    # Rename framework directories
    echo "  🔄 Renaming frameworks..."
    rename_framework_dir() {
        local OLD_FW=$1
        if [ -z "$OLD_FW" ] || [ ! -d "$OLD_FW" ]; then
            return
        fi
        local FW_DIR=$(dirname "$OLD_FW")
        local NEW_FW="$FW_DIR/${MODULE}.framework"
        if [ "$OLD_FW" != "$NEW_FW" ]; then
            mv "$OLD_FW" "$NEW_FW" 2>/dev/null || true
            echo "$NEW_FW"
        else
            echo "$OLD_FW"
        fi
    }

    IOS_FW=$(rename_framework_dir "$IOS_FW")
    IOS_SIM_FW=$(rename_framework_dir "$IOS_SIM_FW")
    MACOS_FW=$(rename_framework_dir "$MACOS_FW")

    # Verify Modules directory
    echo "  🔍 Verifying Modules..."
    for FW in "$IOS_FW" "$IOS_SIM_FW" "$MACOS_FW"; do
        if [ -n "$FW" ] && [ -d "$FW" ]; then
            if [ -d "$FW/Modules" ]; then
                local SWIFTMODULE_COUNT=$(find "$FW/Modules" -name "*.swiftinterface" 2>/dev/null | wc -l | tr -d ' ')
                echo "    ✅ $(basename $(dirname $(dirname $FW))): Modules/ (${SWIFTMODULE_COUNT} swiftinterface files)"
            else
                echo "    ⚠️ $(basename $(dirname $(dirname $FW))): Modules/ MISSING"
            fi
        fi
    done

    # Build XCFramework
    local ARGS=""
    [ -n "$IOS_FW" ] && [ -d "$IOS_FW" ] && ARGS="$ARGS -framework $IOS_FW"
    [ -n "$IOS_SIM_FW" ] && [ -d "$IOS_SIM_FW" ] && ARGS="$ARGS -framework $IOS_SIM_FW"
    [ -n "$MACOS_FW" ] && [ -d "$MACOS_FW" ] && ARGS="$ARGS -framework $MACOS_FW"

    if [ -n "$ARGS" ]; then
        echo "  📦 Creating XCFramework..."
        rm -rf "$OUTPUT_DIR/${MODULE}.xcframework"
        xcodebuild -create-xcframework $ARGS -output "$OUTPUT_DIR/${MODULE}.xcframework" 2>/dev/null

        echo "  🗜️ Creating ZIP..."
        rm -f "$OUTPUT_DIR/${MODULE}.xcframework.zip"
        cd "$OUTPUT_DIR"
        zip -r -q "${MODULE}.xcframework.zip" "${MODULE}.xcframework"
        cd - > /dev/null

        local CHECKSUM=$(swift package compute-checksum "$OUTPUT_DIR/${MODULE}.xcframework.zip")

        echo "  ✅ $MODULE complete"
        echo "     Checksum: $CHECKSUM"
    else
        echo "  ❌ $MODULE failed - no frameworks found"
        echo "     Please verify the scheme '${SCHEME}' exists and builds correctly"
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
        echo "    url: \"https://github.com/midi2kit/MIDI2Kit-SDK/releases/download/v1.0.0/$NAME.xcframework.zip\","
        echo "    checksum: \"$CHECKSUM\""
        echo "),"
        echo ""
    fi
done
