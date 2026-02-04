#!/bin/bash
#
# build-xcframework.sh
# Builds XCFramework for MIDI2Kit
#

set -e

SCHEME="MIDI2KitDynamic"
OUTPUT_NAME="MIDI2Kit"
BUILD_DIR="$(pwd)/build"
OUTPUT_DIR="$(pwd)/dist"

echo "🧹 Cleaning..."
rm -rf "$BUILD_DIR" "$OUTPUT_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

echo ""
echo "📱 Building iOS (Release)..."
xcodebuild build \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$BUILD_DIR/ios" \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    SKIP_INSTALL=NO \
    -quiet 2>&1 | grep -E "error:|BUILD" || true

echo "📱 Building iOS Simulator (Release)..."
xcodebuild build \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "$BUILD_DIR/ios-sim" \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    SKIP_INSTALL=NO \
    -quiet 2>&1 | grep -E "error:|BUILD" || true

echo "💻 Building macOS (Release)..."
xcodebuild build \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$BUILD_DIR/macos" \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    SKIP_INSTALL=NO \
    -quiet 2>&1 | grep -E "error:|BUILD" || true

echo ""
echo "🔍 Finding frameworks..."

# Find the built frameworks (they're named MIDI2KitDynamic.framework in PackageFrameworks)
IOS_FW=$(find "$BUILD_DIR/ios" -path "*Release-iphoneos*PackageFrameworks*" -name "${SCHEME}.framework" -type d 2>/dev/null | head -1)
IOS_SIM_FW=$(find "$BUILD_DIR/ios-sim" -path "*Release-iphonesimulator*PackageFrameworks*" -name "${SCHEME}.framework" -type d 2>/dev/null | head -1)
MACOS_FW=$(find "$BUILD_DIR/macos" -path "*Release*PackageFrameworks*" -name "${SCHEME}.framework" -type d 2>/dev/null | head -1)

# Fallback to Debug if Release not found
[ -z "$IOS_FW" ] && IOS_FW=$(find "$BUILD_DIR/ios" -path "*Debug-iphoneos*PackageFrameworks*" -name "${SCHEME}.framework" -type d 2>/dev/null | head -1)
[ -z "$IOS_SIM_FW" ] && IOS_SIM_FW=$(find "$BUILD_DIR/ios-sim" -path "*Debug-iphonesimulator*PackageFrameworks*" -name "${SCHEME}.framework" -type d 2>/dev/null | head -1)
[ -z "$MACOS_FW" ] && MACOS_FW=$(find "$BUILD_DIR/macos" -path "*Debug*PackageFrameworks*" -name "${SCHEME}.framework" -type d 2>/dev/null | head -1)

echo "iOS: $IOS_FW"
echo "iOS Sim: $IOS_SIM_FW"
echo "macOS: $MACOS_FW"

# Build XCFramework
ARGS=""
[ -n "$IOS_FW" ] && [ -d "$IOS_FW" ] && ARGS="$ARGS -framework $IOS_FW"
[ -n "$IOS_SIM_FW" ] && [ -d "$IOS_SIM_FW" ] && ARGS="$ARGS -framework $IOS_SIM_FW"
[ -n "$MACOS_FW" ] && [ -d "$MACOS_FW" ] && ARGS="$ARGS -framework $MACOS_FW"

if [ -n "$ARGS" ]; then
    echo ""
    echo "📦 Creating XCFramework..."
    xcodebuild -create-xcframework $ARGS -output "$OUTPUT_DIR/${SCHEME}.xcframework"

    # Rename to MIDI2Kit if needed
    if [ "$SCHEME" != "$OUTPUT_NAME" ]; then
        mv "$OUTPUT_DIR/${SCHEME}.xcframework" "$OUTPUT_DIR/${OUTPUT_NAME}.xcframework"
    fi

    echo "🗜️ Creating ZIP..."
    cd "$OUTPUT_DIR"
    zip -r -q "${OUTPUT_NAME}.xcframework.zip" "${OUTPUT_NAME}.xcframework"

    CHECKSUM=$(swift package compute-checksum "${OUTPUT_NAME}.xcframework.zip")

    echo ""
    echo "✅ Success!"
    echo ""
    echo "📍 XCFramework: $OUTPUT_DIR/${OUTPUT_NAME}.xcframework"
    echo "📦 ZIP: $OUTPUT_DIR/${OUTPUT_NAME}.xcframework.zip"
    echo "🔐 Checksum: $CHECKSUM"
    echo ""
    echo "📝 To distribute, add to Package.swift:"
    echo ""
    echo ".binaryTarget("
    echo "    name: \"${OUTPUT_NAME}\","
    echo "    url: \"https://your-server.com/${OUTPUT_NAME}.xcframework.zip\","
    echo "    checksum: \"$CHECKSUM\""
    echo ")"
else
    echo ""
    echo "❌ No frameworks found."
    echo ""
    echo "Build artifacts:"
    find "$BUILD_DIR" -name "*.framework" -type d 2>/dev/null | head -10
fi
