# OpenScribe Local Agent Skills

This folder contains repo-local skills that extend autonomous workflows for this project.

## Available Skills

- `ui-smoke`:
  - Build and test validation
  - Launch app for smoke checks
  - Capture screenshots for review
  - Write a lightweight report in `artifacts/ui-smoke/<timestamp>/report.md`

## Usage

Run skill scripts directly from repo root.

```bash
zsh .agents/ui-smoke/scripts/run.sh
```
