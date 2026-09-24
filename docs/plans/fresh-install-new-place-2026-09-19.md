# Fresh install — place baru ("Place1"), mulai 2026-09-19

**Status: TERBLOKIR.** Akun `hazatargz` kena ban 1 hari (perkiraan buka ~2026-09-20), dan
Studio peer sudah putus dari bridge MCP. Tidak ada satu pun langkah di bawah yang sudah
dijalankan — package baru sampai di Workspace sebagai staging model.

Resep dasarnya: memory `fresh-install-on-finished-map` + `delivery-pack-recipe`.
Bedanya dengan KASMARAN/LANGIT SORE: place ini **masih kosong** (belum ada map), jadi jebakan
"Lighting map ketimpa" belum berlaku — lihat D5.

## Keadaan yang sudah terukur (snapshot sebelum Studio putus)

| Hal | Nilai |
| --- | --- |
| `game.Name` / `PlaceId` / `GameId` | `Place1` / `0` / `0` → **belum pernah di-publish** |
| `Workspace` | `Camera`, `Baseplate`, `Terrain`, `SpawnLocation`, `Model:HazastudioClubKit_Package` |
| `Lighting` | `Sky`, `SunRays`, `Atmosphere`, `Bloom`, `DepthOfField` (isi template Baseplate) |
| `ServerScriptService`, `ReplicatedStorage`, `ServerStorage`, `StarterGui`, `StarterPlayerScripts`, `SoundService` | **kosong semua** → kit belum ke-unpack |
| Pack terbaru yang tersedia | `~/Desktop/ClubKit v2.12.0 Delivery/HazastudioClubKit_Package_v2.12.0.rbxm` (3.3 MB, 2026-09-12) |
| Repo | `VERSION` = 2.12.0, tapi HEAD punya perubahan **unreleased** (lihat D2) |

**Belum terverifikasi:** versi pack yang benar-benar diimport. Studio putus sebelum aku bisa
baca `KIT_VERSION` di `ClubKitManifest` dalam staging model. Langkah 0 di bawah menutup itu.

## Checklist

- [ ] **0. Konfirmasi versi pack.** Baca `KIT_VERSION` dari `ClubKitManifest` di dalam
      `workspace.HazastudioClubKit_Package`. Kalau bukan 2.12.0, hapus model-nya dan import
      ulang dari folder Desktop — jangan unpack pack tua lalu berharap source-sync menutup
      selisih GUI-nya.
- [ ] **1. Unpack** pakai `PackagerCore.unpack`, di-`loadstring` dari dev-serve
      `/repo/tools/ClubKitPackagerPlugin/plugin/` (butuh shim `require(script.Parent.ClubKitManifest)`).
      Jalankan `tools/ClubKitPackagerPlugin/dev-serve.ps1` dulu (port 8798).
      Place masih kosong → `replaceExisting = true` aman, **kecuali** D5 dijawab "map diimport dulu".
- [ ] **2. Source-sync engine** ke target D2 pakai resep hash-manifest (djb2-ish
      `h = 5381; h = (h*31 + byte) % 4294967291`, `\r` dibuang) lewat `/repo/<path>`.
      Batch ≤30 file per `execute_luau`, tiap call hitung ulang drift + assert hash baca-balik.
- [ ] **3. Addon GUI manual** sesuai D3 — `docs/releases/2.12.0/CHANGED_FILES.md` mencatat
      `1000-01-CT-ADDON` dan `99-NotificationCenterV2` **tidak** dikirim Update Engine.
      Cek dulu apakah pack 2.12.0 sudah membawanya (pack-nya dibuat dari PARKLAB, bukan dari
      template murni) sebelum memasang manual.
- [ ] **4. `ConfigPatchCore.patchBuyerConfig`** → fill-forward key baru ke `ClubKitConfig.luau`.
- [ ] **5. Repoint config** (jebakan: config di dalam pack itu punya the-basic, bukan template
      kosong): `Branding.GameName`, `Donation.ApiUrl`, `GameDataApi.GameKey`,
      `Donation.Provider`/`ProviderLink`, `Group.OwnerUserId`, dan Developer Product ID di
      `Shop.Products.Tier1-3` (`GiftId`/`BuyId`) + `PaidBroadcast.ProductId`. Lihat D1 + D4.
- [ ] **6. Publish place** — wajib sebelum langkah 7, karena universe id + place id baru ada
      setelah publish (sekarang dua-duanya 0).
- [ ] **7. Daftar VPS**: `POST /admin/games` + `PATCH /admin/games/<key>/license` dengan
      universe+place eksplisit (`clubkit-vps-ops`). Secret balikan **jangan lewat context** —
      buang respons ke file di `.tmp/`, biar Studio baca lewat `/repo/.tmp/…`, lalu hapus.
      Sekalian pastikan `maintenance_until` tidak diisi tanggal lampau (`maintenance-until-kill-switch`).
- [ ] **8. Ctrl+S / publish lagi.** Tidak ada satu pun tool di bridge yang menyimpan place.
- [ ] **9. Playtest verifikasi**: log `License verify on boot {status=active}`, row VPS keisi
      `kit_version` + `last_seen`, ACM 3D avatar muncul, shop tier bisa di-prompt.

## Keputusan yang masih terbuka

- **D1 — Identitas venue**: nama place, `Branding.GameName`, `GameDataApi.GameKey` (huruf kecil,
  unik di VPS), `Group.OwnerUserId`.
- **D2 — Target source-sync: tag 2.12.0 atau HEAD?** HEAD membawa yang belum dirilis: UI motion
  (ADR 0011), Daily Quest addon, toggle tier membership, `MusicDurationPolicy`, fix role-tools
  folder, fix TeamColor, gate `Features.ImageCustomTitle`. Saranku HEAD kalau place ini memang
  buat nguji barang baru; 2.12.0 kalau ini place buyer yang harus sama dengan yang lain.
- **D3 — Addon GUI manual mana yang dipasang**: CT addon, NotificationCenterV2, dan (kalau D2 =
  HEAD) Daily Quest `1000-02-DQ-ADDON`.
- **D4 — Donasi + produk**: provider mana, `ApiUrl` mana, dan Developer Product harus dibikin
  **baru** setelah publish karena ID-nya universe-scoped.
- **D5 — Map**: mau import map jadi ke place ini nanti? Kalau ya, urutannya map dulu lalu unpack
  dengan `pkg.Lighting:Destroy()` + `replaceExisting = false`, karena unpack normal menimpa
  Lighting dan **undo tidak mengembalikannya**.
