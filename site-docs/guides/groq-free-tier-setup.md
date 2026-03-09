# Groq Free Tier Setup

Groq is the recommended provider for the free-tier OpenScribe setup. It gives you fast transcription, strong polish, and a simpler one-key setup.

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

## 4. Use Groq for polish

For the recommended free-tier setup:

1. Open Settings > Polish.
2. Turn polish on.
3. Choose `Groq` as the provider.
4. Pick `openai/gpt-oss-120b`.

This is the polish setup Stefan is using on this machine.

## 5. Free-plan limits for the recommended models

Groq publishes a shared free-plan rate-limit table. As of March 9, 2026, the recommended models are listed there with these base limits:

- `whisper-large-v3-turbo`: `20 RPM`, `2K RPD`, `7.2K ASH`, `28.8K ASD`
- `openai/gpt-oss-120b`: `30 RPM`, `1K RPD`, `8K TPM`, `200K TPD`

Groq defines `ASH` as audio seconds per hour and `ASD` as audio seconds per day.

Check Groq's current docs before you rely on a limit in production because plan details can change.

## 6. Why this is the recommendation

Groq handles both stages well, keeps setup simpler than a two-provider path, and still gives you room to experiment with Gemini or OpenRouter later.

## Continue

- Main setup guide: [Using Free Tiers](free-tiers.md)
- [Gemini Free Tier Setup](gemini-free-tier-setup.md)
- [OpenRouter Free Tier Setup](openrouter-free-tier-setup.md)
- Provider overview: [Providers and Models](providers.md)
