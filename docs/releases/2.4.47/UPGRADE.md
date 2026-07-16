# Upgrade v2.4.46 → v2.4.47

## Quick steps

1. Backup `ClubKitConfig` + `Secrets`
2. Studio → Plugin ClubKit → **Check Update** → **Update Engine**
3. Review `SpenderRoles` di `ClubKitConfig` (lihat Config changes) — plugin **tidak** replace file config utuh; merge manual / sesuaikan MaxRank + label jika place masih pakai nama lama
4. Save & publish place

## What's new

### Added
- **Dynamic chat bubble offset** — bubble naik/turun mengikuti tinggi overhead (Attachment `ClubKitChatBubble`). Kill switch: `Config.ChatBubble.ENABLED`.

### Changed
- **Chat bubble style** — background `#111111`, teks soft pastel dari warna role speaker.
- **Donation roles** — hapus role giftable `Donatur`. Rename: **Top Robux Donator** / **Top Rupiah Spender**. Keduanya hanya **top 10** (rank `#11+` tidak dapat role/chip).

## Config changes

Di `ClubKitConfig.SpenderRoles` (template + schema):

| Field | Change |
|-------|--------|
| `CashSpender.MaxRank` / `RobuxSpender.MaxRank` | keduanya **10** |
| Labels / ChatTags / ToolFolders | Top Rupiah Spender / Top Robux Donator |
| `Donatur` | **dihapus** dari engine — hapus entry lama di config buyer jika masih ada |

Legacy aliases `Top Supporter` / `Top Donor` masih map ke role baru.

## QA setelah upgrade

- [ ] Rank Robux #1–#10: chip + chat tag Top Robux Donator; #11+ tidak
- [ ] Rank Rupiah #1–#10: chip + chat tag Top Rupiah Spender; #11+ tidak
- [ ] Tidak ada role/tool folder Donatur
- [ ] Bubble chat di atas overhead (Guest pendek vs Owner+badges+couple+donation)
- [ ] Toggle layer overhead → bubble naik/turun
- [ ] Bubble background gelap `#111111`, teks soft sesuai role
- [ ] Chat Off / Nearby tetap jalan
