# Using Free Tiers

If you want the best OpenScribe experience without paying first, use cloud free tiers.

For this guide, the recommended path is:

- Transcription on `Groq Whisper`
- Transcription model `whisper-large-v3-turbo`
- Polish on `Gemini`
- Polish model `gemini-3.1-flash-lite-preview`
- Language mode `auto`
- Copy on complete `On`

This setup gives a better first impression than the default local model alone. Groq transcription is fast and optimized, and polish adds a large part of the value people notice in OpenScribe.

!!! note "Free-tier terms can change"
    These guides focus on providers that currently let many users get started without adding a credit card. Check the linked provider docs to confirm current account, rate-limit, and billing requirements before you rely on them.

## Why this is the recommended path

- Groq gives near-instant transcription and feels better than the local baseline for day-one use.
- Gemini 3.1 Flash Lite is fast and capable for transcript cleanup.
- Gemini can also transcribe, but Groq is the faster transcription choice in this setup.
- Polish makes OpenScribe feel much more useful because the output is closer to ready-to-paste text.
- This combination stays simple: one provider for speech-to-text and one provider for cleanup.

## How Stefan uses OpenScribe

Stefan's current setup on this machine is:

- Transcribe with `Groq Whisper`
- Model `whisper-large-v3-turbo`
- Polish enabled
- Polish provider `Gemini`
- Polish model `gemini-3.1-flash-lite-preview`
- Language `auto`
- Copy on complete enabled

If you want to copy the setup that is already working well in practice, use those exact values.

## Setup order

1. Open Settings > Providers and add your Groq API key.
2. In Settings > Transcribe, choose `Groq Whisper`.
3. Set the transcription model to `whisper-large-v3-turbo`.
4. Back in Settings > Providers, add your Gemini API key.
5. In Settings > Polish, turn polish on.
6. Choose `Gemini` and set the model to `gemini-3.1-flash-lite-preview`.
7. Keep language on `auto`.
8. Leave copy on complete on.

## Provider walkthroughs

- [Groq Free Tier Setup](groq-free-tier-setup.md)
- [Gemini Free Tier Setup](gemini-free-tier-setup.md)
- [OpenRouter Free Tier Setup](openrouter-free-tier-setup.md)

OpenRouter is useful as an alternative for polish experiments. The main recommendation for the best free-tier experience remains Groq transcription plus Gemini polish.

## What about the local model?

OpenScribe still supports local `whisper.cpp`, and it is useful when you specifically want local-only processing. It is not the recommended path for this guide because Groq gives a faster and stronger first-time experience.

## What about OpenAI?

OpenScribe supports OpenAI, but this page is focused on free tiers. OpenAI belongs in the broader [Providers and Models](providers.md) guide rather than this setup path.

## Continue

- First launch and hotkeys: [Getting Started](getting-started.md)
- Full provider overview: [Providers and Models](providers.md)
- Pipeline walkthrough: [How It Works](how-it-works.md)
