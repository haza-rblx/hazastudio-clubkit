#!/usr/bin/env python3
"""
Generate Rojo .model.json Animation files from the legacy NUWA dance/emote lists.

Source (legacy):
  src/ReplicatedStorage/Mods/dance/DanceServerService/Animations/Dances/FreeDances.luau
  src/ReplicatedStorage/Mods/dance/DanceServerService/Animations/Emotes/FreeEmotes.luau

Output (new system / Rojo, Opsi A):
  UPDATED_VERSION/ReplicatedStorage/Emotes/<Name>.model.json          (dances)
  UPDATED_VERSION/ReplicatedStorage/Emotes/Pose/<Name>.model.json     (emotes/poses)

Rules:
- Only ACTIVE entries are migrated. Lines that are Lua-commented (start with --)
  are skipped, matching legacy runtime behavior.
- Each entry is a { "Name"; "Id" } pair. We pair a quoted name line with the
  next quoted numeric-id line.
- Duplicate names get a numeric suffix ("Name (2)") so no file is overwritten.
- Filenames are sanitized for the filesystem; the Animation's true display name
  is preserved via the model file's top-level name (the file stem). Because the
  new AnimationLoader maps by instance .Name, the stem IS the dance name.
"""

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]  # .../LEGACY_VERSION
LEGACY = REPO / "src/ReplicatedStorage/Mods/dance/DanceServerService/Animations"
DANCES_SRC = LEGACY / "Dances/FreeDances.luau"
EMOTES_SRC = LEGACY / "Emotes/FreeEmotes.luau"

OUT_DANCES = REPO / "UPDATED_VERSION/ReplicatedStorage/Emotes"
OUT_POSE = REPO / "UPDATED_VERSION/ReplicatedStorage/Emotes/Pose"

# A "string literal" line: optional leading whitespace, a quote, content, quote,
# optional trailing ; or , and optional trailing inline comment (-- ...).
# Some legacy names carry an inline tag comment, e.g. `"Arms Wave"; -- SV`.
# We must still reject FULL-comment lines (leading --), handled by is_commented.
STRING_LINE = re.compile(r'^\s*"([^"]*)"\s*[;,]?\s*(?:--.*)?$')
ID_LINE = re.compile(r'^\s*"(\d{6,})"\s*[;,]?\s*(?:--.*)?$')
# Illegal filename chars on Windows: \ / : * ? " < > |
ILLEGAL = re.compile(r'[\\/:*?"<>|]')


def is_commented(line: str) -> bool:
    return line.lstrip().startswith("--")


def parse_pairs(path: Path):
    """Return list of (name, anim_id) for active entries only."""
    pairs = []
    pending_name = None
    for raw in path.read_text(encoding="utf-8").splitlines():
        if is_commented(raw):
            # Reset any half-built pair so a commented name can't pair with a
            # later active id (and vice versa).
            pending_name = None
            continue
        m_id = ID_LINE.match(raw)
        if m_id and pending_name is not None:
            pairs.append((pending_name, m_id.group(1)))
            pending_name = None
            continue
        m_str = STRING_LINE.match(raw)
        if m_str:
            # A new name starts a fresh pair. If an id didn't follow the prior
            # name, that prior name is dropped (malformed); keep the newest.
            pending_name = m_str.group(1)
    return pairs


def sanitize(name: str) -> str:
    cleaned = ILLEGAL.sub("", name).strip()
    # Avoid trailing dots/spaces which Windows dislikes.
    cleaned = cleaned.rstrip(". ")
    return cleaned or "Unnamed"


def write_models(pairs, out_dir: Path, kind: str):
    out_dir.mkdir(parents=True, exist_ok=True)
    used = {}
    written = 0
    skipped_dupe_id = 0
    seen_ids = set()
    report = []
    for name, anim_id in pairs:
        if anim_id in seen_ids:
            skipped_dupe_id += 1
            report.append(f"  [dupe-id skip] {name} -> {anim_id}")
            continue
        seen_ids.add(anim_id)

        base = sanitize(name)
        key = base.lower()
        if key in used:
            used[key] += 1
            stem = f"{base} ({used[key]})"
        else:
            used[key] = 1
            stem = base

        model = {
            "className": "Animation",
            "properties": {"AnimationId": f"rbxassetid://{anim_id}"},
        }
        (out_dir / f"{stem}.model.json").write_text(
            json.dumps(model, indent=2) + "\n", encoding="utf-8"
        )
        written += 1
    return written, skipped_dupe_id, report


def main():
    if not DANCES_SRC.exists() or not EMOTES_SRC.exists():
        print(f"ERROR: legacy sources not found under {LEGACY}", file=sys.stderr)
        return 1

    dances = parse_pairs(DANCES_SRC)
    emotes = parse_pairs(EMOTES_SRC)

    dw, dd, drep = write_models(dances, OUT_DANCES, "dance")
    ew, ed, erep = write_models(emotes, OUT_POSE, "pose")

    print(f"Dances : parsed {len(dances)} active, wrote {dw}, skipped {dd} dup-id")
    print(f"Emotes : parsed {len(emotes)} active, wrote {ew}, skipped {ed} dup-id")
    print(f"Total  : {dw + ew} Animation model files generated")
    for line in drep + erep:
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
