# Getting Started

## Install OpenScribe

Download the latest release from [GitHub Releases](https://github.com/streichsbaer/openscribe/releases) and drag `OpenScribe.app` to your Applications folder.

!!! note "Unsigned builds"
    OpenScribe is currently distributed as an unsigned app. On first launch, right-click the app and select Open, then confirm in the security dialog. Apple Developer Program enrollment is pending.

## First launch

1. Open OpenScribe from Applications.
2. Grant microphone access when prompted.
3. The OpenScribe icon appears in your menu bar.

## Your first recording

1. Press `Fn + Space` to start recording.
2. Speak for a few seconds.
3. Press `Fn + Space` again to stop.
4. Click the menu bar icon to open the popover and see your transcript.

The raw transcript appears first. If polish is enabled, the polished version follows.

## What to explore next

- **Providers**: by default, transcription runs locally with whisper.cpp. See [Providers and Models](providers.md) to set up cloud providers or change models.
- **Polish**: enable polish in Settings > Providers to get cleaned-up transcripts. See [Custom Rules](custom-rules.md) to personalize the output.
- **Hotkeys**: customize keyboard shortcuts in Settings > Hotkeys.
- **Settings**: see [Menu and Settings](menu-and-settings.md) for the full settings reference.

## Building from source

If you want to build and run OpenScribe from source, see [Development Setup](../reference/development-setup.md).
