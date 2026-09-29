# UI Reference

This page is the user-facing reference for the menu bar icon, popover tabs, and every Settings tab in OpenScribe.

## Menu bar

The menu bar icon is your home base while OpenScribe is running.

- Left click toggles the popover.
- Right click opens a menu with:
  - `Settings`
  - `Quit OpenScribe`

## Menu bar icon states

The icon changes as your recording moves through the pipeline.

### Idle

OpenScribe is ready for a new recording.

![Menu bar icon in idle state](/images/ui/menubar-icon-light-idle.png){ .menu-icon data-light-src="/images/ui/menubar-icon-light-idle.png" data-dark-src="/images/ui/menubar-icon-dark-idle.png" }

### Recording (working)

Audio capture is active and OpenScribe is receiving usable microphone input.

![Menu bar icon in recording working state](/images/ui/menubar-icon-light-recording-working.png){ .menu-icon data-light-src="/images/ui/menubar-icon-light-recording-working.png" data-dark-src="/images/ui/menubar-icon-dark-recording-working.png" }

### Recording (no audio input)

Recording is active, but OpenScribe is not receiving a usable signal.

![Menu bar icon in recording no-audio state](/images/ui/menubar-icon-light-recording-no-audio.png){ .menu-icon data-light-src="/images/ui/menubar-icon-light-recording-no-audio.png" data-dark-src="/images/ui/menubar-icon-dark-recording-no-audio.png" }

### Transcribing

Recording has stopped and speech-to-text is running.

![Menu bar icon in transcribing state](/images/ui/menubar-icon-light-transcribing.png){ .menu-icon data-light-src="/images/ui/menubar-icon-light-transcribing.png" data-dark-src="/images/ui/menubar-icon-dark-transcribing.png" }

### Polishing

The raw transcript is complete and the optional polish step is running.

![Menu bar icon in polishing state](/images/ui/menubar-icon-light-polishing.png){ .menu-icon data-light-src="/images/ui/menubar-icon-light-polishing.png" data-dark-src="/images/ui/menubar-icon-dark-polishing.png" }

## Popover tabs

Open the popover to see the current run and browse recent sessions.

### Live tab

The Live tab records and shows the current session. The top card holds the record button, a live waveform, the timer, and the microphone picker. The route below it shows each step and where it ran: blue means on this Mac, orange means the cloud, and one sentence says what left the Mac. The transcript card shows your text with vocabulary fixes highlighted. With polish on, switch between Polished, Raw, and Changes. Use Transcribe again or Polish again to rerun a step with another model.

![Live tab](/images/ui/openscribe-live.png){ .guide-shot data-light-src="/images/ui/openscribe-live.png" data-dark-src="/images/ui/openscribe-live-dark.png" }

### History tab

The History tab groups past sessions by day. Select a session to play it, copy it, or open the menu to open it in Live, transcribe it again, reveal it in Finder, select several, or move it to the Trash. A cloud badge marks sessions that sent audio or text to the cloud, and failed sessions offer Retry.

![History tab](/images/ui/openscribe-history.png){ .guide-shot data-light-src="/images/ui/openscribe-history.png" data-dark-src="/images/ui/openscribe-history-dark.png" }

### Stats tab

The Stats tab shows how much you dictated in the last 7 days, 30 days, or all time, with speaking time and pace. Activity shows a year of dictation days with your streak, and Where your words went counts sessions that stayed on this Mac or used the cloud. More details lists all-time totals and the models you use most.

![Stats tab](/images/ui/openscribe-stats.png){ .guide-shot data-light-src="/images/ui/openscribe-stats.png" data-dark-src="/images/ui/openscribe-stats-dark.png" }

## Settings window

You can open Settings from the right-click menu, with `Cmd + ,` when OpenScribe is focused, or with the configured Open Settings hotkey.

![Settings window](/images/ui/settings-window.png){ .guide-shot data-light-src="/images/ui/settings-window.png" data-dark-src="/images/ui/settings-window-dark.png" }

### General

- Appearance mode.
- Copy polished on completion.
- Auto-paste on completion.
- Accessibility permission status and controls.
- Microphone selection and permission controls.

![General settings tab](/images/ui/settings-general.png){ .guide-shot data-light-src="/images/ui/settings-general.png" data-dark-src="/images/ui/settings-general-dark.png" }

### Providers

- API key management for OpenAI, Groq, OpenRouter, Gemini, and Cerebras.
- Verify the current token for each provider.
- Refresh shared provider model lists used by Transcribe and Polish.

![Providers settings tab](/images/ui/settings-providers.png){ .guide-shot data-light-src="/images/ui/settings-providers.png" data-dark-src="/images/ui/settings-providers-dark.png" }

### Transcribe

- Transcription provider selection.
- Full-width transcription model browser.
- Run on the Neural Engine toggle when Local Parakeet is selected.
- Language mode.
- Optional custom transcription instruction.

![Transcribe settings tab](/images/ui/settings-transcribe.png){ .guide-shot data-light-src="/images/ui/settings-transcribe.png" data-dark-src="/images/ui/settings-transcribe-dark.png" }

### Polish

- Enable or disable polish.
- Polish provider.
- Full-width polish model browser.
- Optional custom polish instruction.

![Polish settings tab](/images/ui/settings-polish.png){ .guide-shot data-light-src="/images/ui/settings-polish.png" data-dark-src="/images/ui/settings-polish-dark.png" }

### Hotkeys

- Core shortcuts for recording, the popover, and settings.
- Clipboard shortcuts for copy latest, copy raw, and paste latest.
- Paste latest Accessibility dependency note.
- Popover tab shortcuts.

![Hotkeys settings tab](/images/ui/settings-hotkeys.png){ .guide-shot data-light-src="/images/ui/settings-hotkeys.png" data-dark-src="/images/ui/settings-hotkeys-dark.png" }

### Rules

- Edit the rules markdown used by polish.
- Save, revert, or open rules in an external editor.

![Rules settings tab](/images/ui/settings-rules.png){ .guide-shot data-light-src="/images/ui/settings-rules.png" data-dark-src="/images/ui/settings-rules-dark.png" }

### Vocabulary

- Turn vocabulary on or off, and include or exclude the built-in developer terms.
- See how each engine uses the list and whether Parakeet's vocabulary model is installed.
- Edit your own terms, then save or revert.

![Vocabulary settings tab](/images/ui/settings-vocabulary.png){ .guide-shot data-light-src="/images/ui/settings-vocabulary.png" data-dark-src="/images/ui/settings-vocabulary-dark.png" }

### Data

- Install and delete local models for Parakeet and whisper.cpp.
- View model disk usage.
- Open the App Support folder.
- Move App Support data to Trash.

![Data settings tab](/images/ui/settings-data.png){ .guide-shot data-light-src="/images/ui/settings-data.png" data-dark-src="/images/ui/settings-data-dark.png" }

### About

- App version and build.
- Current provider selections.
- Repository and governance links.

![About settings tab](/images/ui/settings-about.png){ .guide-shot data-light-src="/images/ui/settings-about.png" data-dark-src="/images/ui/settings-about-dark.png" }

## Related docs

- First run and daily workflow: [Getting Started](../guides/getting-started.md)
- Pipeline walkthrough: [How It Works](../guides/how-it-works.md)
- Product behavior contract: [Product Spec](../product/spec.md)
- Popover interaction details: [Popover Contract](popover-contract.md)
