# Upgrade v2.4.55 → v2.4.56

## Quick steps
1. Studio → ClubKit plugin → **Check Update** → **Update Engine**
2. Save place

Client-only patch. No config/schema changes, no buyer action needed.

## What's new
- World donation VFX no longer spam the console with `WorldEffectAborted` when one effect (e.g. Nuke) replaces a running effect (e.g. Smite4/BlackHole). Expected aborts are now silent; only real failures warn.
- Dispatch/skip diagnostics moved to `debug` level (quieter production console).

## Config changes
- None.

## Security note
- Donation preview/test commands (`/testcash`, `/testsaweria`, `/testdonate`, `/testrobux`) are gated by `isAdmin` server-side; manual donation commands require owner-or-Studio. Chat commands are server-authoritative (no client remote), so donation notifications / world VFX cannot be triggered or spammed by an exploiter/executor.

## QA setelah upgrade
- [ ] `/testcash 300000` sebagai admin → Nuke tampil, tanpa error merah di console
- [ ] `/testcash` beruntun (spam) → efek saling replace mulus, tidak ada stack `WorldEffectAborted`
- [ ] Non-admin ketik `/testcash 999999` → ditolak "Admin/Staff-only", tanpa notif/VFX
