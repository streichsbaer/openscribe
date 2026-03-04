---
name: docs-visual-review
description: Verify OpenScribe docs locally or on deployed Pages by running Playwright screenshots with optional uv build and serve steps.
metadata:
  short-description: Visual docs review with Playwright
---

# Skill: docs-visual-review

## Purpose

Run fast and repeatable visual QA for the docs site with local automation.

## Use this when

- You need to verify docs layout or styling changes.
- You want deterministic screenshots for review.
- You want one command that builds, serves, captures, and tears down.

## Invocation in agent sessions

- Invoke by skill name and optional params, for example: `$docs-visual-review --out artifacts/docs-visual/latest`.
- The agent runs and verifies the workflow steps.

## Run

From repo root:

```bash
zsh .agents/skills/docs-visual-review/scripts/run.sh
```

Include app build precheck:

```bash
zsh .agents/skills/docs-visual-review/scripts/run.sh --with-swift-build
```

Custom output path:

```bash
zsh .agents/skills/docs-visual-review/scripts/run.sh --out artifacts/docs-visual/latest
```

Verify deployed docs without local serve:

```bash
zsh .agents/skills/docs-visual-review/scripts/run.sh --remote-url https://openscribe.dev/ --out artifacts/docs-visual/remote-latest
```

Keep server running after capture:

```bash
zsh .agents/skills/docs-visual-review/scripts/run.sh --keep-server
```

## Workflow

1. Verify required tools (`uv`, `playwright-cli`, `curl`, `swift`).
2. Use repo-local uv cache under `.build/uv-cache`.
3. Local mode: build docs (`uv run mkdocs build --strict`) unless skipped.
4. Local mode: start docs server (`uv run mkdocs serve`) unless `--no-serve` is set.
5. Remote mode: use `--remote-url` to skip local serve and docs build, then verify deployed pages directly.
6. Open Playwright browser, navigate to key docs routes, and capture full-page screenshots.
7. Write logs and a short report.
8. Review generated screenshots with the image tool and summarize visual findings.
9. Close Playwright and stop the docs server (unless `--keep-server` is set).
10. Optional precheck: run `swift build` only when `--with-swift-build` is set.

## Required verification output

- Always report both:
  - Script status from `report.md`
  - Visual findings after inspecting `home.png`, `menu-and-settings.png`, and `product-spec.png`
- Visual inspection method:
  - Open and inspect the generated screenshots directly with the image tool.
  - Do not run auxiliary image processing commands such as `ffmpeg`, ImageMagick, pixel probes, or ad hoc dimension scripts unless Stefan explicitly asks for that deeper analysis.
- If visuals and report disagree, treat the run as failed and explain the mismatch.

## Outputs

Default output directory:

- Relative to repo root: `artifacts/docs-visual/<timestamp>/`

Artifacts:

- `swift-build.log`
- `mkdocs-build.log`
- `mkdocs-serve.log`
- `playwright.log`
- `home.png`
- `menu-and-settings.png`
- `product-spec.png`
- `report.md`
