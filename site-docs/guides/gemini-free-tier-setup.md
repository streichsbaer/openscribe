# Gemini Free Tier Setup

Gemini is an alternative free-tier provider for OpenScribe. It can handle both transcription and polish, but it is not the recommended polish provider for the main setup path due to increased latency.

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

## 3. Use Gemini in OpenScribe

If you want to experiment with Gemini as a one-provider path:

1. Open Settings > Transcribe.
2. Choose `Gemini` as the provider.
3. Pick `gemini-3.1-flash-lite-preview` if you want a shared model that works in both Transcribe and Polish.
4. If you also want Gemini polish, open Settings > Polish, turn polish on, choose `Gemini`, and use the same model there.

Use this when you want to stay inside Google's model catalog for both stages.

## 4. How it fits with the main recommendation

Gemini can cover both transcription and polish, but the main recommendation remains Groq transcription plus Groq polish on `openai/gpt-oss-120b`. That path is simpler and matches the setup Stefan is using on this machine.

Use the companion guide here:

- [Groq Free Tier Setup](groq-free-tier-setup.md)

## Continue

- Main setup guide: [Using Free Tiers](free-tiers.md)
- Provider overview: [Providers and Models](providers.md)
