# Release TEMPLATE — jangan commit folder ini sebagai versi

Salin ke `docs/releases/<VERSION>/` saat rilis.

---

## UPGRADE.md

```markdown
# Upgrade v{OLD} → v{NEW}

**Tanggal:** {DATE}

## Langkah cepat

1. **Backup** `Hazastudio_ClubKitConfig` dan `Hazastudio_ClubKitSecrets`
2. Hapus folder engine lama: `Hazastudio_ClubKit` (semua service)
3. **Insert** file RBXM baru (`HazastudioClubKit_v{NEW}.rbxm`)
4. Restore config buyer; merge field baru jika ada di release notes
5. Play test → publish

## Yang baru

- ...

## Perubahan config (jika ada)

| Field | Perubahan |
|-------|-----------|

## File buyer — jangan replace

- `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau`
- `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau`

## QA setelah upgrade

- [ ] ...
```

---

## CHANGED_FILES.md

```markdown
# Changed Files — v{OLD} → v{NEW}

## Summary

| Metrik | Nilai |
|--------|-------|
| Files changed | N |
| Breaking | yes/no |

## Core — ganti via RBXM

| Path | Jenis | Ringkasan |
|------|-------|-----------|

## Buyer-owned — review manual

| Path | Action |
|------|--------|

## Docs / tools only

| Path | Ringkasan |
|------|-----------|
```
