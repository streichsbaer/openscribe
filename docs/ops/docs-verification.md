# Docs Verification

Use this runbook to verify docs changes before and after push.

## Before push

Run local docs checks from repo root:

```bash
uv sync --frozen --only-group docs --no-install-project
uv run mkdocs build --strict
$docs-visual-review --out artifacts/docs-visual/local-latest
```

Pass criteria:

- `mkdocs build --strict` exits successfully.
- `artifacts/docs-visual/local-latest/report.md` shows `playwright: pass`.
- Key screenshots exist: `home.png`, `ui-reference.png`, `product-spec.png`.
- When the change affects docs layout or image presentation, verify both a compact laptop-sized viewport and a larger viewport before push.

## After push

### 1. Confirm deployment workflow

```bash
gh run list --workflow docs-pages --limit 5
gh run view <run-id>
```

Pass criteria:

- Latest `docs-pages` run for `main` is `completed` with `success`.
- Both `build` and `deploy` jobs are green.

### 2. Confirm public routes

```bash
curl -I https://openscribe.dev/
curl -I https://openscribe.dev/reference/ui-reference/
curl -I https://openscribe.dev/product/spec/
```

Pass criteria:

- All key routes return `HTTP 200`.

### 3. Run remote visual verification

```bash
$docs-visual-review --remote-url https://openscribe.dev/ --out artifacts/docs-visual/remote-latest
```

Pass criteria:

- `artifacts/docs-visual/remote-latest/report.md` shows `playwright: pass`.
- Captured pages visually match expected navigation and content.
- Images fit their content area without hiding required detail, and pages do not rely on oversized viewports to keep key content readable.
- Visual checks use direct screenshot inspection. Avoid extra tools (`ffmpeg`, ImageMagick, pixel or dimension probes) unless explicitly requested.

## Compact viewport check

When a docs change affects layout or image presentation:

1. Open the changed page locally after the normal visual review run.
2. Resize to a compact laptop-sized viewport.
3. Confirm there is no horizontal overflow, key callouts remain readable, and images scale without cropping required detail.

## Troubleshooting

- If Pages route checks fail right after deploy, retry after one CDN window (`max-age=600`).
- If remote visual check fails, inspect `playwright.log` and compare screenshots to previous run artifacts.
- If route checks pass but visuals are stale, force-refresh and rerun remote visual verification.
