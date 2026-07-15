# Changed Files — v2.4.37 → v2.4.38

## Summary

- Core role engine + permissions for default Co-Owner
- Template config documents CoOwner under Leadership
- Breaking: no

## Core — replace via source sync / RBXM

| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/Roles.luau` | Default CoOwner definition + aliases |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/RoleCategoryBuilder.luau` | Inject CoOwner if missing; force aliases |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/PermissionDomain.luau` | CoOwner = Owner for gift/admin |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/CommandLibraryDomain.luau` | owner gate includes CoOwner |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/RolesDomain.luau` | isStaffPlus includes CoOwner |
| `src/ReplicatedStorage/Hazastudio_ClubKit/Shared/Domain/Types.luau` | CoOwner as RoleKey |
| `src/ReplicatedStorage/Hazastudio_ClubKit/KitProduct.luau` | KitVersion 2.4.38 |

## Buyer-owned — review manual, jangan replace

| Path | Action |
|------|--------|
| `Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Opsional: tambah entry CoOwner di RoleCategories Leadership |
| `Hazastudio_ClubKitSecrets/Secrets.luau` | Tidak berubah |

## Template / docs / tools

| Path | Change |
|------|--------|
| `src/ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau` | Template: CoOwner di Leadership |
| `tools/ClubKitPackagerPlugin/plugin/ClubKitManifest.luau` | KIT_VERSION 2.4.38 |
| `VERSION` / `CHANGELOG.md` / `UPGRADE_PROGRESS.md` | Rilis 2.4.38 |
| `docs/releases/2.4.38/*` | Upgrade guide |
