# Claudometer

> Track your Claude.ai usage limits right from your Mac menu bar.

Claudometer is a lightweight macOS menu-bar app that shows your Claude.ai
**session (5-hour)** and **weekly (7-day)** usage limits at a glance, with a
color-coded icon and threshold notifications. No Dock icon, no clutter — it
just lives in your menu bar.

## Features

- ⚡ **Live usage** — session (5-hour) and weekly (7-day) utilization with reset times and a countdown to reset
- 📊 **Pro plan support** — shows the weekly Sonnet limit when your account has one
- 🎨 **Color-coded icon** — green / yellow / red; choose whether it tracks your session, weekly, or highest usage
- 🔔 **Threshold alerts** — optional notifications at configurable thresholds (25 / 50 / 75 / 90 / 95%)
- 🔄 **Smart refresh** — configurable poll interval that automatically tightens as you near a limit
- ⌨️ **Global shortcut** — toggle the popover with ⌘U from anywhere (no Accessibility permission needed)
- 🔒 **Secure & local** — your session is stored in the macOS Keychain and only ever sent to claude.ai
- 🎯 **Menu-bar only** — stays out of your way; optional launch at login

## Signing in

Claudometer reads your usage from claude.ai using your logged-in session — there's
**no cookie copy-pasting**. Just sign in once, in-app:

1. Click the menu-bar icon → **Sign in to Claude**.
2. A sign-in window opens to claude.ai. Log in normally — **email/password or Google sign-in both work**.
3. The window closes automatically and your usage appears.

When a session expires, the popover shows **"Sign in again"** — one click re-authenticates.
**Sign out** clears the stored session from the Keychain.

## Build from source

**Requirements:** macOS 13 (Ventura)+ and the Xcode Command Line Tools.

```bash
cd app
./build.sh
```

The built app is `app/build/Claudometer.app`.

> `build.sh` signs with a Developer ID certificate for distribution. To run a
> local build without that certificate, ad-hoc sign it first:
> `codesign --force --deep --sign - app/build/Claudometer.app` then `open` it.

### Signing & notarizing your own build

The build scripts read your identity from environment variables, so you can sign
and ship your own build under your own Apple account without editing any source:

| Variable | Used for | Default |
|----------|----------|---------|
| `CLAUDOMETER_SIGN_ID` | `Developer ID Application: …` identity | `Chris Howe (Z8C4HC36L6)` |
| `CLAUDOMETER_BUNDLE_ID` | overrides `CFBundleIdentifier` (the Keychain item tracks it automatically) | `com.claudometer.app` |
| `CLAUDOMETER_NOTARY_PROFILE` | `notarytool` keychain-profile name | `claudometer-notary` |
| `CLAUDOMETER_TEAM_ID` | your 10-char Apple team id | — |

Find your identity with `security find-identity -v -p codesigning`, then build:

```bash
cd app
CLAUDOMETER_SIGN_ID="Developer ID Application: Your Name (TEAMID)" ./build.sh
```

To produce a **notarized, stapled DMG** installer, first store notary credentials
once (use an app-specific password from appleid.apple.com):

```bash
xcrun notarytool store-credentials "my-notary-profile" \
  --apple-id "you@example.com" --team-id "TEAMID" \
  --password "<app-specific-password>"
```

then:

```bash
CLAUDOMETER_SIGN_ID="Developer ID Application: Your Name (TEAMID)" \
CLAUDOMETER_NOTARY_PROFILE="my-notary-profile" \
CLAUDOMETER_TEAM_ID="TEAMID" \
./create_dmg.sh
```

This signs the app (Hardened Runtime + secure timestamp), builds
`Claudometer-<version>.dmg`, submits it to Apple, and staples the notarization
ticket to the DMG. (The app dragged out of the DMG is notarized too — Gatekeeper
clears it via an online check on first launch, standard for DMG distribution.)

## Privacy

- Your claude.ai session cookie is stored in the **macOS Keychain**, never in plaintext.
- Usage data is fetched directly from claude.ai and kept on your Mac. There is no server, analytics, or third party.

## Disclaimer

Claudometer uses claude.ai's internal API endpoints, which may change without
notice. It is not affiliated with or endorsed by Anthropic. Use at your own risk.

## License

MIT — see [LICENSE](LICENSE).
