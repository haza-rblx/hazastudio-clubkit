# QA Checklist — Club Kit v1.3 (post handover + review pass)

**Tanggal:** 2026-07-07  
**Lingkungan:** Roblox Studio (dev) → staging → production  
**Tester:** _______________  
**Build / place file:** _______________  
**Catatan:** Centang `[x]` setelah lulus. Tulis `FAIL` + screenshot/log kalau gagal.

---

## 0. Pre-flight (wajib sebelum gameplay test)

| # | Test | Pass | Catatan |
|---|------|------|---------|
| 0.1 | Rojo sync / insert place berhasil tanpa error di Output | [ ] | |
| 0.2 | `Secrets.luau` sudah diisi deployer (kalau test donation/API) | [ ] | Kosongkan = fitur API off |
| 0.3 | `Config.HttpApi.ENABLED = false` (default aman) | [ ] | |
| 0.4 | `Config.HttpApi.COUNTERS_ENABLED = false` | [ ] | |
| 0.5 | `./tools/validate-handover.sh` → 0 fail (Git Bash/WSL + aftman) | [ ] | Warn stylua/selene boleh jika pre-existing |
| 0.6 | Server Output: `"Server initialized..."` tanpa error merah | [ ] | |
| 0.7 | Client Output: boot selesai, tidak ada error merah berulang | [ ] | |

---

## 1. Critical — Data loss & shutdown (C1–C2, H3)

### C1 — Settings load gate

| # | Langkah | Expected | Pass | Catatan |
|---|---------|----------|------|---------|
| 1.1 | Player join dengan koneksi normal | Settings UI menampilkan data tersimpan (bukan default kosong) | [ ] | |
| 1.2 | Ubah 1 setting → tunggu 5s → rejoin | Perubahan persist | [ ] | |
| 1.3 | **Stress:** spam toggle setting cepat 10x → rejoin | Tidak revert ke default; tidak corrupt | [ ] | |
| 1.4 | Simulasi load gagal (matikan DataStore API sementara / budget exhausted) → join | Client boleh tampil default; **save/reset ditolak** (tidak overwrite datastore) | [ ] | Cek server log: `settings_not_loaded` |

### C2 — MusicRepository merge

| # | Langkah | Expected | Pass | Catatan |
|---|---------|----------|------|---------|
| 1.5 | Edit playlist/track di 1 server → tunggu sync | Perubahan tersimpan | [ ] | |
| 1.6 | (Multi-server / 2 Studio test place) edit playlist berbeda hampir bersamaan | Tidak ada playlist/track hilang; revision tertinggi menang | [ ] | Opsional jika punya 2 server |

### H3 — Autosave + BindToClose

| # | Langkah | Expected | Pass | Catatan |
|---|---------|----------|------|---------|
| 1.7 | Mainkan 2+ menit (XP/settings/favorites berubah) → stop server graceful | Data tersimpan | [ ] | |
| 1.8 | Cek server log saat shutdown: `BindToClose complete` atau tidak ada warn timeout | [ ] | |
| 1.9 | Player leave → rejoin dalam 30s | XP, settings, favorites masih ada | [ ] | |

---

## 2. Critical — Memory & lifecycle (C3–C5, H5–H8)

### Studio hot-reload (dev-only, tapi wajib untuk hygiene fix)

| # | Langkah | Expected | Pass | Catatan |
|---|---------|----------|------|---------|
| 2.1 | Hot-reload `Main.server` 3x (Rojo) | Tidak ada duplicate join handler (settings sync 1x per join, bukan 3x) | [ ] | |
| 2.2 | Hot-reload `Main.client` 3x | Tidak ada duplicate notif/donation/overhead event | [ ] | |
| 2.3 | Setelah reload: 1 donation notif | Muncul **sekali**, bukan double/triple | [ ] | |
| 2.4 | Monitor Server memory 10 menit + 5 player join/leave (simulasi churn) | Tidak naik terus tanpa batas (trend flat setelah churn) | [ ] | Opsional |

### Player leave cleanup

| # | Langkah | Expected | Pass | Catatan |
|---|---------|----------|------|---------|
| 2.5 | Player join → lihat overhead rank/cash → leave | Tidak error server | [ ] | |
| 2.6 | Couple: kirim request → sender leave sebelum accept | Request hilang dari target UI | [ ] | |
| 2.7 | Music playing → player leave | Tidak error; session bersih | [ ] | |

---

## 3. High — Abuse & edge cases (H9–H13)

| # | Area | Langkah | Expected | Pass | Catatan |
|---|------|---------|----------|------|---------|
| 3.1 | EffectDonate | Trigger efek donate (BlackHole/Blossom/GreenHammer/Nuke) | Efek jalan; tidak freeze client | [ ] | |
| 3.2 | EffectDonate | Biarkan efek meteor berjalan >90s (kalau ada loop) | Loop berhenti (deadline 90s) | [ ] | |
| 3.3 | Donation leaderboard | Burst donasi cepat (3+ dalam 5s) | Leaderboard update ter-debounce (~3s), tidak spam network | [ ] | |
| 3.4 | MusicService | Coba inject non-audio asset ID ke queue | Ditolak (`asset_not_audio`) | [ ] | |
| 3.5 | SignServer | Kirim string >64 char / non-string | Ditolak + rate limited | [ ] | |
| 3.6 | RopeServer | Pakai rope tanpa character valid / spam | Rate limited; tidak exploit | [ ] | |
| 3.7 | GiftPending | Beli gift → ProcessReceipt (atau simulasi retry) | Gift hanya delivered **sekali**, tidak double | [ ] | |
| 3.8 | PaidBroadcast | Beli broadcast → transient fail → retry Roblox | Broadcast tetap terkirim (pending tidak hilang) | [ ] | |
| 3.9 | RoleToolService | Spam request sync tools | Debounce 2s; tidak flicker backpack | [ ] | |
| 3.10 | GlowStick | Dual-color spam | Cooldown sama seperti single color | [ ] | |

---

## 4. Client connection tracking (§5.1 — review pass 2026-07-07)

| # | Modul | Langkah | Expected | Pass |
|---|-------|---------|----------|------|
| 4.1 | Overhead | Join → overhead muncul → hot-reload client → join lagi | Overhead tetap update normal | [ ] |
| 4.2 | Settings (client) | Buka settings → sync dari server → reload client | Panel hydrate benar | [ ] |
| 4.3 | Couple | Buka couple panel → terima announce | Panel + announce jalan setelah reload | [ ] |
| 4.4 | Donation notif | 1 donasi masuk | Notif muncul 1x; queue jalan | [ ] |
| 4.5 | Donation leaderboard | Leaderboard workspace animate | Update via remote + revision attribute | [ ] |
| 4.6 | Shop/Gift | Beli tier / terima grant notif | Grant callback fire sekali | [ ] |
| 4.7 | Admin giftcard | Kirim giftcard (jika punya permission) | Result remote routed benar | [ ] |
| 4.8 | Avatar context | Klik player → like effect | Like effect + panel jalan | [ ] |
| 4.9 | Cinematic dock | Role yang boleh → buka dock | Broadcast + target list jalan | [ ] |
| 4.10 | EffectDonate scripts | Trigger efek → reload client script parent | Tidak orphan connection (efek masih bisa trigger) | [ ] |

---

## 5. Feature smoke (regression cepat)

Centang modul yang relevan dengan feature flags ON di place kamu.

| # | Feature | Langkah singkat | Pass | Catatan |
|---|---------|-----------------|------|---------|
| 5.1 | Settings | Toggle graphics + overhead visibility → save | [ ] | |
| 5.2 | Music player | Play / pause / skip / queue | [ ] | |
| 5.3 | Sync dance | Sync dengan partner | [ ] | Flag: `SyncDanceEnabled` |
| 5.4 | Couple | Request → accept → breakup | [ ] | Flag: `CouplesEnabled` |
| 5.5 | Shop / Gift | Prompt purchase (Studio test product) | [ ] | |
| 5.6 | Donation (cash/Robux) | Panel buka → donasi test | [ ] | |
| 5.6a | `/testrobux 10` (showcase ON) | Aura muncul; **tanpa** Nuke/Smite/BlackHole; board tidak berubah | [ ] | preview only |
| 5.6b | `/testcash 500` (showcase ON) | Aura showcase tier rendah; board tidak berubah | [ ] | preview only |
| 5.6c | `/testcash 2000` (showcase ON) | Aura + world Nuke; board tidak berubah | [ ] | preview only |
| 5.6d | `/testcash 150000` (showcase OFF) | Aura production + world Nuke (100k+); board tidak berubah | [ ] | preview only |
| 5.6e | `/testsaweria 1000` | Masih jalan (alias `/testcash`); board tidak berubah | [ ] | preview only |
| 5.6f | `/testcash 5000` lalu cek leaderboard | Notif/VFX jalan; **board tidak berubah** (no persist) | [ ] | |
| 5.6g | `/addcash <self> 5000` | Board + overhead **berubah** (persist) | [ ] | |
| 5.6h | `DonationCash = false` | Tab IDR panel donasi tersembunyi | [ ] | |
| 5.7 | Stickers | Place + clear sticker | [ ] | |
| 5.8 | Carry | Carry player | [ ] | |
| 5.9 | Admin panel | Buka + 1 aksi aman (list player) | [ ] | |
| 5.10 | Command library | Execute 1 command | [ ] | |
| 5.11 | Streak | Login streak notif (hari baru simulasi) | [ ] | |
| 5.12 | Chat tags | Chat di RBXGeneral | [ ] | Tag format benar |
| 5.13 | Leaderboard | Workspace board tampil top entries | [ ] | |

---

## 6. HttpApi wrapper (hanya setelah staging baseline)

**Jangan enable di production sebelum section ini lulus di staging.**

| # | Langkah | Expected | Pass | Catatan |
|---|---------|----------|------|---------|
| 6.1 | Baseline 1–2 hari dengan `ENABLED=false`, `COUNTERS_ENABLED=false` | Tidak ada regresi gameplay | [ ] | |
| 6.2 | Command Bar: `HttpApiTelemetry.Enable()` | Counter snapshot di server log | [ ] | |
| 6.3 | Workload 30 CCU simulasi (atau max yang bisa) 1–2 hari | Counter masuk akal; tidak ada error baru | [ ] | |
| 6.4 | Command Bar: `HttpApi.Enable()` (parallel-run) | Overhead rank/name resolve normal | [ ] | |
| 6.5 | Bandingkan cache hit rate vs baseline | Sama atau lebih baik | [ ] | |
| 6.6 | Rollback test: `ENABLED=false` lagi | Kembali ke direct API tanpa regresi | [ ] | |

---

## 7. Sign-off

| Kriteria | Status |
|----------|--------|
| Semua **§0 Pre-flight** lulus | [ ] |
| Semua **§1 Critical** lulus | [ ] |
| **§2 Hot-reload** lulus (minimal 2.1–2.3) | [ ] |
| **§3 High** lulus (minimal 3.1, 3.3, 3.7, 3.8) | [ ] |
| **§4 Connection tracking** lulus (minimal 4.1, 4.2, 4.4) | [ ] |
| **§5 Smoke** lulus untuk feature yang ON | [ ] |
| **§6 HttpApi** (jika promote wrapper) | [ ] N/A |

**Keputusan:**

- [ ] **READY for staging publish**
- [ ] **READY for production** (setelah §6 kalau pakai HttpApi wrapper)
- [ ] **BLOCKED** — isi issue di bawah

**Issues found:**

```
1.
2.
3.
```

---

## Quick reference — log strings to watch

| String | Arti |
|--------|------|
| `settings_not_loaded` | Load gate bekerja; save ditolak (expected saat load gagal) |
| `BindToClose complete` | Shutdown flush sukses |
| `BindToClose: timeout` | **FAIL** — data mungkin hilang |
| `Gift pending` + double delivery | **FAIL** — cek GiftPendingRepository |
| `Paid broadcast receipt without valid pending` | Investigate PaidBroadcast flow |
| Duplicate settings sync on join | **FAIL** — connection leak / hot-reload |

---

*Generated for handover state as of 2026-07-07. See `HANDOVER.md` for fix details.*
