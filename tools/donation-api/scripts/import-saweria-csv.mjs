// Convert a Saweria CSV export into idempotent D1 upsert SQL for one game.
//
// Usage:
//   node scripts/import-saweria-csv.mjs <game_key> <csv_path> [out_sql_path]
//
// The generated SQL matches the webhook upsert shape: donations are deduped
// by (game_id, provider_tx_id). Re-running is safe.

import { readFileSync, writeFileSync } from "node:fs";

const gameKey = process.argv[2];
const csvPath = process.argv[3];
const outPath = process.argv[4] || csvPath.replace(/\.csv$/i, "") + ".import.sql";

if (!gameKey || !csvPath) {
  console.error("usage: node scripts/import-saweria-csv.mjs <game_key> <csv_path> [out_sql_path]");
  process.exit(1);
}

// Minimal CSV parser that handles quoted fields, commas, and escaped quotes.
function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = "";
  let inQuotes = false;
  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];
    if (inQuotes) {
      if (ch === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i += 1;
        } else {
          inQuotes = false;
        }
      } else {
        field += ch;
      }
      continue;
    }
    if (ch === '"') {
      inQuotes = true;
    } else if (ch === ",") {
      row.push(field);
      field = "";
    } else if (ch === "\n") {
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
    } else if (ch !== "\r") {
      field += ch;
    }
  }
  if (field.length > 0 || row.length > 0) {
    row.push(field);
    rows.push(row);
  }
  return rows.filter((r) => r.some((c) => c.trim() !== ""));
}

function sqlString(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}

function toIsoUtc(raw) {
  // Saweria exports "2026-05-21 23:05:04+07:00"; normalize the space to T.
  const normalized = String(raw).trim().replace(" ", "T");
  const ms = Date.parse(normalized);
  if (Number.isNaN(ms)) throw new Error(`bad timestamp: ${raw}`);
  return new Date(ms).toISOString();
}

function parseAmount(raw) {
  const digits = String(raw).replace(/[^0-9]/g, "");
  return digits ? Number.parseInt(digits, 10) : 0;
}

const text = readFileSync(csvPath, "utf8");
const rows = parseCsv(text);
if (rows.length < 2) throw new Error("csv has no data rows");

const header = rows[0].map((h) => h.trim());
const col = (name) => header.indexOf(name);
const idx = {
  created_at: col("created_at"),
  id: col("id"),
  type: col("type"),
  status: col("status"),
  amount: col("amount"),
  cut: col("cut"),
  donator_name: col("donator_name"),
  donator_email: col("donator_email"),
  donator_is_user: col("donator_is_user"),
  message: col("message"),
};
for (const [key, value] of Object.entries(idx)) {
  if (value === -1) throw new Error(`missing column: ${key}`);
}

const gameSubquery = `(SELECT id FROM games WHERE game_key=${sqlString(gameKey)})`;
const lines = ["PRAGMA foreign_keys=ON;"];
let kept = 0;
let skipped = 0;

for (let r = 1; r < rows.length; r += 1) {
  const cells = rows[r];
  const type = (cells[idx.type] || "").trim().toLowerCase();
  const status = (cells[idx.status] || "").trim();
  const amount = parseAmount(cells[idx.amount]);
  const providerTxId = (cells[idx.id] || "").trim();

  if (type !== "donation" || status.toUpperCase() !== "SUCCESS" || amount <= 0 || !providerTxId) {
    skipped += 1;
    continue;
  }

  const donatorName = (cells[idx.donator_name] || "").trim() || "Saweria Donor";
  const message = (cells[idx.message] || "").trim();
  const donationAt = toIsoUtc(cells[idx.created_at]);

  const rawPayload = {
    id: providerTxId,
    cut: parseAmount(cells[idx.cut]) * -1 || 0,
    type: "donation",
    message,
    amount_raw: amount,
    created_at: (cells[idx.created_at] || "").trim(),
    donator_name: donatorName,
    donator_email: (cells[idx.donator_email] || "").trim(),
    donator_is_user: (cells[idx.donator_is_user] || "").trim().toUpperCase() === "TRUE",
    source: "csv_import",
  };

  const values = [
    gameSubquery,
    sqlString(providerTxId),
    sqlString(donatorName),
    sqlString(donatorName.toLowerCase()),
    String(amount),
    sqlString(message),
    sqlString("success"),
    sqlString(donationAt),
    sqlString(donationAt),
    sqlString(JSON.stringify(rawPayload)),
    "0",
    sqlString(""),
  ].join(",");

  lines.push(
    "INSERT INTO donations (game_id, provider_tx_id, saweria_name, saweria_name_lc, amount, message, status, donation_at, received_at, raw_payload, is_voided, voided_reason) VALUES (" +
      values +
      ") ON CONFLICT(game_id, provider_tx_id) DO UPDATE SET " +
      "saweria_name=excluded.saweria_name, saweria_name_lc=excluded.saweria_name_lc, amount=excluded.amount, " +
      "message=excluded.message, status=excluded.status, donation_at=excluded.donation_at, raw_payload=excluded.raw_payload;",
  );
  kept += 1;
}

writeFileSync(outPath, lines.join("\n") + "\n", "utf8");
console.log(`IMPORT_SQL_READY=1 game=${gameKey} kept=${kept} skipped=${skipped} out=${outPath}`);
