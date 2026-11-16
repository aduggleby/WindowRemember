# WindowRemember

A native macOS 14+ window-memory utility inspired by [Putback](https://putback.app/remember-window-locations-mac/). Built with SwiftUI, AppKit, and Apple's Accessibility API; no external dependencies or network requests.

## Run

```sh
./scripts/build-app.sh
open dist/WindowRemember.app
```

Grant **System Settings → Privacy & Security → Accessibility → WindowRemember**. Use the packaged app so macOS has a stable bundle identity. After rebuilding, macOS may require toggling Accessibility permission again because the development build is ad-hoc signed.

Arrange your windows and allow three seconds for learning. Each display combination has a separate local layout. Reconnecting a known setup waits two seconds for displays to settle, then restores it. Use the menu bar panel or **Put windows back** for manual restore. **Shift–Command–R** works while the app is active.

- **Scenes:** named snapshots of currently open windows.
- **Display setups:** inspect saved arrangements and pin them to stop learning.
- **History:** restore counts, unavailable windows, and undo of the latest restore.
- **Settings:** pause learning, disable automatic restore, or exclude apps.

Data is stored atomically at `~/Library/Application Support/WindowRemember/layouts.json`. Window titles and app identifiers are stored locally; deleting this file resets the app. There is no telemetry.

## Scope

This is an independently implemented functional starting point, not Putback's source code or branding. It does not implement Scene Studio, wallpaper switching, launching closed apps, configurable global hotkeys, login startup, or licensing. Scenes apply to already-open apps and connected displays. Full-screen and minimized windows are excluded. Apps may reject Accessibility moves or constrain window sizes. Multi-Space behavior and physical dock reconnects require testing on your setup; Accessibility capture is limited by what each app exposes. No private Spaces APIs are used.

The build script produces an app for the current Mac architecture. Distribution requires your own Developer ID signing and notarization.
