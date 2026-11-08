---
name: What Did I Say
description: A macOS menu-bar recorder that transcribes calls on-device and files notes to your vault, dressed entirely in system-native materials.
colors:
  accent-tint: "#007AFF"
  recording-red: "#FF3B30"
  processing-orange: "#FF9500"
  success-green: "#34C759"
  label-primary: "#1D1D1F"
  label-secondary: "#8E8E93"
  surface-material: "#F2F2F7"
  fill-quaternary: "#E5E5EA"
typography:
  display:
    fontFamily: "-apple-system, SF Pro, system-ui, sans-serif"
    fontSize: "22px"
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: "normal"
  headline:
    fontFamily: "-apple-system, SF Pro, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "normal"
  title:
    fontFamily: "-apple-system, SF Pro, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "normal"
  body:
    fontFamily: "-apple-system, SF Pro Text, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.35
    letterSpacing: "normal"
  label:
    fontFamily: "-apple-system, SF Pro Text, system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 400
    lineHeight: 1.2
    letterSpacing: "normal"
  mono:
    fontFamily: "SF Mono, ui-monospace, monospace"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.2
    letterSpacing: "normal"
    fontFeature: "tabular-nums"
rounded:
  callout: "10px"
  control: "6px"
spacing:
  xs: "6px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "20px"
  xxl: "28px"
components:
  button-primary:
    backgroundColor: "{colors.accent-tint}"
    textColor: "#FFFFFF"
    rounded: "{rounded.control}"
    padding: "6px 12px"
  button-primary-recording:
    backgroundColor: "{colors.recording-red}"
    textColor: "#FFFFFF"
    rounded: "{rounded.control}"
    padding: "6px 12px"
  button-secondary:
    backgroundColor: "{colors.fill-quaternary}"
    textColor: "{colors.label-primary}"
    rounded: "{rounded.control}"
    padding: "4px 10px"
  toggle-switch:
    backgroundColor: "{colors.accent-tint}"
    height: "16px"
  textfield-rounded:
    backgroundColor: "{colors.surface-material}"
    textColor: "{colors.label-primary}"
    rounded: "{rounded.control}"
    padding: "4px 8px"
  callout-box:
    backgroundColor: "{colors.fill-quaternary}"
    textColor: "{colors.label-secondary}"
    rounded: "{rounded.callout}"
    padding: "12px"
---

# Design System: What Did I Say

## 1. Overview

**Creative North Star: "The Quiet Instrument"**

This is a precision tool that sits in the menu bar and stays out of the way. Every surface is built from AppKit and SwiftUI system primitives, so the app reads as something that shipped with macOS rather than something bolted onto it. The bar for any control is the one PRODUCT.md sets: would this look out of place next to Bartender, CleanShot, or a native system menu? If yes, it does not ship. Color, type, materials, and controls are all inherited from the operating system, which means the interface adapts automatically to the user's appearance (light/dark), accent color, and Dynamic Type without a single override.

The system is deliberately thin. There is no custom palette, no custom font, no bespoke component library. That absence is the design: familiarity is the trust mechanism. Because the core action is recording a private conversation, the interface earns confidence by being legible and boring in exactly the way a system utility is boring. The one place the design raises its voice is state and consent: the recording dot, the call prompt, the permission flow, and the single cloud-summary boundary are all made obvious, never buried in chrome.

The system explicitly rejects the things PRODUCT.md names as anti-references: no Electron or web-app feel, no custom window chrome, no loud SaaS dashboards with gradient accents or hero-metric templates, no dense settings walls, and nothing that reads as spyware-adjacent. When a surface needs personality, it gets it from correct system materials and honest copy, not from decoration.

**Key Characteristics:**
- System-semantic color only; the OS owns the palette, light and dark
- SF Pro throughout, via semantic text styles that respect Dynamic Type
- Flat by default; depth comes from native window/popover materials, not custom shadows
- Stock, unadorned controls; the only custom elements are the recording dot and level meters
- Fixed-width surfaces sized to their glance-length purpose (340pt menu, compact panels)
- State and consent are loud; everything else recedes

## 2. Colors

The palette is not authored; it is inherited. Every color is a SwiftUI semantic role that AppKit resolves at runtime for the user's appearance and accent selection. The hex values in the frontmatter are approximate Apple sRGB values for the default light appearance, provided only so tooling has something to render. They are not the source of truth.

### Primary
- **System Accent** (`.accentColor` / `.tint`, ~#007AFF default): The one interactive-emphasis color. Carries the primary button when idle, the active step dot, and switch fills. It is whatever the user set as their macOS accent, so it is never assumed to be blue.

### Secondary
- **Recording Red** (`.red`, ~#FF3B30): Reserved for the live recording state and errors. It tints the Stop button, the record glyph (menu card, panel, menu-bar icon) and the symbol on failure messages. Text beside it stays primary for contrast; the timer is primary too. Its scarcity is what makes "we are recording" unmistakable.
- **Processing Orange** (`.orange`, ~#FF9500): The coloured symbol on warnings (a missing microphone, capture problems, Needs Attention). A missing Screen Recording grant is not a warning: in-person recording works without it, so the menu shows one quiet secondary line with Allow… instead. Warning text itself stays primary; only the symbol carries the colour. Signals "attention, not error."
- **Success Green** (`.green`, ~#34C759): Granted permissions and the completed-setup seal only. Confirmation, never decoration.

### Neutral
- **Primary Label** (`.primary` / default foreground, ~#1D1D1F light): All primary text. Dynamic; near-black in light, near-white in dark.
- **Secondary Label** (`.secondary`, ~#8E8E93): The dominant text tone in this app. Row subtitles, captions, timestamps, helper copy, and form descriptions. Most text is intentionally secondary; the interface whispers.
- **Surface Material** (system popover/window material, ~#F2F2F7 light): The background of the menu-bar window and floating panels. A vibrant system material, not a flat fill.
- **Quaternary Fill** (`.quaternary`, ~#E5E5EA): The single tonal-layering device, used at ~40% opacity behind the onboarding privacy callout to lift it off the surface without a border or shadow.

### Named Rules
**The Inherited Palette Rule.** Never introduce a literal hex value in UI code. Always reach for the semantic SwiftUI color (`.red`, `.secondary`, `.accentColor`, `.tint`). A hardcoded color breaks dark mode, breaks the user's accent choice, and breaks Increase Contrast. The frontmatter hex is a tooling approximation, not a token to type.

**The Red Means Recording Rule.** Red is spent only on the recording state and on errors. It never appears as an accent, a highlight, or a decorative touch. When the user sees red, audio is being captured or something failed, nothing else.

## 3. Typography

**Display Font:** SF Pro (system, `-apple-system`)
**Body Font:** SF Pro Text (system)
**Label/Mono Font:** SF Mono (system monospace, digits and countdowns only)

**Character:** One typeface, the platform's own, expressed entirely through SwiftUI's semantic text styles. Hierarchy comes from the system's built-in scale and weight contrast, never from hand-picked point sizes. This guarantees Dynamic Type support for free.

### Hierarchy
- **Display** (`.title2`, bold, ~22px): The app name in the onboarding header. The single largest text in the product.
- **Headline** (`.headline`, semibold, ~15px): The menu title, the call prompt title, and the participant review heading. The workhorse heading.
- **Title** (`.title3`, bold, ~15px): Step titles and the done-state heading in onboarding.
- **Body** (`.callout` / `.body`, regular, ~13px): Menu row titles, explanatory copy, and the "why we need this" text. Row subtitles sit one step down in `.subheadline`. Kept short; these surfaces are read in glances.
- **Label** (`.caption` / `.caption2`, regular, ~11px and smaller): Quiet detail: panel source name, Settings footers and helper hints. Row subtitles, review quotes and warnings use `.subheadline` so they stay readable. This is where the interface does most of its talking, quietly.
- **Mono** (`.system(.body, design: .monospaced)` / `.monospacedDigit()`, ~13px): The call prompt countdown and the elapsed recording clock, so digits do not jitter as they tick.

### Named Rules
**The Semantic Scale Rule.** Size and weight are chosen by naming a text style (`.headline`, `.caption`), never by setting an explicit point size on body text. The only explicit sizes allowed are on SF Symbol glyphs in headers (`.system(size: 26–48)`), where the symbol is functioning as an illustration, not as text.

**The Secondary-First Rule.** Default body and label text to `.secondary`. Primary label weight is reserved for the one or two things on a surface that genuinely lead. A wall of primary-weight text is a design bug.

## 4. Elevation

The system is flat by default and uses no custom `box-shadow` vocabulary. Depth is delegated entirely to native window materials: the `MenuBarExtra` window, floating panels and the call prompt each sit on the system's own translucent material and carry the system's own window shadow. Titlebars are transparent and hidden (`titlebarAppearsTransparent`, `titleVisibility = .hidden`) so the content material runs edge to edge.

Within a surface, the only lift is tonal, not cast: the onboarding privacy callout uses a `.quaternary` fill at ~40% opacity to separate itself from the background. No drop shadow, no border, no glass blur added on top of the system's own.

### Named Rules
**The No Custom Shadow Rule.** Never add a `.shadow()` or a synthetic glass/blur layer. macOS already provides the correct window shadow and material vibrancy. Anything layered on top reads as non-native, which is exactly the "built, not shipped" feel this product forbids.

**The Tonal Lift Rule.** When an element inside a surface needs to stand apart, raise it with a `.quaternary` fill, not a shadow or a stripe. Radii: 7 for hover rows, 8 for the menu's recording and processing cards, 10 for callouts in onboarding.

## 5. Components

Every control is a stock SwiftUI/AppKit primitive used with its default styling. Nothing is re-skinned. The philosophy is stock and unadorned: the only custom-drawn pieces are the recording dot and level meters, which carry meaning a system control cannot.

### Buttons
- **Shape:** System default radius (~6px); never overridden.
- **Primary:** `.borderedProminent`, tinted with the system accent. The single lead action on a surface (Record a Call, Save Note, a missing setup step, or the onboarding step action). Record a Call (with a bordered In Person beside it) and Stop Recording span the menu, and in the onboarding footer's default slot, where it takes Return.
- **Primary while recording:** Same `.borderedProminent`, but `.tint(.red)`. The button itself becomes the recording signal.
- **Secondary:** `.bordered` or the system default, often at `.controlSize(.small)` (Back, Skip, Change…, Make All Notes, Review…).
- **Borderless / icon:** the shared `IconButton`: `.borderless`, an SF Symbol, and a 22pt minimum hit area, for quit, dismiss, open folder and remove-row. Always paired with a `.help(...)` tooltip and an accessibility label.
- **Plain text:** `.borderless` text buttons for low-stakes inline actions (Clear…, Settings…).
- **Control sizing:** `.large` for Start/Stop Recording, default in onboarding and settings, `.small` for dense menu rows and banners. Size signals stakes.

### Toggles
- **Style:** `.switch`, `.controlSize(.small)` in the menu, with the switch at the trailing edge (`TrailingSwitch`) in the menu and onboarding; inside Settings they are native Form toggles with a description line under the label. Reveals dependent controls inline when enabled (the summary backend appears only when AI summary is on, the audio folder only when Keep audio is on).

### Inputs / Fields
- **Style:** `.textFieldStyle(.roundedBorder)` for participant names in review. In Settings the fields (Ollama model, Anthropic API key, file names) are native labelled Form rows.
- **Pickers:** native Form pickers for accuracy and the summary backend.
- **Folders:** one `FolderChoice` control everywhere: the folder name with the full path on hover and a Change… button, or Choose… when none is set.

### Warnings (`Caution`)
- A symbol plus text: the text stays primary so it holds contrast on any background, and only the symbol is coloured (orange for attention, red for failures, accent for relaunch). Colour and words always travel together, never colour alone, so it stays legible under Increase Contrast and for color-blind users.

### Menu Bar Icon and Rows
- The menu-bar icon is the status surface: a waveform when idle, a waveform with a badge for failures, Needs Attention or a pending review, and a red record symbol while recording, each with a VoiceOver label. There is no status badge inside the menu; the current-job slot (recording card, processing card, or start controls) says what is happening.
- Menu rows use `.body` titles with `.subheadline` secondary subtitles. The recording card is a `.quaternary` fill naming the source, with the timer trailing, level meters and a "Saves to" line.
- Relaunching after Screen Recording is granted is always the shared `RelaunchButton`, labelled "Relaunch Now".

### Settings
- A native grouped `Form` (480 x 560) with sections General, Permissions, Notes, Audio and Summary. Every field is labelled, fields that need explaining carry a description line, and there is no app header.

### Call Prompt (signature)
- An `NSPanel` (`.nonactivatingPanel`, floating, joins all Spaces) pinned to the bottom-right of the main screen with a 24pt inset, 360pt wide and sized to its content. The bottom-right avoids the top-right where call apps show their own banners. It shows the detected source (symbol in the accent colour, never red before recording), a "Closes in Ns" countdown, and Not Now / Start Recording buttons. It is the consent surface: it appears before recording starts, states that everyone on the call is recorded and where the audio and transcript go, and never records on its own. The countdown (15 seconds) pauses while the pointer is over it and dismisses with nothing recorded if no choice is made. With VoiceOver or Switch Control on it waits for an answer. The consent line (`Copy.consent`) is shared with the one-time "Start recording?" alert shown before the first recording from the menu, and both follow whether cloud summaries are on. If the last note is still saving it explains why and offers only OK, and turns into a normal offer if the note finishes while it's up. If the last recording is waiting for names it keeps the consent line, adds that the speakers can be named later, and Start Recording parks that recording under Needs Attention. If a start fails, the prompt comes back as "<Source> not recorded" with the reason.

### Floating Recording Panel
- Same placement as the call prompt (bottom-right, all Spaces, no focus). A `.regularMaterial` panel, 292 x 92 expanded and 168 x 40 collapsed. It names the source, shows the timer, level meters, a collapse control and a red Stop button. When a capture problem exists the issue title replaces the source and the collapsed form shows an orange warning symbol instead of the meter.

### Participant Review
- A 420-wide window, sized to its content up to 80% of the screen (the voices scroll past that), titled "Who was talking?" with the recording as subtitle. Labels are right-aligned against rounded-border fields (Return moves to the next; ⌘Return saves from anywhere). Each voice has one `ellipsis.circle` menu: names seen on screen, then Same Person as…. The footer is Delete Recording | Name Later | Save Note. Name Later (also Esc with no field focused, and the close button) parks the recording under Needs Attention and keeps what was typed until quit, restoring it when the review reopens. The window appears without taking focus.

### Onboarding
- A 460 x 400 setup assistant with five steps: Welcome, Microphone, Screen Recording, Notes Folder, Done. The step's action sits in the footer's default slot and becomes Continue once done (Skip or Later beside Screen Recording, Relaunch Now after it is requested). The app header shows only on Welcome. A normal window, so System Settings can sit in front.

### Step Indicator
- Onboarding progress dots in the footer: 6pt circles, system accent for the current step, `.tertiary` for the rest.

## 6. Do's and Don'ts

### Do:
- **Do** use semantic SwiftUI colors (`.red`, `.secondary`, `.accentColor`, `.tint`) for every color. The OS owns the palette.
- **Do** choose type by naming a semantic text style (`.headline`, `.caption`), so Dynamic Type works without effort.
- **Do** default text to `.secondary`; reserve primary weight for the one thing that leads.
- **Do** keep red for the recording state and errors only, per the Red Means Recording Rule.
- **Do** pair every status color with a text label and an SF Symbol; never rely on color alone. Warnings are primary text with a coloured symbol.
- **Do** use stock `.borderedProminent` / `.bordered` / `.borderless` buttons and `.switch` toggles as-is, and reuse the shared `Caution`, `IconButton`, `FolderChoice`, `RelaunchButton`, `PermissionStatus` and `TrailingSwitch`.
- **Do** lean on native window materials and transparent titlebars for depth; let macOS draw the shadow.
- **Do** make capture state and the single cloud-summary boundary obvious, per PRODUCT.md's "consent is a feature, not a footnote."
- **Do** reveal advanced settings progressively (the summary backend appears only when AI summary is enabled).

### Don't:
- **Don't** hardcode a hex color anywhere in UI code; it breaks dark mode, the user's accent, and Increase Contrast.
- **Don't** add custom window chrome, non-native controls, or any Electron / web-app feel. Native materials and SF Symbols, or nothing.
- **Don't** build loud SaaS dashboards: no gradient accents, no hero-metric templates, no marketing-style cards crammed into the popover.
- **Don't** expose every option at once in a dense settings wall; simple by default, depth only when relevant.
- **Don't** ship anything that reads as spyware-adjacent; recording state and data destination must always be legible and consent-forward.
- **Don't** add `.shadow()`, decorative glassmorphism, or a blur on top of the system's own material.
- **Don't** use a `border-left`/`border-right` colored stripe as an accent on any callout, row, or alert; lift with a `.quaternary` fill instead.
- **Don't** set explicit point sizes on body text; only SF Symbol glyphs in headers get an explicit `.system(size:)`.
- **Don't** spend red, green, or orange on decoration; each is a state signal, not a highlight.

### States that wait on the user

A spinner means the app is working. When the app is waiting on the user (the participant review), the menu's current-job slot shows a still `person.2.fill` glyph, "Who was talking?" with no ellipsis and a plain Review… button, with the Record controls still below it (recording then parks that review under Needs Attention, as the call prompt does), and the menu-bar icon carries the attention badge. Failures that leave a recording under Needs Attention are reported on that recording's row ("failed while transcribing"), not in a separate banner.
