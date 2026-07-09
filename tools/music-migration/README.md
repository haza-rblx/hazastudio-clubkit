# Music Migration Tool

Tool buat import lagu dari sistem musik lain ke THE BASIC CLUB KIT.

## Files

| File | Fungsi |
|---|---|
| `MigrateMusic.server.luau` | Self-contained migration script. Ini yang kamu run. |
| `example-source.luau` | Referensi format data sumber. Cuma contoh, bukan dipakai. |
| `README.md` | File ini. |

## Quick Start

### 1. Siapkan data sumber

Buka `example-source.luau`, lihat struktur tabel-nya. Format minimum:

```lua
{
    tracks = {
        {
            name = "Track Name",
            creator = "Artist",
            playlistName = "My Playlist", -- opsional
            parts = { "rbxassetid://1234567890" },
            normalPlaybackSpeed = 0.85,   -- opsional
        },
        -- ... lebih banyak track
    },
}
```

### 2. Edit `MigrateMusic.server.luau`

Cari blok `local SOURCE_DATA = { ... }` (sekitar line 65), paste data sumber kamu di situ.

### 3. Run dry-run dulu (default)

Default `MODE = "dry_run"` — gak nyentuh DataStore, cuma preview di Output.

**Pilih salah satu cara run:**

**Cara A — Drop ke ServerScriptService (recommended):**
1. Drag file `MigrateMusic.server.luau` ke `ServerScriptService` di Studio
2. Klik **Play** (F5) — script auto-run
3. Liat Output window
4. **HAPUS script-nya** setelah selesai

**Cara B — Command Bar:**
1. Open Studio, buka file di Roblox Studio
2. Test mode (Run, bukan Edit) — supaya DataStore enabled
3. Copy seluruh isi file → paste di Command Bar → Enter
4. Liat Output

### 4. Verify output

Output bakal kayak gini:

```
[MusicMigration] === START === mode=dry_run strategy=merge
[MusicMigration] Loaded existing: 3 playlists, 12 tracks
[MusicMigration] Playlist baru: Late Night Vibes (id=...)
[MusicMigration] Track baru: 'Make You Mine' by 'PUBLIC' (2 parts speed=0.85)
[MusicMigration] Track 'Untitled Drop' by 'Anonymous' udah ada, skip.
[MusicMigration] === SUMMARY ===
[MusicMigration] Playlists added : 2
[MusicMigration] Playlists skipped: 1
[MusicMigration] Tracks added    : 5
[MusicMigration] Tracks skipped  : 1
[MusicMigration] Errors          : 0
[MusicMigration] DRY RUN — no DataStore writes performed. Set MODE='commit' untuk apply.
```

### 5. Commit

Kalau hasil dry-run sudah sesuai:

```lua
local MODE: string = "commit"  -- ganti dari "dry_run"
```

Run lagi. Kali ini bakal beneran nulis ke DataStore.

### 6. Bersihin

**HAPUS script `MigrateMusic.server.luau` dari ServerScriptService** setelah migrasi.
Kalau gak dihapus, script bakal jalan terus tiap server start (re-create track yang sama).

## Configuration

Yang bisa di-tweak di top of `MigrateMusic.server.luau`:

| Const | Default | Note |
|---|---|---|
| `MODE` | `"dry_run"` | `"dry_run"` (preview) atau `"commit"` (write) |
| `STRATEGY` | `"merge"` | `"merge"` (preserve existing) atau `"replace"` (wipe all) |
| `DATASTORE_NAME` | `"MusicLibrary_v1"` | Match `Config.Music.DATASTORE_NAME` |
| `MAX_TRACK_PARTS` | `9` | Match `Config.Music.MAX_TRACK_PARTS` |
| `DEFAULT_PLAYLIST_NAME` | `"Imported"` | Fallback playlist buat track tanpa playlist info |
| `MIGRATION_TAG` | `"migration-tool-v1"` | Disimpan di `syncSource`, dipakai buat dedupe |

## Field Mapping

Mapper accept variasi nama field dari sistem lain:

| Target field | Source field (any of) |
|---|---|
| `name` | `name` |
| `creator` | `creator`, `artist`, `author` |
| `playlistId` | `playlistId` |
| `playlistName` | `playlistName` (lookup by name, case-insensitive) |
| `parts` | `parts`, `assetIds`, `audioIds`, `audios`, atau flat `assetId1..N` / `part1..N` / `audioId1..N` |
| `playbackSpeed` | `playbackSpeed`, `normalPlaybackSpeed`, `speed` (number atau "2.3x") |

Asset ID prefix flexible: `"rbxassetid://123"`, `"rbx://123"`, `"123"`, `123` semua di-normalize jadi `"rbxassetid://123"`.

## Strategies

### `merge` (default, recommended)

- Preserve playlist & track existing
- Skip duplicate by `(name, creator)` pair (case-insensitive)
- Auto-create playlist baru kalau referensi nama yang belum ada
- Idempotent: re-run dgn data sama gak duplicate

### `replace` (DESTRUCTIVE)

- WIPE semua playlist & track existing
- Tulis cuma data dari `SOURCE_DATA`
- Ada countdown 5 detik sebelum write (cancel via Stop kalau salah pilih)
- Use case: fresh install, reset library

## Troubleshooting

**"DataStore butuh server context"**
→ Lagi di Edit Mode. Klik Play (F5) dulu, baru run.

**"GetDataStore failed"**
→ Studio belum enable API services. Game Settings → Security → Allow HTTP & API Services ON. Atau publish ke experience yang udah enable.

**Track muncul tapi gak bisa di-play**
→ Asset ID-nya invalid atau gak shared ke universe ini. Pakai `tools/AssetPermissionGranterPlugin.luau` buat grant permission.

**Mau rollback**
→ DataStore Roblox punya versioning. Pakai `DataStoreService:GetDataStore():ListVersionsAsync()` atau Studio's DataStore Editor plugin buat restore previous version.

## Compatibility

- ✅ `Config.Music.MAX_TRACK_PARTS = 9` (default kit v1.1+)
- ✅ Per-track `playbackSpeed` (kit v1.1+)
- ⚠️ Kit lama dgn `MAX_TRACK_PARTS = 5`: tool akan truncate parts > 5 jika kamu set `MAX_TRACK_PARTS = 5` di top of script
