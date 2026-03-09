# OpenRouter Free Tier Setup

OpenRouter is an alternative free-tier option when you want one API key and access to rotating free chat models. For OpenScribe, it is most useful as a polish experiment path, not the main recommendation.

!!! note "Free models can change quickly"
    OpenRouter's free-model availability and rate limits can change. Check the current [authentication guide](https://openrouter.ai/docs/api-reference/authentication) and [FAQ](https://openrouter.ai/docs/faq) before you depend on a specific model.

## 1. Create an OpenRouter API key

1. Sign in to [OpenRouter](https://openrouter.ai/).
2. Create an API key from the key settings flow linked in the [authentication guide](https://openrouter.ai/docs/api-reference/authentication).
3. Copy the key.

## 2. Add the key to OpenScribe

1. Open Settings > Providers.
2. Paste the key into the OpenRouter field.
3. Use Verify.
4. Use Refresh models.

## 3. Use OpenRouter for polish

If you want to experiment with OpenRouter on its free tier:

1. Open Settings > Polish.
2. Turn polish on.
3. Choose `OpenRouter` as the provider.
4. Start with `openrouter/free` if it appears in the model list.
5. If you want a fixed model, choose a model variant that ends with `:free`.

## 4. Keep the main recommendation in mind

OpenRouter is useful when you want flexibility. The main free-tier recommendation for the best OpenScribe experience is still:

- Groq transcription with `whisper-large-v3-turbo`
- Groq polish with `openai/gpt-oss-120b`

## Continue

- Main setup guide: [Using Free Tiers](free-tiers.md)
- Provider overview: [Providers and Models](providers.md)
