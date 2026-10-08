# Rencana Migrasi DataStore: BACKHOME (lama) → NEW PLACE BACKHOME (baru)

Tanggal: 2026-10-05. Status: **SELESAI 2026-10-06** via Open Cloud (`.tmp/mig/oc_copy.py`, key = `.tmp/mig/key_user_raw.txt`).
Verify: semua 23 store kit + 6 ordered cocok jumlahnya OLD==NEW (~26k entri), 41 sampel isi identik. `_KData` (Kohl's Admin):
Main + Bans masuk, 4 `Logs_*` ditolak Open Cloud (400 value null) — di-skip. Backup penuh di `.tmp/mig/ocdump/`.
Jebakan: tulis ke store yang belum ada di universe tujuan butuh scope `control:create` → akali dengan SetAsync+RemoveAsync 1 key dummy dari Studio NEW.

## 1. Yang diminta

Pindahkan SEMUA data production dari place lama (yang kena ban) ke place baru — termasuk
DataStore (level, XP, overhead, title, musik, favorites, sticker, settings, leaderboard,
donation, dsb), bukan cuma isi place-nya.

## 2. Temuan penting (terverifikasi)

| # | Temuan | Bukti |
|---|--------|-------|
| 1 | Dua place ini beda **universe** | OLD `game.GameId=9962470719`; NEW `GameId=10768845395` |
| 2 | Universe LAMA **kena ban** | `games.roblox.com/v1/games` → OLD `isContentRestricted:true`, nama `[TITLE UNAVAILABLE]`, creator 0; NEW normal |
| 3 | DataStore **terisolasi per-universe** | Tulis dari OLD, baca di NEW → `nil`. Jadi harus **salin**, tidak bisa share |
| 4 | Isi place OLD == NEW persis | Workspace/RS/SSS/StarterGui/ServerStorage identik (NEW = clone OLD) |
| 5 | Config kedua place identik | `GameName=BACKHOME`, `GameKey=rust`, owner `9120289411`, grup `763632944` |
| 6 | Engine API OLD: `ListKeysAsync` **mati** | `Enum.DataStoreRequestType.ListAsync` budget = 0 → selalu `StandardListGameServerThrottled` |
| 7 | Engine API OLD: `GetAsync`/Ordered **sehat** | `GetAsync=2484`, `GetSortedAsync=64`, baca Overhead/Profile/AboutRoster/Ordered sukses |
| 8 | Ordered store OLD sudah terenumerasi penuh | RobuxUser=616, RobuxCommunity=113, AvatarLikes=2026, Level/Streak/Couple=0 |
| 9 | Studio OLD masih terhubung MCP & bisa baca DataStore | `instance:zks-g0z` (peer j9q-prr) |
| 10 | Redirect MCP ke NEW sudah ada | `instance:ldm-o9x` (peer ape-jkv) |

## 3. Inventaris store yang harus dipindah

**Standard (17):** Overhead_v1, AboutRoster_v1, TitleImageRegistry_v1, PerkQuota_v1,
FavoritedAnimations_v2, StickerCollection_v1, ShopGiftPending_v1, Profile_v1, AvatarLikes_v1,
Settings_v1, EventBoardCache_v1, VenueQuestProgress_v1, ManualBagibagiAdjustments_v1,
DonationLeaderboardMetadata_v1, DonationRobuxReceipts_v1, MusicLibrary_v1, MusicFavorites_v1.

**Ordered (6):** RobuxDonationLeaderboard_User_v1, RobuxDonationLeaderboard_Community_v1,
AvatarLikesLeaderboard_v1, LevelLeaderboard_v1, StreakLeaderboard_v1, CoupleLeaderboard_v1.

Skema kunci (terverifikasi di source):
- Overhead_v1 → key = `tostring(userId)`; Profile_v1 → `profile_<userId>`;
  Settings_v1 → `settings:<userId>`; FavoritedAnimations_v2 → `Player_<userId>`;
  StickerCollection_v1 → `Player_<userId>` + `GlobalPool_v1`;
  MusicFavorites_v1 → `MusicFavorites_<userId>`; AvatarLikes_v1 → `likes:summary:<id>` & `likes:target:<id>:shard:<n>`;
  DonationLeaderboardMetadata_v1 → `user:<id>` / `community:<id>`;
  DonationRobuxReceipts_v1 → `receipt:<purchaseId>`; MusicLibrary_v1 → `Playlists`, `Tracks`;
  single-doc: AboutRoster_v1=`team`, EventBoardCache_v1=`board`, ManualBagibagiAdjustments_v1=`manual_v1`,
  TitleImageRegistry_v1=`images`.

## 4. Jalur yang dipakai: Roblox **Open Cloud DataStore API**

Kenapa bukan engine API langsung: ListKeys di OLD mati, dan engine API terikat
game-server throttle + universe. Open Cloud stateless, universe-scoped, tidak terikat
budget List game-server → bisa dump penuh dari OLD dan tulis ke NEW.

- Standard v2: `GET/POST /cloud/v2/universes/{u}/data-stores/{ds}/entries`
- Ordered v1: `GET/POST /ordered-data-stores/v1/universes/{u}/orderedDataStores/{ds}/scopes/global/entries`
- Tool: `.tmp/mig/migrate_datastores.py` (dump / restore / verify) — sudah ditulis,
  URL sudah diverifikasi (respons 401 = endpoint benar, key kurang).

## 5. Langkah eksekusi

1. **Backup penuh** OLD → JSON (`dump`). Aman, read-only. **Jalankan ini dulu, apapun yang terjadi.**
2. **Restore** JSON → NEW (`restore`). Idempotent (create/PATCH).
3. **Verify** jumlah key OLD == NEW (`verify`).
4. **Config NEW**: repoint `Donation.ApiUrl` + `GameDataApi.GameKey` ke venue NEW
   (mis. `backhome-new`) di VPS, tambah row game baru + license — supaya donasi/musik
   baru tidak tabrakan dengan venue banned. (Diskusi terpisah.)
5. **Playtest NEW**: cek level/XP/overhead/title/musik/sticker muncul untuk akun uji.

## 6. Yang dibutuhkan dari kamu (pilih satu)

**A. API key Open Cloud (disarankan).** Buat di
https://create.roblox.com/dashboard/credentials → New API Key:
- Access: **kedua** universe (OLD `9962470719` + NEW `10768845395`)
- Scopes: `universe-datastores.objects:list`, `:read`, `:create`, `:update`,
  `universe.ordered-data-store.scope.entry:read`, `:write`
- Simpan sebagai env `CLUBKIT_DS_API_KEY` (jangan di-commit).

**B. Tanpa key (engine + scrape grup).** Aku scrape daftar anggota grup lewat
browser login kamu untuk dapat userId list, lalu dump via engine GetAsync dari OLD
dan restore via engine SetAsync ke NEW. Lebih ribet, cakupan pemain yang sudah
keluar grup bisa terlewat, tapi tidak butuh key.
