# Providers and Models

OpenScribe lets you mix local and cloud providers depending on how you want the app to behave. A simple setup can stay fully local. A more flexible setup can add cloud models for transcription, polish, or both.

If you want the best no-cost setup path, start with [Using Free Tiers](free-tiers.md) and configure Groq transcription plus Groq polish on `openai/gpt-oss-120b`.

![Providers settings tab](/images/ui/settings-providers.png){ .guide-shot data-light-src="/images/ui/settings-providers.png" data-dark-src="/images/ui/settings-providers-dark.png" }

## Start with transcription

If you want the default local-first path, keep transcription on whisper.cpp. It runs on your Mac, needs no API key, and keeps your audio off the network.

If you want cloud transcription, add an API key in Settings > Providers and then choose that provider in Settings > Transcribe.

### Local: whisper.cpp

- No API key needed.
- Default model: `base`.
- Larger models improve accuracy but use more memory and take longer.
- Manage installed models in Settings > Data.

### Cloud transcription

These providers send your audio over the network and require an API key:

- **OpenAI Whisper API** for broad compatibility and strong accuracy.
- **Groq Whisper API** for fast inference.
- **OpenRouter** for access to multiple upstream model providers.
- **Gemini** for Google-hosted models through an OpenAI-compatible interface.

## Turn on polish when you want cleaner output

Polish runs a language model on your raw transcript to improve grammar, formatting, and structure. All polish providers are cloud-based, so this step always needs an API key.

- **OpenAI** -- built-in default: `gpt-5-nano`.
- **Groq** -- recommended cloud polish path with `openai/gpt-oss-120b`.
- **OpenRouter** -- access to multiple model providers through one API key.
- **Gemini** -- Google models that can cover transcription and polish, but they are not the recommended polish path.

Polish is disabled by default. Enable it in Settings > Polish.

![Transcribe settings tab](/images/ui/settings-transcribe.png){ .guide-shot data-light-src="/images/ui/settings-transcribe.png" data-dark-src="/images/ui/settings-transcribe-dark.png" }

## Add your keys, then refresh models

1. Open Settings > Providers.
2. Enter your API key for each provider you want to use.
3. Use Verify to confirm the key and Refresh models to pull the latest shared model list for that provider.
4. Select your preferred transcription provider and model in Settings > Transcribe.
5. Select your preferred polish provider and model in Settings > Polish.

API keys are stored in the macOS Keychain.
App updates do not clear those saved keys for the same macOS user account.

## Choose a model deliberately

Use the model picker in Settings > Transcribe or Settings > Polish to browse what each provider offers. Refresh the provider model list in Settings > Providers when you want the latest options.

For transcription, larger models are usually more accurate and slower. For polish, the right choice depends on how much latency you are willing to trade for better cleanup. If you want the simplest recommended hosted setup, use `whisper-large-v3-turbo` for transcription and `openai/gpt-oss-120b` on Groq for polish.

## Language

Language mode lives in Settings > Transcribe. The default is `auto`, which lets the provider detect the spoken language. If you mainly dictate in one language, setting it explicitly can improve consistency.

## Continue

- Free-tier setup: [Using Free Tiers](free-tiers.md)
- Groq walkthrough: [Groq Free Tier Setup](groq-free-tier-setup.md)
- Gemini walkthrough: [Gemini Free Tier Setup](gemini-free-tier-setup.md)
- OpenRouter walkthrough: [OpenRouter Free Tier Setup](openrouter-free-tier-setup.md)
- How the pipeline works: [How It Works](how-it-works.md)
- Polish rules: [Custom Rules](custom-rules.md)
- Full field reference: [UI Reference](../reference/ui-reference.md)
- Provider behavior details: [Product Spec](../product/spec.md)
