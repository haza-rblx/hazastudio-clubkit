# Keluhan player BACKHOME — triage & plan (2026-10-13)

Status: **plan, belum dieksekusi.** Sumber kebenaran kode = repo (lebih baru); place BACKHOME = live, Edit mode, tanpa playtest.
Aturan: `ClubKitConfig.luau` dan `Secrets.luau` buyer **tidak pernah** diganti — perubahan config = edit place-only (fill-forward, ADR 0001).

## Verifikasi cepat (read-only)

| Cek | Hasil |
|---|---|
| Dance panel: touch-camera suppression (`setScrollTouchCameraSuppressed`) | Ada di repo **dan** di BACKHOME → bukan kode yang hilang; butuh repro |
| Title gate `selfServiceOn` | Ada di BACKHOME; bug di repo terbukti (lihat item 3) |
| Sync Lead wiring (`requestLeadDanceSync`) | Ada di repo **dan** BACKHOME → butuh repro |
| `Branding.DiscordInvite` di BACKHOME | `""` (kosong) |
| `Perks` di BACKHOME | `Fly` Tier2 (VVIP), `Smite` Tier3 = 3/minggu — sama dengan repo |
| Role-tool priority shadow bug (`RoleToolService:_resolveFolderNames`) | **Masih ada** di repo: prioritas dipilih sebelum cek folder ada |

## Triage per keluhan

| # | Keluhan | Jenis | Status / akar | Keputusan owner? |
|---|---|---|---|---|
| 1 | Kolom chat private & team dipisah | Fitur baru | Kit tidak punya UI chat sendiri (hanya `ChatTagsController`, `ChatBubbleAdornee`). Perlu pilih: channel `TextChatService` vs UI sendiri | Ya — spec |
| 2 | Dance panel (kiri) & scroll album bikin avatar bergerak | Bug | Kode suppression sudah ada; hipotesis: sentuhan di sisi kiri (zona thumbstick mobile) lolos ke movement. Repro di emulator HP dulu | Tidak |
| 3 | Opsi Title: "You do not have a custom title..." padahal sudah punya title; dulu bisa ganti sendiri | **Bug terkonfirmasi** | `TitleAccessDomain.evaluate` return `LOCKED` saat `selfServiceOn=false` **sebelum** cek `hasTitle`. `ProfileMenuService` mengirim `selfServiceOn = Config.FeatureFlags.SelfCustomTitleEnabled` (default `false`). Komentar di kode & `ClubKitConfig.CustomTitle` bilang admin-title selalu bisa diedit → regresi dari 2.12.0 (commit `08804ce`) | Tidak |
| 4 | Link Discord | Config | `DiscordInvite = ""` di BACKHOME. Isi `discord.gg/ybHT8e3GbW` di `ClubKitConfig.Branding` (place-only) | Tidak |
| 5 | Posisi kamera CCTV cinematic dock admin belum pas | Konten/tuning | Tidak ada kode yang salah; butuh tahu kamera mana & seharusnya di mana | Ya — screenshot/target |
| 6 | Hilangkan Fly & Smite untuk VVIP/Supreme | Config | `Perks.Fly = { Tier2 = true }`, `Perks.Smite = { Tier3 = 3 }`. Pilihan: kosongkan keduanya, atau `Perks.Enabled = false` (perlu cek apakah ikut mematikan `StaffBypass`). **Jangan** sentuh Nuke/Smite VFX donasi — itu fitur berbeda | Konfirmasi ringan |
| 7 | List inventory per tier (VIP / VVIP / Supreme) | Konten + sedikit config | Item = tool di `ServerStorage.Tools/<folder>` (buyer content). `FOLDERS_BY_MEMBERSHIP` hardcoded VIP/VVIP/SUPREME. Asumsi: tier bertingkat (VVIP punya item VIP). "HP → iPong 17 Pro Max" = rename tool, tanpa kode | Ya — kumulatif? |
| 8 | Inventory hilang terus, bahkan setelah rejoin | Bug, penyebab belum diketahui | Kandidat: (a) shadow bug role-tool di atas → folder prioritas tinggi tidak ada → 0 tool; (b) tool diberi saat spawn lalu dibersihkan saat respawn/Backpack reset; (c) load/save hotbar/inventory; (d) membership belum resolve saat rejoin. Perlu repro sebelum fix | Tidak |
| 9 | Menu broadcast berbayar 10 Robux untuk non-Supreme | Config + dashboard | Sekarang `Announcement.MinMembership = "Tier2"` (VVIP gratis). Ubah ke `Tier3`. Harga 10 R$ diatur di Creator Dashboard untuk Product `3503700307` (kit fetch harga live) | Ya — staff/top spender tetap gratis? |
| 10 | Tombol Sync Lead di top menu tidak bisa dipakai; harus klik avatar | Bug | Wiring ada di repo & BACKHOME (`Main.client` ~1781–1787). Perlu repro: gate visibilitas/leader di `SyncLeadTopbarController` | Tidak (kecuali perilaku non-leader) |
| 11 | Tag CREW untuk owner/co-owner/staff | Fitur baru | Tidak ada string "crew" di repo. Opsi: chip/badge overhead `CREW` (menggantikan `OwnerCoOwner`/`Admin`?) atau teks di nametag | Ya — bentuk & lokasi |
| 12 | "Ajarin pasang overhead (logo)" | Pertanyaan/dokumentasi | `Branding.LogoImage` mengganti logo kit-wide (workspace, loading, join modal) via `BrandLogoApplier`. Overhead tidak memakai `BrandLogoApplier` — belum jelas maksud "logo overhead" | Ya — maksudnya apa |
| 13 | Backup STREAK | Fitur baru | Layak secara teknis (belum diverifikasi lokasi penyimpanan streak). Opsi: key DataStore tambahan (additive, versioned, didokumentasikan) atau restore lewat admin command | Ya — scope |

## Urutan eksekusi (setelah keputusan owner)

**Fase A — config/konten, place-only, risiko rendah**
1. Link Discord (4).
2. Fly/Smite dicabut untuk VVIP/Supreme (6) — cek dulu cara `Perks` dibaca dan apakah tabel kosong diisi ulang default.
3. Broadcast gate (9) — ubah `MinMembership`; harga di dashboard.
4. Isi tool per tier (7) — setelah item 8 diperiksa (folder shadow bug bisa bikin tier tampak kosong).

**Fase B — bug, repo dulu lalu sync ke BACKHOME**
5. Title (3): regresi terkonfirmasi → fix di domain murni `TitleAccessDomain` (cek admin-grant sebelum gate `selfServiceOn`). Logika pure di `Shared/` → TDD (`tdd-luau`): tes merah dulu — *admin title + flag off → canEdit=true, reason="admin"*; plus tes "tanpa title + flag off → locked".
6. Role-tool shadow bug (dari 7/8): filter kandidat folder by existence sebelum pilih prioritas. Tes pure dulu.
7. Inventory hilang (8): `diagnosing-bugs` — bangun loop repro dulu (solo playtest, harness server; **tanpa multi-client** sesuai aturan owner), rangking 3–5 hipotesis, instrumentasi satu variabel per waktu, baru fix.
8. Dance panel (2) & Sync Lead (10): repro di emulator HP / desktop; catat hasil sebelum hipotesis fix.

**Fase C — fitur yang butuh spec**
9. Chat private/team (1), CREW (11), Streak backup (13), kamera CCTV (5), logo overhead (12) — tunggu jawaban owner.

## Pertanyaan untuk owner (wajib sebelum fase A/C)

1. Broadcast: yang berbayar itu menu Paid Broadcast saja, atau juga announce/broadcast gratis? Staff & top spender tetap gratis?
2. Inventory: tier kumulatif (VVIP = VIP + tambahan)? Konfirmasi daftar per tier di atas.
3. CREW: tampil sebagai chip overhead, teks nametag, atau keduanya? Menggantikan badge owner/admin yang ada?
4. Chat: kolom "private" dan "team" dipakai di mana — chat global Roblox (TextChatService channels) atau panel sendiri di top menu?
5. "Overhead logo": maksudnya logo di atas kepala pemain, logo kit, atau badge rank?
6. CCTV: kamera mana (nama/screenshot) dan posisi yang diharapkan.
7. Streak backup: otomatis (salinan tiap update) atau cukup restore manual oleh admin?

## Catatan risiko

- Place BACKHOME di-replace engine pada 2026-10-09 (`_OldEngine_2026-10-09` masih ada di ServerStorage) — jangan hapus sebelum owner konfirmasi.
- Perubahan kode di repo tidak masuk BACKHOME sampai sync; sync engine **tidak** menimpa `ClubKitConfig` / `Secrets`.
- Tidak ada bump `VERSION` selama development (CLAUDE.md).
- Item 8 bisa menyentuh DataStore — kalau ada perubahan key, itu migrasi breaking dan harus didokumentasikan.
