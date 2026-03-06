# How It Works

OpenScribe turns speech into text through a three-stage pipeline: record, transcribe, polish. Each stage runs in sequence, and you can see progress in the menu bar icon and the Live tab.

## The pipeline

### 1. Record

Press the start/stop hotkey (default: `Fn + Space`) to begin recording. The menu bar icon changes to show that audio capture is active.

Speak naturally. OpenScribe writes audio to disk incrementally during recording.

When you press the hotkey again, recording stops and the audio file is finalized.

### 2. Transcribe

After recording stops, OpenScribe sends the audio through your selected speech-to-text provider. By default this is whisper.cpp, which runs entirely on your Mac with no network calls.

The raw transcript appears in the Live tab as soon as transcription completes.

If the recording had no usable speech signal, OpenScribe skips transcription and shows a "No audio captured" status.

### 3. Polish (optional)

If polish is enabled, OpenScribe sends the raw transcript to a language model that cleans up grammar, formatting, and structure. The polish step uses your custom rules from `Rules/rules.md` to guide its output.

The polished text appears below the raw transcript in the Live tab.

If polish is disabled, the polished output is a direct copy of the raw transcript.

## What you see during each stage

The menu bar icon reflects the current pipeline state:

- **Idle**: ready for a new recording.
- **Recording (working)**: audio capture is active with usable input.
- **Recording (no audio)**: recording is active but no microphone signal is detected.
- **Transcribing**: speech-to-text is running.
- **Polishing**: the language model is cleaning up the transcript.

The Live tab header also shows elapsed time for the current stage.

## After the pipeline completes

Every completed session saves four artifacts:

- `audio.m4a` -- your recording.
- `session.json` -- metadata (provider, model, timestamps).
- `raw.txt` -- the raw transcript.
- `polished.md` -- the polished output.

If copy-on-complete is enabled (the default), the polished text is automatically copied to your clipboard.

## Re-processing

You can re-run transcription or polish on any session from the Live or History tab. Each re-run lets you pick a different provider and model, so you can compare results without recording again.

## Continue

- Full UI reference: [Menu and Settings](menu-and-settings.md)
- Provider options: [Providers and Models](providers.md)
- Where your files are stored: [Your Data](your-data.md)
