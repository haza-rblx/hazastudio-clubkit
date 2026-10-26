#!/usr/bin/env bash
# Builds the three install pieces (and the Studio parity kit) into build/.
set -e
cd "$(dirname "$0")/.."
blink net/booth >/dev/null
for t in shared server client; do rojo build build/$t.project.json -o build/$t.rbxm >/dev/null; done
rojo build tools/parity/parity.project.json -o build/parity.rbxm >/dev/null
lune run tools/package >/dev/null
ls -la build/*.rbxm | awk '{print $5, $9}'
