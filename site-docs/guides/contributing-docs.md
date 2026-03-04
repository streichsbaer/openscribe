# Contributing Docs

## Goal

Keep product docs crisp, current, and linkable from one clear entry path.

## Structure rule

- `site-docs/` is the published docs surface.
- Use Product, Guides, Operations, and Reference sections.
- Keep internal-only notes outside `site-docs/`.

## Authoring rules

- Start with user outcome, then link to deep details.
- Keep pages short and scannable.
- Add update dates for roadmap or time-sensitive pages.

## Validation

```bash
uv sync --frozen --only-group docs --no-install-project
uv run mkdocs build --strict
uv run mkdocs serve --dev-addr 127.0.0.1:8000
```

Preview URL:

- `http://127.0.0.1:8000/`

## Continue

- Product summary: [Product Spec](../product/spec.md)
- Ops checks: [Testing](../ops/testing.md)
- Ticket workflow: [Issue Tracking](../ops/issue-tracking.md)
