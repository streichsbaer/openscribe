# Gemini Free Tier Setup

Gemini is the recommended polish provider for the free-tier OpenScribe setup. It is fast, capable, and works well as the cleanup step after Groq transcription.

!!! note "Free-tier availability can vary"
    Google publishes separate free and paid tiers for the Gemini API, and regional availability can change. Check the current [API key guide](https://ai.google.dev/gemini-api/docs/api-key), [pricing](https://ai.google.dev/pricing), and [rate limits](https://ai.google.dev/gemini-api/docs/rate-limits) before you commit to a setup.

## 1. Create a Gemini API key

1. Open [Google AI Studio](https://aistudio.google.com/app/apikey).
2. Create or view a Gemini API key.
3. If AI Studio asks for a project, create one there or import an existing Google Cloud project first.
4. Copy the API key.

## 2. Add the key to OpenScribe

1. Open Settings > Providers.
2. Paste the key into the Gemini field.
3. Use Verify.
4. Use Refresh models.

## 3. Use Gemini for polish

For the recommended free-tier setup:

1. Open Settings > Polish.
2. Turn polish on.
3. Choose `Gemini` as the provider.
4. Pick `gemini-3.1-flash-lite-preview`.

This is the polish setup Stefan is using on this machine.

## 4. Recommended pairing

Gemini can also handle transcription in OpenScribe, but it is slower than Groq for this job. That is why the recommended pairing uses both providers for the tasks they do best: Groq for fast transcription and Gemini for polish.

Use the companion guide here:

- [Groq Free Tier Setup](groq-free-tier-setup.md)

## Continue

- Main setup guide: [Using Free Tiers](free-tiers.md)
- Provider overview: [Providers and Models](providers.md)
