# Changed Files — v2.4.80 → v2.5.0

## Summary
- 34 files changed (31 modified, 3 new)
- Breaking: no — all new config keys fill-forward to safe defaults (`Currency` → `"IDR"`); Admin Hub falls back to script-built sheets if `ActionTemplates` are absent

## Core — replace via source sync (Update Engine)
| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | `KitVersion` → `2.5.0` |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/CashCurrencyDomain.luau` | **New** — `IDR`/`PHP` presets (symbol, boardPrefix, chipSuffix, roleLabel, shortRoleLabel, groupSep, adminHint) + `normalize`/`getPreset`/`getActive` |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Utils/DonationAmountFormat.luau` | `formatGrouped(value, groupSep)`, `formatCash`, `formatCashBoard`, `formatCashCompact` (currency-aware) |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ClubKitConfigSchema.luau` | `Donation.Currency = "IDR"` |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ConfigBootstrap.luau` | Maps `donation.Currency` → `Config.Donation.CASH_CURRENCY` via `CashCurrencyDomain.normalize` |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config.luau` | `Donation.CASH_CURRENCY = "IDR"` default; `Gravity.RESTORE_DOWNWARD_AT_MIN/MAX` (independent drop-intensity dial, separate from `FLOAT_SPEED_AT_MIN/MAX`); comments updated |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/CommandLibraryDomain.luau` | Command Library descriptions (`/donatecash`, `/addcash`, `/removecash`, `/fakecash`, `/testcash`, `/testsaweria`, `/testdonate`) route through active `CashCurrencyDomain` unit |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Leaderboards/WorkspaceLeaderboardRenderer.luau` | `"RP 0"` fallback → `DonationAmountFormat.formatCashBoard(0)` |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/DonationController.luau` | Chat command replies/usage strings (`/dumpbagibagi`, `/fakecash`, `/donatecash`, `/addcash`, `/removecash`, `/listbagibagi`) — `"IDR"` → active `CashCurrencyDomain` unit |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Controllers/GravityController.luau` | `/gravity [1-10]` accepts an optional drop-intensity argument (independent of `/ungravity`'s float speed); remote `disable` action carries `restoreIntensity` |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/GravityService.luau` | `speedToRestoreVelocity` scales the downward kick from its own intensity input (1 soft → 10 hard); `setServerMode`/`disable` accept `restoreIntensity` separately from float speed |
| `src/ServerScriptService/Hazastudio_ClubKit/Server/Services/JoinGreetingService.luau` | `"Top Rupiah Spender #%d"` fallback → `CashCurrencyDomain.getActive().roleLabel`; `"Rp "` prefix → `DonationAmountFormat.formatCashCompact` |
| `src/StarterPlayerScripts/.../Client/Controllers/AdminHubController.luau` | Sheet openers bind `ActionTemplates`; **separate Ungravity/Gravity gear dials** (`floatSpeed` vs `restoreSpeed`, each with its own sheet + command); Donate Fake = self, Manual/credit picks player after mode select; cash preview/field hints via `CashCurrencyDomain` |
| `src/StarterPlayerScripts/.../Client/Controllers/DonationLeaderboardController.luau` | Dropped local `formatGrouped`; cash branch uses `DonationAmountFormat.formatCashBoard` |
| `src/StarterPlayerScripts/.../Client/Controllers/DonationNotificationController.luau` | Dropped local `formatGrouped`/`formatRupiah`; uses `DonationAmountFormat.formatCash`/`formatGrouped` |
| `src/StarterPlayerScripts/.../Client/Controllers/GravityController.luau` | Shift+G macro replays the last-used speed as `restoreIntensity` on the `disable` remote action |
| `src/StarterPlayerScripts/.../Client/Controllers/JoinGreetingController.luau` | Same rank-label + `"Rp "` prefix fix (client-side mirror) |
| `src/StarterPlayerScripts/.../Client/Controllers/SettingsController.luau` | `OVERHEAD_LAYER_LABELS.TopSpender` "Top Rupiah" → `CashCurrencyDomain.getActive().shortRoleLabel` |
| `src/StarterPlayerScripts/.../Client/UI/AdminHubUI.luau` | `openSheet` clones `ActionTemplates` into `SheetContent` (masters kept, never destroyed); `SelectedPlayerInfo` clones the redesigned template; sheet icon/color follows the selected tile; `_restoreSpeed` + independent gear-label sync (ungravity vs gravity); header `Hi, {Role} {DisplayName}!`; Option1–5 top-header filter shell |
| `src/StarterPlayerScripts/.../Client/UI/MenuSettingsCore.luau` | Settings "Name Tag Details" `TopSpender` toggle label → `CashCurrencyDomain.getActive().shortRoleLabel` |
| `src/StarterPlayerScripts/.../Client/UI/OverheadUI.luau` | `applyChip(..., "RUPIAH")` → `CashCurrencyDomain.getActive().chipSuffix` |

## Buyer-owned — review manually, do not replace
| Path | Action |
|------|--------|
| `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Template gains `Donation.Currency = "IDR"` + cash-unit comments (repo template only). Existing buyer values are **not** overwritten — Update Engine fill-forwards the new key if missing. Set to `"PHP"` manually if your venue settles in Peso. |
| `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau` | No change |

## Plugin / tools
| Path | Change |
|------|--------|
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | `KIT_VERSION` + `PLUGIN_VERSION` → `2.5.0` |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitPanel.luau` | Packager → **Unpack RBXM…** button; Donations tab → **Cash currency** dropdown (`IDR`/`PHP`) |
| `tools/ClubKitPackagerPlugin/plugin/PackagerCore.luau` | `promptAndUnpackFromRbxm` (`PromptImportFileAsync` + `SerializationService:DeserializeInstancesAsync`, staged + validated before parenting) |
| `tools/ClubKitPackagerPlugin/plugin/PackagerPanel.luau` | Help text for Export / Unpack RBXM flow |
| `tools/ClubKitPackagerPlugin/plugin/ConfigEditCore.luau` | `Snapshot.donation.currency` read/default + `WritePayload.donation.currency` patch (`Donation.Currency`, uppercased + `%q`-quoted) |
| `tools/ClubKitPackagerPlugin/README.md` | Unpack RBXM steps |
| `tools/dev/RehomeAdminHubActionTemplates.luau` | **New** — command-bar util if `ActionTemplates` land under `SheetBody` instead of the gallery root |

## Ops backend (donation-api) — not shipped to buyers
| Path | Change |
|------|--------|
| `tools/donation-api/src/worker.js` | `normalizeCurrency` (whitelist `IDR`/`PHP`, parameterized SQL); `currency` in game payload, `POST`/`PATCH /admin/games` (auth-gated), and `clubKitConfigLines.donation_currency` |
| `tools/donation-api/admin-panel/src/App.jsx` | `formatIdr` → currency-aware `formatCash`; `currency` prop threaded through pages/tables; Games table + Quick-create currency dropdown |
| `tools/donation-api/migrations/0009_game_currency.sql` | **New** — `games.currency TEXT NOT NULL DEFAULT 'IDR'`. **Run `npm run cf:d1:migrate:remote` before deploying the new worker.** |

## Docs / meta only
| Path | Change |
|------|--------|
| `CHANGELOG.md` | `[2.5.0]` section |
| `CLUB_KIT_SETUP.md` | Section 4 — `Currency` field, provider settlement matching, retune + live-switch warning |
| `docs/locales/{en,id,es,ja}.js` | Setup flow step 5 — `Currency` field mention |
| `UPGRADE_PROGRESS.md` | Reset after release |
| `VERSION` | `2.5.0` |
| `.gitignore` | Added scratch/build patterns (`.local/`, `.tmp-*/`, `deliver/`, `deliverables/`) |
| `docs/releases/2.5.0/` | This folder |
