# Getting Started

## Install OpenScribe

Download the latest stable release from [GitHub Releases](https://github.com/streichsbaer/openscribe/releases/latest/download/OpenScribe-latest.zip) and drag `OpenScribe.app` to your Applications folder.

### Install with Homebrew

```bash
brew install --cask https://github.com/streichsbaer/openscribe/releases/latest/download/openscribe.rb
```

OpenScribe is distributed as a signed and notarized app for direct download.

## Launch it once

Open OpenScribe from Applications and grant microphone access when macOS prompts you. After launch, the app lives in your menu bar, so the key thing to look for is the OpenScribe icon near the clock.

On a fresh install, OpenScribe opens a setup assistant in Settings. You can follow the `Best setup` checklist for the recommended Groq path, switch to `Local only` for local transcription, or skip it and return later from Settings or the menu bar.

## Your first recording

1. Press `Fn + Space` to start recording.
2. Speak for a few seconds.
3. Press `Fn + Space` again to stop.
4. Click the menu bar icon to open the popover and see your transcript.

The raw transcript appears first. If polish is enabled, the polished version appears below it in the same view.

![Live tab after a recording](/images/ui/openscribe-live.png){ .guide-shot data-light-src="/images/ui/openscribe-live.png" data-dark-src="/images/ui/openscribe-live-dark.png" }

If you do not see any text after stopping, check the menu bar icon state. A no-audio icon usually means macOS recorded silence or the wrong microphone.

## Tune the basics next

If you just want a quick smoke test, the default local whisper.cpp provider is enough to confirm that recording works.

If you want the best day-to-day setup after launch, continue with [Using Free Tiers](free-tiers.md) and configure Groq transcription plus Groq polish on `openai/gpt-oss-120b`.

If you want OpenScribe to clean up grammar and formatting after transcription, turn on polish in Settings > Polish and then tailor the output with [Custom Rules](custom-rules.md).

If the default shortcuts do not fit your workflow, open Settings > Hotkeys and adjust them before you build muscle memory.

For a complete tour of the popover, menu bar states, and every settings tab, use the [UI Reference](../reference/ui-reference.md).

## Building from source

If you want to build and run OpenScribe from source, see [Development Setup](../reference/development-setup.md).
