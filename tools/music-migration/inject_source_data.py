#!/usr/bin/env python3
"""Inject the generated SOURCE_DATA into MigrateMusic.server.luau, replacing
the empty placeholder block. Idempotent: matches from the SOURCE_DATA decl up
to the first standalone '}' that closes it."""
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
GEN = HERE / "SOURCE_DATA.generated.lua"
TARGET = HERE / "MigrateMusic.server.luau"

gen = GEN.read_text(encoding="utf-8").strip("\n")
# Re-annotate the type on the first line to match the original declaration.
gen = gen.replace(
    "local SOURCE_DATA = {",
    "local SOURCE_DATA: { [string]: any } = {",
    1,
)

src = TARGET.read_text(encoding="utf-8")

# Match the placeholder block:
# local SOURCE_DATA: { [string]: any } = {
# 	playlists = {},
# 	tracks = {},
# }
pattern = re.compile(
    r"local SOURCE_DATA: \{ \[string\]: any \} = \{\s*\n"
    r"\tplaylists = \{\},\s*\n"
    r"\ttracks = \{\},\s*\n"
    r"\}",
    re.MULTILINE,
)

if not pattern.search(src):
    print("ERROR: placeholder SOURCE_DATA block not found (already injected?).", file=sys.stderr)
    sys.exit(1)

new_src = pattern.sub(lambda _: gen, src, count=1)
TARGET.write_text(new_src, encoding="utf-8")
print(f"Injected {gen.count('parts = {')} tracks into {TARGET.name}")
