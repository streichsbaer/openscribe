# Issue Tracking

## Goal

Use GitHub Issues as the live roadmap and execution tracker.
Use docs pages for concise product narrative and contributor guidance.
Scribe can read, create, and update issues through GitHub CLI automation.

## Contribution model

- External contributions should start as issues with clear acceptance criteria.
- Maintainer and Scribe open implementation pull requests for accepted work.
- If external code already exists, attach a fork-branch link or coding-agent session link in the issue.

## Recommended issue model

- One issue per feature slice or bug.
- Clear acceptance criteria in each issue.
- Explicit labels for status, type, and area.

## Live roadmap views

- [Open features](https://github.com/streichsbaer/openscribe/issues?q=is%3Aopen+label%3Atype%2Ffeature)
- [Planned](https://github.com/streichsbaer/openscribe/issues?q=is%3Aopen+label%3Astatus%2Fplanned)
- [In progress](https://github.com/streichsbaer/openscribe/issues?q=is%3Aopen+label%3Astatus%2Fin-progress)
- [Done](https://github.com/streichsbaer/openscribe/issues?q=is%3Aclosed+label%3Astatus%2Fdone)
- [Docs work](https://github.com/streichsbaer/openscribe/issues?q=is%3Aopen+label%3Aarea%2Fdocs)

## Keep docs and issues aligned

- Product summary pages point to roadmap views.
- Issue closures trigger doc updates where behavior changed.
- Roadmap docs stay short and link to issue filters for current state.

## GitHub CLI comment formatting

- Use real multiline comment bodies for GitHub Issues.
- Do not pass literal `\n` escape sequences in comment text.
- Preferred close flow: post the completion comment first, then close the issue.

```bash
gh issue comment 123 --body-file - <<'EOF'
Closing as completed.

Implemented in commit abc1234.

Verified with targeted tests:
- swift test --filter ExampleTests
EOF

gh issue edit 123 --remove-label status/in-progress --add-label status/done
gh issue close 123 --reason completed
```

- If a single close command is required, use command substitution with a heredoc so newlines are preserved.

```bash
gh issue close 123 --reason completed --comment "$(cat <<'EOF'
Closing as completed.

Implemented in commit abc1234.
EOF
)"
```

## Continue

- Label taxonomy: [Label Conventions](label-conventions.md)
- Product roadmap page: [Roadmap](../product/roadmap.md)
