#!/usr/bin/env python3
"""
Convert the legacy secret-dj ConfigService playlist dump (legacy_playlist.json)
into a ready-to-paste Lua SOURCE_DATA block for MigrateMusic.server.luau.

Legacy shape per song: { Id, Title, Author? }
Target shape per track: { name, creator, playlistName, parts = { "rbxassetid://..." } }

Cleaning rules:
- Skip songs with empty/blank Id or empty Title (these are placeholder slots).
- Normalize Author: ""/"-"/"=" -> "Unknown".
- Preserve playlist order and song order.
- Title is used as track name; Author as creator; single-part track (one asset id).
- Lua long-bracket strings are used to avoid escaping issues with quotes/CJK.
"""

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE / "legacy_playlist.json"
OUT = HERE / "SOURCE_DATA.generated.lua"

BAD_AUTHORS = {"", "-", "=", "PAWWHO".lower()}  # PAWWHO kept actually; see below


def clean_author(raw):
    if raw is None:
        return "Unknown"
    a = str(raw).strip()
    if a in ("", "-", "="):
        return "Unknown"
    return a


def lua_str(s: str) -> str:
    """Safely emit a Lua string literal. Use long-bracket if it contains
    quotes or backslashes; otherwise a normal double-quoted string."""
    if '"' in s or "\\" in s:
        # find a safe long-bracket level
        level = 0
        while ("]" + "=" * level + "]") in s:
            level += 1
        eq = "=" * level
        return f"[{eq}[{s}]{eq}]"
    return '"' + s + '"'


def main():
    if not SRC.exists():
        print(f"ERROR: {SRC} not found", file=sys.stderr)
        return 1

    data = json.loads(SRC.read_text(encoding="utf-8"))

    lines = []
    lines.append("local SOURCE_DATA = {")
    lines.append("\tplaylists = {")
    for pl in data:
        name = pl.get("Name", "Imported")
        lines.append(f"\t\t{{ name = {lua_str(name)} }},")
    lines.append("\t},")
    lines.append("\ttracks = {")

    total_in = 0
    total_out = 0
    skipped_empty = 0
    skipped_dupe = 0
    per_playlist = []

    for pl in data:
        pname = pl.get("Name", "Imported")
        songs = pl.get("Songs", []) or []
        seen_ids = set()
        kept = 0
        for song in songs:
            total_in += 1
            sid = str(song.get("Id", "")).strip()
            title = str(song.get("Title", "")).strip()
            if sid == "" or title == "":
                skipped_empty += 1
                continue
            if not sid.isdigit():
                skipped_empty += 1
                continue
            if sid in seen_ids:
                skipped_dupe += 1
                continue
            seen_ids.add(sid)
            creator = clean_author(song.get("Author"))
            lines.append("\t\t{")
            lines.append(f"\t\t\tname = {lua_str(title)},")
            lines.append(f"\t\t\tcreator = {lua_str(creator)},")
            lines.append(f"\t\t\tplaylistName = {lua_str(pname)},")
            lines.append(f'\t\t\tparts = {{ "rbxassetid://{sid}" }},')
            lines.append("\t\t},")
            kept += 1
            total_out += 1
        per_playlist.append((pname, len(songs), kept))

    lines.append("\t},")
    lines.append("}")
    lines.append("")

    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"Playlists       : {len(data)}")
    print(f"Songs in source : {total_in}")
    print(f"Tracks emitted  : {total_out}")
    print(f"Skipped (empty) : {skipped_empty}")
    print(f"Skipped (dupe)  : {skipped_dupe}")
    print(f"Output          : {OUT.name}")
    print("--- per playlist (name: source -> kept) ---")
    for pname, src_n, kept in per_playlist:
        flag = "" if src_n == kept else f"  ({src_n - kept} dropped)"
        print(f"  {pname}: {src_n} -> {kept}{flag}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
