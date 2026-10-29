# BACKHOME (`backhome`)

Catatan konfigurasi dan kustomisasi place-spesifik untuk **BACKHOME**.
*Diperbarui: 2026-10-13*

---

## 1. Konfigurasi Place-Spesifik (`ClubKitConfig.luau`)

File: `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig.luau`  
*(Aturan ADR 0001: File ini adalah buyer-owned, tidak boleh ditimpa penuh oleh engine update)*

| Konfigurasi | Key | Nilai | Catatan |
|---|---|---|---|
| **Branding Discord** | `Branding.DiscordInvite` | `"discord.gg/ZB7nb84NZ"` | Diupdate 2026-10-13 |
| **Perks Member** | `ExternalAdmin.Perks.Fly` | `{}` | Dicabut untuk member/VVIP |
| | `ExternalAdmin.Perks.Smite` | `{}` | Dicabut untuk member/Supreme |
| | `ExternalAdmin.Perks.StaffBypass` | `true` | Staff Adonis tetap bisa akses |
| **Broadcast Berbayar** | `Announcement.DevProductId` | `3718328017` | Produk Roblox 10 Robux |
| | `Announcement.MinMembership` | `"none"` | Supreme tetap wajib bayar |
| **Chat Tag Staff** | `RoleCategories[...].roles[Staff]` | `chatTag = "CREW"` | Chat tag Staff diubah ke CREW |
| **Chat Tag Co-Owner** | `RoleCategories[...].roles[CoOwner]` | `chatTag = "CO-OWNER"` | Tetap CO-OWNER |

---

## 2. Konten & Aset Place-Owned

* **Inventory Tools per Tier:**
  * Disimpan di `ServerStorage.Tools/` (misal folder VIP, VVIP, SUPREME).
  * Bersifat konten milik place BACKHOME, bukan bagian dari source code kit.

---

## 3. Kustomisasi Script Client Khusus BACKHOME (Preservasi)

Script di place BACKHOME memiliki modul sticker yang tidak ada di repo default (retired di base kit tapi aktif di BACKHOME).
**Wajib dipertahankan saat sinkronisasi script client:**

1. **`StarterPlayer.StarterPlayerScripts.Hazastudio_ClubKit.Client.Services.InventoryChromeAnimator`:**
   * `HOTBAR_FRAME_NAMES` menyertakan `hotbarCfg.STICKER_WRAPPER_NAME`.
   * `ensureHotbarChromeRoot()` memanipulasi dan memasukkan `stickerGui` ke dalam `chromeRoot`.
   * **Jangan timpa penuh file ini dari repo tanpa membawa kembali kedua blok sticker tersebut.**

2. **`StarterPlayer.StarterPlayerScripts.Hazastudio_ClubKit.Main`:**
   * Lifecycle sticker: `trackClientLifecycle("StickerBillboardAnimator", ClientMods.StickerBillboardAnimator)`
   * Boot task `ClientMods.StickerBillboardAnimator.init(...)`
   * Inisialisasi `StickerController` dan binding hotbar `binder:bindStickerRequested(...)`
   * Image preload: `reg("background", Config.Sticker, "Config.Sticker")`

---

## 4. Status Triage Keluhan BACKHOME (2026-10-13)

### ✅ Sudah Selesai Diterapkan di BACKHOME:
1. **Chat Channels:** Menggunakan Roblox default `TextChatService` channels (`CreateDefaultTextChannels = true`).
2. **Custom Title Lock Bug:** Fix `TitleAccessDomain.luau` (admin-grant bypass sebelum self-service gate).
3. **Link Discord Baru:** `discord.gg/ZB7nb84NZ`.
4. **Cabut Perks Fly & Smite Member:** Dikosongkan di `ClubKitConfig.ExternalAdmin`.
5. **List Inventory per Tier:** Penjelasan pembagian tool di `ServerStorage.Tools`.
6. **Role-Tool Shadow Bug:** Fix folder resolution di `RoleToolService.luau` (inventory tidak hilang lagi).
7. **Broadcast 10 Robux:** Dev Product `3718328017` + `MinMembership = "none"`.
8. **Tag CREW untuk Staff:** Terpasang di `ClubKitConfig.RoleCategories`.
9. **Logo Overhead:** Selesai.
10. **Command Restore Streak:** Admin command `/setstreak <player> <angka>` aktif.
11. **Hotbar Hilang Pasca Avatar Menu (ACM):** Fix siklus ACM & dynamic re-bind `setupAcmWatcher()` diterapkan via MCP.
12. **Modal Join Community:** Auto-skip jika player sudah bergabung di grup.

### ⏳ Belum / Pending:
* **No. 2 — Scroll tembus di Mobile (Dance Panel & Music List):** Riset selesai (solusi modal/thumbstick sink), pending eksekusi.
* **No. 5 — Posisi Kamera CCTV Admin Dock:** Menunggu target posisi/koordinat kamera yang diinginkan.
* **No. 10 — Tombol Sync Lead Top Menu Tidak Responsif:** Menunggu investigasi lanjutan / repro.
