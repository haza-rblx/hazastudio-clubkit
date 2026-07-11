# Hazastudio Club Kit v1.3 — Setup Guide

Panduan ini untuk **buyer / venue** yang pasang kit di place Roblox mereka.

---

## Ringkasan: file apa yang diedit?

| Path di Explorer (Studio) | Edit? | Fungsi |
|------|-------|--------|
| `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig` | **YA** | Satu file config place (group, shop, role, donasi, dll.) |
| `ServerScriptService/Hazastudio_ClubKitSecrets/Secrets` | **YA** | API secret (server-only, tidak ke client) |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Config/ClubKitShowcase` | Opsional | **Switch demo** — ada = showcase, hapus = live |
| `ReplicatedStorage/Hazastudio_ClubKit/` (sisanya) | **JANGAN** | Engine shared — replace saat update kit |
| `ServerScriptService/Hazastudio_ClubKit/Server/` | **JANGAN** | Engine server |
| `ReplicatedStorage/Hazastudio_ClubKit/Shared/Constants/Config` | **JANGAN** | Engine internal (advanced) |

> **Satu sumber config buyer:** `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig` saja. Jangan edit `ClubKitDefaults`.

---

## Demo vs Live mode

| Kondisi | Mode | Leaderboard |
|---------|------|-------------|
| File `ClubKitShowcase.luau` **ada** & `ACTIVE = true` | **Showcase** | Data demo (profiles palsu) |
| File **dihapus** atau `ACTIVE = false` | **Live** | DataStore + API Bagi-Bagi |

Tidak perlu atur `Showcase.Enabled` di `ClubKitConfig` — itu otomatis dari file showcase.

**Kirim ke buyer:** hapus `ClubKitShowcase.luau` dari package → langsung live mode.

**Toggle runtime (owner):** `/showcase on` · `/showcase off` · `/showcase status`

---

## Checklist setup (urutan disarankan)

### 1. Branding & group

Edit `ClubKitConfig.luau`:

```lua
Branding = {
    GameName = "Nama Club Kamu",
    WelcomeMessage = "Welcome to %s",
    Greeting = "Welcome to %s",
},

Group = {
    GroupId = 12345678,        -- ID group Roblox (wajib live)
    OwnerUserId = 987654321,   -- userId owner place
    OwnerGroupRank = 255,
},

AdminUserIds = {
    -- [111111] = true,  -- backup admin tanpa group rank
},
```

### 2. Shop membership (Developer Products)

Creator Dashboard → Monetization → Developer Products → buat VIP / VVIP / Supreme (+ gift).

```lua
Shop = {
    Products = {
        Tier1 = { BuyId = 123, GiftId = 456, Price = 1 },  -- VIP
        Tier2 = { BuyId = 789, GiftId = 101, Price = 1 },  -- VVIP
        Tier3 = { BuyId = 112, GiftId = 131, Price = 1 },  -- Supreme
    },
},
```

Aktifkan product di dashboard. `Price` = harga tampil di UI.

### 2b. Paid broadcast (Developer Product)

Player bayar Robux lewat ikon topbar **Broadcast** untuk kirim pesan ke seluruh server. Staff dengan `canAnnounce` tetap bisa `/announce` gratis.

Creator Dashboard → Monetization → Developer Products → buat **satu** product (mis. "Server Broadcast"), atur harga Robux.

```lua
PaidBroadcast = {
    ProductId = 3503700307, -- ganti dengan Product ID dari Creator Dashboard
},
```

Path: `ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig` → `PaidBroadcast.ProductId`.

**Penting:** ini product terpisah dari `Shop.Products` — jangan pakai BuyId/GiftId membership.

Verifikasi: Play test → ikon Broadcast → prompt Robux muncul. Jika `ProductId` masih `0`, Output: `[ConfigBootstrap] PaidBroadcast.ProductId belum diisi`.

### 3. Membership & role (nama tier + rank)

```lua
Membership = {
    Tier1 = { Label = "VIP", Enabled = true, Priority = 40 },
    Tier2 = { Label = "VVIP", Enabled = true, Priority = 50 },
    Tier3 = { Label = "Supreme", Enabled = true, Priority = 60 },
},
```

Sesuaikan `RoleCategories`, `SpenderRoles`, `CommandAliases` jika rename role.

### 4. Donasi cash (IDR — Bagi-Bagi / Saweria)

```lua
Donation = {
    Provider = "bagibagi", -- "bagibagi" | "saweria" — nama & label donor otomatis
    ProviderLink = "https://bagibagi.co/halaman-kamu",
    ApiUrl = "https://xxx.workers.dev/game/clubkit-key",
    Cash = { Enabled = true },
    Robux = { Enabled = true },
    MinAmount = 1000, -- threshold notif + leaderboard (IDR)
    -- Aura karakter (Robux + Bagi-Bagi/Saweria)
    AuraTiers = {
        { level = 1, min = 10, idrMin = 0, idrMax = 9999, effect = "Level1", sound = "Level1", duration = 4, cameraDuration = 0 },
        -- min = Robux | idrMin/idrMax = range IDR
    },
    -- World VFX global (hanya Bagi-Bagi/Saweria)
    WorldEffectTiers = {
        { min = 100000, effect = "Nuke" },
        { min = 250000, effect = "Smite4" },
        { min = 500000, effect = "BlackHole" },
    },
},
```

**Aura vs world (behavior matrix):**

| Sumber | Aura karakter | World VFX |
|--------|---------------|-----------|
| **Robux** | Ya (`min` Robux) | **Tidak** |
| **Bagi-Bagi / Saweria** | Ya (`idrMin`..`idrMax`) | Ya (`min` IDR) |

Legacy key `RobuxAuraTiers` / `SaweriaWorldTiers` masih dibaca sebagai alias.

### 5. Secrets (server)

`ServerScriptService/Hazastudio_ClubKitSecrets/Secrets.luau`:

```lua
Secrets.DonationApiSecret = "secret-dari-worker-kamu"
Secrets.GameDataApiSecret = ""  -- opsional, social API
```

Harus match secret di Cloudflare Worker / backend. **Jangan share file ini ke publik.**

### 6. Fitur on/off

```lua
Features = {
    MusicPlayer = true,
    Shop = true,
    Leaderboards = true,
    DonationCash = true,
    DonationSaweria = true, -- legacy alias untuk DonationCash
    DonationRobux = true,
    -- matikan yang tidak dipakai: false
},
```

### 7. Cek isi rbxm (setelah insert)

Kit sudah termasuk di file **`.rbxm`**:

- GUI kit (`StarterGui` — folder `01-` … `15-`)
- Workspace leaderboard boards (`RobuxDonationBoard`, `SaweriaDonationBoard`, dll.)
- `ServerStorage/Tools/` sesuai `toolFolder` di config

Pastikan semua muncul di Explorer setelah insert.

### 8. Test & publish

Studio → Play test → **File → Publish to Roblox**.

Tidak perlu Rojo/Argon — edit config langsung di Explorer (double-click ModuleScript).

---

## Leaderboard: sumber data per board

| Board | Butuh ApiUrl? | Sumber live |
|-------|---------------|-------------|
| **Robux** | Tidak | DataStore (pembelian VIP / donasi Robux) |
| **Community** | Tidak | DataStore |
| **Likes** | Tidak | DataStore (like avatar in-game) |
| **Bagi-Bagi / Saweria** | **Ya** | HTTP worker + cache |

**Live tanpa API:** board Saweria tampil pesan *"Donation API not configured yet"*. Robux/Likes kosong = *"No … yet"* (belum ada data), bukan error API.

### Seed leaderboard manual (one-time)

Script pihak ketiga `tools/OneTimeLeaderboardSeeder/` — untuk isi awal **Cash**, **Robux**, dan/atau **Likes** tanpa sentuh engine kit. Copy ke `ServerScriptService`, isi `LeaderboardSeedData.luau`, dry_run → commit, lalu `/refreshleaderboard all`. Matikan (`ENABLED = false`) atau hapus setelah dipakai.

Panduan lengkap: [`docs/index.html#leaderboard-seeder`](docs/index.html#leaderboard-seeder)

---

## Test commands (admin)

| Command | Efek | Persist? |
|---------|------|----------|
| `/testcash <idr>` | Notif + **aura + world VFX** (preview) | ❌ tidak |
| `/testrobux <robux>` | Notif + **aura saja** (preview) | ❌ tidak |
| `/testsaweria <idr>` | Deprecated alias → `/testcash` | ❌ tidak |
| `/testdonate <idr>` | Deprecated alias → `/testcash` | ❌ tidak |
| `/addcash <user> <idr>` | Leaderboard + overhead sync | ✅ ya |
| `/setrobux <user> <robux>` | Leaderboard Robux | ✅ ya |
| `/donatecash <user> <idr>` | Persist + notif + VFX | ✅ ya |

Gunakan `/testcash` / `/testrobux` untuk uji notif + VFX tanpa mengubah leaderboard. Untuk isi board manual pakai `/addcash` atau `/setrobux`.

**Showcase (`ClubKitShowcase.luau` aktif):** tier rendah — contoh `/testrobux 10` → aura Level4; `/testcash 2000` → aura + Nuke. Nonaktifkan showcase untuk threshold production (100k+ world VFX).

---

## Deploy checklist

### Live production

- [ ] `GroupId` + `OwnerUserId` terisi
- [ ] `Shop.Products` BuyId/GiftId terisi & product aktif di dashboard
- [ ] `PaidBroadcast.ProductId` terisi & product aktif di dashboard
- [ ] `Donation.ApiUrl` + `Secrets.DonationApiSecret` (jika donasi cash aktif)
- [ ] `ClubKitShowcase.luau` **dihapus** (atau `ACTIVE = false`)
- [ ] `/showcase status` → OFF
- [ ] Tool folders ada di `ServerStorage/Tools/`
- [ ] Test shop, `/setrole`, leaderboard di Studio
- [ ] Publish

### Demo / trailer saja

- [ ] Biarkan `ClubKitShowcase.luau` ada
- [ ] Tidak wajib ApiUrl untuk board terisi demo
- [ ] Sebelum go-live: hapus showcase file + isi API

---

## Troubleshooting singkat

| Masalah | Solusi |
|---------|--------|
| Shop warning BuyId `0` | Isi ID di `Shop.Products` |
| `PaidBroadcast.PRODUCT_ID masih 0` | Buat Developer Product broadcast → isi `PaidBroadcast.ProductId` |
| Saweria "API not configured" | Isi `ApiUrl` + `DonationApiSecret` |
| Robux/Likes "No … yet" | Normal — belum ada donasi/like di DataStore |
| Mau isi leaderboard manual | `/addcash` atau `/setrobux` — bukan `/testcash` |
| Board blank tanpa teks | Tambah `LoadingOverlay` di template SurfaceGui place |
| `Group.GROUP_ID tidak valid` | Isi `GroupId` atau nyalakan showcase |

---

## Command penting

### Preview (tidak persist) — admin

| Command | Fungsi |
|---------|--------|
| `/testcash <idr>` | Notif + aura + world VFX; board **tidak** berubah |
| `/testrobux <robux>` | Notif + aura saja; board **tidak** berubah |
| `/testsaweria <idr>` | Deprecated alias → `/testcash` |
| `/testdonate <idr>` | Deprecated alias → `/testcash` |

### Persist — owner (atau Studio bypass)

| Command | Fungsi |
|---------|--------|
| `/donatecash <player> <idr> [msg]` | Persist + notif + VFX |
| `/addcash <player> <idr>` | Persist leaderboard cash saja (tanpa VFX) |
| `/removecash <player> [idr]` | Hapus manual IDR (alias: `/removebagibagi`). Studio: `/removecash me` clear self |
| `/setrobux <player> <robux>` | Persist leaderboard Robux (tanpa VFX) |
| `/removerobux <player> [robux]` | Hapus Robux LB. Studio: `/removerobux me` clear self |

### Umum

| Command | Akses | Fungsi |
|---------|-------|--------|
| `/setrole <player> <role>` | canGift | Set role |
| `/gift <player> <tier>` | canGift | Beri membership |
| `/showcase on\|off\|status` | owner | Toggle demo leaderboard |
| `/refreshleaderboard all` | owner | Refresh board |

---

## Cara kirim panduan ini ke Discord

**Super lengkap (14 pesan):** buka **[DISCORD_SETUP_MESSAGES.txt](DISCORD_SETUP_MESSAGES.txt)** — copy tiap blok `MESSAGE 1/14` … `MESSAGE 14/14` → kirim satu per satu di channel `#setup` → pin MESSAGE 1.

**Ringkas (1 pesan):** **[DISCORD_SETUP_POST.txt](DISCORD_SETUP_POST.txt)**

**File lengkap:** lampirkan `CLUB_KIT_SETUP.md` sebagai attachment di pesan pertama.

---

## Struktur di Explorer (setelah insert rbxm)

```
ReplicatedFirst/
└── Hazastudio_ClubKit/
    └── LoadingBootstrap.client

ReplicatedStorage/
├── Hazastudio_ClubKit/              ← engine (jangan edit)
│   └── Shared/Config/
│       └── ClubKitShowcase          ← hapus untuk live
├── Hazastudio_ClubKitConfig/        ← EDIT
│   └── ClubKitConfig
└── WorldEffects/                    ← model VFX donasi

ServerScriptService/
├── Hazastudio_ClubKit/
│   └── Server/
│       └── Main.server
└── Hazastudio_ClubKitSecrets/       ← EDIT
    └── Secrets

StarterPlayer/StarterPlayerScripts/
└── Hazastudio_ClubKit/
    └── Main.client

StarterGui/                          ← folder 01- … 15- (GUI kit)
ServerStorage/Tools/                 ← STAFF, VIP, DONOR, …
Workspace/                           ← RobuxDonationBoard, SaweriaDonationBoard, …
```

---

Hazastudio · Club Kit v1.3
