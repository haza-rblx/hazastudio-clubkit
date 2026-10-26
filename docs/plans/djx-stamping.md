# djX stamped downloads + venue pre-bind — build contract

Status: **built 2026-10-26**, tested end-to-end on a local API. Steps covered: template upload → pre-bind via the real Roblox API → download → `read`/identify → activation (wrong universe refused, bound venue ok) → beacon.

Not yet done: a deploy, Lune installed on the VPS, and loading a stamped file in Studio.

Watermark reach on the real template: 63 scripts are marked, and 27 of them are long enough to carry the full fingerprint on their own. Scripts with a multi-line string are skipped. Decisions: ADR 0022 item 12. API base: `docs/plans/djx-license-api.md`.

## Template layout (`build/djx-template.rbxm`, made by `dj-booth/tools/package.luau`)

One root `Folder "djX"` with three children:

```
djX (Folder)
├── ReplicatedStorage (Folder)     → HazaDJ  (from build/shared.rbxm)
├── ServerScriptService (Folder)   → HazaDJ  (from build/server.rbxm; contains ModuleScript "Stamp")
└── StarterPlayerScripts (Folder)  → HazaDJ  (from build/client.rbxm)
```

The buyer moves each `HazaDJ` into the service its folder names.

## Stamp module

`ServerScriptService/HazaDJ/Stamp` is fully rewritten per download:

```lua
--!strict
-- The download stamp (ADR 0022 §12). Written by the licence server for this download only.
return {
	licenseId = "lic_…",
	buyerId = 0,
	downloadId = "dl_…",
	fingerprint = "fp_…",
	universeId = 0,
	placeId = 0,
	ownerId = 0,
	ownerType = "User", -- "User" | "Group"
}
```

- `universeId = 0` means **not pre-bound** (dev downloads). The in-game venue check is then skipped.
- Strings only use `[A-Za-z0-9_-]`. Numbers are integers.

## Watermark (the fingerprint spread over many points)

- It is invisible: one bit per source line, carried by trailing whitespace. A line ending in `" "` is 0 and `"\t"` is 1.
- **Payload:** the ASCII bytes of `"FP:" .. fingerprint .. ";"`, MSB first. It repeats for as long as the script has lines, and **restarts at line 1 of every script**, so any one surviving script with enough lines still identifies the download.
- **Which scripts:** every `ModuleScript`/`Script`/`LocalScript` in the template, except `Stamp` and anything under a folder named `Packages` or `ServerPackages`.
- Existing trailing whitespace is stripped first. Lines after the last newline count too. The script's own newlines are kept.
- **Reading back:** for each script, collect the bits from the trailing whitespace of each line, turn them into bytes, and find `FP:([A-Za-z0-9_-]+);`. The most common match across scripts wins.

## Stamp CLI (`clubkit-infra/apps/api/djx/stamp.luau`, Lune 0.8.9)

```
lune run djx/stamp.luau stamp <template.rbxm> <out.rbxm> <stamp.json>
lune run djx/stamp.luau read  <file.rbxm>
```

- `stamp`: writes the Stamp module from the JSON (same keys as above) and applies the watermark. Exit 0 on success, non-zero with a message on stderr otherwise (missing Stamp, more than one Stamp, bad value).
- `read`: prints one JSON line to stdout, `{"stamp": {…parsed from the Stamp source, or null}, "watermark": "<fingerprint or empty>", "scripts": <n with a match>}`.

## VPS

- **Fingerprint:** `fp_` + 20 base32 chars. **Download id:** `dl_` + 16 base32 chars.
- **Pre-bind:** the `place` input (a Roblox game link or a numeric place id) is resolved by:
  1. `GET https://apis.roblox.com/universes/v1/places/{placeId}/universe` → `{universeId}`
  2. `GET https://games.roblox.com/v1/games?universeIds={id}` → `data[0].creator {id, type}`, `name`
- It is stored in the existing binding columns while `status='unused'` and `activated_at=''`.
