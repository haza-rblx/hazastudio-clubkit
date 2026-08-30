# Club Kit 2.11.0 — Changed Files

Paths are relative to `src/`. **Replace** files are engine-owned and are overwritten wholesale by **Update Engine** — do not hand-edit them in a buyer place. **Buyer-owned** files are never overwritten (fill-forward merge, ADR 0001). **Optional** items are place-level choices.

---

## Replace (engine-owned — auto-updated)

### Role colours, chip, per-role privileges
| File | Change |
|---|---|
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/RoleColorDomain.luau` | **New (pure).** Normalises `roleColor.stops`, builds the gradient keypoints, derives chat `primary`/`secondary` from the first/last stop. |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/RolesDomain.luau` | Sanitises `stops` at boot (malformed dropped, <2 valid = no gradient). |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/Roles.luau` | `RoleColor.stops` + `specialRank.chip` types. |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/Types.luau` | Overhead payload field `roleChip`. |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/OverheadDomain.luau` | Emits `roleChip`; chip roles show their `chatTag` on the rank row instead of repeating the chip text. |
| `ServerScriptService/.../Server/Controllers/OverheadController.luau` | `roleChip` in the delta-sync fingerprint. |
| `StarterPlayerScripts/.../Client/UI/OverheadUI.luau` | `applyRoleStopsGradient` on `04-SpecialRank`; `RoleChipWrapper` pill in `00-DonationLayers` (hides that role's `#N ROBUX` / `#N cash` / SUPPORTER chips). |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/RoleCategoryBuilder.luau` | Per-role `privileges` merged over the category set (`ROLE_PRIVILEGES`). |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/PermissionDomain.luau` | Role-level privileges consulted before the category's. |
| `StarterPlayerScripts/.../Client/Controllers/AdminHubController.luau` | Set-role picker built from `Config.Roles` at open time (cards re-keyed/cloned/parked); hardcoded list is fallback only. |

### Runtime integrity & abuse defense (ADR 0008, phase 1)
| File | Change |
|---|---|
| `ServerScriptService/.../Server/Init/RuntimeGuard.luau` | **New.** SoundGuard (rogue audio), ScriptGuard (runtime script injection), RemoteStorm, AvatarGuard (oversized / laser accessories). |
| `ServerScriptService/.../Server/Init/MovementGuard.luau` | **New.** Position sampler + strike ledger; fly / speed / noclip / teleport / infinite jump. Ships `ENFORCE = "log"`. |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/MovementPolicy.luau` | **New (pure).** Movement rules + strike decay. |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/AvatarPolicy.luau` | **New (pure).** Accessory size / effect judgement. |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/CharacterReady.luau` | `pivotTo` stamps `ClubKitTeleportAt` (server-teleport exemption). |
| `ServerScriptService/.../Server/Init/ServerModuleBag.luau`, `Server/Main.server.luau` | Start the two guards after gravity/carry services. |

### Boot, loading contract, music
| File | Change |
|---|---|
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | `Config.RuntimeGuard`, `Config.MovementGuard` (`ENFORCE = "log"`), `Config.AvatarGuard`; `Config.ClientBoot` external-loading attributes + `EXTERNAL_LOADING_TIMEOUT` (300 s); **`Config.Loading.BOOTSTRAP_WAIT_TIMEOUT` 30 → 120 s**; `RoleColorPalette.stops`. |
| `StarterPlayerScripts/.../Main.client.luau` | Publishes `ClubKitBootProgress` / `ClubKitBootSettled` / `ClubKitGameplayReady`; holds `enterGameplay` while `ClubKitExternalLoading` is true. |
| `StarterPlayerScripts/.../Client/Controllers/MusicPlayerController.luau` | Kit music Sounds join a `SoundService.ClubKitMusic` group, ducked while an external loading screen is up. |

### Place-pack flag
| File | Change |
|---|---|
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ClubKitConfigSchema.luau` | New feature key `HierapolisCustom` (default `false`) + manifest entry. |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ConfigBootstrap.luau` | When that flag is true, merges the buyer-owned `Hazastudio_ClubKitConfig.HierapolisCustom` overlay over the config at boot (missing/broken module → warn, stock catalogue). |

### Version anchors (bookkeeping, not engine behaviour)
- `VERSION` → `2.11.0`
- `ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` → `KitVersion = "2.11.0"`, `BuildId = "20260830"`
- `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` → `KIT_VERSION` / `PLUGIN_VERSION` = `2.11.0`
- `tools/ClubKitPackagerPlugin/plugin/PackagerCore.luau` → blank template resets `HierapolisCustom`; strips the overlay module from packages

---

## Buyer-owned (NOT overwritten — review only)

| File | Action |
|---|---|
| `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | **No change required.** Update Engine fill-forwards the new `Features.HierapolisCustom = false` key. Optional: add `roleColor.stops` and/or `specialRank.chip = true` to roles, and `privileges` blocks to individual roles — see `UPGRADE.md`. |
| `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau` | **Unchanged.** |

## Optional

- `Config.MovementGuard.ENFORCE = "kick"` — enforce movement kicks now instead of waiting for the kit-wide default flip (planned after one week of clean reports).
- `Config.RuntimeGuard.SOUND_ENFORCE = "block"` — stop + delete rogue sounds instead of only logging them.
- `Config.MovementGuard.IGNORE_COLLECTION_TAG` (`ClubKitNoclipIgnore`) — tag fake walls / curtains the noclip check must ignore; `MovementGuard.stampTeleport(character)` — call before script-driven teleports.
- `Config.AvatarGuard` — `"cap"` (default) vs `"strip"` for beam/trail/light accessories.
- Custom loading screens: the `ClubKitExternalLoading` contract (see `UPGRADE.md`) and `extras/place-packs/CinematicLoading` as a worked example.
