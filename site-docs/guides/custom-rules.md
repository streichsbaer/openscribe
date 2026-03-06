# Custom Rules

Custom rules let you guide how OpenScribe polishes your transcripts. When polish is enabled, the rules file is included in the prompt sent to the language model.

## What rules do

Rules give the polish model instructions about your preferred writing style, formatting conventions, terminology, and structure. For example, you might add rules to:

- Use British English spelling.
- Format lists with dashes instead of bullets.
- Preserve technical terms without paraphrasing.
- Keep paragraphs short.

## Where rules live

Your rules are stored in a single markdown file:

```
~/Library/Application Support/OpenScribe/Rules/rules.md
```

OpenScribe creates this file on first launch with sensible defaults.

## Editing rules

Open Settings > Rules to edit your rules directly in the app. The Rules tab provides:

- A text editor for the rules markdown.
- **Save** to write changes to disk.
- **Revert** to discard unsaved edits and reload from disk.
- **Open in editor** to edit in your preferred external markdown editor.

You can also open the Rules tab with the rules hotkey (default: `Ctrl + Option + R`).

## Rules history

OpenScribe keeps a history of rule changes in `Rules/rules.history.jsonl`. Each save appends a timestamped entry so you can track how your rules evolved.

## Continue

- How polish fits in the pipeline: [How It Works](how-it-works.md)
- Provider and model selection: [Providers and Models](providers.md)
- Where all your data lives: [Your Data](your-data.md)
