# what-did-i-say

macOS menu-bar app that detects Slack huddles / Teams calls / Google Meet (in the browser), records both sides, transcribes locally with WhisperKit, and writes a markdown note to your Obsidian vault.

See [DESIGN.md](DESIGN.md) for the full design and [PRODUCT.md](PRODUCT.md) for the product overview.

## Requirements

- Apple Silicon, macOS 14+
- Xcode 16+ / Swift 6 toolchain

## Build & run

```sh
./Scripts/bundle.sh release
open build/WhatDidISay.app
```

`bundle.sh` compiles the executable, wraps it in a `.app` (so TCC permissions attach to the bundle id), and ad-hoc signs it with the hardened runtime.

On first use, grant the permissions macOS prompts for:

- **Microphone** — records your side
- **Screen Recording** — required for ScreenCaptureKit to capture the other participants' audio

## Usage

1. Click the waveform menu-bar icon.
2. Set **Vault** to your Obsidian vault (or any folder) and pick a Whisper **Model** (`base` is a good default; `large-v3` is most accurate).
3. **Manual:** click *Start Recording* / *Stop Recording*.
4. **Auto:** toggle *Auto-detect huddles & calls*. When your mic goes live while Slack or Teams is running — or a browser has a live Google Meet tab open — a countdown prompt appears; click *Start Recording* to begin. If you do nothing, the prompt dismisses after 15 seconds and nothing is recorded. Recording stops when the mic goes quiet.

   Google Meet detection uses Accessibility to spot a tab whose title carries a Meet meeting code (`abc-defg-hij`), so a browser that's merely open won't trigger a prompt. Grant Accessibility if macOS prompts for it; without it, Meet calls still record via *Start Recording* manually. Capture targets the host browser's audio, so audio from that browser's other tabs can bleed into the recording.

Notes are written as `YYYY-MM-DD HHMM <Source>.md` with YAML frontmatter and a `Me` / `Others` labeled transcript.

## Layout

```
Sources/WhatDidISay/
├── App.swift                      MenuBarExtra UI
├── AppCoordinator.swift           wires detector → confirmation → recorder
├── Settings.swift                 model, vault (bookmark), toggles
├── SettingsView.swift             settings pane UI
├── Onboarding.swift               first-run setup flow
├── PermissionsManager.swift       microphone / screen-recording status
├── Keychain.swift                 secure storage for the Anthropic API key
├── ParticipantReview.swift        post-recording roster confirm/correct dialog
├── Capture/                       RecordingController, System/Mic capture, Session
├── Transcription/                 WhisperKit service, merge, segment model, Diarizer
├── Summary/SummaryService.swift   Ollama / Claude summarizers
├── Output/                        MarkdownWriter (note rendering), RecordingHistory
└── Detection/                     CallDetector + CallActivityMonitor (Core Audio),
                                   BrowserCallDetector (Meet tab via Accessibility),
                                   ConfirmationController, ParticipantDetector
```

## Status

- ✅ Phase 1 — two-track capture (ScreenCaptureKit + AVAudioEngine)
- ✅ Phase 2 — local transcription + markdown output
- ✅ Phase 3 — auto-detect with confirmation
- ✅ Phase 4 — AI summary (local Ollama / cloud Claude), recording history, SpeakerKit diarization
- ✅ Phase 5 — per-app audio capture (records only the call app) + reliable huddle-end detection via Core Audio per-process output
- ✅ Phase 6 — best-effort participant detection (Accessibility + Vision OCR) with a post-recording review dialog to confirm/correct the roster
- ✅ Phase 7 — browser call support: auto-detect Google Meet via an Accessibility tab-title check and capture the host browser's audio

## Optional features

- **AI summary** — toggle in the menu. *Local* uses [Ollama](https://ollama.com) on `localhost:11434` (set the model name; default `llama3.2`). *Cloud* uses the Anthropic API (`claude-opus-4-8`) — paste an API key (stored in the macOS Keychain). A "## Summary" + action-items section is prepended to each note.
- **Separate remote speakers** — toggle to run SpeakerKit diarization on the system-audio track, relabeling `Others` as `Speaker 1`, `Speaker 2`, … Downloads a diarization model on first use.
- **Recent recordings** — the last five notes appear in the menu with quick-open buttons; history persists in `~/Library/Application Support/WhatDidISay/history.json`.
