# Upgrade Progress — Club Kit

Internal scratch pad to track work **before** a version is released.

**Current version:** `2.5.0` (see [`VERSION`](VERSION))
**Next release target:** _(not set)_
**Active branch:** `main`

---

## Status summary

| Area | Status |
|------|--------|

---

## File changes (unreleased)

| Path | Change |
|------|--------|

---

## On release — agent checklist

1. [ ] User confirms version number
2. [ ] Move `[Unreleased]` in `CHANGELOG.md` to new version section + date
3. [ ] Update `VERSION` + `ClubKitManifest.KIT_VERSION` + `KitProduct.KitVersion`
4. [ ] `git diff vPREVIOUS..HEAD --name-only` → `docs/releases/<version>/CHANGED_FILES.md`
5. [ ] Generate `docs/releases/<version>/UPGRADE.md`
6. [ ] Reset unreleased table in this file
7. [ ] Git tag: `git tag vX.Y.Z`
8. [ ] **Rebuild / reinstall Studio plugin** from `tools/ClubKitPackagerPlugin` (plugin-build sync alone is not enough if the place Tool still uses an old binary)
