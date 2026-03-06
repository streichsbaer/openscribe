# Contributing

## How contributions work

OpenScribe uses an issue-first model. External contributions start as GitHub Issues with clear acceptance criteria. The maintainer and Scribe open implementation pull requests for accepted work.

If you already have code, attach a fork-branch link or coding-agent session link in the issue rather than opening an unsolicited pull request.

## Filing issues

- One issue per feature slice or bug.
- Include clear acceptance criteria.
- The maintainer and Scribe apply labels for status, type, and area after triage. See [Label Conventions](../ops/label-conventions.md) for the tracking taxonomy.

## Documentation contributions

### Structure rules

- `site-docs/` is the published docs surface.
- Use Guides, Project, and Reference sections as defined in the site navigation.
- Keep internal-only notes outside `site-docs/`.

### Authoring guidelines

- Start with user outcome, then link to deeper details.
- Keep pages short and scannable.
- Add update dates for time-sensitive pages.

### Validation

Before submitting docs changes, verify locally:

```bash
uv sync --frozen --only-group docs --no-install-project
uv run mkdocs build --strict
uv run mkdocs serve --dev-addr 127.0.0.1:8000
```

Preview URL: `http://127.0.0.1:8000/`

## Tracking

- Live roadmap views: [Issue Tracking](../ops/issue-tracking.md)
- Label taxonomy: [Label Conventions](../ops/label-conventions.md)
- Product direction: [Roadmap](roadmap.md)
