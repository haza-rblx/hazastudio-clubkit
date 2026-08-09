# Template place delivery — full pack + SyncBhms add-on

Ship **two Workspace models** for a standard Club Kit template delivery (no RBXM export required):

| Model (Workspace) | Contents |
|-------------------|----------|
| `HazastudioClubKit_Package` | Full place kit (everything per service, **no BHMS**) |
| `HazastudioClubKit_SyncBhmsAddon` | **Optional** — legacy SyncBhms / BHMS dance place-pack only |

**Not included** in the main template (by design):

- SyncBhms instances (see add-on model above)
- Buyer `Secrets` (never ship production secrets)

Group / roles / shop IDs live in the main pack `ClubKitConfig` (blank template or filled before publish).

---

## Step 0 — Duplicate the dev place first

**Do not pack from the live dev place directly.**

1. Open your dev kit place (e.g. `THE BASIC TEST 1.3`).
2. **File → Save to File As…** (or **Publish to Roblox As…**) → name e.g. `ClubKit Template v2.4.75`.
3. All delivery work happens in the **duplicate** only.

---

## Step 1 — Prepare the duplicate place

Main template uses **Club Kit dance** (default):

```lua
LegacySyncBhms = false,
SyncDance = true,
```

Optional: blank `Group.GroupId = 0` / `OwnerUserId = 0` in config when shipping a generic template.

---

## Step 2 — Update engine & plugin

1. Plugin → **Update plugin** → **Update Engine** → latest tag (e.g. `v2.4.75`).
2. Rebuild plugin if needed: `.\tools\ClubKitPackagerPlugin\build-plugin-rbxm.ps1`
3. Enable **Settings → Seller mode** → **Packager** tab.

---

## Step 3 — Create main template pack

1. Packager → **Main template pack** → **Create package**.
2. Output: **`Workspace/HazastudioClubKit_Package`** (Model)
3. Check **Output** for BHMS exclusions logged and no critical `missing` lines.

### What the main pack includes

**Full service clone** — every top-level child in each service (not a manifest pick-list):

| Service | Rule |
|---------|------|
| `ReplicatedFirst` | All children |
| `ReplicatedStorage` | All children (except BHMS; Config = blank template if enabled) |
| `ServerScriptService` | All children (except BHMS + Secrets) |
| `ServerStorage` | All children |
| `StarterGui` | All kit UI (except `DanceGui`) |
| `StarterPlayerScripts` | All scripts (except BHMS dance clients) |
| `Workspace` | Map, boards, spawn, etc. (not `Camera` / `Terrain`) |
| `Lighting` | Sky, atmosphere, post-FX |

**Excluded (→ SyncBhms add-on):** `SyncBhmsGate`, `SyncBhmsAcmBridge`, `Remotes2`, `StoredAnimations`, `SyncSettings`, `SyncBhmsRemotes`, `SyncServer`, `DanceGui`, BHMS client scripts.

---

## Step 4 — Create SyncBhms add-on (separate, optional)

1. Same duplicate place (must still have BHMS instances in live services).
2. Packager → **SyncBhms add-on** → **Create SyncBhms add-on**.
3. Output: **`Workspace/HazastudioClubKit_SyncBhmsAddon`** (Model) — includes **`Workspace/SyncBhms`** from `extras/place-packs/SyncBhms/SyncBhms.rbxm` when present in the place.

Buyer install:

1. Unpack **main template** first.
2. Unpack **SyncBhms add-on** into the same place.
3. Set `ClubKitConfig.Features.LegacySyncBhms = true` (and keep `SyncDance = true` for ACM button).

Guide: [`extras/place-packs/SyncBhms/README.md`](../../extras/place-packs/SyncBhms/README.md)

---

## Step 5 — Buyer install (main only)

1. Copy **main template** model → Plugin → **Unpack**.
2. Fill `Secrets.luau` on the buyer universe.
3. Edit `ClubKitConfig` (Group, shop IDs, donation URL).
4. Enable **HttpService** → Publish → test.

---

## QA checklist (before send)

- [ ] Play duplicate — server boots, loading screen completes
- [ ] Main pack: BHMS exclusions logged; no BHMS instances inside main model
- [ ] SyncBhms add-on model contains bridges + DanceGui + SyncServer + **`Workspace/SyncBhms`** (full rbxm pack)
- [ ] `LegacySyncBhms = false` on main-only install → Club Kit dance panel works
