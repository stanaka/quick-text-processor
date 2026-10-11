# QuickTextProcessor

A native macOS utility: press a global shortcut anywhere, capture the selected
text (plus its surrounding context), run it through an LLM with a task-specific
prompt, and get the result in a small floating window — or inserted straight
back at the cursor.

Built with Swift 5.9+, SwiftUI + AppKit, SwiftPM and a Makefile. No Xcode
project, no third-party dependencies.

## Features

- **Global hotkey → task palette.** Default ⌃⌥Space (configurable). A small
  floating palette lists your tasks; pick with ↑/↓, 1–9, or ⏎; esc cancels.
- **Selection capture via Accessibility**, with automatic fallback to the
  current clipboard text when an app exposes no AX selection. Up to N
  characters before/after the selection and the frontmost app's name are sent
  along so the LLM can match tone and terminology. Password fields are never
  read.
- **Five bundled tasks** (editable, reset-to-default): fix dictation,
  proofread, summarize, translate → Japanese, translate → English.
- **Result handling.** Streaming floating window with Copy / Insert / Retry.
  Tasks with per-task auto-insert wait for your response when the result is
  ready: ⏎ replaces the selection (AX first, ⌘V paste fallback with clipboard
  save/restore), esc keeps your text untouched.
- **Main window** with:
  - **Playground** — try any text/task/provider without leaving the app,
  - **History** — locally persisted runs (capped, searchable, re-run/delete),
  - **Dictionary** — a glossary injected into prompts ({{glossary}}),
  - **Settings** — hotkey, providers, prompt templates, capture and history
    options, launch at login.
- **Three provider types** (any number of profiles):
  - `openai-compatible` — any `/v1/chat/completions` endpoint (OpenAI, xAI
    api.x.ai, Ollama, LM Studio, OpenRouter, …) with an API key,
  - `codex-oauth` — your ChatGPT subscription via the same OAuth flow and
    backend as the Codex CLI (sign in in-app, or import `~/.codex/auth.json`),
  - `xai-oauth` — your SuperGrok subscription via the grok CLI's OAuth flow
    (sign in in-app, or import `~/.grok/auth.json`).
- API keys and OAuth tokens live only in the macOS Keychain. The CLIs'
  `auth.json` files are read-only inputs and never modified.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ command line tools (`xcode-select --install`)

## Build, run, test

```sh
make build   # swift build -c release
make app     # assemble build/QuickTextProcessor.app
make icon    # regenerate build/AppIcon.icns from Support/AppIcon.png
make run     # build, assemble, launch
make test    # unit tests (QTPCore)
make clean
make cert    # one-time: create a stable dev signing identity (see below)
```

### DMG builds and releases

Build a release disk image locally on macOS:

```sh
make dmg VERSION=0.1.0
```

This builds an **Apple Silicon (arm64)** app in release configuration, stamps
both bundle version fields with `0.1.0`, signs it ad-hoc, and creates
`build/QuickTextProcessor-0.1.0-arm64.dmg`. The image contains the app and an
Applications shortcut for drag-and-drop installation. Packaging also verifies
the disk image, architecture, macOS 14 deployment target, version, signature,
icon, and bundled resources. Versions must be `X.Y.Z` with no leading zeros.

For ordinary app builds, `make app VERSION=0.1.0 ARCH=arm64` optionally overrides
the bundle version and build architecture. Omitting these retains the checked-in
plist version and SwiftPM's native build architecture.

To publish a release, commit and push the release changes, then tag that commit:

```sh
git tag -a v0.1.0 -m "QuickTextProcessor 0.1.0"
git push origin v0.1.0
```

The **Release** GitHub Actions workflow accepts stable `vX.Y.Z` tags only. It
runs tests and packaging checks on an Apple Silicon macOS runner, creates a
draft GitHub Release with generated notes, uploads the DMG, and publishes after
confirming the upload. It uses the built-in GitHub token with `contents: write`;
no additional secrets are required.

If a run fails, fix the underlying issue and rerun it from GitHub Actions when
the tagged source is still correct. A rerun resumes an existing draft and
replaces its DMG. Published releases are left untouched and cause the run to
fail explicitly. If a source change is required, commit it and publish a new
version tag rather than moving an existing tag.

These DMGs support **Apple Silicon Macs running macOS 14 or later**. They are
ad-hoc signed and **not notarized**. After downloading, drag the app to
Applications, attempt to open it, then use **System Settings → Privacy &
Security → Open Anyway** if macOS blocks it. Grant Accessibility as described
below. Developer ID signing, notarization, Intel builds, prereleases, and
automatic updates are not included in this release flow.

For the first published release, download the actual GitHub asset on an Apple
Silicon Mac and check installation, launch, the icon, bundled resources, and
the Accessibility permission flow. CI verifies the package but does not perform
interactive installation or launch checks.

### App icon

`Support/AppIcon.png` is the master artwork and the only thing you need to
touch to re-skin the app. `make app` renders it into `build/AppIcon.icns` via
`scripts/make-icon.swift` (CoreGraphics + `iconutil`, both stock macOS) and
copies it into the bundle before signing; the render only reruns when the PNG
or the script changes.

The script scales the artwork onto the standard macOS icon grid — an 824x824
body on a 1024x1024 canvas — and clips it to a rounded rect, so full-bleed
artwork does not end up oversized in the Dock and an opaque background does not
show up as a square. A uniform border around the artwork (image generators
usually return one) is detected and trimmed first, so the background does not
survive as a frame around the clip. Both ratios are constants at the top of the
script. Supply a 1024x1024 or larger master; anything smaller warns.

macOS caches icons by bundle identifier, so after changing the artwork the Dock
often keeps showing the old one. `touch build/QuickTextProcessor.app && killall
Dock` usually clears it.

### Accessibility permission

On first hotkey use, macOS asks to grant **Accessibility** to
QuickTextProcessor (System Settings → Privacy & Security → Accessibility).
Without it the app still works via the clipboard fallback, but cannot read
selections or synthesize ⌘V.

**Important for development:** an ad-hoc signature changes on every rebuild,
which makes macOS drop the Accessibility grant each time. To keep the grant
across rebuilds, run once:

```sh
make cert
```

This creates a self-signed code-signing certificate named
`QuickTextProcessor Dev` in your login keychain and marks it trusted for code
signing. Expect two one-time prompts:

1. during `make cert`, an authorization dialog for the trust settings;
2. on the first build afterwards, a keychain dialog *"codesign wants to sign
   using key…"* — click **Always Allow**.

After the next `make run`, grant Accessibility once more; because the app's
signing identity (and bundle id) is now stable, the grant survives all future
rebuilds.

When no `IDENTITY` is passed, `make app` picks a signing identity
automatically: the `QuickTextProcessor Dev` certificate if present, else any
`Apple Development` identity from your keychain, else ad-hoc (`-`) with a
warning. An explicit `make IDENTITY=... app` always wins.

If `make cert` cannot set the trust settings automatically (e.g. over SSH),
create the certificate manually instead: Keychain Access → Certificate
Assistant → Create a Certificate… → name `QuickTextProcessor Dev`, type
*Code Signing*; then Get Info → Trust → Code Signing: **Always Trust**.

## Configuring providers

Open **Settings → Providers** in the main window.

- **OpenAI-compatible**: set base URL + model, paste an API key, Save.
  The key goes to the Keychain.
- **ChatGPT (Codex)**: click *Sign in with Browser…* (uses
  `auth.openai.com` with the Codex CLI's client id; the redirect lands on
  `localhost:1455`, so quit any running `codex login` first) — or click
  *Import from Codex CLI* if you are already logged in there.
  Default model: `gpt-5.6-sol`.
- **Grok (xAI)**: same idea against `auth.x.ai` (ports 56121–56125), or
  *Import from Grok CLI*. Default model: `grok-4.6`. Requires a SuperGrok
  subscription.

The refresh button next to the model field fetches the provider's current
model list (`GET …/v1/models` for OpenAI-compatible endpoints, the CLI
catalog endpoints for Codex/Grok) into a picker menu; free-text entry
always stays possible for models the list doesn't carry.

> **Note:** the codex and xai OAuth providers talk to the same subscription
> backends as the official CLIs (`chatgpt.com/backend-api/codex`,
> `cli-chat-proxy.grok.com`). These are not public APIs — they can change
> without notice, and using them from third-party clients may not be covered
> by the providers' terms of service. The `openai-compatible` profile type is
> the always-supported path. All endpoint constants are isolated in
> `Sources/QTPCore/CodexWire.swift` / `XAIWire.swift` for easy fixing. If the
> codex backend starts rejecting requests with an instructions error, refresh
> `Sources/QuickTextProcessor/Resources/codex_instructions.md` from
> `openai/codex:codex-rs/core/<model>_prompt.md`.

## Usage

1. Select text in any app (or copy something if the app has no AX selection).
2. Press ⌃⌥Space.
3. Pick a task (↑/↓ + ⏎, or 1–9).
4. Watch the result stream into the floating window → **Copy** or **Insert**;
   tasks with *auto-insert* (default: Fix dictation) then wait for your
   response — press ⏎ to replace the selection, esc to dismiss.

Empty input is refused with a message; multiline text, emoji and Japanese are
handled correctly end to end (all Accessibility ranges are UTF-16-safe).

## Customizing

- **Prompts**: Settings → Tasks. Templates use `{{selected_text}}`,
  `{{context_before}}`, `{{context_after}}`, `{{app_name}}`, `{{glossary}}`.
  Substitution is single-pass, so placeholder-like text inside the captured
  selection is never expanded. Bundled tasks have a *Reset to Default*.
- **Glossary**: the Dictionary section. Entries become a "Preferred
  terminology" block wherever a task includes `{{glossary}}`.
- **Context size**: Settings → General (characters per side, 0 disables).
- **History**: pause saving or change the cap in Settings; data lives in
  `~/Library/Application Support/QuickTextProcessor/` as plain JSON
  (`tasks.json`, `history.json`, `glossary.json`).

## Code layout

```
Sources/QTPCore/            pure logic, unit-tested (swift test)
  Models, stores (JSON), TemplateRenderer, GlossaryFormatter,
  TextContext (UTF-16 range math), SSEParser, provider wire formats
  (OpenAICompatWire / ResponsesWire / CodexWire / XAIWire), PKCE
Sources/QuickTextProcessor/ the app
  AppController (hotkey → capture → palette → LLM → result/insert pipeline)
  Hotkey/   Carbon RegisterEventHotKey + recorder UI
  Capture/  AX selection+context capture, insert-back (AX / paste)
  Panels/   non-activating floating palette & result panels
  LLM/      URLSession streaming, per-provider clients, token refresh
  OAuth/    localhost callback server + browser PKCE flows
  Views/    Playground, History, Dictionary, Settings
Tests/QTPCoreTests/         unit tests for everything in QTPCore
Support/                    Info.plist, AppIcon.png (icon master)
scripts/                    dev-cert.sh (signing identity), make-icon.swift
```

Design choices worth knowing before hacking:

- The palette panel is a **non-activating** `NSPanel` that can become key —
  it takes keystrokes without activating the app, so the target app keeps its
  selection/focus for insert-back. Never call `NSApp.activate` around it.
- All AX text ranges are **UTF-16 code units**; slicing goes through
  `TextContext`, which is surrogate-pair-safe. Don't use `prefix`/`suffix`
  with AX counts.
- Chromium apps get `AXManualAccessibility` set on first capture failure
  (`Capture/ElectronAccessibility.swift`). The legacy `AXEnhancedUserInterface`
  is **never** set: it breaks window moving/resizing in Electron apps.
- Insert-back hides the app's own panels before synthesizing ⌘V, then
  restores the previous clipboard only if `changeCount` proves nobody else
  wrote to it meanwhile.
- Every request body is built with `Codable` — no string-interpolated JSON
  anywhere.

## Troubleshooting

- **Hotkey does nothing**: the combo may be taken by another app (Settings →
  General shows a warning); Accessibility may be missing for capture.
- **No selection captured in Electron apps** (Slack, Discord, ...): Chromium
  keeps its accessibility tree off until an assistive technology asks for it.
  QuickTextProcessor sets `AXManualAccessibility` on the app and waits for the
  tree; Electron debounces that switch-on by 2 s, so the first press after an
  app launches can take a moment, and later ones are immediate. Plain Google
  Chrome ignores the attribute and may keep degrading.
- **No selection captured in VS Code** (or Cursor, Windsurf, Positron, Azure
  Data Studio): the tree above is necessary but not sufficient. Monaco paints
  the selection as overlay elements and only writes it somewhere readable when
  it thinks a screen reader is attached, so a capture needs
  `"editor.accessibilitySupport": "on"` in VS Code's settings. That is a real
  trade: it also disables the minimap, code folding, and word wrap. Without it
  the editor selection cannot be read through the Accessibility API at all —
  though selections in VS Code's *webviews* (markdown preview, chat) still work.
- **Diagnosing a capture**: every capture logs one line at `notice`, which is
  persisted, so a press that already happened can be inspected after the fact:
  `log show --last 5m --predicate 'subsystem == "com.stanaka.QuickTextProcessor"'`
  (or `log stream --predicate ...` to follow live). `Captured N chars from ...`
  means it worked; `Enabled AXManualAccessibility for pid N` means the app
  accepted the switch-on, and `rejected` means it is not an Electron app. If
  even the subsystem filter shows nothing, widen it to
  `log show --last 5m --predicate 'process == "QuickTextProcessor"'` — silence
  there means the running app is not this build.
- **No context captured in some apps**: Java apps (and Chromium ones without a
  full tree) often lack the AX range attributes — the app degrades to
  selection-only, then clipboard.
- **Insert did nothing**: some apps accept the AX write but ignore it; the
  paste fallback needs the target app to accept ⌘V in the focused field.
- **Port 1455 busy** during ChatGPT sign-in: quit `codex login` and retry.
- **Clipboard managers** will record the transient pasteboard value used by
  the paste fallback; that is unavoidable.
