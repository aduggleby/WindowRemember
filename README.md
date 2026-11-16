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

This is an independently implemented functional starting point, not Putback's source code or branding. It does not implement Scene Studio, wallpaper switching, launching closed apps, configurable global hotkeys, login startup, or licensing. Scenes apply to already-open apps and connected displays. Minimized windows are excluded. Full-screen sessions exposed through Accessibility are remembered, including Windows App sessions exposed only through the focused/main-window attributes. Restoring a full-screen session to another monitor temporarily exits full-screen, moves it, then re-enters full-screen. macOS may switch Spaces during this process; some apps may reject the transition. Apps may reject Accessibility moves or constrain window sizes. Multi-Space behavior and physical dock reconnects require testing on your setup; Accessibility capture is limited by what each app exposes. No private Spaces APIs are used.

The build script produces an app for the current Mac architecture. Distribution requires your own Developer ID signing and notarization.

## Diagnostics and troubleshooting

Settings → **Capture diagnostic snapshot** records what Accessibility sees. **Open logs folder** opens `~/Library/Application Support/WindowRemember/Diagnostics/`.

`debug.jsonl` contains timestamped JSON events for app startup, permission changes, every learning capture, app process identity, window role/subrole and full-screen state, capture exclusions, display geometry and IDs, saved/live matching, move requests, numeric AX error codes, observed frames, full-screen transitions, and restore summaries. One previous log is retained; rotation occurs at approximately 5 MB per file (approximately 10 MB total). Window titles can contain private document or host names. Logs remain local and are not committed or uploaded automatically.

If a move fails, learning is suspended to preserve the saved target rather than overwrite it with the misplaced layout. Retry the restore, or choose **Resume learning from current windows** in Settings when you intentionally want to adopt the current arrangement. Closed apps are recorded as unavailable; they are not launched. Windows App sessions require an exact title match to avoid moving the connection browser instead.

To reproduce a reconnect problem, put the session on the intended monitor, wait for learning, unplug, reconnect, and inspect the logs. Full-screen support has been verified for capture of the ThinkPad session; physical reconnect and full-screen movement still require validation on the actual monitor setup.

Run regression tests with `swift test --disable-sandbox`.
