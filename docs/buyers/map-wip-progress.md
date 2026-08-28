# Buyer: Waktu Indonesia Party (WIP) — migration progress

Status: **kit v2.9.0 terpasang berdampingan dengan sisa sistem lama; data pemain sudah diimport; belum Publish.** Last touched 2026-08-27.

Migrasi dari sistem custom lama (RemoteWaktuIndonesia / Donation Board V3 / lizzy TopLikes / ProfileStore) ke Club Kit. Tool import: [`tools/migrate-wip-legacy.luau`](../../tools/migrate-wip-legacy.luau).

## A. Place identity

| Field | Value |
|---|---|
| PlaceName | [ DRIFT LAYOUT ] Waktu Indonesia Party |
| PlaceId | `109791739457192` |
| UniverseId (GameId) | `10071926159` |
| GroupId | `712239722` |
| OwnerUserId | `8296961389` (Guntur) |
| Owner/admin UserIds lama (union dari script lama) | 8296961389, 2863369613, 7432971421, 6008726031, 8785553022, 3155773397, 8336317218, 9093045317, 8853511501, 8353722778, 8963072893, 2904134425, 9121134674 |

## B. Rank group lama → belum dimapping ke role kit

| Rank | Nama lama | Catatan |
|---|---|---|
| 255 | Owner | = kit Owner |
| 254 | Istri Owner | **belum diputuskan** |
| 253 | Manager | **belum diputuskan** (CoOwner?) |
| 252 | Developer / Head Club | → Staff? |
| 240 | Admin / ORANG DALAM | → Staff |
| 170 | STAFF | → Staff |
| 160 | Head DJ | → DJ |
| 150 | DJ | → DJ |
| 50 | THE IDOL | **belum diputuskan** (Influencer?) |
| 11 | TOP SPENDER | kit: leaderboard otomatis |
| 10 | DONATUR | kit: leaderboard otomatis |
| 3 | Anak Owner | **belum diputuskan** |
| 2 | PART OF WIP | **belum diputuskan** |

## C. ClubKitConfig — sudah dipatch

- `Branding.GameName = "Waktu Indonesia Party"`
- `Group.GroupId = 712239722`, `Group.OwnerUserId = 8296961389`
- `ExternalAdmin.Provider = "Kohls"` (Kohl's Admin di SSS = yang aktif; Adonis_Loader di Workspace masih boot → kit warn "Both detected")
- `Shop.Products.Tier1.BuyGamePassId = 1811057201` (VIP lama), `Tier2.BuyGamePassId = 1811891170` (VVIP lama)
- `Donation.RobuxProducts` = 12 dev product lama: 3580734548 (10), 3580675645 (25), 3580675735 (50), 3580675930 (100), 3580676007 (250), 3580675562 (500), 3580676591 (1000), 3580676661 (1500), 3580676762 (2500), 3580677116 (5000), 3580677250 (10000), 3580677343 (20000)

Masih template / belum real: `Donation.GameKey` / `ApiUrl` / `ProviderLink` (masih `thebasic`), `Secrets.DonationApiSecret` kosong, `Branding.LogoImage` default, `PaidBroadcast.ProductId` default, Tier1/Tier2 `GiftId`, seluruh Tier3.

## D. Import DataStore (2026-08-27, strategi `max`, idempotent)

| Store lama | Target kit | Hasil |
|---|---|---|
| `SS_TopLikesV1` (ordered) | `AvatarLikesLeaderboard_v1` + `AvatarLikes_v1` `likes:summary:<id>` | 509 ✅ |
| `Donation Board // V3 - Data` → `Donations` | `RobuxDonationLeaderboard_User_v1` + `DonationLeaderboardMetadata_v1` | 425 donor, 1.845.263 R$ ✅ |
| `CustomTitles` `Title_<id>` | `Overhead_v1.specialTitle` + `specialTitlePreset` (Rainbow→Rainbow, Zebra→Zebra, Fire→Lava, Fireblue→ElectricStroke, Water→OceanicStroke, Black→Silver, Janda/Imut→Bubblegum; font dibuang) | 144 ✅ |
| `PlayerData` (ProfileStore) `FavoriteDances` | `FavoritedAnimations_v2` `Player_<id>` (JSON union) | 17 pemain dari 4.752 profil ✅ |
| `GiftGamepassStore` `Gift_<VIP\|VVIP>_<id>` | `Overhead_v1.giftedMemberships[{tier=Tier1/Tier2, grantedBy=0, source="legacy_import"}]` | **4.326 key**; 2.722 + 1.604 tulis. 413 key gagal di job utama karena throttle → 89 diverifikasi sudah tertulis job paralel, **324 belum diverifikasi** (list di scratchpad `gift-failed-keys-job1-snapshot1.txt`; cek ulang di delta-run) |
| `SawerLeaderboard` (cash) | — | **sengaja skip**, akan diinject via xlsx |
| `PlusTitles` | — | drop (tidak ada padanan) |

Rencana: **delta-run** sekali lagi tepat sebelum cutover (sistem lama sudah tidak nulis DataStore lagi setelah pembersihan, jadi delta ≈ verifikasi 324 gift key saja).

Pelajaran teknis: `ListKeysAsync` dari edit-mode kena throttle permanen → jalankan job listing dari solo playtest `run` (`eval_server_runtime`); write paralel >2 worker memicu `StandardWriteExperienceThrottled`.

## E. Install package (2026-08-27)

`Workspace.HazastudioClubKit_Package` v2.9.0 di-unpack manual (mirror `PackagerCore.unpack`, replaceExisting=false): 51 item, 13 Rojo init-twin dibersihkan. Di-skip: `RS.Icon` lama, `Kohl's Admin` lama, `Adonis_Loader` (package), `Workspace.Part`/`SpawnLocation`, **seluruh `Lighting`** (look map dipertahankan). Model package masih di Workspace (boleh dihapus).

Smoke test run-mode: "Server initialized", 0 error script. Error asset izin: `104629759158002` dan sound `8578316223` belum di-share ke experience.

## F. Pembersihan sistem lama (2026-08-27)

Dipindah ke `ServerStorage._LegacyArchive_2026-08-27` (script disabled, reversible), 26 item:

- **Donation**: `Donation Board // V3`, `SawerPart`, `SawerLeaderboardLive`, `AnonimRig`, `SS.SPX`, `SS.EffectSawer`, `SS.EffectDonate`, `StarterGui.SHOP`, `RS.Sounds`
- **Overhead/likes**: `SS.LikeGranted`, `WS.TopLikes`
- **Remotes lama**: seluruh `RS.RemoteWaktuIndonesia` (RemoteGift, RemoteSawer, DonateCean, Titlee + 136 FontPresets, PesanAdmin, Banyakk, LayarTV, Emotes, CloseMainMenu)
- **Teams/chat tag**: 8 Team lama + `SPS.Folder` (LocalScriptDonate, uiannounce, titleanim, LocalScriptStaff, LocalScriptChat, DJMIXXER1)
- **Orphan**: `VIPTool`/`VVIPTool` lama, `BotolApi`, `TongkatApi`, `EmoteAnimasi` (15 stiker)

Server script lama lainnya (ScriptBasic, Title, Folder, DonoSawer, DATASTORE, Music, Layar+TExt, Gacha, DKISTUDIO server, dst.) sudah dihapus manual oleh user sebelumnya.

**Sengaja dibiarkan (lampu & pyro)**: GLights, NLasers, QPyro/PYRO, LightController+PartMesh+LightEvents+LightControlGui, CenzGLights*, CenzGlobalEffects*, AutoLightsClient, StarterPack `Light WIP`.

**Belum disentuh (di luar scope pembersihan)**: `AFKServer`/`AFKClient`/`AFKRejoin` (kit punya AfkGuard), `Sign@Lumin` (kit punya SignGui), `RS.Icon` lama (mungkin dipakai Cenz topbar), `Handler` (Holo Music, disabled), `BebeqAvatar*`, `CeremonyCamera*`, `DKISTUDIO-ADMINREMOTE`, `DriftClient`, `ReloadScript`, `GroupService`, `TopBarClose`, `VIPWalls`/`VVIPWalls`, `TOP ROBUX SIGN`, `SIGN`, `TVedit`/`TVedit2`, `Adonis_Loader` di Workspace.

Kandidat dipindah ke kit dari arsip: tool VIP/VVIP lama → `ServerStorage/Tools/VIP`,`VVIP`; 15 stiker `EmoteAnimasi` → format Stickers kit; `RS.Shared.Animations` (katalog dance lama, masih di place) → katalog dance kit (keputusan: pakai list lama).

## G. Next

1. Putuskan mapping rank (bagian B) → `ClubKitConfig.Roles`.
2. Isi `Donation.GameKey`/`ApiUrl`/`ProviderLink` + `Secrets` per-buyer; logo; Tier3.
3. Engine 2.9.0 → 2.9.2 (sync via dev-serve `/repo/`).
4. Port `Shared.Animations` lama ke katalog dance kit; stiker & tool dari arsip (opsional).
5. Inject cash/Sawer via xlsx.
6. Delta-run import + verifikasi 324 gift key.
7. Share asset izin (104629759158002, 8578316223); matikan Adonis di Workspace kalau Kohl's saja.
8. Publish.
