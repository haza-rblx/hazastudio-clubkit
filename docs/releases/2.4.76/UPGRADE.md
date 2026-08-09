# Upgrade v2.4.75 → v2.4.76

## Quick steps
1. Studio → ClubKit plugin → **Settings → Update plugin** (if offered), then **Engine → Update Engine**
2. Or rebuild local plugin: `.\tools\ClubKitPackagerPlugin\build-plugin-rbxm.ps1` → **restart Studio**
3. Save place
4. Play test — Command Library topbar opens; donation / carry tools as needed

`ClubKitConfig` / `Secrets` are never fully replaced. Missing config keys may be fill-forwarded.

## What's new

- **Carry animations in the main plugin** — Open Panel → **Tools → Carry animations** (scan, CreateAssetAsync upload, patch `ClubKitConfig`). No separate **Carry Upload** toolbar plugin.
- **Command Library click fix** — Studio `GetRankInGroup` NetFail no longer blocks the topbar icon.
- **SociaBuzz cash-tab** — branded illustration asset + height 160.
- **Docs** — single 9-step setup flow, new Reference page, owner-facing voice, visual cleanup.

## Config changes

None required for this upgrade. Carry upload still patches `Carry.Styles.*.animations` IDs when you run **Upload + patch** (buyer-owned config).

## Breaking

**No.** Standalone `CarryAnimUploaderPlugin` is deprecated but optional if you still use it.

## QA after upgrade

- [ ] F9 / KitVersion **2.4.76** (after Update Engine)
- [ ] Plugin panel shows plugin / kit **2.4.76**
- [ ] Open Panel → Tools → **Carry animations** visible (Scan + Upload + patch)
- [ ] CreateAssetAsync beta enabled if you upload carry clips
- [ ] Command Library topbar icon opens the panel in Studio
- [ ] Donation cash tab looks correct for SociaBuzz (if used)
