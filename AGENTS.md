# OpenScribe Agent Rules

## Build Policy

- Implement the current behavior directly.
- Do not add migration code, deprecation handling, compatibility shims, fallback paths, or legacy settings upgrades unless the user explicitly requests them.
- Prefer a single clear path that works now over backward-compatibility logic.

## Writing Style

- Do not use em dashes.
- Do not use contrastive negation phrasing such as "it is not X, it is Y."

## SOUL

- Load `SOUL.md` at the start of work.
- Always read `SOUL.md` before planning or editing code in each new session.
- Treat `SOUL.md` as the product and engineering voice for this repository.
- Use `SOUL.md` to guide priorities, privacy stance, and communication tone.

## Local Skills

- Repo-local skills live under `.agents/<skill>/SKILL.md`.
- When a task matches a local skill, load that skill before implementing.
- Prefer scripts in `.agents/<skill>/scripts/` for repeatable automation.

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
- Use a quote-safe pattern that tolerates apostrophes in commit body text.
- After each commit, verify formatting with `git log -1 --pretty=medium`.
- Do not amend or rewrite prior commits unless explicitly requested.
- If unrelated files are already staged, commit only intended paths.
- Run `git add` and `git commit` sequentially to avoid `.git/index.lock` races.

### Shell Quote Safety

- Default pattern for multiline commit messages:

```bash
zsh -lic "git commit -F - <<'EOF'
feat: short subject

Why
- Reason.

What
- Change summary.

Instruction
- User request summary, including apostrophes like don't or it's.
EOF"
```

- This pattern is required because a single-quoted `zsh -lic '...'` payload can break when the commit body contains apostrophes.
- If a command still fails to parse, retry with the same pattern and avoid changing semantics of the commit body.

### Commit Message Examples

```bash
git add path/to/file.swift
zsh -lic "git commit -F - <<'EOF'
fix: improve status chip contrast

Why
- Polishing state color blended into some menu bar themes.

What
- Changed polishing chip/icon color to mint.

Instruction
- User asked for a neutral polishing color.
EOF"
git log -1 --pretty=medium
```

## Commit Cadence

- Create one commit for each completed behavior change after local verification.
- Create one commit for each focused bug fix.
- Group related documentation or governance updates into one docs commit.
- Do not wait for large batches when a scoped, verified unit is complete.
- If work is exploratory and unverified, hold commits until the change is validated.
