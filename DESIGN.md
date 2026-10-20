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
  status-badge:
    textColor: "{colors.label-secondary}"
    typography: "{typography.label}"
---

# Design System: What Did I Say

## 1. Overview

**Creative North Star: "The Quiet Instrument"**

This is a precision tool that sits in the menu bar and stays out of the way. Every surface is built from AppKit and SwiftUI system primitives, so the app reads as something that shipped with macOS rather than something bolted onto it. The bar for any control is the one PRODUCT.md sets: would this look out of place next to Bartender, CleanShot, or a native system menu? If yes, it does not ship. Color, type, materials, and controls are all inherited from the operating system, which means the interface adapts automatically to the user's appearance (light/dark), accent color, and Dynamic Type without a single override.

The system is deliberately thin. There is no custom palette, no custom font, no bespoke component library. That absence is the design: familiarity is the trust mechanism. Because the core action is recording a private conversation, the interface earns confidence by being legible and boring in exactly the way a system utility is boring. The one place the design raises its voice is state and consent: the recording dot, the countdown toast, the permission flow, and the single cloud-summary boundary are all made obvious, never buried in chrome.

The system explicitly rejects the things PRODUCT.md names as anti-references: no Electron or web-app feel, no custom window chrome, no loud SaaS dashboards with gradient accents or hero-metric templates, no dense settings walls, and nothing that reads as spyware-adjacent. When a surface needs personality, it gets it from correct system materials and honest copy, not from decoration.

**Key Characteristics:**
- System-semantic color only; the OS owns the palette, light and dark
- SF Pro throughout, via semantic text styles that respect Dynamic Type
- Flat by default; depth comes from native window/popover materials, not custom shadows
- Stock, unadorned controls; the only custom elements are status indicators
- Fixed-width surfaces sized to their glance-length purpose (320pt popover, compact panels)
- State and consent are loud; everything else recedes

## 2. Colors

The palette is not authored; it is inherited. Every color is a SwiftUI semantic role that AppKit resolves at runtime for the user's appearance and accent selection. The hex values in the frontmatter are approximate Apple sRGB values for the default light appearance, provided only so tooling has something to render. They are not the source of truth.

### Primary
- **System Accent** (`.accentColor` / `.tint`, ~#007AFF default): The one interactive-emphasis color. Carries the primary button when idle, the active step dot, and switch fills. It is whatever the user set as their macOS accent, so it is never assumed to be blue.

### Secondary
- **Recording Red** (`.red`, ~#FF3B30): Reserved for the live recording state and errors. It tints the primary button while recording, the recording dot, the elapsed-time label, and failure messages. Its scarcity is what makes "we are recording" unmistakable.
- **Processing Orange** (`.orange`, ~#FF9500): The transient in-between states, saving audio, transcribing, permissions-needed warnings, and the relaunch note. Signals "attention, not error."
- **Success Green** (`.green`, ~#34C759): Granted permissions and completed setup only. Confirmation, never decoration.

### Neutral
- **Primary Label** (`.primary` / default foreground, ~#1D1D1F light): All primary text. Dynamic; near-black in light, near-white in dark.
- **Secondary Label** (`.secondary`, ~#8E8E93): The dominant text tone in this app. Section headers, captions, timestamps, helper copy, and idle status. Most text is intentionally secondary; the interface whispers.
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
- **Headline** (`.headline`, semibold, ~15px): The popover title, section headings inside modals, and the confirmation toast title. The workhorse heading.
- **Title** (`.title3`, bold, ~15px): Step titles and the done-state heading in onboarding.
- **Body** (`.callout` / `.body`, regular, ~13px): Explanatory copy, the "why we need this" text, and the recording timer label. Kept short; these surfaces are read in glances.
- **Label** (`.caption` / `.caption2`, regular, ~11px and smaller): The most-used size in the app. Settings row labels, toggle text, history entries, timestamps, permission rows, and helper hints. This is where the interface does most of its talking, quietly.
- **Mono** (`.system(.body, design: .monospaced)` / `.monospacedDigit()`, ~13px): The detection countdown and the elapsed recording clock, so digits do not jitter as they tick.

### Named Rules
**The Semantic Scale Rule.** Size and weight are chosen by naming a text style (`.headline`, `.caption`), never by setting an explicit point size on body text. The only explicit sizes allowed are on SF Symbol glyphs in headers (`.system(size: 26–48)`), where the symbol is functioning as an illustration, not as text.

**The Secondary-First Rule.** Default body and label text to `.secondary`. Primary label weight is reserved for the one or two things on a surface that genuinely lead. A wall of primary-weight text is a design bug.

## 4. Elevation

The system is flat by default and uses no custom `box-shadow` vocabulary. Depth is delegated entirely to native window materials: the `MenuBarExtra` window, floating `NSWindow`s, and the `NSPanel` toast each sit on the system's own translucent material and carry the system's own window shadow. Titlebars are transparent and hidden (`titlebarAppearsTransparent`, `titleVisibility = .hidden`) so the content material runs edge to edge.

Within a surface, the only lift is tonal, not cast: the onboarding privacy callout uses a `.quaternary` fill at ~40% opacity to separate itself from the background. No drop shadow, no border, no glass blur added on top of the system's own.

### Named Rules
**The No Custom Shadow Rule.** Never add a `.shadow()` or a synthetic glass/blur layer. macOS already provides the correct window shadow and material vibrancy. Anything layered on top reads as non-native, which is exactly the "built, not shipped" feel this product forbids.

**The Tonal Lift Rule.** When an element inside a surface needs to stand apart, raise it with a `.quaternary` fill and a `10px` corner radius, not a shadow or a stripe.

## 5. Components

Every control is a stock SwiftUI/AppKit primitive used with its default styling. Nothing is re-skinned. The philosophy is stock and unadorned: the only custom-drawn pieces are the status indicators that must carry meaning a system control cannot.

### Buttons
- **Shape:** System default radius (~6px); never overridden.
- **Primary:** `.borderedProminent`, tinted with the system accent. The single lead action on a surface (Start Recording, Continue, Save, Grant Permission). Full-width inside modal footers and the popover.
- **Primary while recording:** Same `.borderedProminent`, but `.tint(.red)`. The button itself becomes the recording signal.
- **Secondary:** `.bordered`, often at `.controlSize(.small)` (Open Setup Guide, Back).
- **Borderless / icon:** `.borderless` with an SF Symbol only, for quit, open-note, and remove-row. Always paired with a `.help(...)` tooltip.
- **Plain text:** `.font(.caption)` bare buttons for low-stakes inline actions (Choose vault, Open Settings, Add).
- **Control sizing:** `.large` in onboarding modals, default in the popover, `.small`/`.mini` for dense settings and banners. Size signals stakes.

### Toggles
- **Style:** `.switch`, `.controlSize(.mini)`, label in `.caption`. Used for auto-detect, diarization, and AI summary. Reveals dependent controls inline when enabled (the summary backend picker appears only when AI summary is on).

### Inputs / Fields
- **Style:** `.textFieldStyle(.roundedBorder)` for names, Ollama model, and vault input; `SecureField` (same style) for the Anthropic API key. `.controlSize(.small)` in settings.
- **Pickers:** menu style for model/vault selection; `.segmented` for the local-vs-cloud summary backend toggle.

### Status Badge (signature)
- A custom indicator, not a system control, because state must be unmistakable. An 8pt `Circle` filled with the state color (`.secondary` idle, `.red` recording, `.orange` processing) plus a `.caption` `.secondary` text label. Color and text always travel together, never color alone, so it stays legible under Increase Contrast and for color-blind users.

### Recording Countdown Toast (signature)
- An `NSPanel` (`.nonactivatingPanel`, floating, joins all Spaces) pinned to the bottom-right of the active screen with a 24pt inset. Shows the detected source, a monospaced countdown, and Ignore / Start Now actions. It is the consent surface: it appears before recording starts, states that all participants may be recorded, and never records on its own — if the visible 15-second count elapses without a choice, the toast dismisses and nothing is recorded.

### Step Indicator
- Onboarding progress dots: 6pt circles, system accent for the current step, `.secondary` at 30% opacity for the rest.

## 6. Do's and Don'ts

### Do:
- **Do** use semantic SwiftUI colors (`.red`, `.secondary`, `.accentColor`, `.tint`) for every color. The OS owns the palette.
- **Do** choose type by naming a semantic text style (`.headline`, `.caption`), so Dynamic Type works without effort.
- **Do** default text to `.secondary`; reserve primary weight for the one thing that leads.
- **Do** keep red for the recording state and errors only, per the Red Means Recording Rule.
- **Do** pair every status color with a text label and an SF Symbol; never rely on color alone.
- **Do** use stock `.borderedProminent` / `.bordered` / `.borderless` buttons and `.switch` toggles as-is.
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
