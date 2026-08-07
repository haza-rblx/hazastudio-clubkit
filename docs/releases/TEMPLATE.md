# Release TEMPLATE — do not commit this folder as a version

Copy to `docs/releases/<VERSION>/` on release.

---

## UPGRADE.md

```markdown
# Upgrade v{OLD} → v{NEW}

**Date:** {DATE}

## Quick steps

1. **Backup** `Hazastudio_ClubKitConfig` and `Hazastudio_ClubKitSecrets`
2. Remove old engine folders: `Hazastudio_ClubKit` (all services)
3. **Insert** new RBXM file (`HazastudioClubKit_v{NEW}.rbxm`)
4. Restore buyer config; merge new fields if listed in release notes
5. Play test → publish

## What's new

- ...

## Config changes (if any)

| Field | Change |
|-------|--------|

## Buyer files — do not replace

- `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau`
- `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau`

## QA after upgrade

- [ ] ...
```

---

## CHANGED_FILES.md

```markdown
# Changed Files — v{OLD} → v{NEW}

## Summary

| Metric | Value |
|--------|-------|
| Files changed | N |
| Breaking | yes/no |

## Core — replace via RBXM

| Path | Type | Summary |
|------|------|---------|

## Buyer-owned — review manually

| Path | Action |
|------|--------|

## Docs / tools only

| Path | Summary |
|------|---------|
```
