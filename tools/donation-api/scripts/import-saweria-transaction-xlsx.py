#!/usr/bin/env python3
"""
Convert Saweria wallet "Transaction Report" .xlsx export into idempotent D1 upsert SQL.

Keeps rows where Transaction Type == transaction and Debit/Credit == Debit (incoming donations).
Skips withdraw / Credit rows.

Usage:
  python scripts/import-saweria-transaction-xlsx.py <game_key> <xlsx_path> [out_sql_path]
  python scripts/import-saweria-transaction-xlsx.py <game_key> <xlsx_path> --json-out donations.json

Requires: pip install openpyxl
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timedelta, timezone

WIB = timezone(timedelta(hours=7))
from pathlib import Path

try:
    import openpyxl
except ImportError:
    print("error: pip install openpyxl", file=sys.stderr)
    sys.exit(1)

EXPECTED_HEADERS = (
    "Transaction ID",
    "Transaction Type",
    "Debit/Credit",
    "Sender Username",
    "Amount",
    "Fee",
    "Net Amount",
    "Transaction Date",
)


def sql_string(value: str) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def to_iso_utc(dt: datetime) -> str:
    # Saweria transaction report dates are local (WIB) without offset.
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=WIB)
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def parse_amount(raw) -> int:
    if raw is None:
        return 0
    if isinstance(raw, (int, float)):
        return int(raw)
    digits = "".join(ch for ch in str(raw) if ch.isdigit())
    return int(digits) if digits else 0


def main() -> None:
    if len(sys.argv) < 3:
        print(
            "usage: python scripts/import-saweria-transaction-xlsx.py <game_key> <xlsx_path> [out_sql_path]",
            file=sys.stderr,
        )
        sys.exit(1)

    game_key = sys.argv[1].strip().lower()
    xlsx_path = Path(sys.argv[2])
    json_out: Path | None = None
    sql_out: Path | None = None
    extra = sys.argv[3:]
    index = 0
    while index < len(extra):
        arg = extra[index]
        if arg == "--json-out" and index + 1 < len(extra):
            json_out = Path(extra[index + 1])
            index += 2
            continue
        if not arg.startswith("--"):
            sql_out = Path(arg)
        index += 1

    out_path = sql_out or xlsx_path.with_suffix(".import.sql")

    if not xlsx_path.is_file():
        print(f"error: file not found: {xlsx_path}", file=sys.stderr)
        sys.exit(1)

    wb = openpyxl.load_workbook(xlsx_path, read_only=True, data_only=True)
    ws = wb.active
    rows_iter = ws.iter_rows(values_only=True)
    header_row = next(rows_iter, None)
    if not header_row:
        print("error: empty workbook", file=sys.stderr)
        sys.exit(1)

    header = tuple(str(h).strip() if h is not None else "" for h in header_row)
    if header[: len(EXPECTED_HEADERS)] != EXPECTED_HEADERS:
        print("error: unexpected header row", file=sys.stderr)
        print("expected:", EXPECTED_HEADERS, file=sys.stderr)
        print("got:", header, file=sys.stderr)
        sys.exit(1)

    game_subquery = f"(SELECT id FROM games WHERE game_key={sql_string(game_key)})"
    lines = [
        "PRAGMA foreign_keys=ON;",
        "-- Abort if game row missing (otherwise INSERTs get NULL game_id and leaderboard stays empty).",
        f"SELECT CASE WHEN (SELECT COUNT(*) FROM games WHERE game_key={sql_string(game_key)}) = 0 "
        f"THEN RAISE(ABORT, 'game_key not found: {game_key}') END;",
    ]
    kept = 0
    skipped = 0
    donation_rows: list[dict] = []

    for row in rows_iter:
        if not row or row[0] is None:
            skipped += 1
            continue

        tx_id = str(row[0]).strip()
        tx_type = str(row[1] or "").strip().lower()
        debit_credit = str(row[2] or "").strip()
        sender = str(row[3] or "").strip() or "Saweria Donor"
        amount = parse_amount(row[4])
        fee = parse_amount(row[5])
        tx_date = row[7]

        if tx_type != "transaction" or debit_credit != "Debit" or amount <= 0 or not tx_id:
            skipped += 1
            continue

        if not isinstance(tx_date, datetime):
            print(f"error: bad Transaction Date for {tx_id}: {tx_date!r}", file=sys.stderr)
            sys.exit(1)

        donation_at = to_iso_utc(tx_date)
        saweria_lc = sender.lower()

        raw_payload = {
            "id": tx_id,
            "transaction_type": tx_type,
            "debit_credit": debit_credit,
            "donator_name": sender,
            "amount_raw": amount,
            "fee": fee,
            "net_amount": parse_amount(row[6]),
            "transaction_date": donation_at,
            "source": "xlsx_transaction_report_import",
        }

        values = ", ".join(
            [
                game_subquery,
                sql_string(tx_id),
                sql_string(sender),
                sql_string(saweria_lc),
                str(amount),
                sql_string(""),
                sql_string("success"),
                sql_string(donation_at),
                sql_string(donation_at),
                sql_string(json.dumps(raw_payload, separators=(",", ":"))),
                "0",
                sql_string(""),
            ]
        )

        lines.append(
            "INSERT INTO donations (game_id, provider_tx_id, saweria_name, saweria_name_lc, "
            "amount, message, status, donation_at, received_at, raw_payload, is_voided, voided_reason) "
            f"VALUES ({values}) "
            "ON CONFLICT(game_id, provider_tx_id) DO UPDATE SET "
            "saweria_name=excluded.saweria_name, saweria_name_lc=excluded.saweria_name_lc, "
            "amount=excluded.amount, message=excluded.message, status=excluded.status, "
            "donation_at=excluded.donation_at, raw_payload=excluded.raw_payload;"
        )
        donation_rows.append(
            {
                "provider_tx_id": tx_id,
                "saweria_name": sender,
                "amount": amount,
                "message": "",
                "status": "success",
                "donation_at": donation_at,
                "raw_payload": raw_payload,
            }
        )
        kept += 1

    wb.close()
    if "--json-out" in sys.argv and json_out is None:
        print("error: --json-out requires a file path", file=sys.stderr)
        sys.exit(1)
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    if json_out:
        json_out.write_text(
            json.dumps({"game_key": game_key, "donations": donation_rows}, indent=2),
            encoding="utf-8",
        )
    print(
        f"IMPORT_READY game={game_key} kept={kept} skipped={skipped} sql={out_path}"
        + (f" json={json_out}" if json_out else "")
    )


if __name__ == "__main__":
    main()
