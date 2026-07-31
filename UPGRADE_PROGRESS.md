# Upgrade Progress - Club Kit

Scratch pad internal untuk track pekerjaan **sebelum** versi dirilis.

**Versi saat ini:** `2.4.68` (lihat [`VERSION`](VERSION))  
**Target rilis berikutnya:** _(belum ditetapkan)_

---

## Status ringkas

| Area | Status |
|------|--------|
| Plugin panel v2 (Engine/Tools UI) | WIP — ship rebuild nanti |
| UI Motion Level-Up (hybrid) | Done — presets + press + migrate; TopMenu spring open |

---

## Perubahan file (unreleased)

| Path | Change |
|------|--------|
| `src/.../Client/Utils/MotionPresets.luau` | NEW — calm motion tokens + MOTION_SCALE |
| `src/.../Client/Utils/PressFeedback.luau` | NEW — press UIScale helper |
| `src/.../Client/Utils/AnimationHelper.luau` | Wire center/panel/dialog to MotionPresets |
| `src/.../Shared/Constants/Config.luau` | `Config.UIMotion` block |
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
| `tools/ClubKitPackagerPlugin/plugin/UpdaterPanel.luau` | Panel v2 UI (Engine/Tools) |
| `tools/ClubKitPackagerPlugin/plugin/DovetailTheme.luau` | AMOLED tokens |
| `tools/ClubKitPackagerPlugin/plugin/HazastudioClubKit.plugin.luau` | Wire Gen Tools / Carry fix callbacks |
| `tools/ClubKitPackagerPlugin/prototypes/plugin-panel-v2.html` | Design iterations |
| `tools/ClubKitPackagerPlugin/plugin-build/**` | Synced copies (panel v2) |
| `src/.../Client/UI/AdminHubUI.luau` | NEW — binder; popup forms ≈ HTML (2-col pick, white chips, callouts) |
| `src/.../Client/Controllers/AdminHubController.luau` | NEW — action hub → commands; sheet callout/hint/preview polish |
| `src/.../Client/Controllers/AdminController.luau` | `bindTopbar=false` when hub owns icon |
| `src/.../Client/Init/ClientModuleBag.luau` | Export AdminHubController |
| `src/.../Main.client.luau` | Boot AdminHub; MobilePanel → hub GUI |
| `src/.../Shared/Constants/Config.luau` | `Config.Admin.HUB_GUI_NAME` |
| `tools/BuildAdminHub.editmode.luau` | Studio shell — HTML popup tokens (surface #141414, 360/440) |
| `tools/prototypes/admin-hub-v1.html` | HTML prototype |

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
