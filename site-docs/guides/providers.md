# Providers and Models

OpenScribe supports local and cloud providers for both transcription and polish. You choose your providers in Settings > Providers.

## Transcription providers

### Local: whisper.cpp (default)

Whisper.cpp runs speech-to-text entirely on your Mac. No API key needed, no audio leaves your machine.

- Default model: `base`.
- Larger models (small, medium, large) improve accuracy but use more memory and take longer.
- Manage installed models in Settings > Data.

### Cloud transcription

These providers require an API key and send your audio over the network:

- **OpenAI Whisper API** -- high accuracy, widely used.
- **Groq Whisper API** -- fast inference.
- **OpenRouter** -- OpenAI-compatible API with access to multiple model providers.
- **Gemini** -- OpenAI-compatible API from Google.

## Polish providers

Polish runs a language model on your raw transcript to improve grammar, formatting, and structure. All polish providers are cloud-based and require an API key:

- **OpenAI** -- default: `gpt-5-nano`.
- **Groq** -- fast inference for supported models.
- **OpenRouter** -- access to multiple model providers through one API key.
- **Gemini** -- Google models.

Polish is disabled by default. Enable it in Settings > Providers.

## Setting up API keys

1. Open Settings > Providers.
2. Enter your API key for each provider you want to use.
3. Use the verification button to confirm your key works.
4. Select your preferred provider and model from the dropdowns.

API keys are stored in the macOS Keychain.

## Choosing a model

Each provider offers multiple models. Use the model picker in Settings > Providers to browse available options. The refresh button updates the model list from the provider.

For transcription, larger models are generally more accurate but slower. For polish, the choice depends on your preference for speed versus output quality.

## Language

Language mode is set in Settings > Providers. The default is `auto`, which lets the transcription provider detect the spoken language. You can also set a specific language.

## Continue

- How the pipeline works: [How It Works](how-it-works.md)
- Polish rules: [Custom Rules](custom-rules.md)
- Provider behavior details: [Product Spec](../product/spec.md)
