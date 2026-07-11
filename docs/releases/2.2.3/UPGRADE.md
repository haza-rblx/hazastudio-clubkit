# Upgrade v2.2.2 → v2.2.3

**Tanggal:** 2026-07-11

## Langkah cepat

1. Studio → Club Kit Packager → **Check Update** → **Update Engine**
2. Save place

## What's new

- **Gravity / Ungravity** dibalik sesuai makna: `/ungravity` + Shift+U = melayang; `/gravity` + Shift+G = turun
- Restore dari float lebih cepat (kick ke bawah + Freefall, tidak ngambang dulu)

## Breaking

Tidak. Hanya perilaku keybind/command yang berubah dari v2.2.0.

## QA

- [ ] Shift+U / `/ungravity` → float
- [ ] Shift+G / `/gravity` → turun cepat (tidak hang di udara)
- [ ] `/ungravity 5` set speed float
