# Codex Touch Bar Pet

A little companion for your MacBook Pro Touch Bar: Codex quota, live task status, and an animated pet that reacts while Codex works.

[简体中文](README.zh-CN.md) · [Download](https://github.com/CsokiW/codex-touchbar-pet/releases) · [Report an issue](https://github.com/CsokiW/codex-touchbar-pet/issues)

Maintained by [CsokiW](https://github.com/CsokiW). Derived from [wjx8/CodexBar](https://github.com/wjx8/CodexBar), which builds on [Jack Chen's TouchBarCodexToken](https://github.com/jackchensky/TouchBarCodexToken). Not affiliated with OpenAI or Apple.

## What's different?

- **A pet with a job.** The bundled character, **王臭吉 (Wang Chou Ji)**, animates for working, waiting, errors, and completion. Tap it to say hello.
- **Real task state.** Reads local Codex Desktop runtime status instead of guessing from chat text. Follows 40 recent unarchived local tasks and continues following older subscribed tasks that are still running or waiting, not exclusively the selected task.
- **Quota at a glance.** Remaining 5-hour and weekly allowance, reset times, and reset credits when the account exposes them. Missing windows are hidden.
- **One context button.** Refresh quota while Codex is frontmost; return to Codex from another app. Pending input and errors make it stand out.
- **Chinese voice input.** Tap the microphone to record and tap again to return to Codex and insert into a verified editable field. If the target cannot be verified, the text is retained for retry.
- **Presentation recovery.** Restores the bar after wake or an unexpected system dismissal, respecting sleep, screen lock, and menu-based hiding.

Quota and voice input originate in the upstream project. This version adds the pet, task-state tracking, completion animation, context button, and presentation recovery. The compact layout replaces upstream's yesterday/lifetime token columns with pet and task status.

## Preview

![Codex Touch Bar Pet native interface](docs/touchbar-preview.png)

The actual native view rendered with synthetic quota values, not a capture of a personal account. Includes the author-created Wang Chou Ji artwork. Reproduce with `bash scripts/render-preview.sh` on macOS with GUI access.

## Requirements

- A MacBook Pro with a **physical Touch Bar** for the pet display. The menu-bar quota entry can work without one.
- macOS 12 or later, subject to compatibility of private Touch Bar APIs; a recent Apple Swift toolchain for source builds. macOS 12 is the deployment target, not a claim of hardware testing on every OS version.
- Codex Desktop or the ChatGPT desktop app hosting Codex, with a working local Codex login.
- Known bundled CLI paths under `/Applications/ChatGPT.app` or `/Applications/Codex.app`.
- Task status additionally uses `~/.codex/ipc/ipc.sock` and `~/.codex/state_5.sqlite`. These are private interfaces and can change.

**Compatibility:** Intel (`x86_64`) is the primary local build target. Apple Silicon can be built natively from source but is not claimed as tested. Release filenames identify their architecture.

The current UI and permission messages are primarily Chinese. Local build and synthetic checks were run on an Intel MacBook Pro, macOS 26.6.2, with ChatGPT desktop 26.1013.40934 installed. This is not a cross-version or end-to-end voice-input compatibility guarantee.

## Install

1. Download an archive matching your Mac from [Releases](https://github.com/CsokiW/codex-touchbar-pet/releases) and check its SHA-256 checksum.
2. Unzip and move **Codex Touch Bar Pet.app** into `~/Applications` or `/Applications`.
3. Open the companion, then Codex. First launch installs a user-level LaunchAgent to follow Codex's desktop lifecycle.

For the 0.2.2 archives, put the downloaded files and checksum list in the same directory, then run:

```bash
shasum -a 256 -c Codex-Touch-Bar-Pet-0.2.2-SHA256SUMS.txt
```

The app is ad-hoc signed and not Apple-notarized. If macOS blocks it, inspect the release and use the per-app **Open Anyway** control in System Settings → Privacy & Security. Do not disable Gatekeeper globally.

Only run one Touch Bar replacement at a time. This app has an independent name, bundle identifier, and startup item, so it does not overwrite upstream CodexBar. Quit other Touch Bar replacements before starting it.

### Build from source

Install Xcode or Xcode Command Line Tools, then:

```bash
git clone https://github.com/CsokiW/codex-touchbar-pet.git
cd codex-touchbar-pet
bash scripts/test.sh
bash scripts/build-app.sh
open 'build/Codex Touch Bar Pet.app'
```

The build uses Apple Swift/AppKit and system SQLite, without third-party runtime packages. It builds for the current Mac architecture. Tests use synthetic task/quota state, a local mock server, mocked speech permissions and insertion, and synthetic launcher sessions. They never open your Codex account data, record audio or type into real windows. They do not replace physical Touch Bar, Accessibility or speech-service testing. `bash scripts/package-dmg.sh` builds a DMG.

## Daily use

The Touch Bar stays visible when switching to other apps while Codex is running. Quit Codex completely to stop the companion. Its menu-bar entry can hide, show, reload the Touch Bar, refresh quota, or quit. Manually quitting suppresses relaunch for the current Codex session; restarting Codex allows automatic launch again.

**Pets:** Wang Chou Ji is bundled under MIT. For a custom cloud pet selected in Codex Desktop, the companion can fetch the artwork URL already present in the local desktop cache. Codex's built-in pet images are not distributed here; selecting one uses Wang Chou Ji as fallback. Runtime custom artwork is not written into the repository or distributed to other users.

**Task status:** waiting takes priority over running across local tasks. Celebration requires an observed transition from in-progress to completed. Reconnects and old completed tasks are not new successes. The app does not send approval decisions. Timing metadata is used internally for completion detection; this release's compact UI focuses on status rather than a separate elapsed-time counter.

**Voice:** microphone and Speech Recognition permissions are requested when used; direct typing also needs Accessibility permission. The companion returns to a running Codex host and verifies its editable focus before inserting; it is not system-wide dictation. The current host is preferred, followed by standalone Codex if multiple hosts are running. Activation/focus failures keep the transcript: select the intended Codex text field and tap Input again. Insertion does not press Send. Apple Speech may use Apple's services, depending on system availability; offline transcription is not guaranteed. Quota and pet display need no microphone permission.

## Privacy

- Quota comes through the local official `codex app-server`, which uses your existing Codex login and may contact OpenAI to refresh account limits. No API key is requested by this project.
- Recent task IDs are read from SQLite in read-only mode. Local desktop IPC messages are reduced to runtime flags, pending-request counts, and timing fields; the task monitor does not save or log conversation text.
- Pet selection is read from `~/.codex/.codex-global-state.json`. Account identifiers are used in memory to find the matching selection, not embedded in the app or uploaded.
- Custom pets can cause an HTTPS artwork download to the URL recorded by Codex Desktop.
- No project telemetry, analytics endpoint, or conversation-log upload is added. Apple's speech service and Codex's account service retain their own behavior.

## Troubleshooting

**Blank Touch Bar:** quit competing Touch Bar apps, confirm Codex is running, then select **重新加载 Touch Bar** (Reload Touch Bar). If normal system controls are missing too, investigate the macOS Touch Bar service separately.

**Quota shows `--`:** check the desktop and CLI login, then refresh. Available limits depend on the account plan. Backend requests time out after 20 seconds. Refresh reconnects after a backend failure; the normal 60-second timer also retries. Failed refreshes retain the last available numbers, marked as old in orange with their last successful update time. The menu-bar warning icon and tooltip show the error. A successful update clears the warning.

**Pet says 未连接 (offline):** quota may still work if the private desktop task-status interface has changed. IPC/database compatibility may need an update.

## Uninstall

Quit the companion from its menu and unload its startup item:

```bash
launchctl bootout "gui/$(id -u)/com.github.csokiw.CodexTouchBarPet.Launcher"
```

Move the installed app and `~/Library/LaunchAgents/com.github.csokiw.CodexTouchBarPet.Launcher.plist` to Trash. Optionally remove `~/Library/Application Support/CodexTouchBarPet/`, which holds the manual-quit marker. Do not delete `~/.codex`; it contains Codex's own login and task history.

## Credits and license

MIT. Retain the upstream notices in source and app distributions. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for provenance and artwork attribution.

Report bugs with macOS version, CPU architecture, desktop app version, and symptoms. Do not post credentials, signed artwork URLs, or raw conversation logs. If you enjoy having a little companion on the Touch Bar, a Star is appreciated.
