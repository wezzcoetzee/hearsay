# Product

## Register

product

## Users

Mac users who spend their day in Slack huddles and Teams calls and keep their thinking in an Obsidian vault (or a plain folder). They are privacy-conscious: the reason they reach for a local-first tool instead of an Otter or a Fireflies is that they do not want their audio leaving the machine.

The app is publicly distributed as a notarized download, so the audience is broader than power users. A first-time user meets the app cold: they need to understand what it does, grant Microphone and Screen Recording permissions, and trust it with something sensitive (recording a live call) before they get any value. The design has to carry a stranger from install to first successful note.

Context of use: the menu-bar popover is opened in short glances, often mid-call or in the seconds before and after one. Decisions are fast and low-stakes (start, stop, is it working). The vault, model, and toggles are set once and rarely revisited.

## Product Purpose

A macOS menu-bar utility that detects when you are in a Slack huddle or Teams call, records both sides, transcribes on-device with WhisperKit, and writes a markdown note (with optional AI summary and action items) into your Obsidian vault.

It exists so that call knowledge stops evaporating, without the privacy cost of a cloud transcription service. Success is when the user forgets the app is running, then later finds an accurate, well-formatted note waiting in their vault, and never once wondered where their audio went.

## Brand Personality

Calm, native, trustworthy.

The interface should feel like it shipped with the operating system, not like something bolted on. Voice is quiet and factual, never salesy or cute. Because the core action is recording a private conversation, the UI treats consent and data location as first-class: it is always clear what is being captured, where it goes, and the one moment (cloud summary) when anything leaves the machine. Trust is earned through familiarity and transparency, not through reassurance copy layered over an unfamiliar UI.

## Anti-references

- **Electron / cross-platform shells.** No custom window chrome, non-native controls, or web-app feel inside a native wrapper. Native materials and SF Symbols, or nothing.
- **Loud SaaS dashboards.** No gradient accents, hero-metric templates, or marketing-style cards crammed into a menu popover.
- **Power-user overload.** No dense settings walls with every option exposed at once. Simple by default; depth revealed only when relevant.
- **The sketchy "recorder" vibe.** Nothing that reads as spyware-adjacent or untrustworthy. Recording state and data handling must always be legible and consent-forward.

## Design Principles

- **Feel native, not built.** The bar for every control is: would this look out of place next to Bartender, CleanShot, or a system menu? Reach for system materials, standard controls, and SF Symbols before anything custom.
- **Consent is a feature, not a footnote.** Because it records private calls, the UI earns trust by making capture state and data destination obvious at a glance. The confirmation prompt and permission flow are core product surfaces, not chrome.
- **Local-first is the promise; name the exception.** Reinforce that audio stays on device, and clearly flag the single moment (cloud summary) when a transcript leaves the machine. Never let that boundary be ambiguous.
- **Invisible until needed.** The tool should recede. Surface status, errors, and recording state only when they matter; keep the resting state quiet and uncluttered.
- **Progressive disclosure.** A stranger sees a simple surface and a clear next step. Advanced settings, backends, and history reveal themselves in context, never all at once.

## Accessibility & Inclusion

Standard macOS accessibility, following system conventions rather than overriding them: Dynamic Type support, complete VoiceOver labels for every control and status, respect for Reduce Motion and Increase Contrast. Because the app leans on native controls, most of this comes from not fighting the platform; the burden is on any custom status indicator (recording dot, permission states) to carry proper labels and not rely on color alone.
