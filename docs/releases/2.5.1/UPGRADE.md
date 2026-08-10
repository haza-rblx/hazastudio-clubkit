# Upgrade v2.5.0 → v2.5.1

## Quick steps
1. Studio → ClubKit plugin → **Settings → Update plugin** (if outdated)
2. Studio → ClubKit plugin → **Engine → Update Engine** → Save place (optional — only `KitProduct.KitVersion` changed)

Plugin-only patch. No `ClubKitConfig` / `Secrets` changes.

## What's new
- **Packager "Include blank secrets" toggle** — the Packager's **Create package** button now ships a blank `Hazastudio_ClubKitSecrets` template by default (new switch next to "Include blank config"), so a freshly created package is ready for a new buyer to drop their own API keys into. Any real secret values already filled in on your dev place are automatically blanked before packaging — a distributed `.rbxm` can never carry your own live keys.

## Config changes
- None.

## Breaking
- None.

## QA after upgrade
- [ ] Packager panel → Packager tab shows "Include blank secrets" switch (default on)
- [ ] Create package with the switch on → exported package's `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets` has empty string values, even if your dev place has real secrets filled in
- [ ] Create package with the switch off → `Hazastudio_ClubKitSecrets` is omitted entirely (previous behavior)
