# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Claudometer is a macOS **menu-bar-only** (`LSUIElement`) app that displays your
claude.ai usage limits. It reads usage by calling claude.ai's **private,
undocumented web API** (`/api/organizations/{org}/usage`, `/api/bootstrap`) using
the logged-in session cookie. There is no public API and no backend — everything
runs locally on the user's Mac.

This data source is why the app ships via **Developer ID + notarized DMG**, not
the Mac App Store (App Review rejects unofficial-API wrappers). Keep that
constraint in mind: don't propose App Store distribution or a sandbox rewrite
without flagging the private-API blocker.

## Project layout

There is **no Xcode project and no Swift Package Manager** — the app is a flat
set of `.swift` files in `app/` compiled directly with `swiftc`. Adding a new
source file requires no project edit; `build.sh` globs `*.swift`. Targets macOS
**13+** (SMAppService and the modern APIs require it).

## Build & run

All commands run from `app/`.

```bash
# Fast typecheck / dev loop (arm64 only, no signing) — use this while iterating:
swiftc *.swift -target arm64-apple-macos13.0 \
  -framework SwiftUI -framework AppKit -framework WebKit -o /tmp/cm

# Full universal build + Developer ID sign + launch (needs the cert in keychain):
./build.sh

# Local build WITHOUT the Developer ID cert — build.sh refuses to ad-hoc sign,
# so build it yourself and ad-hoc sign to run locally:
codesign --force --deep --sign - build/Claudometer.app && open build/Claudometer.app

# Notarized, stapled DMG for distribution (needs cert + notarytool profile):
./create_dmg.sh
```

`build.sh` **never falls back to ad-hoc signing** (it would break notarization)
— if the Developer ID identity isn't in the keychain it errors out and exits.

There is **no test suite**. Verification is manual: build the `.app`, launch it,
and exercise the popover/settings. A live claude.ai session cookie is required
to test the fetch/parse path at all.

### Signing & distribution config

`build.sh` and `create_dmg.sh` read these env vars (each falls back to the
project's default signing values), so a different machine can sign/ship without
editing source:

- `CLAUDOMETER_SIGN_ID` — `Developer ID Application: …` identity
- `CLAUDOMETER_BUNDLE_ID` — overrides `CFBundleIdentifier` at build time
- `CLAUDOMETER_NOTARY_PROFILE` / `CLAUDOMETER_TEAM_ID` — for `create_dmg.sh`

The app signature **must** carry Hardened Runtime (`--options runtime`) and a
secure `--timestamp` or notarization fails — both are in `build.sh`. `--deep` is
intentionally omitted (the bundle has no nested code).

## Architecture

The app is split by concern. The dependency flow is: `AppDelegate` (coordinator)
→ `UsageManager` (state) → everything else.

- **`AppDelegate.swift`** — `@main` entry + app lifecycle coordinator. Owns the
  status item, popover, the self-rescheduling refresh timer, and wires the other
  controllers together. Rendering and the hotkey live in their own controllers.
- **`UsageManager.swift`** — the `@MainActor` `ObservableObject` that is the
  single source of truth for the UI and menu-bar icon. Orchestrates the API
  client, settings, notifications, login item, and Keychain. It does **not** do
  networking/parsing/persistence itself — it delegates. All `@Published`
  mutations must stay on the main thread (hence `@MainActor`).
- **`ClaudeAPIClient.swift`** — all networking + parsing. Resolves the org id
  (from the cookie, falling back to `/api/bootstrap`), fetches usage, retries
  transient failures with backoff, and distinguishes offline vs. auth-expired
  (401/403) vs. other errors via `APIError`.
- **`UsageModels.swift`** — Codable wire DTOs (every field optional — the private
  API "may change without notice", so a missing key degrades gracefully instead
  of throwing), domain models, `APIError`, and a lenient ISO8601 parser.
- **`SettingsStore.swift`** — all UserDefaults persistence, including two one-time
  migrations (legacy notifications key; legacy plaintext cookie → Keychain) and
  the cached usage snapshot for instant render on launch.
- **`CookieStore.swift`** — session cookie in the Keychain. Its service name is
  derived from `Bundle.main.bundleIdentifier`, so it stays in sync with
  `CLAUDOMETER_BUNDLE_ID` automatically — changing the bundle id moves the
  Keychain item, which is why rebuilding under a new bundle id starts with a
  fresh login.
- **`LoginWindowController.swift`** — in-app sign-in via `WKWebView`. Loads
  claude.ai, captures the full cookie header the moment `sessionKey` appears.
  Presents as desktop Safari and routes SSO popups into child windows so
  Google/Apple SSO work inside an embedded web view.
- **`NotificationService.swift`** — `UNUserNotificationCenter` wrapper (requests
  auth at launch; delivery silently no-ops without a signed bundle + grant).
- **`StatusItemController.swift`** — draws the colored spark icon + percentage.
  The icon is deliberately **not** a template image: its green/yellow/red color
  *is* the status signal, so it must not adapt to the menu-bar appearance.
- **`HotKeyManager.swift`** — global ⌘U via Carbon `RegisterEventHotKey` (no
  Accessibility permission needed). Installs the event handler and hot key
  together and tears both down on disable (don't reintroduce the handler leak).
- **`LoginItem.swift`** — launch-at-login via `SMAppService.mainApp`; reads back
  real system status rather than caching a bool.

### Things that look like bugs but aren't

- The status icon stays alive even if the SwiftUI popover faults — "process
  running" does not prove the UI renders. Verify the popover by opening it.
- `build.sh` ends by launching the app (`open`), even during a release build.
