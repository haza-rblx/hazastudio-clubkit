# Upgrade Progress - Club Kit

Scratch pad internal untuk track pekerjaan **sebelum** versi dirilis.

**Versi saat ini:** `2.4.70` (lihat [`VERSION`](VERSION))  
**Target rilis berikutnya:** _(belum ditetapkan)_  
**Branch aktif:** `wip/admin-hub`

---

## Status ringkas

| Area | Status |
|------|--------|
| Merge main `2.4.69` + `2.4.70` | Done — DonationWorldEffects, /drone, /crowd, SociaBuzz, plugin panel v2 + motion |
| UI Motion Level-Up (hybrid) | Done — presets + press + migrate; TopMenu spring open |
| Admin Hub | Done — unreleased |
| Daily boards ×3 (combined / robux / cash) | Done — unreleased |
| LiveChat Footer + pop polish | Done — unreleased |

---

## Perubahan file (unreleased)

| Path | Change |
|------|--------|
| `src/.../Client/Utils/MotionPresets.luau` | NEW — calm motion tokens + MOTION_SCALE |
| `src/.../Client/Utils/PressFeedback.luau` | NEW — press UIScale helper |
| `src/.../Client/Utils/AnimationHelper.luau` | Wire center/panel/dialog to MotionPresets |
| `src/.../Shared/Constants/Config.luau` | `Config.UIMotion` + daily board flags (`DAILY_*`) |
| `src/.../Client/Utils/UISpring.luau` | NEW — critically-damped UI spring driver |
| `src/.../Client/Controllers/TopMenuController.luau` | Spring open/close + press; sidebar presets |
| `src/.../Client/UI/MenuShellUI.luau` | Sidebar presets + press on tabs/modal |
| `src/.../Client/UI/MenuSettingsCore.luau` | Drop unused local sidebar TweenInfo |
| `src/.../Client/UI/ShopUI.luau` / `GiftUI.luau` | PressFeedback on CTAs |
| `src/.../Client/UI/DancePanelUIBinder.luau` | PressFeedback on category tabs |
| `src/.../Client/UI/CommandLibraryUI.luau` | Center open/close via MotionPresets |
| `src/.../Client/UI/AvatarContextUI.luau` | Bottom panel motion via MotionPresets |
| `src/.../Client/UI/AdminPanelUI.luau` | Floating open → presentCenterPanel |
| `src/.../Client/UI/DonationSystemUI.luau` | Floating open → presentCenterPanel |
| `src/.../Client/Services/GeneralNotificationCenterService.luau` | Toast enter/exit via MotionPresets |
| `src/.../Client/UI/AdminHubUI.luau` | NEW — binder; popup forms ≈ HTML (2-col pick, white chips, callouts) |
| `src/.../Client/Controllers/AdminHubController.luau` | NEW — action hub → commands; sheet callout/hint/preview polish |
| `src/.../Client/Controllers/AdminController.luau` | `bindTopbar=false` when hub owns icon |
| `src/.../Client/Init/ClientModuleBag.luau` | Export AdminHubController |
| `src/.../Main.client.luau` | Boot AdminHub; MobilePanel → hub GUI |
| `src/.../Shared/Constants/Config.luau` | `Config.Admin.HUB_GUI_NAME` |
| `tools/BuildAdminHub.editmode.luau` | Studio shell — HTML popup tokens (surface #141414, 360/440) |
| `tools/prototypes/admin-hub-v1.html` | HTML prototype |
| `src/.../DonationNotificationController.luau` | LiveChat Footer hide when idle + pop polish |
| `src/.../DonationController.luau` | `dailyCombined` merge by `lastDonationAt`; fingerprint + empty payload |
| `src/.../DemoDataProvider.luau` | Demo combined + robux for daily |
| `src/.../DonationLeaderboardController.luau` | 3 specs, part-scoped resolve, RP prefix, RobuxLogo toggle |
| `src/.../WorkspaceLeaderboardRenderer.luau` | Cash format `RP ` |
| `tools/place-fixes/**` | Place-only editmode helpers (Sign/Glow/trails/tools) |
| `tools/plugin-prototype/**` | Swiss-knife panel HTML prototype (Setup/Config/Diagnostics/Engine/Tools/Packager/Settings) |

---

## Saat rilis - checklist agent

1. [ ] User konfirmasi nomor versi
2. [ ] Pindahkan `[Unreleased]` di `CHANGELOG.md` ke section versi baru + tanggal
3. [ ] Update `VERSION` + `ClubKitManifest.KIT_VERSION` + `KitProduct.KitVersion`
4. [ ] `git diff vPREVIOUS..HEAD --name-only` → `docs/releases/<version>/CHANGED_FILES.md`
5. [ ] Generate `docs/releases/<version>/UPGRADE.md`
6. [ ] Reset tabel unreleased di file ini
7. [ ] Tag git: `git tag vX.Y.Z`
8. [ ] **Rebuild / reinstall Studio plugin** dari `tools/ClubKitPackagerPlugin` (plugin-build sync saja tidak cukup jika place Tool pakai binary lama)
