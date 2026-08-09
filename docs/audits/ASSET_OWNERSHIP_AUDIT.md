# Asset Ownership Audit — Hazastudio Club Kit

**Date:** 2026-08-08  
**Place scanned:** THE BASIC TEST 1.3 (`placeId` 75916114543452)  
**Method:** source scan (`src/`) + Studio `MarketplaceService:GetProductInfo`  
**Owned accounts treated as “kit-controlled”:**  
- User `hazatargz` (8842050215)  
- Group `NUWA STUDIO` (10256610252)  
- Group `LVL Comunity` (9769481274) — *only if you control this group*  
- User `Roblox` (1) — platform defaults (safe)

Musik (~503 ID di `tools/music-migration`) **tidak** diikutkan di report ini.

---

## 1. Executive summary

| Area | Unique IDs | Owned / Roblox | Third-party |
|------|------------|----------------|-------------|
| Kit engine (`Hazastudio_*` + Icon) | ~47 | ~43 | **4** (+ Camera LVL jika group bukan milikmu) |
| `ServerStorage.Tools` + `ReplicatedStorage.WorldEffects` | **173** | **19** | **154** |
| **Total action surface** | — | — | **~158+** |

**Implikasi:**  
- Update Engine (source sync) → cukup fix kit third-party + grant permission asset milikmu.  
- Pack RBXM yang ikut **Tools / WorldEffects** → buyer akan bergantung pada permission **154** asset orang lain (atau kamu re-upload / ganti).

File data: [`tools-worldeffects-assets.tsv`](tools-worldeffects-assets.tsv) · [`kit-engine-assets.tsv`](kit-engine-assets.tsv)

---

## 2. Kit engine — third-party (harus diganti / re-upload)

| Asset ID | Owner | Type | Dipakai |
|----------|-------|------|---------|
| `101906294438076` | HD Admin (group 934508079) | Image | TopbarPlus caret |
| `124920646932671` | HD Admin (group 934508079) | Image | TopbarPlus drop shadow |
| `947384308` | Wizzoblox02 (103219254) | Audio | Nuke firework launch (`SpawnFireworks`) |
| `78416657618448` | inevercaredxx (2240621145) | Animation | Cinematic dance default |
| `131545412033411` | LVL Comunity (9769481274) | Image | Topbar Camera — treat as third-party jika group bukan milikmu |

### Kit engine — milikmu (grant experience / open use)

Lihat [`kit-engine-assets.tsv`](kit-engine-assets.tsv). Ringkas:

- **hazatargz:** 40 assets (UI icons, badges, logo, hover/click SFX, plugin icons)
- **NUWA STUDIO:** 3 (`71634976881165`, `74687624322129` enter SFX, `101268994273611` broadcast)
- **LVL:** 1 Camera icon (jika group milikmu)

Roblox-owned (aman): idle R6/R15, font Inter/Rubik.

---

## 3. WorldEffects + Tools — overview

### Folders

**WorldEffects** (`ReplicatedStorage.WorldEffects`)  
- Smite3, Smite4, BlackHole, Nuke — **137** unique IDs only in WE  

**Tools** (`ServerStorage.Tools`) — 15 tools share almost the same FX set:  
- DJ, DONOR, INFLUENCER, LEAD DANCE, MODERATOR, OWNER, STAFF, STREAMER, SUPREME  
- TOP DONOR, TOP ROBUX DONATOR, TOP RUPIAH SPENDER, TOP SUPPORTER, VIP, VVIP  
- **36** unique IDs only in Tools  

Tidak ada overlap ID Tools↔WorldEffects (0 “both”).

### Owned dalam Tools/WE

| Owner | Count | Notes |
|-------|-------|-------|
| Roblox | 18 | default meshes/textures/SFX aman |
| hazatargz | 1 | `93040740783271` — Animation “FixedV2 1M donation Clone” (Smite3/Smite4) — **grant permission juga** |

**154 sisanya = third-party.**

### Full TSV export (173 rows)

File spreadsheet lengkap ada di Studio (edit mode place):

`ServerStorage._AssetAuditTSV` (ModuleScript — `Source` berisi TSV penuh tab-separated)

Cara ambil: buka script itu → copy isi di antara `[[` dan `]]` → paste ke `docs/audits/tools-worldeffects-assets.tsv`.

Kolom: `AssetId | Type | Name | CreatorType | CreatorName | CreatorId | OwnedByKit | Scopes | RefCount`

---

## 4. Tools + WorldEffects — third-party by creator (sorted by count)

| # | Creator | IDs | Mostly in |
|---|---------|-----|-----------|
| 32 | User:kirbyzaz (29775193) | textures/SFX/mesh FX | WorldEffects (all) |
| 14 | User:CodeWriter (39876101) | RenderMesh packs | Smite3/Smite4 |
| 7 | User:APMOfficial (7462718749) | Audio library | Smite / BlackHole |
| 4 | User:SirBloxy007 (363870464) | Mesh + Image | **All Tools** |
| 4 | User:gkku (358230) | particles | BlackHole |
| 4 | User:ProSoundEffects (7462895450) | Audio | WE + Tools foliage |
| 3 | Group:Zenith Aquatic (9992886888) | Anim + Audio | **All Tools** (Banana swing, hits) |
| 2 | Group:BloxenRBLX (7187032898) | Image | All Tools |
| 2 | User:Z0nito (3204456279) | Image | All Tools |
| 2 | User:cybraid (4880552990) | Mesh + texture | All Tools (shark plush) |
| 2 | Group:No²³ (5520226951) | Image | All Tools |
| 2 | User:Preston_Username (19717956) | Audio meteor | WE |
| 2 | User:SuperEvilAzmil (21280389) | portal audio | WE |
| 1 each | ~70 other creators | — | see TSV |

Full per-ID rows: [`tools-worldeffects-assets.tsv`](tools-worldeffects-assets.tsv).

### Top risk clusters (buyer “asset not authorized”)

1. **kirbyzaz (32)** — backbone visual FX semua WorldEffects  
2. **CodeWriter meshes (14)** — Smite mesh parts  
3. **Tools shared set (~36 third-party IDs)** — satu permission fail → **semua 15 rank tools** pecah bersamaan  
4. **Zenith Aquatic** — anim + hit SFX tools  
5. **APMOfficial / ProSoundEffects** — banyak SFX WE

---

## 5. Full third-party ID lists (Tools / WorldEffects)

### kirbyzaz (29775193) — 32

```
2701519583, 3048527478, 3048532143, 3048532869, 3678188033,
4936211373, 4949259834, 4998928231, 5505466476, 6191452797,
6569118042, 6569255608, 7229481183, 7231519809, 7245988767,
7245989092, 8120269816, 8120666025, 8698792742, 8698794520,
8698794956, 8699547016, 8973045221, 8982092797, 9009370950,
9467262263, 9482255913, 11308394828, 11308394937, 12156505819,
12360893247, 12360899465
```

### CodeWriter (39876101) — 14 meshes

```
1699715537, 1699715541, 1699715550, 1699715557, 1699715562,
1699715576, 1699715593, 1699715602, 1699715610, 1699715616,
1699715627, 1699715632, 1699715641, 1699715652
```

### APMOfficial (7462718749) — 7 audio

```
1836918964, 1837829140, 1837829231, 1837829481, 1843115984,
9043184557, 9045206449
```

### SirBloxy007 (363870464) — Tools

```
6974375971 (Mesh), 6974376014 (Image), 6974377084 (Mesh), 6974377128 (Image)
```

### Zenith Aquatic (9992886888) — Tools

```
95783950451867 (Animation SwordSlice), 99896413052089 (Audio), 115570253220496 (Audio hit)
```

### ProSoundEffects (7462895450)

```
9112775414, 9114219445, 9114515375 (also Tools), 9125544457
```

*(Sisa creator 1–2 ID: lihat TSV.)*

---

## 6. Recommended action plan

### A. Kit engine (priority — semua buyer Update Engine)

1. Grant **open use / experience permissions** untuk semua asset `hazatargz` + `NUWA`.  
2. Re-upload & replace: HD Admin caret/shadow, firework SFX, cinematic anim, Camera (LVL) jika perlu.  

### B. WorldEffects + Tools (hanya jika ikut di-ship ke buyer)

Opsi terbaik jangka panjang:

1. **Re-upload** FX kritis ke `hazatargz` / NUWA (mulai cluster kirbyzaz + Tools shared set).  
2. Atau **strip** Tools/WorldEffects dari pack buyer; biarkan buyer pasang sendiri / demo place only.  
3. Atau terima risiko: banyak place sudah “inherit” permission lewat ownership experience — **tidak stabil** untuk produk jual.

### C. Yang tidak perlu disentuh

- Roblox default assets  
- Musik migration library (di luar scope report ini)  
- Kohl’s Admin / place clutter di luar folder kit (tidak di-audit sebagai produk)

---

## 7. Related files

| File | Isi |
|------|-----|
| [`kit-engine-assets.tsv`](kit-engine-assets.tsv) | Kit Config/UI/Icon IDs + ownership |
| [`tools-worldeffects-assets.tsv`](tools-worldeffects-assets.tsv) | Semua 173 ID Tools+WE + ownership |

---

*Generated by Cursor agent audit · Studio GetProductInfo · 2026-08-08*
