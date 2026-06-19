#!/bin/bash

APP_NAME="Claudometer"
APP_PATH="build/${APP_NAME}.app"

# ---------- Preflight ----------
# Fail fast with a clear message rather than dying minutes into notarization.
if [ ! -d "$APP_PATH" ]; then
    echo "❌ $APP_PATH not found. Run ./build.sh first." >&2
    exit 1
fi

# The app must already be Developer-ID signed (not ad-hoc) or the notary service
# will reject it. Capture into a variable rather than piping into `grep -q`:
# grep closing the pipe early can SIGPIPE codesign, which (under pipefail) would
# falsely fail this check.
SIG_INFO=$(codesign -dvv "$APP_PATH" 2>&1)
if ! grep -q "Authority=Developer ID Application" <<< "$SIG_INFO"; then
    echo "❌ $APP_PATH is not signed with a Developer ID Application certificate." >&2
    echo "   Re-run: CLAUDOMETER_SIGN_ID=\"Developer ID Application: …\" ./build.sh" >&2
    exit 1
fi

# Version comes from the built bundle so the DMG name always tracks the app.
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "0.0")
DMG_NAME="${APP_NAME}-${VERSION}"

# Create a temporary directory for DMG contents
TMP_DIR="dmg_temp"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# Copy the app
cp -R "$APP_PATH" "$TMP_DIR/"

# Strip all extended attributes (including quarantine)
xattr -cr "$TMP_DIR/${APP_NAME}.app"

# Create symbolic link to Applications folder
ln -s /Applications "$TMP_DIR/Applications"

# Create a background image (optional - we'll use text instead)
mkdir -p "$TMP_DIR/.background"

# Set custom icon positions and window size using AppleScript
cat > /tmp/dmg_setup.applescript << 'APPLESCRIPT'
tell application "Finder"
    tell disk "DISK_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 600, 400}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set position of item "APP_NAME.app" of container window to {150, 150}
        set position of item "Applications" of container window to {350, 150}
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

# Detach any stale Claudometer volumes left mounted by a previous/failed run —
# otherwise the volume-name collision makes `hdiutil convert` fail with
# "Resource temporarily unavailable".
for v in /Volumes/"$APP_NAME" /Volumes/"$APP_NAME"\ *; do
    [ -d "$v" ] && hdiutil detach "$v" -force 2>/dev/null
done
rm -f temp.dmg

# Create temporary DMG
hdiutil create -volname "${APP_NAME}" -srcfolder "$TMP_DIR" -ov -format UDRW temp.dmg

# Mount it (-nobrowse so it doesn't pop in Finder). Capture the device node and
# mount point robustly — the volume name can contain spaces, so awk '{print $3}'
# is wrong; detach by device node instead.
ATTACH_OUT=$(hdiutil attach -readwrite -noverify -nobrowse temp.dmg)
DEVICE=$(echo "$ATTACH_OUT" | awk '/^\/dev\/disk/ {print $1; exit}')
MOUNT_DIR=$(echo "$ATTACH_OUT" | grep '/Volumes/' | sed -E 's|^.*(/Volumes/.*)$|\1|')

# Run AppleScript to set up the window (best-effort cosmetic layout)
sed "s/DISK_NAME/${APP_NAME}/g; s/APP_NAME/${APP_NAME}/g" /tmp/dmg_setup.applescript > /tmp/dmg_setup_final.applescript
osascript /tmp/dmg_setup_final.applescript 2>/dev/null || echo "Note: DMG layout customization skipped"

# Unmount by device node (robust to spaces in the volume name)
hdiutil detach "$DEVICE" -force 2>/dev/null || hdiutil detach "$MOUNT_DIR" -force 2>/dev/null

# Convert to compressed final DMG — abort loudly if it fails (don't print a fake
# success and then trip over a missing file at the signing step).
rm -f "${DMG_NAME}.dmg"
if ! hdiutil convert temp.dmg -format UDZO -o "${DMG_NAME}.dmg"; then
    echo "❌ hdiutil convert failed — a stale mount or busy DMG is the usual cause." >&2
    rm -f temp.dmg
    rm -rf "$TMP_DIR"
    exit 1
fi

# Clean up
rm -f temp.dmg
rm -rf "$TMP_DIR"
rm -f /tmp/dmg_setup*.applescript

echo "✅ DMG created: ${DMG_NAME}.dmg"

# ---------- Sign + Notarize + Staple ----------
# Override these with env vars to sign/notarize under your own account:
#   CLAUDOMETER_SIGN_ID    — your "Developer ID Application: …" identity
#   CLAUDOMETER_NOTARY_PROFILE — your notarytool keychain-profile name
#   CLAUDOMETER_TEAM_ID    — your 10-char Apple team id (used in the help text)
DEVELOPER_ID="${CLAUDOMETER_SIGN_ID:-Developer ID Application: Chris Howe (Z8C4HC36L6)}"
NOTARY_PROFILE="${CLAUDOMETER_NOTARY_PROFILE:-claudometer-notary}"
TEAM_ID="${CLAUDOMETER_TEAM_ID:-Z8C4HC36L6}"

# Sign the DMG itself (the .app inside was already signed + hardened in build.sh).
echo ""
echo "🔏 Signing DMG with Developer ID..."
if codesign --force --timestamp --sign "$DEVELOPER_ID" "${DMG_NAME}.dmg"; then
    echo "✅ DMG signed"
else
    echo "❌ DMG signing failed — fix before notarizing." >&2
    exit 1
fi

# Notarize. Capture the output so we can (a) confirm Accepted and (b) pull the
# failure log by submission id if it's rejected.
echo ""
echo "📤 Submitting to Apple notary service (this can take 5–15 min)..."
SUBMIT_OUT=$(xcrun notarytool submit "${DMG_NAME}.dmg" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)
SUBMIT_STATUS=$?
echo "$SUBMIT_OUT"
SUBMISSION_ID=$(echo "$SUBMIT_OUT" | awk '/^[[:space:]]*id:/{print $2; exit}')

if [ $SUBMIT_STATUS -eq 0 ] && echo "$SUBMIT_OUT" | grep -q "status: Accepted"; then
    # Staple the ticket into the DMG (the artifact users download). The app
    # dragged out of it isn't separately stapled, but its code is notarized, so
    # Gatekeeper clears it via an online check on first launch — standard for
    # DMG-distributed apps. (For guaranteed offline first-launch you'd notarize
    # and staple the .app *before* packaging; not needed for normal download use.)
    echo "📎 Stapling notarization ticket to DMG..."
    if xcrun stapler staple "${DMG_NAME}.dmg"; then
        echo "✅ Notarized and stapled — ready to ship"
    else
        echo "⚠️  Stapling failed (DMG is notarized, but ticket not embedded — first launch must be online)"
    fi

    echo ""
    echo "🔎 Gatekeeper assessment:"
    spctl -a -t open --context context:primary-signature -v "${DMG_NAME}.dmg" 2>&1 || true
else
    echo ""
    echo "❌ Notarization failed."
    if [ -n "$SUBMISSION_ID" ]; then
        echo "   Notary log for submission $SUBMISSION_ID:"
        xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" 2>&1 || true
    fi
    echo ""
    echo "If you haven't set up notary credentials yet, run this once:"
    echo ""
    echo "  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
    echo "    --apple-id \"<your-apple-id-email>\" \\"
    echo "    --team-id \"$TEAM_ID\" \\"
    echo "    --password \"<app-specific-password from appleid.apple.com>\""
    echo ""
    echo "Then re-run this script."
    exit 1
fi

echo ""
echo "Users can now:"
echo "1. Download ${DMG_NAME}.dmg"
echo "2. Double-click to mount"
echo "3. Drag ${APP_NAME}.app to Applications folder"
echo "4. Eject the DMG"
echo "5. Open ${APP_NAME} from Applications!"
