#!/usr/bin/env python3
"""
Push aggregated Saweria totals into production D1 via existing admin /seed API.
No wrangler required — only ADMIN_TOKEN (Cloudflare secret for hazastudio-donation-api).

Usage (PowerShell):
  $env:ADMIN_TOKEN="<from Cloudflare Workers secrets>"
  python scripts/push-nuwa-leaderboard-seed.py nuwa "C:\path\to\transaction-report.xlsx"

After success, verify:
  https://hazastudio-donation-api.hazastudio.workers.dev/game/nuwa?secret=...&action=leaderboard&type=alltime&limit=5
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

try:
    import openpyxl
except ImportError:
    print("pip install openpyxl", file=sys.stderr)
    sys.exit(1)

API_BASE = os.environ.get("API_BASE", "https://hazastudio-donation-api.hazastudio.workers.dev").rstrip("/")
WIB = timezone(timedelta(hours=7))
HEADERS = ("Transaction ID", "Transaction Type", "Debit/Credit", "Sender Username", "Amount", "Fee", "Net Amount", "Transaction Date")


def parse_amount(raw) -> int:
    if raw is None:
        return 0
    if isinstance(raw, (int, float)):
        return int(raw)
    digits = "".join(ch for ch in str(raw) if ch.isdigit())
    return int(digits) if digits else 0


def post_seed(game_key: str, saweria_name: str, total_amount: int, admin_token: str) -> None:
    payload = json.dumps(
        {
            "saweria_name": saweria_name,
            "total_amount": total_amount,
            "note": "xlsx_transaction_report_aggregate",
        }
    ).encode("utf-8")
    req = urllib.request.Request(
        f"{API_BASE}/admin/games/{game_key}/seed",
        data=payload,
        method="POST",
        headers={
            "content-type": "application/json",
            "authorization": f"Bearer {admin_token}",
        },
    )
    with urllib.request.urlopen(req, timeout=60) as res:
        body = json.loads(res.read().decode("utf-8"))
        if not body.get("ok"):
            raise RuntimeError(body.get("error") or "seed_failed")


def main() -> None:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    admin_token = os.environ.get("ADMIN_TOKEN", "").strip()
    if not admin_token:
        print("error: set ADMIN_TOKEN (Cloudflare Worker secret)", file=sys.stderr)
        sys.exit(1)

    game_key = sys.argv[1].strip().lower()
    xlsx_path = Path(sys.argv[2])
    if not xlsx_path.is_file():
        print(f"error: file not found: {xlsx_path}", file=sys.stderr)
        sys.exit(1)

    wb = openpyxl.load_workbook(xlsx_path, read_only=True, data_only=True)
    ws = wb.active
    rows = ws.iter_rows(values_only=True)
    header = tuple(str(h).strip() if h is not None else "" for h in next(rows, ()))
    if header[: len(HEADERS)] != HEADERS:
        print("error: unexpected xlsx header", file=sys.stderr)
        sys.exit(1)

    totals: dict[str, int] = defaultdict(int)
    display_name: dict[str, str] = {}
    tx_count = 0

    for row in rows:
        if not row or row[0] is None:
            continue
        tx_type = str(row[1] or "").strip().lower()
        debit_credit = str(row[2] or "").strip()
        if tx_type != "transaction" or debit_credit != "Debit":
            continue
        sender = str(row[3] or "").strip() or "Saweria Donor"
        amount = parse_amount(row[4])
        if amount <= 0:
            continue
        key = sender.lower()
        totals[key] += amount
        display_name[key] = sender
        tx_count += 1

    wb.close()
    donors = len(totals)
    print(f"aggregate: {tx_count} donations -> {donors} unique donors for game={game_key}")

    ok = 0
    for key, total in sorted(totals.items(), key=lambda item: item[1], reverse=True):
        name = display_name[key]
        try:
            post_seed(game_key, name, total, admin_token)
            ok += 1
            if ok <= 5 or ok == donors:
                print(f"  seeded {ok}/{donors}: {name} = {total}")
            elif ok == 6:
                print("  ...")
        except urllib.error.HTTPError as err:
            detail = err.read().decode("utf-8", errors="replace")
            print(f"  FAIL {name}: HTTP {err.code} {detail}", file=sys.stderr)
        except Exception as err:
            print(f"  FAIL {name}: {err}", file=sys.stderr)

    print(f"DONE seeded={ok}/{donors} — open leaderboard in browser to verify")


if __name__ == "__main__":
    main()
