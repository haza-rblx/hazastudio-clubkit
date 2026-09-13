# Club Kit 2.12.0 — Changed Files

Paths are relative to `src/`. **Replace** files are engine-owned and are overwritten wholesale by **Update Engine** — do not hand-edit them in a buyer place. **Buyer-owned** files are never overwritten (fill-forward merge, ADR 0001). **Optional** items are place-level choices.

File list derived from working-tree modification times since the 2.11.0 release (2026-08-30) cross-checked against `CHANGELOG.md [2.12.0]` and the per-change file notes in `UPGRADE_PROGRESS.md` — `git` was not available on the release machine, so this is not a `git diff` listing.

---

## Replace (engine-owned — auto-updated)

### Overhead layers / badges can be switched off entirely (ADR 0009)
| File | Change |
|---|---|
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/OverheadLayerPolicy.luau` | **New (pure).** `classify` / `defaultVisible` / `disabledSet` / `isDisabled` / `enforce` / `invalidValueKeys` — the three-value (`true` / `false` / `"off"`) rule for `DefaultLayers` and `DefaultBadges`. |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/OverheadDomain.luau` | `buildPayload` forces hard-off keys false on both public maps (retroactive, rides the existing fingerprint map so deltas still broadcast); `defaultStoredData` seeds from the projected defaults; `isLayerDisabled` helper. |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/CoupleDomain.luau` | `applyCouple` no longer forces `CoupleName` visible when that layer is hard-off. |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | `Config.Overhead.DEFAULT_LAYER_VISIBLE` / `DEFAULT_BADGE_VISIBLE` / `DISABLED_LAYERS` / `DISABLED_BADGES` / `SHOW_SUPPORTER_CHIP`. |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ConfigBootstrap.luau` | Projects the buyer tables, fills the disabled sets **in place** before `table.freeze`, warns per invalid key instead of guessing. |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ClubKitConfigSchema.luau` | `Overhead.DefaultLayers` / `DefaultBadges` / `ShowSupporterChip` defaults + validation. |
| `ServerScriptService/.../Server/Controllers/AdminController.luau` | Admin title grant no longer force-shows a hard-off `SpecialTitle`. |
| `ServerScriptService/.../Server/Controllers/OverheadController.luau` | Same guard on the couple path. |
| `ServerScriptService/.../Server/Controllers/SettingsController.luau` | Write filter drops a hard-off key, so a crafted remote cannot bank a `true`. |
| `StarterPlayerScripts/.../Client/UI/OverheadUI.luau` | `isLayerVisible` / `isBadgeVisible` refuse a hard-off layer even when the viewer's own attribute says otherwise; supporter chip gated by `SHOW_SUPPORTER_CHIP`. |
| `StarterPlayerScripts/.../Client/UI/MenuSettingsCore.luau` | `shouldShowSettingsItem` hides the row (and every per-badge row under `BadgeGroup`) before the payload guard runs. |
| `StarterPlayerScripts/.../Client/Controllers/SettingsController.luau` | Client-side force-true path for `CoupleName` gated the same way. |

### Membership tiers are a real on/off switch
| File | Change |
|---|---|
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ConfigBootstrap.luau` | `SHOP_TIERS` derived from the enabled set, filtered **in place** (three consumers capture it by reference at module load). |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | Validation skips Game Pass / Product ids of a disabled tier. |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/OverheadDomain.luau` | `getHighestStoredMembership` drops a disabled tier at resolve time (never at storage — re-enabling restores what buyers paid for); gifted entries filtered individually. |
| `StarterPlayerScripts/.../Client/UI/ShopUI.luau` | Hides the disabled tier's card + notification; remaining cards reflow on the existing `UIListLayout`. |
| `StarterPlayerScripts/.../Client/UI/GiftUI.luau` | Hides the tab frame plus any selector button left unbound (resolution falls back to position). |

### Self-service custom title, free first title, Free Title event
| File | Change |
|---|---|
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/TitleQuotaDomain.luau` | **New (pure).** Rolling quota `evaluate` / `record`, plus `QuotaEnabled = false` (unlimited; `record` banks nothing while off). |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/TitleAccessDomain.luau` | **New (pure).** Who may edit — `admin → level → event → free`, and `shouldSpendFree`. A legacy record with `specialTitleFromAdmin = nil` reads as an admin grant (backward compatibility). |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/TitleEventDomain.luau` | **New (pure).** `normalizeMode` / `evaluate` / `describeRoutes` — a threshold above 0 switches its axis on, `Mode` says how active axes combine (`Any` / `All` / `Disabled`). Fail-closed throughout. |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/Types.luau` | `OverheadStoredData.specialTitleChanges` / `specialTitleFreeUsed` / `specialTitleFromAdmin`; profile-menu payload fields (`customTitle*`, `titleEvent*`). |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | `Config.CustomTitle` (limits, messages, `UNLOCK_*` wording) + `Config.FreeTitleEvent` + `Config.FeatureFlags.SelfCustomTitleEnabled` / `FreeTitleEventEnabled`. |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ClubKitConfigSchema.luau`, `Shared/Config/ConfigBootstrap.luau` | `Features.SelfCustomTitle`, `CustomTitle`, `FreeTitleEvent` schema + projection; `FreeTitleEventEnabled` derived from `Mode ~= "disabled"`. |
| `ServerScriptService/.../Server/Services/ProfileMenuService.luau` | `customTitle` / `customTitleRemove` branches: validate → filter (`TextFilterUtil`) → spend quota inside the repository updater; event re-checked server-side; Robux/cash-worded rejections. |
| `ServerScriptService/.../Server/Controllers/ProfileMenuController.luau` | Payload plumbing for the new fields. |
| `ServerScriptService/.../Server/Services/OverheadService.luau`, `Server/Controllers/AdminController.luau` | Admin grant stamps `specialTitleFromAdmin = true`; reset clears it without refunding the free slot. |
| `ServerScriptService/.../Server/Main.server.luau`, `Server/Init/ServerModuleBag.luau`, `Server/Init/EarlyRemotes.luau` | Wiring: `setDonationService` injection (consulted only in donation mode) and remote registration. |
| `StarterPlayerScripts/.../Client/UI/CustomTitleUI.luau` | **New.** Binds the `1000-01-CT-ADDON` panel: size / preset / typeface lists built from config, preset rows painted with the preset itself, quota + locked sentences generated from `describeRoutes`, close/back/backdrop resolved optionally. |
| `StarterPlayerScripts/.../Client/UI/FreeTitleEventUI.luau` | **New.** Drives the buyer's `ADDON-FreeTitleEventTrigger` card: gameplay-ready entrance, idle motion, locked state, session-final dismiss, phone resting scale. |
| `StarterPlayerScripts/.../Client/UI/MenuShellUI.luau` | Profile Title row opens the panel (falls back to the text-only modal with a warn); `openCustomTitlePanel()`; live syncs repaint only the quota/locked half, never the form the player is typing in. |
| `StarterPlayerScripts/.../Client/Utils/PresetPreview.luau`, `Client/Controllers/AdminTitleV3Controller.luau`, `Client/UI/AdminPanelV3UI.luau`, `Client/Controllers/AdminController.luau` | Shared preset painting + admin-side title surfaces touched by the same workstream. |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/TitleImageDomain.luau`, `ServerScriptService/.../Server/Repositories/TitleImageRegistryRepository.luau` | Title-image registry changes made alongside the admin title panel (no separate CHANGELOG entry). |
| `StarterPlayerScripts/.../Main.client.luau`, `Client/Init/ClientModuleBag.luau` | Register the two new UI modules. |

### Graphics presets
| File | Change |
|---|---|
| `StarterPlayerScripts/.../Client/Services/WorldGraphicsService.luau` | **New.** Single owner of shadow casting + `SurfaceAppearance` across the whole Workspace (untagged maps included), with a `DescendantAdded` watcher while anything is forced off. |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/GraphicsQuality.luau` | High declares `shadowQuality = "High"`; new `clampPresetForDevice`, `shouldSuggestQualityBump`, `resolvePreset`; `lightShadows` / `partShadows` / `surfaceAppearance` bundle fields. A comment marks where the reverted `meshFidelity` field was. |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/SettingsDomain.luau` | `defaultStoredData()` reads the starting preset at call time from config (kit default **Low**). |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | `Config.Graphics.DEFAULT_PRESET` / `SUGGEST_QUALITY_BELOW_LEVEL` / `MSG_RAISE_ROBLOX_QUALITY` / `PHONE_MAX_PRESET`. |
| `StarterPlayerScripts/.../Client/Controllers/SettingsController.luau` | Preset application through `WorldGraphicsService`; shadows round-trip restores the preset's own fidelity; one-per-session slider notice. |
| `StarterPlayerScripts/.../Client/UI/MenuSettingsCore.luau` | `isMappedToggleEnabled` gained an opt-in `onValues` list so the Shadows row does not read OFF on the best-shadow preset. |

### Notification center V2
| File | Change |
|---|---|
| `StarterPlayerScripts/.../Client/Utils/NotificationCenterGui.luau` | **New.** Resolves `99-NotificationCenterV2` first, `99-NotificationCenter` as fallback; lifts a V2 GUI left at `DisplayOrder` 0. |
| `StarterPlayerScripts/.../Client/Utils/GuiFade.luau` | **New.** Fades a Frame card by descendant (background, text, image, `UIStroke`, `UIShadow`) where a CanvasGroup would use `GroupTransparency`. |
| `StarterPlayerScripts/.../Client/Utils/TextFit.luau` | **New.** `singleLine` — steps the designed `TextSize` down until the text fits; truncates only below size 12. |
| `StarterPlayerScripts/.../Client/Services/GeneralNotificationCenterService.luau`, `Client/Controllers/DonationNotificationController.luau`, `Client/Controllers/JoinGreetingController.luau`, `Client/Controllers/GenericBroadcastController.luau` | All four binders resolve through the new module and animate by card class; on V2 they follow the designer's UIScale / bar width / text size / stroke instead of kit constants. RichText escaping for donor messages. |
| `StarterPlayerScripts/.../Client/Services/MobileScaleService.luau`, `Client/Services/MobilePanelManager.luau` | Treat both GUI names alike; new phone entries for `04-AdminPanelv3` (0.45), `1000-01-CT-ADDON` (0.55), Free Title card (0.7). |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | `Config.NotificationCenter.V2_DISPLAY_ORDER` (300), `Config.MobileScale.*`. |

### Fixes
| File | Change |
|---|---|
| `StarterPlayerScripts/.../Client/UI/StreakUI.luau` | `play()` shows `Overlay`, spins the sunburst (`Config.Streak.ROTATION_SPEED`), fades the backdrop to `OVERLAY_TRANSPARENCY`; `dismiss()` reverses all three behind a play-id guard. |
| `StarterPlayerScripts/.../Client/Services/ImagePreloadService.luau` | Readiness from `PreloadAsync`'s per-asset callback instead of `ImageLabel.IsLoaded` (`warmed 0 → 230`). |
| `StarterPlayerScripts/.../Client/Controllers/DonationSystemController.luau` | `applyOverheadProfile` returns early when the merged donor snapshot is unchanged (53 repaints → 1). |
| `ServerScriptService/.../Server/Repositories/DonationLeaderboardRepository.luau` | Six `tryReturnLastGood<T>(…)` call sites replaced with an annotated receiving local — the explicit-generic form is not Luau syntax and threw on every DataStore error path. |
| `StarterPlayerScripts/.../Client/Controllers/TopMenuController.luau` | Open state reads `Config.TopbarMenu.LABEL_SELECTED` ("Close Menu") at the theme's text size. |

### Version anchors (bookkeeping, not engine behaviour)
- `VERSION` → `2.12.0`
- `ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` → `KitVersion = "2.12.0"`, `BuildId = "20260912"`
- `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` → `KIT_VERSION` / `PLUGIN_VERSION` = `2.12.0`

---

## Buyer-owned (NOT overwritten — review only)

| File | Action |
|---|---|
| `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | **No change required.** Update Engine fill-forwards `Overhead.DefaultLayers` / `DefaultBadges` / `ShowSupporterChip`, `Graphics.DefaultPreset`, `CustomTitle`, `FreeTitleEvent` and `Features.SelfCustomTitle`. Optional edits described in `UPGRADE.md`. |
| `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau` | **Unchanged.** |

---

## Optional (place data — only if you want the new panels)

These are **not** shipped by Update Engine. They arrive in the delivery RBXM and are installed by hand.

| Item | Where | Needed for |
|---|---|---|
| `1000-01-CT-ADDON` ScreenGui | `StarterGui` | The self-service custom title panel (`Features.SelfCustomTitle = true`). Without it the Title row falls back to the old text-only modal. |
| `ADDON-FreeTitleEventTrigger` frame | inside your `IconGroup` | The Free Title event card (`FreeTitleEvent.Mode ~= "Disabled"`). |
| `99-NotificationCenterV2` ScreenGui | `StarterGui` | The redesigned notification center. V1 places keep their exact previous behaviour on `99-NotificationCenter`. |
| Join greeting `Message` label | inside the V2 notification center | Single-line fitting needs a fixed width with `TextWrapped` off. |
| `Lighting.Technology` | `Lighting` | High's `ShadowSoftness` does nothing on `Voxel`. Not settable by any kit code — change it in Studio and save. |
| `MeshPart.RenderFidelity` | your map | `Performance` meshes stay low-detail on every preset. Not settable at run time — set them in Studio (Edit mode) and save. |
