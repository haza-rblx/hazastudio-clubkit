# DJ deck: progress notes

Living log for the standalone DJ deck (dj-booth). Newest entry first.

## 2026-10-28

### Lock screen (src/client/Features/Lock.luau), done
- Full-bleed artwork (rbxassetid://133559573964792, ScaleType Crop) behind everything.
- Right column: xfade mark on top (three rows: "xfade", DUAL DECK tag, "by kosmik"), then the form centred between the mark and the copyright.
- Copy: title "Your DJ deck is / waiting backstage.", body "Enter your activation code".
- Footer: "© 2026 Cosmic Studio HQ".
- Backstage pass, lanyard, beam, stamps and the "ALL ACCESS" band were removed from the code. The guest pass modal stays.
- Unlock: the whole panel rises 0.7 s with its contents, then hides and resets its position.
- Compact (small screen) mode also shows the artwork, and the logo and footer stay hidden there.
- Studio-only replay: changing ReplicatedStorage.HazaDJ attribute "UnlockPreview" replays the unlock.
- Verified: selene 0 errors, stylua clean, Studio source length matches the repo (20548 vs 20549 bytes, the difference is the trailing newline).
- Saved with Ctrl+S via PostMessage. Save is not confirmed by the tool, but the restarted playtest loaded the new code.
- Not committed to git.

### Runtime-only (not in repo)
- "Replay unlock" button in client-1 (ScreenGui ReplayTest) for testing. It disappears when the playtest restarts.

### Rebrand (HazaDJ -> XFADEBYKOSMIK), mapped, not started
- Mapped: 177 occurrences in about 80 files under dj-booth.
- Phase 1 (display text only) is the agreed starting point.
- Keep unchanged unless migrated: DataStore keys (HazaDJ_v1, HazaDJ_Prefs_v1, HazaDJ_License_v1 and their topics), Blink remote scope (HAZADJ / HAZADJ_BLINK), buyer-facing tags and attributes (HazaDJ_DjDeck, HazaDJ_Booth, HazaDJ_Stand, HazaDJ_Speaker, HazaDJ_BPM, HazaDJ_BeatAt, HazaDJ_Fixture, HazaDJ_LicenseStub*).
- Phase 2 (optional, later): internal instance names and the module root (ReplicatedStorage/ServerScriptService/StarterPlayerScripts .HazaDJ, default.project.json, build/*.project.json, tools/package.luau).
- Backup done (repo): C:\Users\haza\Desktop\backups\djbooth-pre-rebrand-20261028-032112\dj-booth (589 files).
- Backup pending (Studio): save a copy of the .rbxl with File -> Save to File As.

### Obfuscation and djX fingerprint, planning
- Fingerprint lives in src/server/Stamp.luau and as a per-line trailing-whitespace watermark on every script except Stamp and Packages (docs/plans/djx-stamping.md). Obfuscation that rewrites whitespace or merges lines destroys it.
- Planned approach: obfuscate src/client and src/shared only. Keep src/server plain, so the watermark survives in server scripts.
- Candidate obfuscators: Prometheus fork (open source, Lua 5.1, not Luau-aware, needs a Luau parser and a line-preserving pass), Luraph, MoonSec, Wynfuscate, luau-protect. No choice made yet.
- Pipeline test: rojo builds of shared, server and client are done into a scratch folder (C:\Users\haza\AppData\Local\hermes\cache\scratch\djx-test\build). The package, stamp and read steps are not run yet.
- Tools available locally: Lune 0.8.9, Rojo 7.5.1, selene, stylua, luau-lsp. The stamp CLI (clubkit-infra/apps/api/djx/stamp.luau) is not on this machine.

### Known issue (open)
- Playtest log shows "Asset type does not match requested type" WARNs for seven IDs: 203785492, 16888522364, 16888522489, 16888522657, 16888522738, 16888522837, 16888522973.
- Source: Audio.luau line 232 (PreloadAsync for library tracks, wrapped in pcall, so no crash). The IDs are not in the place source or instances, so they probably come from saved library data.
- Likely cause: library tracks whose asset ID is not an audio asset. Repeats on every join.
- Not yet done: identify which tracks they are, and decide whether to clean the data or validate the ID on add.

### Not yet tested
- The DJ panel UI (opened from the topbar "DJ" icon). Audio playback.

## Open decisions
- Rebrand: phase 1 only, or go on to phase 2?
- Obfuscator: which one, or defer?
- Studio .rbxl backup before any Studio-side rename.
