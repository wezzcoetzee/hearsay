# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

Recorded as `ios` only because Impeccable has no macOS value; it loads Apple-native guidance (SF type, semantic colors, Dynamic Type, materials, VoiceOver). The product is a native **macOS** app: SwiftUI, a menu-bar utility (`LSUIElement`, no Dock icon), macOS 14+, Apple Silicon only. iPhone-specific rules (tab bars, safe areas, edge-swipe back, 44pt touch targets) do not apply; macOS HIG conventions (menu-bar extras, popovers, Settings windows, floating panels, pointer and keyboard) do.

## Users

Mac users who spend their day in Slack huddles, Teams calls and Google Meet, and keep their thinking in an Obsidian vault (or a plain folder). They also meet in person and want those conversations captured the same way. They are privacy-conscious: the reason they reach for a local-first tool instead of an Otter or a Fireflies is that they do not want their audio leaving the machine.

The app is publicly distributed, so the audience is broader than power users. A first-time user meets the app cold: they need to understand what it does, grant Microphone (and, for calls, Screen Recording) permissions, and trust it with something sensitive (recording a live conversation) before they get any value. The design has to carry a stranger from install to first successful note.

Context of use: the menu-bar popover is opened in short glances, often mid-call or in the seconds before and after one. Decisions are fast and low-stakes (start, stop, is it working). The vault, model, and toggles are set once and rarely revisited.

## Product Purpose

A macOS menu-bar utility that detects when you are in a Slack huddle, Teams call or Google Meet, asks before recording, captures both sides, transcribes on-device with WhisperKit, and writes a markdown note (with optional AI summary and action items) into your Obsidian vault. It also records in-person meetings from the microphone alone and lets you name each voice afterwards.

It exists so that conversation knowledge stops evaporating, without the privacy cost of a cloud transcription service. Success is when the user forgets the app is running, then later finds an accurate, well-formatted note waiting in their vault, and never once wondered where their audio went.

## Positioning

Three commitments together, which a cloud meeting recorder cannot truthfully claim:

- **Consent per call.** Nothing records automatically. A detected call raises a prompt with a 15 second countdown; doing nothing means nothing is recorded.
- **On-device.** Audio is transcribed on the Mac and deleted once the note is saved (keeping audio is opt-in). The single exception is the optional cloud summary, which sends the transcript, never audio.
- **Your file, your folder.** The output is a plain markdown note in a folder the user owns, not a record in someone else's workspace.

## Operating Context

- **Call apps:** Slack huddles and Teams calls (detected via Core Audio mic and per-process output activity), Google Meet in a browser (detected by an Accessibility check for a Meet code in a tab title). Manual *Record a Call* covers anything else.
- **In person:** mic-only capture with no Screen Recording requirement; every voice is diarized and named in review.
- **After a call:** a participant review window names voices and confirms the roster (names seen on screen start unticked), then the optional summary runs, then the note is written.
- **Destination:** an Obsidian vault or any folder. Notes are `YYYY-MM-DD HHMM <Source> - <Topic>.md` with YAML frontmatter and a speaker-labelled transcript.
- **Surfaces:** menu-bar popover, call prompt (bottom-right), floating recording panel, participant review window, first-run onboarding, Settings window.

## Capabilities and Constraints

- Transcription is English only. Models: `small` (Accurate, default), `large-v3` (Most accurate), `tiny` (Fastest).
- Summary backends: local Ollama, or cloud Anthropic with an API key stored in the Keychain. If a summary fails, the note says why.
- Permissions: Microphone (always), Screen Recording (calls only), Accessibility (Meet detection and participant names, optional).
- Recovery: recordings that never became notes are kept under *Needs Attention*, including across crashes and relaunches.
- Recent Recordings in the menu; removing an entry never deletes files.
- Meet capture targets the host browser's audio, so other tabs in that browser can bleed in.
- **Distribution:** both the Mac App Store and a notarized direct download (DMG).

## Brand Personality

Calm, native, trustworthy.

The interface should feel like it shipped with the operating system, not like something bolted on. Voice is quiet and factual, never salesy or cute. Because the core action is recording a private conversation, the UI treats consent and data location as first-class: it is always clear what is being captured, where it goes, and the one moment (cloud summary) when anything leaves the machine. Trust is earned through familiarity and transparency, not through reassurance copy layered over an unfamiliar UI.

## Anti-references

- **Electron / cross-platform shells.** No custom window chrome, non-native controls, or web-app feel inside a native wrapper. Native materials and SF Symbols, or nothing.
- **Loud SaaS dashboards.** No gradient accents, hero-metric templates, or marketing-style cards crammed into a menu popover.
- **Power-user overload.** No dense settings walls with every option exposed at once. Simple by default; depth revealed only when relevant.
- **The sketchy "recorder" vibe.** Nothing that reads as spyware-adjacent or untrustworthy. Recording state and data handling must always be legible and consent-forward.

## Evidence on Hand

- Six Mac App Store screenshots (2880 x 1800) in `docs/appstore/`, rendered from fixtures by `Scripts/appstore-screenshots.sh`.
- A full screenshot catalog of every surface and state, light and dark, via `Scripts/screenshots.sh` into `build/screenshots/`.
- No testimonials, user counts, reviews, ratings, press, or pricing facts exist. Future work must not fabricate them.

## Design Principles

- **Feel native, not built.** The bar for every control is: would this look out of place next to Bartender, CleanShot, or a system menu? Reach for system materials, standard controls, and SF Symbols before anything custom.
- **Consent is a feature, not a footnote.** Because it records private conversations, the UI earns trust by making capture state and data destination obvious at a glance. The confirmation prompt and permission flow are core product surfaces, not chrome.
- **Local-first is the promise; name the exception.** Reinforce that audio stays on device, and clearly flag the single moment (cloud summary) when a transcript leaves the machine. Never let that boundary be ambiguous.
- **Invisible until needed.** The tool should recede. Surface status, errors, and recording state only when they matter; keep the resting state quiet and uncluttered.
- **Progressive disclosure.** A stranger sees a simple surface and a clear next step. Advanced settings, backends, and history reveal themselves in context, never all at once.

## Accessibility & Inclusion

Standard macOS accessibility, following system conventions rather than overriding them: Dynamic Type support, complete VoiceOver labels for every control and status, respect for Reduce Motion and Increase Contrast. Because the app leans on native controls, most of this comes from not fighting the platform; the burden is on any custom status indicator (recording dot, permission states) to carry proper labels and not rely on color alone.
