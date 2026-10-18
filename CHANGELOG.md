# Changelog

## 0.2.2 — Menu-bar quota display fix

- Size the menu-bar item to its content so weekly quota remains visible when percentage text grows.

## 0.2.1 — Reliability fixes

- Ignore cancelled or superseded speech authorization, recognition and insertion callbacks.
- Verify editable Codex focus before speech insertion; use element-bound insertion or PID-targeted events instead of global keystrokes.
- Preserve recognized text after permission or focus errors, including after the error message expires.
- Reconnect the quota backend after failure and bound initialization/read requests to 20 seconds.
- Mark retained quota values as stale with an update timestamp and menu-bar warning.
- Scope manual-quit suppression to host PIDs and start times so rapid restarts and subsequent logins can relaunch.
- Add synthetic quota transport/retry, voice cancellation/retention, stale UI and launcher-session regression checks.
- Correct artwork extension, runtime product/version metadata and English/Chinese usage boundaries.

## 0.2.0 — Initial Codex Touch Bar Pet release

- Derive from wjx8/CodexBar, preserving original MIT notices.
- Add Wang Chou Ji and state-based animations.
- Display aggregated local task activity and waiting/error status.
- Observe completion transitions without celebrating historical completions on reconnect.
- Use one context button for quota refresh or returning to Codex.
- Recover Touch Bar presentation after wake and unexpected dismissal.
- Recognize newer bundled Codex CLI locations.
- Use an independent app name, bundle identifier, and LaunchAgent.
- Exclude Codex built-in pet artwork and personal pet IDs from distribution.
- Include English/Chinese documentation and synthetic state/timing tests.
