# SmartTranscript Agent Rules

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
- Do not amend or rewrite prior commits unless explicitly requested.
- If unrelated files are already staged, commit only intended paths.
- Run `git add` and `git commit` sequentially to avoid `.git/index.lock` races.

## Commit Cadence

- Create one commit for each completed behavior change after local verification.
- Create one commit for each focused bug fix.
- Group related documentation or governance updates into one docs commit.
- Do not wait for large batches when a scoped, verified unit is complete.
- If work is exploratory and unverified, hold commits until the change is validated.
