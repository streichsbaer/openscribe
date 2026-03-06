# Your Data

OpenScribe stores all data locally on your Mac. Nothing is synced to the cloud unless you explicitly use a cloud provider for transcription or polish.

## Where data lives

All app data is stored under:

```
~/Library/Application Support/OpenScribe/
```

You can open this folder from Settings > Data.

## Session recordings

Each recording session creates a folder organized by date:

```
Recordings/
  2026-03-06/
    143052-<session-id>/
      audio.m4a        -- your recording
      session.json     -- session metadata (provider, model, timestamps)
      raw.txt          -- raw transcript from speech-to-text
      polished.md      -- polished output from the language model
```

Every session keeps all four files, so you can replay audio, re-read transcripts, or re-process with different settings at any time.

## Other data

- **Rules/rules.md** -- your custom polish rules.
- **Rules/rules.history.jsonl** -- timestamped history of rule edits.
- **Stats/usage.events.jsonl** -- usage metrics (session counts, durations, provider usage).
- **Models/whisper/** -- downloaded local transcription models.
- **Config/settings.json** -- app preferences.

## Finding your data

- From the **History tab**: each session row has a "Reveal in Finder" action.
- From **Settings > Data**: open the app support folder directly.
- From **Finder**: navigate to `~/Library/Application Support/OpenScribe/`.

## Managing storage

- **Local models**: install and delete whisper models from Settings > Data. Model disk usage is shown next to each model.
- **Session data**: delete individual sessions from the History tab, or use bulk selection to remove multiple sessions at once.
- **Full cleanup**: Settings > Data includes an option to move all app data to Trash.

## Technical details

For the full file layout specification, see the [Storage Contract](../reference/storage-contract.md).

## Continue

- How recordings are created: [How It Works](how-it-works.md)
- Custom polish rules: [Custom Rules](custom-rules.md)
