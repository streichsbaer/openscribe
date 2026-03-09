# Using Free Tiers

If you want the best OpenScribe experience without paying first, use cloud free tiers.

For this guide, the recommended path is:

- Transcription on `Groq Whisper`
- Transcription model `whisper-large-v3-turbo`
- Polish on `Groq`
- Polish model `openai/gpt-oss-120b`
- Language mode `auto`
- Copy on complete `On`

This setup gives a better first impression than the default local model alone. Groq transcription is fast and optimized, polish adds a large part of the value people notice in OpenScribe, and one provider key keeps the setup simpler.

!!! note "Free-tier terms can change"
    These guides focus on providers that currently let many users get started without adding a credit card. Check the linked provider docs to confirm current account, rate-limit, and billing requirements before you rely on them.

## Why this is the recommended path

- Groq gives near-instant transcription and feels better than the local baseline for day-one use.
- `openai/gpt-oss-120b` on Groq is strong for transcript cleanup without adding a second provider.
- Gemini can cover both transcription and polish if you want to experiment there, but it is not the recommended polish provider for this guide.
- Polish makes OpenScribe feel much more useful because the output is closer to ready-to-paste text.
- This combination stays simple: one provider, one key, and one model catalog to refresh.

## How Stefan uses OpenScribe

Stefan's current setup on this machine is:

- Transcribe with `Groq Whisper`
- Model `whisper-large-v3-turbo`
- Polish enabled
- Polish provider `Groq`
- Polish model `openai/gpt-oss-120b`
- Language `auto`
- Copy on complete enabled

If you want to copy the setup that is already working well in practice, use those exact values.

## Setup order

1. Open Settings > Providers and add your Groq API key.
2. In Settings > Transcribe, choose `Groq Whisper`.
3. Set the transcription model to `whisper-large-v3-turbo`.
4. In Settings > Polish, turn polish on.
5. Choose `Groq`.
6. Set the polish model to `openai/gpt-oss-120b`.
7. Keep language on `auto`.
8. Leave copy on complete on.

## Provider walkthroughs

- [Groq Free Tier Setup](groq-free-tier-setup.md)
- [Gemini Free Tier Setup](gemini-free-tier-setup.md)
- [OpenRouter Free Tier Setup](openrouter-free-tier-setup.md)

OpenRouter and Gemini are useful as alternative experiment paths. The main recommendation for the best free-tier experience is Groq transcription plus Groq polish on `openai/gpt-oss-120b`.

## What about the local model?

OpenScribe still supports local `whisper.cpp`, and it is useful when you specifically want local-only processing. It is not the recommended path for this guide because Groq gives a faster and stronger first-time experience.

## What about OpenAI?

OpenScribe supports OpenAI, but this page is focused on free tiers. OpenAI belongs in the broader [Providers and Models](providers.md) guide rather than this setup path.

## Continue

- First launch and hotkeys: [Getting Started](getting-started.md)
- Full provider overview: [Providers and Models](providers.md)
- Pipeline walkthrough: [How It Works](how-it-works.md)
