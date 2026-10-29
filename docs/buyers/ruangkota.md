# RUANG KOTA (`ruangkota`)

Fresh install, 2026-10-10. Place `RUANG KOTA` — placeId `139187296278320`, universe `10769457658`,
owned by group **Infinity Creative Studio** (`521612350`, owner `harutokuroneko` / `5667064678`).

## A. Kit

- Source: hazastudio Experiment Area copied via SerializationService (base64 over localhost),
  then Config/ClubKitConfig/MusicCatalog overwritten from the repo working tree.
- Engine parity with the repo working tree (post-3.0.0, unreleased changes included): **520/520** by hash manifest.
- Left out on purpose: `ClubKitShowcase` (dev overlay), the 5 sticker modules + `11-StickerSystemGUI`
  (retired), `1000-01-CT-ADDON`, `DJGUI`/`DanceGui`/BHMS scripts (experiments), `CCTV`, `RunningText`.
- Copied: engine roots (RF/RS/SSS/SPS `Hazastudio_ClubKit`, `ReplicatedStorage.Icon`), `WorldEffects`, `Emotes`,
  `OverheadGUIMainTemplateV4/V6`, `DuelWeld` (needed by the `DualGlowStick` tools),
  `ServerStorage.{DonationEffects,DonationSounds,Tools}`, 26 kit ScreenGuis, `Workspace.hazastudioBoard`
  (+ `CoupleBoard` into `V3`).
- Lighting untouched (the map's own look).
- Boards are **parked outside the map** (+130 studs on Z from their Experiment Area spots, x≈-22..78, z≈328..457);
  the owner places them.

## B. Buyer config (`ClubKitConfig`)

| Key | Value |
|-----|-------|
| `Branding.GameName` | `RUANG KOTA` |
| `Group.GroupId` / `OwnerUserId` | `521612350` / `5667064678` |
| `GameDataApi.GameKey` | `ruangkota` |
| `Donation.ApiUrl` | `https://api.hazastudio.id/game/ruangkota` |
| `Donation.NukeWorldPosition` | `Vector3.new(-178, 16.6, 126.7)` — stage floor behind the DJ deck, between the two back speakers |
| `Shop.Products.Tier1-3` ids, `PaidBroadcast.ProductId` | `0` (the-basic ids are universe-scoped; fill from Creator Dashboard) |
| `Donation.Provider` / `ProviderLink` | template default (`bagibagi`, empty) — not decided yet |

## C. Backend (`api.hazastudio.id`)

Registered 2026-10-10 by `.tmp/ruangkota/register-ruangkota.sh` (run over ssh, response captured to a local
file, written into Studio, file deleted): `POST /admin/games` + `PATCH /admin/games/ruangkota/license`
(`license_status=active`, `license_enforced=1`, universe/place above, no `maintenance_until`).
Dashboard owner account `ruangkota` (owner_users id 20). `Secrets.DonationApiSecret` (= `games.secret`) and
`Secrets.GameDataApiSecret` (= `games.social_secret`) are set in Studio — values are not recorded anywhere.
Webhook URL for the cash provider: `https://api.hazastudio.id/webhook/{saweria|bagibagi|sociabuzz}/ruangkota/<webhook_token>`
(token from the dashboard / `GET /admin/games/ruangkota`).
Music (BRM) access: `games.music_enabled = 1` set 2026-10-10 (`.tmp/ruangkota/music-enable.sh`); licence active +
universe bound, so the dashboard's music-context reports `entitled`.
VPS leftovers: `/root/ruangkota-create.json`, `/root/ruangkota-license.json` (root-only, chmod 600, hold secrets) — delete.

## D. Open items

1. **Ctrl+S** in Studio (nothing above is saved yet) and publish.
2. **Share asset access** to universe `10769457658`: 125 assets owned by user `hazatargz` (105 images,
   20 animations, 2 audio — the kit's UI images, emotes/dances, sounds) + 2 textures owned by group
   *LABS Project* (only that group can share them). In Studio: Output → click any
   "Click to share access" line → share all. List below.
3. Product/gamepass ids, donation provider + webhook, board positions, branding logo.

## E. Assets needing permission

| Asset id | Type | Owner | Name |
|----------|------|-------|------|
| 100132107617839 | Animation | User:hazatargz:8842050215 | Cool 2 |
| 100644672308979 | Animation | User:hazatargz:8842050215 | Feeling |
| 100975067372227 | Animation | User:hazatargz:8842050215 | CaramelDancen |
| 101011990104581 | Animation | User:hazatargz:8842050215 | Dxrk R |
| 132401905689089 | Audio | User:hazatargz:8842050215 | Hover |
| 109847084382411 | Audio | User:hazatargz:8842050215 | Clicked |
| 135193838429269 | Image | User:hazatargz:8842050215 | icons8-menu-96 |
| 70457204831369 | Image | User:hazatargz:8842050215 | icons8-command-48 |
| 73049045961531 | Image | User:hazatargz:8842050215 | shop2 |
| 134937924523939 | Image | User:hazatargz:8842050215 | generic settingsv2 |
| 109703706311990 | Image | User:hazatargz:8842050215 | icons8-cd-collection-96 |
| 119219253317473 | Image | User:hazatargz:8842050215 | gift2 |
| 73598133071651 | Image | User:hazatargz:8842050215 | icons8-microsoft-admin-48 |
| 102211998575577 | Animation | User:hazatargz:8842050215 | El soon 4 |
| 101316017663713 | Animation | User:hazatargz:8842050215 | swooo |
| 101793871019920 | Animation | User:hazatargz:8842050215 | Cholo Cumbia 1 |
| 102259623892351 | Animation | User:hazatargz:8842050215 | Salsa Dancing 5 |
| 130233599769147 | Animation | User:hazatargz:8842050215 | 2pa2 |
| 89191924240854 | Animation | User:hazatargz:8842050215 |  Banana Shake |
| 74230242312298 | Animation | User:hazatargz:8842050215 | AllowSleepÂ´s Vibe |
| 116678932569957 | Animation | User:hazatargz:8842050215 | Arms Up |
| 97063157573641 | Animation | User:hazatargz:8842050215 |  Belly Twist R |
| 118018923445056 | Animation | User:hazatargz:8842050215 | Avion |
| 125430069027104 | Animation | User:hazatargz:8842050215 | Bachata 1 |
| 95097116352874 | Animation | User:hazatargz:8842050215 | Bizcochito |
| 140288939141013 | Animation | User:hazatargz:8842050215 | Bizcocho |
| 77389924375836 | Animation | User:hazatargz:8842050215 | BHAnew |
| 80335866044748 | Animation | User:hazatargz:8842050215 | Belly Dance |
| 88723713053515 | Animation | User:hazatargz:8842050215 | Bel Air |
| 76421319383025 | Image | User:hazatargz:8842050215 | Texture |
| 105332257572128 | Image | User:hazatargz:8842050215 | Texture |
| 118196125326891 | Image | User:hazatargz:8842050215 | Texture |
| 87479186690180 | Image | User:hazatargz:8842050215 | full body |
| 113679135532210 | Image | User:hazatargz:8842050215 | Texture |
| 126866972878520 | Image | User:hazatargz:8842050215 | Texture |
| 126281074508689 | Image | User:hazatargz:8842050215 | down to fun |
| 124392921024385 | Image | User:hazatargz:8842050215 | slash |
| 87272651050606 | Image | User:hazatargz:8842050215 | generic settings |
| 82655670841185 | Image | User:hazatargz:8842050215 | head |
| 99143048206723 | Image | User:hazatargz:8842050215 | nametag |
| 120181247918895 | Image | User:hazatargz:8842050215 | Texture |
| 104368298266529 | Image | User:hazatargz:8842050215 | Texture |
| 84120496876687 | Image | User:hazatargz:8842050215 | Texture |
| 70692404618828 | Image | User:hazatargz:8842050215 | Texture |
| 115696416196138 | Image | User:hazatargz:8842050215 | Texture |
| 94928591392266 | Image | User:hazatargz:8842050215 | Texture |
| 137095705806436 | Image | User:hazatargz:8842050215 | enter |
| 132600999999748 | Image | User:hazatargz:8842050215 | cincin |
| 79366863686652 | Image | User:hazatargz:8842050215 | single |
| 94227935854947 | Image | User:hazatargz:8842050215 | bubble chat |
| 104572654745007 | Image | User:hazatargz:8842050215 | torso |
| 107629225021909 | Image | User:hazatargz:8842050215 | Texture |
| 120528034474669 | Image | User:hazatargz:8842050215 | Texture |
| 80833761298381 | Image | User:hazatargz:8842050215 | Texture |
| 102707776395252 | Image | User:hazatargz:8842050215 | Texture |
| 111683032304056 | Image | User:hazatargz:8842050215 | Texture |
| 97878647107864 | Image | User:hazatargz:8842050215 | Texture |
| 78255461602603 | Image | User:hazatargz:8842050215 | Texture |
| 113131041821285 | Image | User:hazatargz:8842050215 | Texture |
| 74797681150467 | Image | User:hazatargz:8842050215 | Texture |
| 123512558618382 | Image | User:hazatargz:8842050215 | Texture |
| 115281405771061 | Image | Group:LABS Project:347553422 | Texture |
| 87150709234065 | Image | User:hazatargz:8842050215 | Texture |
| 104098421594357 | Image | User:hazatargz:8842050215 | Texture |
| 124763627884474 | Image | User:hazatargz:8842050215 | Texture |
| 87769421053814 | Image | User:hazatargz:8842050215 | Texture |
| 107879319900293 | Image | User:hazatargz:8842050215 | Texture |
| 134476914059182 | Image | User:hazatargz:8842050215 | Texture |
| 134903887530325 | Image | User:hazatargz:8842050215 | Texture |
| 125640759408132 | Image | User:hazatargz:8842050215 | Texture |
| 76745118860734 | Image | Group:LABS Project:347553422 | Texture |
| 95726098804496 | Image | User:hazatargz:8842050215 | Texture |
| 84537700816368 | Image | User:hazatargz:8842050215 | Texture |
| 73850772585277 | Image | User:hazatargz:8842050215 | Texture |
| 108477828961521 | Image | User:hazatargz:8842050215 | Texture |
| 125196313785752 | Image | User:hazatargz:8842050215 | Texture |
| 139401731343393 | Image | User:hazatargz:8842050215 | Texture |
| 96708834836532 | Image | User:hazatargz:8842050215 | Texture |
| 70378485477504 | Image | User:hazatargz:8842050215 | Texture |
| 103126797637113 | Image | User:hazatargz:8842050215 | Texture |
| 135445189444807 | Image | User:hazatargz:8842050215 | Texture |
| 80396721891565 | Image | User:hazatargz:8842050215 | Texture |
| 89156825494191 | Image | User:hazatargz:8842050215 | Texture |
| 137053279394543 | Image | User:hazatargz:8842050215 | reset icon |
| 133721587218517 | Image | User:hazatargz:8842050215 | Texture |
| 75823633879992 | Image | User:hazatargz:8842050215 | Texture |
| 75467598830089 | Image | User:hazatargz:8842050215 | Texture |
| 135882743989371 | Image | User:hazatargz:8842050215 | Texture |
| 105203950476408 | Image | User:hazatargz:8842050215 | Texture |
| 83337728090708 | Image | User:hazatargz:8842050215 | Texture |
| 79119968254507 | Image | User:hazatargz:8842050215 | Texture |
| 70796895792875 | Image | User:hazatargz:8842050215 | Texture |
| 118255490338084 | Image | User:hazatargz:8842050215 | Texture |
| 87277955521921 | Image | User:hazatargz:8842050215 | Texture |
| 133986382652012 | Image | User:hazatargz:8842050215 | Texture |
| 96238609415861 | Image | User:hazatargz:8842050215 | Texture |
| 113715654560908 | Image | User:hazatargz:8842050215 | Texture |
| 74300404873363 | Image | User:hazatargz:8842050215 | one last time |
| 126339115340126 | Image | User:hazatargz:8842050215 | Texture |
| 139084530185004 | Image | User:hazatargz:8842050215 | Texture |
| 99794814326784 | Image | User:hazatargz:8842050215 | Texture |
| 96883678546137 | Image | User:hazatargz:8842050215 | Texture |
| 119997653780131 | Image | User:hazatargz:8842050215 | Texture |
| 81587389519720 | Image | User:hazatargz:8842050215 | Texture |
| 138311659786153 | Image | User:hazatargz:8842050215 | Texture |
| 97246026265952 | Image | User:hazatargz:8842050215 | Texture |
| 124548394179643 | Image | User:hazatargz:8842050215 | Texture |
| 101855854873849 | Image | User:hazatargz:8842050215 | Texture |
| 87406816590870 | Image | User:hazatargz:8842050215 | Texture |
| 111805367352967 | Image | User:hazatargz:8842050215 | Texture |
| 110034735985704 | Image | User:hazatargz:8842050215 | Texture |
| 74029031567445 | Image | User:hazatargz:8842050215 | Texture |
| 72492024151251 | Image | User:hazatargz:8842050215 | Texture |
| 113221958826189 | Image | User:hazatargz:8842050215 | Texture |
| 89164749117949 | Image | User:hazatargz:8842050215 | Texture |
| 117147623788832 | Image | User:hazatargz:8842050215 | Texture |
| 103923871608427 | Image | User:hazatargz:8842050215 | Texture |
| 89744205085140 | Image | User:hazatargz:8842050215 | Texture |
| 75726391560105 | Image | User:hazatargz:8842050215 | Texture |
| 76735589689834 | Image | User:hazatargz:8842050215 | Texture |
| 79000981778388 | Image | User:hazatargz:8842050215 | Texture |
| 102376917415210 | Image | User:hazatargz:8842050215 | Texture |
| 94017746091309 | Image | User:hazatargz:8842050215 | Texture |
| 72914550286274 | Image | User:hazatargz:8842050215 | Texture |
| 124143778277635 | Image | User:hazatargz:8842050215 | Texture |
| 76253987574708 | Image | User:hazatargz:8842050215 | Texture |
| 113150974507253 | Image | User:hazatargz:8842050215 | Texture |
