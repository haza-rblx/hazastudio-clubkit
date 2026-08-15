---
name: code-review
description: Use when the user asks to review changes, a diff, work-in-progress, or a release candidate — two-axis review (Standards vs Spec) run as parallel sub-agents. Standards = AGENTS.md conventions + Luau smell baseline. Spec = UPGRADE_PROGRESS.md entries + CHANGELOG [Unreleased]. This is the required gate before "release version X.Y" / release.ps1 -Execute.
---

# Code Review — Two Axes

Adapted from mattpocock/skills. Review the diff between `HEAD` and a fixed point along two axes, each in its own sub-agent so neither pollutes the other:

- **Standards** — does the code follow this repo's conventions?
- **Spec** — does it implement what was actually asked, nothing more?

A change can pass one axis and fail the other. Report separately; never merge or rerank across axes.

## 1. Pin the fixed point

Whatever the user said — tag, SHA, `main`. Default for release review: the previous version tag. Use the portable git:

```powershell
.\git.ps1 rev-parse <fixed-point>            # must resolve; fail here if not
.\git.ps1 diff <fixed-point>...HEAD          # three-dot (merge-base)
.\git.ps1 log <fixed-point>..HEAD --oneline
```

Bad ref or empty diff fails now, not inside sub-agents.

## 2. Standards sources (for the Standards sub-agent)

- [`AGENTS.md`](../../../AGENTS.md) — code conventions section: `--!strict` on new files, minimal scope, match surrounding style.
- **Register budget** — run `.\tools\count-locals.ps1` on touched Main/UI files; ≥170 top-level locals = freeze violation, ≥185 = blocker (ADR 0002).
- **Buyer-owned files** — `ClubKitConfig.luau` / `Secrets.luau` must never be replaced in the diff (ADR 0001); new config keys must appear in schema + template.
- **DataStore keys** — any key change is a breaking migration; must be deliberate and documented.
- Plus the smell baseline below (Fowler, ch.3) — always judgement calls, repo standards override them, skip what tooling enforces:

Mysterious Name · Duplicated Code · Feature Envy · Data Clumps · Primitive Obsession · Repeated Switches · Shotgun Surgery · Divergent Change · Speculative Generality · Message Chains · Middle Man

## 3. Spec sources (for the Spec sub-agent)

In order: `UPGRADE_PROGRESS.md` status/file tables → `CHANGELOG.md` `[Unreleased]` entries → a path the user supplies. None found → ask the user; if there is no spec, Spec sub-agent reports "no spec available" and skips.

## 4. Spawn both sub-agents in parallel (actor tool, spawn ×2)

**Standards prompt:** diff command + commit list + the standards sources above pasted in. Brief: "Per file/hunk: (a) violations of documented standards — cite the rule; (b) baseline smells — name it, quote the hunk. Distinguish hard violations from judgement calls. Skip what tooling enforces. Under 400 words."

**Spec prompt:** diff command + spec contents. Brief: "(a) requirements missing or partial; (b) behavior in the diff not asked for (scope creep); (c) requirements implemented but looking wrong. Quote the spec line per finding. Under 400 words."

## 5. Aggregate

Present under `## Standards` and `## Spec` headings, verbatim or lightly cleaned. End with one line: findings per axis + worst issue within each. Don't pick a winner across axes.

**Release gate:** any hard Standards violation (buyer file replaced, register blocker, undocumented DataStore key change) blocks the release checklist in `UPGRADE_PROGRESS.md` until resolved.
