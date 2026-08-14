# Plugin delivery — Hazastudio Club Kit Packager

Ship the **Studio plugin** separately from the template place. Buyers install it once; engine updates happen in-app.

---

## What you deliver

| File | Who | Purpose |
|------|-----|---------|
| `HazastudioClubKit_Plugin_vX.Y.Z.rbxm` | Buyer / dev | Studio toolbar — Config, Update Engine, **Unpack** |
| Template place (published or `.rbxl`) | Buyer | Full kit already in the place (your Workspace models) |

The plugin is **not** inserted into the buyer place. It lives in the local Plugins folder.

---

## Build (seller, before send)

From repo root:

```powershell
.\tools\ClubKitPackagerPlugin\build-plugin-rbxm.ps1 -CopyToDeliver
```

This:

1. Runs Rojo → `HazastudioClubKitPackager.rbxm`
2. Installs to `%LOCALAPPDATA%\Roblox\Plugins\` (your Studio)
3. Copies a versioned copy to `deliver/HazastudioClubKit_Plugin_vX.Y.Z.rbxm`

Restart Studio after build so you test the same RBXM buyers get.

---

## Public download link (docs site)

`docs/setup.html#plugin-install` has a **Download .rbxm** button pointing to
`https://github.com/haza-rblx/hazastudio-clubkit/releases/latest`. GitHub only
serves that download if a release actually has the `.rbxm` attached as an
asset — the daily `.\tools\release.ps1 -Execute -GhRelease` flow creates a
**notes-only** release with no asset. To make the docs download button work,
either:

1. Attach `deliver/HazastudioClubKit_Plugin_vX.Y.Z.rbxm` to the GitHub
   release manually (Releases → edit release → upload asset), or
2. Host the `.rbxm` elsewhere (e.g. a private CDN / Discord) and swap the
   `href` in `setup.html`'s `.download-card` link.

---

## Buyer install

1. Download `HazastudioClubKit_Plugin_vX.Y.Z.rbxm`
2. Copy or drag into:
   ```
   %LOCALAPPDATA%\Roblox\Plugins\
   ```
3. Restart Roblox Studio
4. **Plugins** tab → toolbar **Hazastudio Club Kit** → open panel

**Seller mode:** leave **OFF** (default). Packager tab is for you only.

---

## What buyers use the plugin for

| Tab / action | Use |
|--------------|-----|
| **Engine → Update engine** | Pull latest kit scripts from GitHub tag (after you release) |
| **Settings → Update plugin** | Soft-update panel/modules without re-installing RBXM |
| **Config** | Edit `ClubKitConfig` fields in Studio |
| **Packager → Unpack** | If you ship Workspace **models** (`HazastudioClubKit_Package`, SyncBhms add-on) instead of a pre-built place |

If the buyer only gets a **published template place** (everything already unpacked), they mainly need the plugin for **Config + Update Engine**.

---

## Updates after first install

1. You release tag `vX.Y.Z` on GitHub (`main` + tag push via `.\tools\release.ps1`)
2. Buyer: **Update plugin** → **Update engine** (HTTP enabled in Game Settings)
3. `ClubKitConfig` / `Secrets` are **not** overwritten

Re-send a new `.rbxm` only when the **bootstrap** changes (`HazastudioClubKit.plugin.luau`) — rare.

Set `UPDATER.githubOwner` / `githubRepo` in `ClubKitManifest.luau` before buyers use Update Engine.

---

## Seller vs buyer

| | Seller (you) | Buyer |
|---|--------------|-------|
| Seller mode | ON | OFF |
| Packager → Create package | Yes | No |
| Packager → Unpack | Optional | Yes (if models shipped) |
| Update engine | Yes | Yes |

---

## Suggested delivery bundle

```
deliver/
  HazastudioClubKit_Plugin_v2.5.3.rbxm
  HazastudioClubKit_Package_v2.5.3.rbxm
  HazastudioClubKit_SyncBhmsAddon_v2.5.3.rbxm   ← optional
  README.md
```

Template place: publish to Roblox **or** send the `.rbxm` packs above. Models `HazastudioClubKit_Package` + optional `HazastudioClubKit_SyncBhmsAddon` can stay in Workspace for reference or be unpacked once then deleted.

See also: [`TEMPLATE_PLACE.md`](TEMPLATE_PLACE.md) · [`../../CLUB_KIT_SETUP.md`](../../CLUB_KIT_SETUP.md)
