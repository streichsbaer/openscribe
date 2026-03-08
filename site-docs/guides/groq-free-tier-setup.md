# Groq Free Tier Setup

Groq is the recommended transcription provider for the free-tier OpenScribe setup. It is fast, optimized, and gives a much better day-one experience than relying on the default local model alone.

!!! note "Check current plan limits first"
    Groq publishes separate free-plan and developer-plan limits. Review the current [rate limits](https://console.groq.com/docs/rate-limits) and [spend limits](https://console.groq.com/docs/spend-limits) before you rely on a setup.

## 1. Create a Groq API key

1. Sign in to the [Groq Console](https://console.groq.com/keys).
2. Create a new API key.
3. Copy it once and keep it ready for OpenScribe.

## 2. Add the key to OpenScribe

1. Open Settings > Providers.
2. Paste the key into the Groq field.
3. Use Verify.
4. Use Refresh models.

OpenScribe stores provider keys in the macOS Keychain.

## 3. Use Groq for transcription

For the recommended free-tier setup:

1. Open Settings > Transcribe.
2. Choose `Groq Whisper` as the provider.
3. Pick `whisper-large-v3-turbo`.
4. Leave language on `auto`.

This is the speech-to-text setup Stefan is using on this machine.

## 4. Recommended pairing

Groq is the recommended transcription step. For polish, pair it with Gemini rather than trying to do everything with one provider.

Use the companion guide here:

- [Gemini Free Tier Setup](gemini-free-tier-setup.md)

## Continue

- Main setup guide: [Using Free Tiers](free-tiers.md)
- Provider overview: [Providers and Models](providers.md)
