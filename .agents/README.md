# OpenScribe Local Agent Skills

This folder contains repo-local skills that extend autonomous workflows for this project.

## Available Skills

- `ui-smoke`:
  - Build and test validation
  - Launch app for smoke checks
  - Capture screenshots for review
  - Enforce required screenshot coverage, then review visuals manually
  - Write a lightweight report in `artifacts/ui-smoke/<timestamp>/report.md`
- `release`:
  - Run release preflight checks
  - Bump app version/build
  - Build release artifact and Homebrew cask snippet
  - Print commit/tag/publish commands aligned with release policy

## Usage

Run skill scripts directly from repo root (`pwd=/path/to/OpenScribe`).

```bash
zsh .agents/skills/ui-smoke/scripts/run.sh
zsh .agents/skills/ui-smoke/scripts/run.sh --out artifacts/ui-smoke/latest
zsh .agents/skills/release/scripts/cut.sh --version 0.1.1 --build 2
```

`ui-smoke` default output path is `artifacts/ui-smoke/<timestamp>/` relative to repo root.
