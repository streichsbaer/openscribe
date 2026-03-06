# Menu and Settings

This page is the user-facing reference for OpenScribe menu behavior, popover tabs, and all Settings tabs.

## Menu bar behavior

- Left click on the menu bar icon toggles the popover.
- Right click on the menu bar icon opens a menu with:
  - `Settings`
  - `Quit OpenScribe`

## Menu bar icon states

### Idle

OpenScribe is ready and no active run is in progress.

![Menu bar icon in idle state](../images/ui/menubar-icon-light-idle.png){ .menu-icon }

### Recording (working)

Audio is currently being captured.

![Menu bar icon in recording working state](../images/ui/menubar-icon-system-recording-working.png){ .menu-icon }

### Recording (no audio input)

Recording is active, but OpenScribe is not receiving usable microphone input.

![Menu bar icon in recording no-audio state](../images/ui/menubar-icon-system-recording-no-audio.png){ .menu-icon }

### Transcribing

Audio capture is complete and speech-to-text is running.

![Menu bar icon in transcribing state](../images/ui/menubar-icon-system-transcribing.png){ .menu-icon }

### Polishing

Transcript polishing is running.

![Menu bar icon in polishing state](../images/ui/menubar-icon-system-polishing.png){ .menu-icon }

## Popover tabs

### Overview

![OpenScribe popover](../images/ui/openscribe-live.png)

### Live tab

- Shows the current run state and latest raw/polished text.
- Supports rerun actions for transcription and polish.

![Live tab](../images/ui/openscribe-live.png)

### History tab

- Lists previous sessions.
- Supports replay and opening the session folder in Finder.

![History tab](../images/ui/openscribe-history.png)

### Stats tab

- Shows aggregate usage and recent-run metrics.

![Stats tab](../images/ui/openscribe-stats.png)

## Settings window

You can open Settings from the right-click menu, from `Cmd + ,` when OpenScribe is focused, or with the configured Open Settings hotkey.

### Full settings window

![Settings window](../images/ui/settings-window.png)

### General tab

- Appearance mode.
- Copy polished on completion.
- Auto-paste on completion.
- Accessibility permission status and controls.
- Microphone selection and permission controls.

![General settings tab](../images/ui/settings-general.png)

### Providers tab

- API key management for OpenAI, Groq, OpenRouter, and Gemini.
- Verify the current token for each provider.
- Refresh shared provider model lists used by Transcribe and Polish.

![Providers settings tab](../images/ui/settings-providers.png)

### Transcribe tab

- Transcription provider selection.
- Full-width transcription model browser.
- Language mode.
- Optional custom transcription instruction.

![Transcribe settings tab](../images/ui/settings-transcribe.png)

### Polish tab

- Enable or disable polish.
- Polish provider.
- Full-width polish model browser.
- Optional custom polish instruction.

![Polish settings tab](../images/ui/settings-polish.png)

### Hotkeys tab

- Core shortcuts for recording, the popover, and settings.
- Clipboard shortcuts for copy latest, copy raw, and paste latest.
- Paste latest Accessibility dependency note.
- Popover tab shortcuts.

![Hotkeys settings tab](../images/ui/settings-hotkeys.png)

### Rules tab

- Edit the rules markdown used by polish.
- Save, revert, or open rules in an external editor.

![Rules settings tab](../images/ui/settings-rules.png)

### Data tab

- Install and delete local transcription models.
- View model disk usage.
- Open App Support folder.
- Move App Support data to Trash.

![Data settings tab](../images/ui/settings-data.png)

### About tab

- App version and build.
- Current default providers.
- Repository and governance links.

![About settings tab](../images/ui/settings-about.png)

## Related references

- Product behavior contract: [Product Spec](../product/spec.md)
- Popover interaction details: [Popover Contract](../reference/popover-contract.md)
