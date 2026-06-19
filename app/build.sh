#!/bin/bash

# Build script for Claudometer

echo "Building Claudometer..."

# Create fresh build directory (delete any stale build to avoid accumulated xattrs
# from prior signs, which can cause "resource fork / detritus" errors on codesign).
rm -rf build
mkdir -p build

# Create app bundle structure first
APP_NAME="Claudometer.app"
APP_PATH="build/$APP_NAME"

mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# Copy Info.plist
cp Info.plist "$APP_PATH/Contents/"

# Override the bundle identifier for a custom build. CookieStore reads the
# bundle id at runtime for its Keychain service, so this stays in sync automatically.
#   CLAUDOMETER_BUNDLE_ID="com.example.claudometer" ./build.sh
if [ -n "$CLAUDOMETER_BUNDLE_ID" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $CLAUDOMETER_BUNDLE_ID" "$APP_PATH/Contents/Info.plist"
    echo "ℹ️  Bundle identifier set to $CLAUDOMETER_BUNDLE_ID"
fi

# Create icon if it doesn't exist
if [ ! -f "Claudometer.icns" ]; then
    echo "Creating app icon..."
    ./make_app_icon.sh >/dev/null 2>&1
fi

# Copy icon to Resources
if [ -f "Claudometer.icns" ]; then
    cp Claudometer.icns "$APP_PATH/Contents/Resources/"
    # Update Info.plist to reference icon
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Claudometer" "$APP_PATH/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile Claudometer" "$APP_PATH/Contents/Info.plist"
fi

# The app is split across multiple Swift files — compile them all together.
SWIFT_SOURCES=(*.swift)

# Compile the Swift app for arm64
swiftc -parse-as-library -o "$APP_PATH/Contents/MacOS/Claudometer_arm64" \
    "${SWIFT_SOURCES[@]}" \
    -framework SwiftUI \
    -framework AppKit \
    -framework WebKit \
    -target arm64-apple-macos13.0

# Compile for x86_64 (Intel)
swiftc -parse-as-library -o "$APP_PATH/Contents/MacOS/Claudometer_x86_64" \
    "${SWIFT_SOURCES[@]}" \
    -framework SwiftUI \
    -framework AppKit \
    -framework WebKit \
    -target x86_64-apple-macos13.0

# Create universal binary
lipo -create -output "$APP_PATH/Contents/MacOS/Claudometer" \
    "$APP_PATH/Contents/MacOS/Claudometer_arm64" \
    "$APP_PATH/Contents/MacOS/Claudometer_x86_64"

# Clean up individual arch binaries
rm "$APP_PATH/Contents/MacOS/Claudometer_arm64"
rm "$APP_PATH/Contents/MacOS/Claudometer_x86_64"

# Create PkgInfo file
echo -n "APPL????" > "$APP_PATH/Contents/PkgInfo"

# Set proper permissions first
chmod 755 "$APP_PATH/Contents/MacOS/Claudometer"

# Clean any "detritus" that codesign rejects: extended attributes, ._files, .DS_Store
xattr -cr "$APP_PATH"
find "$APP_PATH" -name '._*' -delete 2>/dev/null
find "$APP_PATH" -name '.DS_Store' -delete 2>/dev/null
dot_clean "$APP_PATH" 2>/dev/null

# Sign with Developer ID certificate. NEVER silently fall back to ad-hoc — that
# fails notarization later. If real signing fails, error out loudly.
# Override with your own identity via the CLAUDOMETER_SIGN_ID env var, e.g.
#   CLAUDOMETER_SIGN_ID="Developer ID Application: Your Name (TEAMID)" ./build.sh
# Run `security find-identity -v -p codesigning` to see your installed identities.
DEVELOPER_ID="${CLAUDOMETER_SIGN_ID:-Developer ID Application: Chris Howe (Z8C4HC36L6)}"
# --options runtime (Hardened Runtime) and --timestamp (secure timestamp) are
# BOTH required for the app to pass Apple notarization. --deep is intentionally
# omitted: Apple advises against it for distribution, and this bundle has no
# nested code (single Mach-O executable) so signing the bundle is sufficient.
if codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP_PATH"; then
    echo "✅ App signed with Developer ID"
    if codesign --verify --verbose=2 "$APP_PATH" 2>&1 | grep -q "valid on disk"; then
        echo "✅ Signature verified"
    else
        echo "❌ Signature verification failed — fix before shipping" >&2
        exit 1
    fi
else
    echo "❌ Developer ID signing failed. NOT falling back to ad-hoc (would break notarization)." >&2
    echo "   Fix the cause above (often: stale xattrs / ._files / cert not in keychain) and re-run." >&2
    exit 1
fi

echo "Build successful!"
echo "App bundle created at: $APP_PATH"
echo "Launching app..."
open "$APP_PATH"
