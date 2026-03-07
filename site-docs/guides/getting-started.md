# Getting Started

## Install OpenScribe

Download the latest release from [GitHub Releases](https://github.com/streichsbaer/openscribe/releases) and drag `OpenScribe.app` to your Applications folder.

!!! note "Unsigned builds"
    OpenScribe is currently distributed as an unsigned app. On first launch, macOS may block it. If that happens, try to open the app once, then go to System Settings > Privacy & Security and use Open Anyway. Apple Developer Program enrollment is pending.

## Launch it once

Open OpenScribe from Applications and grant microphone access when macOS prompts you. After launch, the app lives in your menu bar, so the key thing to look for is the OpenScribe icon near the clock.

## Your first recording

1. Press `Fn + Space` to start recording.
2. Speak for a few seconds.
3. Press `Fn + Space` again to stop.
4. Click the menu bar icon to open the popover and see your transcript.

The raw transcript appears first. If polish is enabled, the polished version appears below it in the same view.

![Live tab after a recording](/images/ui/openscribe-live.png){ .guide-shot data-light-src="/images/ui/openscribe-live.png" data-dark-src="/images/ui/openscribe-live-dark.png" }

If you do not see any text after stopping, check the menu bar icon state. A no-audio icon usually means macOS recorded silence or the wrong microphone.

## Tune the basics next

If you want the simplest setup, leave transcription on the default local whisper.cpp provider. If you want cloud transcription or model choices, open [Providers and Models](providers.md) and add the services you want to use.

If you want OpenScribe to clean up grammar and formatting after transcription, turn on polish in Settings > Polish and then tailor the output with [Custom Rules](custom-rules.md).

If the default shortcuts do not fit your workflow, open Settings > Hotkeys and adjust them before you build muscle memory.

For a complete tour of the popover, menu bar states, and every settings tab, use the [UI Reference](../reference/ui-reference.md).

## Building from source

If you want to build and run OpenScribe from source, see [Development Setup](../reference/development-setup.md).
