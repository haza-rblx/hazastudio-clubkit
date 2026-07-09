# Upgrade v1.3.0 → v2.0.0

**Tanggal:** 2026-07-10

## Langkah cepat (buyer / deploy RBXM)

1. **Backup** `Hazastudio_ClubKitConfig` dan `Hazastudio_ClubKitSecrets`
2. Hapus folder engine lama: `Hazastudio_ClubKit` (semua service)
3. **Insert** file RBXM baru (`HazastudioClubKit_v2.0.0.rbxm`) — export dari Packager setelah build
4. Restore config buyer; merge field baru jika ada
5. Play test → publish

## Yang baru di v2.0.0

- Workflow release + changelog untuk track upgrade
- Fix `/re` refresh berulang
- Fix Command GUI keyboard stuck setelah tutup
- Fix mobile freecam — avatar tidak ikut gerak
- Fix boot crash circular require `DonationProviderDomain`
- Rate limit `/re` naik ke 10 per 30 detik

## File buyer — jangan replace

- `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau`
- `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau`

## QA setelah upgrade

- [ ] `/re` 3x — avatar rebuild setiap kali
- [ ] Command GUI tutup → WASD normal
- [ ] Mobile freecam — avatar diam di tempat
- [ ] Boot tanpa error require
