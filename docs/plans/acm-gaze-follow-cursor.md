# ACM 3D avatar — arah pandang ngikutin kursor (dibangun 2026-09-20, unreleased)

Ide owner (2026-09-19): seperti map foto yang bikin kepala avatar ngadep kamera — di panel
Avatar Context Menu, arah pandang avatar 3D-nya ngikutin kursor. Dibangun 2026-09-20 setelah
owner menjawab ronde 1 dengan satu kalimat: **"kalau fitur ini aktif, matiin dulu rotate 3d nya."**
Sisa pertanyaan diputuskan sendiri dengan saran-saran di bawah; semuanya tercatat di § Keputusan.

## Temuan dari kode (sudah diverifikasi)

- ACM default masih **V1** (`Config.FeatureFlags.AvatarContextMenuV2Enabled = false`), jadi jalur
  3D-nya aktif. V2 memakai `ProfilePicture` statis — fitur ini tidak berlaku di sana
  (`AvatarContextUI.luau:222`, `:266-270`).
- Satu modul dipakai **tiga** panel: `AvatarContextUI`, `DonationSystemUI`, `ProfileTabBinder`
  (`Client/Utils/AvatarViewport3D.luau`). Karena itu gaze dibikin **opt-in per instance**
  (`setGazeFollow`), dan dua panel lain tidak berubah sama sekali.
- Perilaku lama: seluruh model diputar sumbu Y lewat `PrimaryPart.CFrame`, 30°/detik, di-throttle
  `AUTO_ROTATE_SKIP_RATE = 3`. Gaze **menggantikan** loop itu, bukan menumpanginya.
- `pool:take()` mentransfer ownership dan model-nya di-`Destroy()` saat `cleanup()`, jadi tidak ada
  risiko leher miring terwarisi ke viewport berikutnya. Tetap saja `setGazeFollow(false)`
  mengembalikan pose leher ke rest, biar aman kalau suatu saat pool mendaur ulang model.

## Spike Studio 2026-09-20 — rencana teknis lama TERBANTAH

Rencana semula ("putar `Neck` Motor6D lewat `neck.Transform`, tulis di `BindToRenderStep` pada
`RenderPriority.Character.Value + 1`") salah di **dua** titik. Yang terukur di THE BASIC TEST:

1. **Rig sekarang tidak punya `Motor6D`.** Avatar modern (termasuk model dari `AvatarPrewarmPool`)
   memakai **`AnimationConstraint`** — `Head.Neck`, berdampingan dengan `NeckBallSocket`
   (`BallSocketConstraint`). R6 masih `Motor6D` di `Torso.Neck`; R15 lama juga. Jadi kode harus
   melayani dua generasi rig.
2. **`Transform` dimiliki Animator, di prioritas mana pun.** Dengan track idle jalan, tulisan ke
   `neck.Transform` ditimpa di Input(100), Camera(200), Character+1(301), 500, Last(2000), dan
   Last+100(2100) — keenam-enamnya. Baru nempel setelah track idle di-`Stop()`. Pertanyaan
   "urutan evaluasi animator" karena itu bukan soal prioritas; tidak ada prioritas yang menang.

**Yang menang: rest offset sendi**, yang tidak pernah disentuh Animator — `Motor6D.C0` untuk rig
lama, `Attachment0.CFrame` (rig attachment di part induk, mis. `UpperTorso.NeckRigAttachment`)
untuk `AnimationConstraint`. Ditulis sekali, nempel antar-frame, menumpuk di atas animasi idle
(napas idle tetap jalan), dan kembali persis waktu dipulihkan. Terukur: yaw tahan di 36.88–36.92°
selama 10 frame; restore balik ke −3.0° (nilai idle).

Rumusnya diputar di **ruang part induk**, bukan ruang sendi:

```lua
pose = CFrame.new(base.Position) * CFrame.Angles(pitch, yaw, 0) * base.Rotation
```

karena `Neck.C0` milik R6 membawa rotasi −90°/180° sendiri — pakai sudut di ruang sendi, R6 bakal
nengok ke sumbu yang salah. Dengan rumus ini R15 (`AnimationConstraint`) dan R6 (`Motor6D`) sama-sama
diuji dengan track idle jalan dan hasilnya identik. Aksesori kepala ikut sendiri (weld ke `Head`).

**Catatan bahaya:** attachment yang sama juga jadi frame `NeckBallSocket`. Aman di ViewportFrame
(tidak ada simulasi fisika di `WorldModel`), **jangan** dipakai di karakter hidup di Workspace.

Konversi kursor → ruang GUI juga diukur, bukan ditebak:
`GetMouseLocation() = AbsolutePosition + GuiInset (0, 58)` — di ScreenGui ACM yang `IgnoreGuiInset`
sekalipun. Jadi pointer dibaca sebagai `GetMouseLocation() - GuiService:GetGuiInset()`.

## Keputusan (ronde 1, ditutup 2026-09-20)

1. **Cakupan gerak** — leher, plus (2026-09-21, permintaan owner "coba kalau badan ikut condong")
   `UpperTorso.Waist` di R15. Yaw ±40°, pitch ±25°, damping eksponensial (rate 11/detik). Satu arah
   pandang dibagi dua: pinggang 35% yaw / 20% pitch, leher sisanya — leher anak dari UpperTorso,
   jadi putarannya menumpuk dan kepala tetap sampai sudut penuh. R6 tidak punya pinggang → leher saja.
2. **Hubungan dengan auto-rotate** — **jawaban owner**: gaze aktif → spin mati. Bukan cuma berhenti
   saat kursor masuk: selama gaze memegang model, badan diparkir menghadap kamera (yaw π, orientasi
   yang dilihat kamera di `_positionCamera`) dan tidak berputar sama sekali. Ini juga menghapus
   "gaze putus" yang tadinya jadi keberatan opsi kedua.
3. **Area trigger** — seluruh panel ACM (`MainWrapper`). Sudut diukur dari **titik tengah viewport**
   (tempat avatarnya), dinormalkan dengan **setengah lebar/tinggi panel**, jadi kursor di pojok panel
   = belokan penuh. Di luar panel: balik halus ke tengah, bukan mentok di clamp.
4. **Mobile & gamepad** — tidak ada kursor, jadi tetap auto-rotate seperti sekarang
   (`MouseEnabled and not TouchEnabled`). Tidak ada drag-to-look.
5. **Panel mana** — ACM saja, opt-in per instance (*diganti 2026-09-21: donation + profile ikut, lihat bawah*). `DonationSystemUI` dan `ProfileTabBinder` tidak
   disentuh.
6. **Buyer bisa matikan?** — tidak menambah key ClubKitConfig. Konstanta engine
   `Config.AvatarContext.GAZE_*` (`GAZE_FOLLOW_ENABLED`, `GAZE_YAW_LIMIT`, `GAZE_PITCH_LIMIT`,
   `GAZE_HEAD_SPRING_FREQ`, `GAZE_BODY_SPRING_FREQ`, `GAZE_SKIP_RATE`, …), plus mati otomatis kalau `GuiService.ReducedMotionEnabled`
   (ADR 0011) atau rignya tidak punya sendi leher (fallback ke spin, bukan avatar beku).

## File yang berubah (source sync, tanpa RBXM)

| File | Isi |
|------|-----|
| `Shared/Constants/Config.luau` | blok `AvatarContext.GAZE_*` |
| `Client/Utils/AvatarViewport3D.luau` | `setGazeFollow`, loop gaze ter-damping + throttle, `resolveGazeJoint`/`writeGazeJoint` dua generasi rig, gaze dimatikan di `cleanup()` |
| `Client/UI/AvatarContextUI.luau` | 3 baris: opt-in viewport v1, hit area `MainWrapper` |

## Verifikasi live (THE BASIC TEST, 2026-09-20)

- Kursor pojok kiri-atas panel → pitch +19.0° / yaw +35.6° (kepala naik). **Tanda yaw salah baca:** badan
  menghadap kamera (yaw π), jadi yaw positif = nengok ke kanan layar — kepala menjauhi kursor. Angka
  cocok dengan kode, tapi kodenya kebalik; ketahuan waktu owner coba 2026-09-21 (kursor kanan → lihat
  kiri). Difix: `targetYaw = dx * yawLimit`. Pelajaran: sudut yang terukur tidak membuktikan arah —
  uji arah dengan mata, atau hitung arah LookVector kepala di ruang kamera.
- Kursor kiri-bawah titik tengah viewport → pitch −5.2° / yaw +17.8° (dagu turun).
- Kursor keluar panel → balik ke rest (pitch 2.9° / yaw −3.1° = nilai idle).
- Badan: 0.000° putaran selama 0.8 detik, `LookVector` (0, 0, 1) — spin benar-benar mati.
- Tutup lalu buka lagi panel: 1 `WorldModel` (tidak ada orphan), gaze jalan lagi, log bersih.
- Dua generasi rig diuji di viewport scratch dengan track idle jalan (R15 `AnimationConstraint`,
  R6 `Motor6D` dari `CreateHumanoidModelFromDescription`).

## Sisa

- Owner masih perlu **Ctrl+S** di Studio kalau mau perubahan yang di-sync lewat `/repo/` tersimpan
  di place.
- Belum diuji dengan `ReducedMotionEnabled` menyala (setting-nya read-only dari Luau; butuh run
  manual owner).
- Opt-in untuk panel donasi/profile tab dan drag-to-look di HP: sengaja tidak dikerjakan.

## Spin + sway (2026-09-21) — menggantikan keputusan 2 ronde 1

Owner memilih "variasi 1 + goyang tipis": kursor di luar panel selama `GAZE_RESUME_SPIN_DELAY` (1.5 s)
→ badan muter lagi (`AUTO_ROTATE_SPEED`, naik halus lewat `GAZE_SPIN_RAMP`); kursor masuk → badan
balik ke kamera lewat jalur terpendek (spring badan) lalu goyang ±12° per 6 s. Kepala
dihitung relatif ke kamera: `yaw leher = yaw kursor − offset badan`, jadi goyangan tidak menggeser
tatapan; selama badan masih membelakangi (>90°) kepala lurus dulu. Semua di satu loop gaze —
`startAutoRotate` tetap tidak jalan selama gaze memegang model. Ditolak: muter terus + kepala
ngikutin (tatapan putus di belakang), drag-to-rotate (bentrok dengan tombol, fitur terpisah).

Trace playtest (yaw dunia HRP vs Head): spin lanjut setelah jeda dan naik ke ~30°/s, wrap ±180°
mulus; kursor masuk → badan ke ~0° dalam ~0.5 s; kursor tetap di kanan → badan −12…+12°, kepala
29–33° (target 32°).

## Donation panel + profile tab (2026-09-21) — menggantikan keputusan 5

Owner minta gaze di dua panel lain juga. Hit area: donation = `MainWrapper`, profile tab =
`refs.outerWrapper` menu. Karena profile tab memuat avatarnya sekali dan membiarkannya hidup
walau menu tertutup, loop gaze sekarang diam kalau viewport-nya tidak benar-benar tampil
(`isOnScreen`: semua GuiObject sampai LayerCollector `Visible`, collector `Enabled`). Terukur di
playtest: donation (kursor kanan-atas) kepala 36–40° / pitch 15°, badan goyang ±6°; profile
(kursor kiri-atas) kepala −31° / 11°; donation tertutup → avatar beku.

## Spring (2026-09-21)

Owner: "kurang smooth". Dua penyebab: `GAZE_SKIP_RATE = 2` bikin kepala cuma ditulis 30 Hz
(tersendat), dan easing eksponensial langsung lompat ke kecepatan penuh tiap target bergeser
(kursor gerak, spin → balik ke kamera). Diganti `UISpring` critically-damped (rumus Freecam, sudah
ada di kit): kepala 1.6 Hz, badan 0.9 Hz, ditulis tiap frame. Spin mendorong *goal* spring badan,
jadi momentum spin terbawa mulus ke gerak balik. `GAZE_SMOOTHING`/`GAZE_TURN_SMOOTHING` dihapus
(belum dirilis). Terukur: 0/880 frame beku saat bergerak; sisa lonjakan kecepatan antar-frame
≤ ~10°/s dan cuma ikut jitter frame-time Studio.

## Waist lean (2026-09-21)

`Config.AvatarContext.GAZE_WAIST_ENABLED` / `GAZE_WAIST_YAW_SHARE` (0.35) / `GAZE_WAIST_PITCH_SHARE`
(0.2); `AvatarViewport3D:_writeGaze` menulis pinggang + leher dengan rumus rest-offset yang sama.
Diukur di viewport scratch saat playtest (R15 `AnimationConstraint`, idle jalan, relatif ke
LowerTorso): paksa 20°/40° → torso +3.9°/+14.0°, kepala total +16°/+42° (rotasi tidak komutatif,
pitch kepala kurang ~4°, tidak kelihatan); restore persis. Kursor asli di pojok panel → torso +12°,
kepala 38°; kursor keluar → balik ke rest. Belum dilihat mata di ACM beneran — owner perlu coba.
