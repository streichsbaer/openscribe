# OpenScribe Agent Rules

## SOUL

- Load `SOUL.md` at the start of work.
- Always read `SOUL.md` before planning or editing code in each new session.
- Treat `SOUL.md` as the product and engineering voice for this repository.
- Use `SOUL.md` to guide priorities, privacy stance, and communication tone.

## Build Policy

- Implement the current behavior directly.
- Do not add migration code, deprecation handling, compatibility shims, fallback paths, or legacy settings upgrades unless the user explicitly requests them.
- Prefer a single clear path that works now over backward-compatibility logic.

## Writing Style

- Do not use em dashes.
- Do not use contrastive negation phrasing such as "it is not X, it is Y."

## Documentation Boundaries

- `SOUL.md` captures enduring product values, priorities, and quality intent.
- `AGENTS.md` captures repository workflow, execution rules, and collaboration protocol.
- `site-docs/product/spec.md` and `site-docs/product/roadmap.md` are canonical product docs.
- `site-docs/ops/` contains operational runbooks for testing, releases, and issue tracking.
- Update the canonical location first and replace duplicate content with links.

## CI Security and Review Hygiene

- Pin third-party GitHub Actions to immutable full commit SHAs.
- Pin externally downloaded CI dependencies to explicit versions.
- Use least-privilege workflow permissions and scope write or OIDC permissions to the smallest set of jobs.
- For public repositories, avoid running privileged jobs for fork pull requests.
- Triage external review findings before merge and either fix them or document rationale for deferral.

## Product Specs Source of Truth

- Use `site-docs/product/spec.md` as the canonical product spec.
- Use `site-docs/product/roadmap.md` as the canonical roadmap summary.
- When asked what is next, start from `site-docs/product/roadmap.md`.
- Follow links from product docs into deeper pages under `site-docs/`.

## Issue and Feature Tracking

- Use GitHub Issues as the live tracker for features, bugs, and docs work.
- Before creating, editing, labeling, commenting on, or closing any issue, load `site-docs/ops/issue-tracking.md` and `site-docs/ops/label-conventions.md`.
- Follow `site-docs/ops/issue-tracking.md` for tracking workflow and saved query links.
- Follow `site-docs/ops/label-conventions.md` for label taxonomy.
- New issues should include one `type/*`, one `status/*`, and one `area/*` label.
- Keep product docs aligned with issue status when behavior changes.
- When work is completed, set `status/done` and close the related issue.
- For GitHub CLI issue comments and close comments, use multiline input via heredoc with `--body-file -` or `$(cat <<'EOF' ... EOF)`.
- Do not include literal `\n` escape sequences in issue comments.
- Use issue-first external collaboration. Redirect unsolicited external pull requests to issues.

## Change Approval

- Stefan is the final approver for changes to `SOUL.md`, `AGENTS.md`, `site-docs/product/spec.md`, and `site-docs/product/roadmap.md`.
- I can draft and apply updates when Stefan requests them directly.
- If I identify a governance improvement outside a direct request, I propose it first, then wait for approval before editing.
- Product direction changes require explicit approval before implementation.

## Release Verification

- Follow `site-docs/ops/testing.md` and `site-docs/ops/release.md` for release validation steps.
- Keep release checklists in `site-docs/ops/` and avoid duplicating them in `SOUL.md`.

## Verification Playbooks

- For app behavior changes or test requests, load `site-docs/ops/testing.md` before running checks.
- For docs content, docs styling, docs workflow, or GitHub Pages verification, load `docs/ops/docs-verification.md` and `.agents/skills/docs-visual-review/SKILL.md`.
- For app UI, docs layout, or docs image changes, verify both a compact laptop-sized viewport and a larger viewport. Confirm key actions stay visible or reachable by scrolling, and confirm required image detail is not cropped away.
- For Cloudflare DNS, edge security headers, HTTPS settings, or domain routing tasks, load `docs/ops/cloudflare.md` before making changes.
- For GitHub issue triage or issue updates, load `site-docs/ops/issue-tracking.md` and `site-docs/ops/label-conventions.md` before running issue commands.
- For post-push docs verification, run `$docs-visual-review --remote-url https://openscribe.dev/ --out artifacts/docs-visual/remote-latest` and report `report.md` plus screenshot paths.
- For docs visual checks, inspect generated screenshots directly with the image tool. Do not run auxiliary image processing commands unless Stefan explicitly requests deeper analysis.
- When sharing local review assets, especially images, always provide a repo-relative path so Stefan can click it directly in the terminal.
- If an asset is generated outside the repo, copy it into a gitignored path under `artifacts/` before sharing it.
- For marketing or release screenshot capture from the live app state, load `docs/ops/marketing-screenshots.md` before taking screenshots.
- For release tasks, load `site-docs/ops/release.md` and `site-docs/ops/testing.md`.
- If a required playbook is missing or stale, update the playbook first, then execute.

## Local Skills

- Repo-local skills live under `.agents/skills/<skill>/SKILL.md`.
- Each `SKILL.md` must include YAML front matter delimited by `---` with at least `name` and `description`.
- When a task matches a local skill, load that skill before implementing.
- Prefer scripts in `.agents/skills/<skill>/scripts/` for repeatable automation.

## Git Commit Policy

- Commit in small logical slices.
- Do not mix unrelated changes in one commit.
- Use subject format: `<type>: <imperative summary>`.
- Allowed commit types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`.
- Keep subject line at 72 characters or fewer.
- Use concise, factual tone in commit messages.
- Add a commit body for every commit with these sections: `Why`, `What`, and `Instruction`.
- `Instruction` must summarize Stefan's request that triggered the change in concise terms.
- Use real line breaks in commit bodies. Do not include literal `\n` escape sequences.
- Required multiline flow: pass a heredoc directly to `git commit -F -`.
- Do not use temporary commit message files for multiline commit bodies.
- Do not use shell-escaped multiline patterns like `-m $'...'` for commit bodies.
- When running commit commands via `zsh -lic`, do not wrap the entire command payload in single quotes.
- Use a quote-safe pattern and avoid apostrophes in commit body text.
- After each commit, verify formatting with `git log -1 --pretty=medium`.
- Push each commit to the current branch after creating it unless Stefan explicitly says to keep it local.
- After each push, report the branch name, commit SHA, and relevant verification status.
- Do not amend or rewrite prior commits unless explicitly requested.
- Do not force-push, amend pushed commits, or push unrelated local changes unless Stefan explicitly requests it.
- If unrelated files are already staged, commit only intended paths.
- Run `git add` and `git commit` sequentially to avoid `.git/index.lock` races.
- Keep commit body bullets short and direct.

### Shell Quote Safety

- Known failure cause:
- Heredoc commit payloads can still fail parsing when the command string contains apostrophes in body text.
- Contractions like `don't`, `it's`, or `You've` are common triggers in this workflow.

- Required prevention rules:
- Write commit bodies in plain ASCII.
- Do not use apostrophes in commit body text.
- Rewrite contractions: use `do not`, `it is`, `You have`.
- Keep each bullet to one concise sentence.

- Canonical commit flow template:

```bash
git add path/to/file.swift
zsh -lic "git commit -F - <<'EOF'
feat: short subject

Why
- Reason.

What
- Change summary.

Instruction
- User request summary without apostrophes.
EOF"
git log -1 --pretty=medium
```

- This pattern is required because a single-quoted `zsh -lic '...'` payload can break.
- If a commit command fails to parse, stop and rewrite the message with zero apostrophes before retry.

## Commit Cadence

- Create one commit for each completed behavior change after local verification.
- Create one commit for each focused and verified bug fix.
- Group related documentation or governance updates into one docs commit.
- Do not wait for large batches when a scoped, verified unit is complete.
- If work is exploratory and unverified, hold commits until the change is validated and approved by Stefan.
