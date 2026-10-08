# Runbook — Migrasi DataStore lintas-universe (engine path, tanpa Open Cloud)

Tanggal: 2026-10-05 · Venue: BACKHOME (`rust`) · Repo: Club Kit v2.12.0

## Situasi
- OLD = universe **9962470719** (place 85501880339890, `[Rap/Rnb/HipHop] BACKHOME`) — **dibanned Roblox**, engine API masih bisa baca/tulis.
- NEW = universe **10768845395** (place 130748620444133, `NEW PLACE BACKHOME`) — hidup, kosong, konten = clone OLD.
- DataStore **terisolasi per-universe** → wajib salin kunci-demi-kunci.
- Open Cloud API key ditolak (401 Invalid API Key, semua format; IP mesin 182.8.225.13 tidak masuk allowlist / key nonaktif) → jalur engine.

## Batasan teknis engine (terukur)
| Permintaan | Edit DM OLD | Playtest server OLD |
|---|---|---|
| GetAsync budget | ~2500 | ~2500 |
| GetSortedAsync budget | 64→31 | 31 |
| ListAsync (ListKeysAsync) | **0 (mati)** | **~1 panggilan / 60–75 s** |

Konsekuensi: enumerasi kunci store per-user dilakukan di **playtest server** (budget List segar),
di-pace ~70 detik per halaman (50 kunci/halaman). Baca nilai tidak jadi masalah.

## Alat (di `.tmp/`)
| File | Fungsi |
|---|---|
| `relay.py` | HTTP relay localhost:8799, tempat dump & restore bertemu. Jalankan sebagai service: `python relay.py 8799`. |
| `migcall.py` | klien MCP `execute_luau` (target=edit) ke instance tertentu. |
| `startplay.py` → `solo_playtest` | start/stop playtest Run-mode di OLD (`instance:zks-g0z`). |
| `dump_all_paced.lua` | dump penuh semua store dari playtest server OLD → relay. Paced, retry, marker progres. |
| `restore_all.lua` | baca manifest relay → tulis semua entri ke NEW (idempoten). |
| `verify_counts.lua` | hitung kunci per store di universe tempat dijalankan → relay. |
| `watch_mig.py` | pantau progres dump/restore dari file relay. |
| `run_dump.py` | launcher fire-and-forget (MCP timeout ≠ eksekusi batal; lihat aturan #11 skill mcp-studio). |

## Prosedur
1. **Relay**: `python .tmp/relay.py 8799` (service persisten).
2. **Playtest OLD**: `solo_playtest start mode=run instance:zks-g0z` → tunggu roles `[edit, server]`.
3. **Dump**: `python .tmp/run_dump.py .tmp/dump_all_paced.lua` (target `server`).
   - Fase A: store dokumen-tunggal (tanpa ListKeys): AboutRoster `team`, TitleImage `images`,
     EventBoardCache `board`, ManualBagibagi `manual_v1`, MusicLibrary `Playlists`+`Tracks`,
     StickerCollection `GlobalPool_v1`.
   - Fase B: store per-user via ListKeysAsync paced (Overhead, Profile, Settings,
     FavoritedAnimations, StickerCollection, MusicFavorites, AvatarLikes, VenueQuestProgress,
     DonationLeaderboardMetadata, ShopGiftPending, DonationRobuxReceipts, PerkQuota).
   - Fase C: OrderedDataStore via GetSortedAsync (Robux User/Community, AvatarLikes,
     Level, Streak, Couple).
   - Selesai ditandai `mig___pt_ALLDONE.json`.
4. **Restore** (di NEW, edit DM, `instance:ldm-o9x`): `python .tmp/run_dump.py .tmp/restore_all.lua`… 
   catatan: restore berjalan di **edit DM NEW** (bukan playtest) — SetAsync budget cukup.
5. **Verify**: `verify_counts.lua` di kedua universe → bandingkan jumlah kunci; spot-check
   Overhead owner + AboutRoster.

## Jebakan yang sudah ketemu (jangan diulang)
- `ListKeysAsync` di **Edit DM OLD** mati total (budget 0) — jangan coba-coba; pakai playtest server.
- Lebih dari ~1 ListKeysAsync per ~60 s di playtest server → `StandardListGameServerThrottled`;
  halaman `AdvanceToNextPageAsync` juga kena — pace 70 s sebelum tiap advance.
- Karakter `#` pada path URL relay = fragment → **terpotong sebelum server**. Nama chunk store
  dokumen pakai `Store__doc_Key`, restore membuang `#doc` via `gsub(data.store, "#.*$", "")`.
- MCP `execute_luau` timeout ≠ eksekusi gagal — eksekusi lanjut di Studio; pantau lewat marker relay.
- Manifest relay (`/mig/_manifest`) hanya menghitung file `_x_*` non-marker; `complete` ditentukan
  ada-nya `_x_ALLDONE`.
- Jangan hammer budget List untuk "cek cepat" — 1 uji kecil saja, lalu tunggu jendela.

## Yang TIDAK ikut bermigrasi (universe-scoped, harus dibuat ulang manual)
- Developer Product / GamePass ID di `ClubKitConfig` (`Shop.Products.*.GiftId/BuyId`,
  `PaidBroadcast.ProductId`) — ID lama tak berlaku di universe baru.
- MemoryStore (cache leaderboard/invalidate bus) — ephemeral, dibangun ulang otomatis.
- Badge universe lama.
- Registrasi VPS: daftarkan universe+place baru (`/admin/games`, license) sebelum go-live.
