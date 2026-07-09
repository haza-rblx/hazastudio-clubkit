/**
 * Push every Saweria transaction into production D1 (full history).
 * Requires Worker with POST /admin/games/:gameKey/import-donations (deploy once).
 *
 *   $env:ADMIN_TOKEN="..."
 *   node scripts/push-full-donation-history.mjs nuwa backups/nuwa-donations.json
 */

import { readFileSync } from "node:fs";

const apiBase = (process.env.API_BASE || "https://hazastudio-donation-api.hazastudio.workers.dev").replace(/\/$/, "");
const adminToken = process.env.ADMIN_TOKEN || "";
const gameKey = process.argv[2];
const jsonPath = process.argv[3];

if (!adminToken || !gameKey || !jsonPath) {
  console.error("usage: ADMIN_TOKEN=... node scripts/push-full-donation-history.mjs <game_key> <donations.json>");
  process.exit(1);
}

const payload = JSON.parse(readFileSync(jsonPath, "utf8"));
const donations = Array.isArray(payload.donations) ? payload.donations : payload;
const chunkSize = 400;

async function pushChunk(chunk, index, total) {
  const res = await fetch(`${apiBase}/admin/games/${gameKey}/import-donations`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${adminToken}`,
    },
    body: JSON.stringify({ donations: chunk }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || body.ok === false) {
    throw new Error(body.error || `HTTP ${res.status} chunk ${index + 1}/${total}`);
  }
  console.log(`chunk ${index + 1}/${total}: imported=${body.imported} skipped=${body.skipped}`);
  return body;
}

async function main() {
  const chunks = [];
  for (let i = 0; i < donations.length; i += chunkSize) {
    chunks.push(donations.slice(i, i + chunkSize));
  }
  console.log(`pushing ${donations.length} donations in ${chunks.length} chunk(s) to game=${gameKey}`);
  let imported = 0;
  for (let i = 0; i < chunks.length; i += 1) {
    const result = await pushChunk(chunks[i], i, chunks.length);
    imported += Number(result.imported) || 0;
  }
  console.log(`DONE total_imported=${imported}`);
  const verify = await fetch(
    `${apiBase}/game/${gameKey}?secret=${process.env.ROBLOX_SECRET || ""}&action=leaderboard&type=alltime&limit=3`,
  ).catch(() => null);
  if (verify?.ok) {
    const body = await verify.json();
    console.log("leaderboard_top", JSON.stringify(body.data || body.leaderboard || []));
  } else {
    console.log("verify: open leaderboard URL in browser after import");
  }
}

main().catch((err) => {
  console.error(err.message || err);
  if (String(err.message).includes("not_found")) {
    console.error("Deploy worker first: npm run cf:deploy");
  }
  process.exit(1);
});
