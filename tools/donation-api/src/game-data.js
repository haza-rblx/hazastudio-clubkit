/** Shared donation DB queries used by v1 action routes and v2 REST routes. */

export function cleanString(value, fallback = "") {
  if (value === undefined || value === null) return fallback;
  const cleaned = String(value).trim();
  return cleaned || fallback;
}

export function toLc(v) {
  return cleanString(v).toLowerCase();
}

const WIB_OFFSET_SECONDS = 7 * 3600;
const SECONDS_PER_DAY = 86400;

/** Donasi harian WIB: 00:01 s/d 23:59:59, reset setelah tengah malam WIB. */
export function getWibDailyDonationWindowUnix(nowSeconds = Math.floor(Date.now() / 1000)) {
  const bucket = Math.floor((nowSeconds + WIB_OFFSET_SECONDS) / SECONDS_PER_DAY);
  const dayStart = bucket * SECONDS_PER_DAY - WIB_OFFSET_SECONDS;
  return {
    start: dayStart + 60,
    end: dayStart + SECONDS_PER_DAY - 1,
  };
}

export async function getGameByKey(db, gameKey) {
  return db.prepare("SELECT * FROM games WHERE game_key = ? LIMIT 1").bind(gameKey).first();
}

export async function lookupRobloxUser(username) {
  const name = cleanString(username).replace(/^@/, "");
  if (!name) return null;
  try {
    const res = await fetch("https://users.roblox.com/v1/usernames/users", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ usernames: [name], excludeBannedUsers: false }),
    });
    if (!res.ok) return null;
    const body = await res.json().catch(() => ({}));
    const match = Array.isArray(body?.data) ? body.data[0] : null;
    if (!match || match.id === undefined || match.id === null) return null;
    return {
      userId: Number(match.id) || null,
      username: cleanString(match.name, name),
      displayName: cleanString(match.displayName, cleanString(match.name, name)),
    };
  } catch {
    return null;
  }
}

export async function getRobloxDonorCashProfile(db, gameId, userId, username) {
  const uid = Math.floor(Number(userId) || 0);
  const usernameLc = toLc(cleanString(username)).replace(/^@/, "");
  const successStatuses = "'success','paid','completed','settlement'";

  const perSaweriaCte = `WITH per_saweria AS (
       SELECT saweria_name_lc, SUM(amount) AS total_amount
       FROM (
         SELECT saweria_name_lc, total_amount AS amount
         FROM legacy_seed_entries
         WHERE game_id = ?
         UNION ALL
         SELECT saweria_name_lc, amount
         FROM donations
         WHERE game_id = ?
           AND status IN (${successStatuses})
           AND is_voided = 0
       )
       GROUP BY saweria_name_lc
     )`;

  const rankSql = `${perSaweriaCte},
     per_roblox_user AS (
       SELECT dl.roblox_user_id AS user_id, SUM(ps.total_amount) AS cash_total
       FROM per_saweria ps
       INNER JOIN donor_links dl
         ON dl.game_id = ?
        AND dl.saweria_name_lc = ps.saweria_name_lc
       WHERE dl.roblox_user_id IS NOT NULL AND dl.roblox_user_id > 0
       GROUP BY dl.roblox_user_id
     ),
     ranked AS (
       SELECT
         user_id,
         cash_total,
         ROW_NUMBER() OVER (ORDER BY cash_total DESC, user_id ASC) AS cash_rank
       FROM per_roblox_user
     )
     SELECT user_id, cash_total, cash_rank FROM ranked WHERE user_id = ?`;

  let row = null;
  if (uid > 0) {
    row = await db.prepare(rankSql).bind(gameId, gameId, gameId, uid).first();
  }

  if (!row && usernameLc !== "") {
    const usernameSql = `${perSaweriaCte},
       per_username AS (
         SELECT lower(trim(dl.roblox_username)) AS username_lc, SUM(ps.total_amount) AS cash_total
         FROM per_saweria ps
         INNER JOIN donor_links dl
           ON dl.game_id = ?
          AND dl.saweria_name_lc = ps.saweria_name_lc
         WHERE trim(dl.roblox_username) != ''
         GROUP BY lower(trim(dl.roblox_username))
       ),
       ranked AS (
         SELECT
           username_lc,
           cash_total,
           ROW_NUMBER() OVER (ORDER BY cash_total DESC, username_lc ASC) AS cash_rank
         FROM per_username
       )
       SELECT cash_total, cash_rank FROM ranked WHERE username_lc = ?`;
    row = await db.prepare(usernameSql).bind(gameId, gameId, gameId, usernameLc).first();
  }

  const cashTotal = Number(row?.cash_total) || 0;
  const cashRank = Number(row?.cash_rank) || 0;
  return {
    cash_total: cashTotal,
    cash_rank: cashTotal > 0 && cashRank > 0 ? cashRank : null,
  };
}

export async function buildMergedLeaderboard(db, gameId, limit) {
  const rows = await db
    .prepare(
      `WITH combined AS (
         SELECT saweria_name_lc, saweria_name, total_amount AS amount, NULL AS received_at FROM legacy_seed_entries WHERE game_id = ?
         UNION ALL
         SELECT saweria_name_lc, saweria_name, amount, CAST(strftime('%s', donation_at) AS INTEGER) AS received_at
         FROM donations
         WHERE game_id = ? AND status IN ('success', 'paid', 'completed', 'settlement') AND is_voided = 0
       )
       SELECT saweria_name_lc, MAX(saweria_name) AS saweria_name, SUM(amount) AS total_amount, MAX(received_at) AS last_donation_at
       FROM combined
       GROUP BY saweria_name_lc
       ORDER BY total_amount DESC, last_donation_at ASC
       LIMIT ?`,
    )
    .bind(gameId, gameId, limit)
    .all();
  return (rows.results || []).map((r) => ({
    saweria_name: r.saweria_name,
    saweria_name_lc: r.saweria_name_lc,
    total_amount: Number(r.total_amount) || 0,
    last_donation_at: Number(r.last_donation_at) || 0,
  }));
}

export async function buildDailyLeaderboard(db, gameId, limit) {
  const { start, end } = getWibDailyDonationWindowUnix();
  const rows = await db
    .prepare(
      `SELECT
         saweria_name_lc,
         MAX(saweria_name) AS saweria_name,
         SUM(amount) AS total_amount,
         MAX(CAST(strftime('%s', received_at) AS INTEGER)) AS last_donation_at
       FROM donations
       WHERE game_id = ?
         AND status IN ('success', 'paid', 'completed', 'settlement')
         AND is_voided = 0
         AND CAST(strftime('%s', received_at) AS INTEGER) >= ?
         AND CAST(strftime('%s', received_at) AS INTEGER) <= ?
       GROUP BY saweria_name_lc
       ORDER BY total_amount DESC, last_donation_at ASC
       LIMIT ?`,
    )
    .bind(gameId, start, end, limit)
    .all();
  return (rows.results || []).map((r) => ({
    saweria_name: r.saweria_name,
    saweria_name_lc: r.saweria_name_lc,
    total_amount: Number(r.total_amount) || 0,
    last_donation_at: Number(r.last_donation_at) || 0,
  }));
}

/** Enrich leaderboard rows with Roblox link data from donor_links. */
export async function enrichLeaderboardWithLinks(db, gameId, entries) {
  if (!entries.length) return [];
  const nameLcs = entries.map((e) => e.saweria_name_lc).filter(Boolean);
  if (!nameLcs.length) return entries.map((e, i) => formatLeaderboardRow(e, i + 1, null));

  const placeholders = nameLcs.map(() => "?").join(",");
  const linkRows = await db
    .prepare(
      `SELECT saweria_name_lc, roblox_username, roblox_user_id, roblox_display_name
       FROM donor_links
       WHERE game_id = ? AND saweria_name_lc IN (${placeholders})`,
    )
    .bind(gameId, ...nameLcs)
    .all();
  const linkByLc = new Map();
  for (const row of linkRows.results || []) {
    linkByLc.set(row.saweria_name_lc, row);
  }
  return entries.map((entry, index) => formatLeaderboardRow(entry, index + 1, linkByLc.get(entry.saweria_name_lc) || null));
}

function formatLeaderboardRow(entry, rank, link) {
  const lastAt = entry.last_donation_at
    ? new Date((Number(entry.last_donation_at) || 0) * 1000).toISOString()
    : "";
  return {
    rank,
    saweria_name: entry.saweria_name,
    donor_name: entry.saweria_name,
    provider_name: entry.saweria_name,
    total: Number(entry.total_amount) || 0,
    last_at: lastAt,
    roblox_username: link?.roblox_username || "",
    roblox_user_id: link?.roblox_user_id != null ? Number(link.roblox_user_id) : null,
    roblox_display_name: link?.roblox_display_name || "",
  };
}

export async function fetchNotificationsAfterCursor(db, gameId, cursor, limit) {
  const sinceDate = cursor?.received_at || "1970-01-01T00:00:00.000Z";
  const sinceId = Number(cursor?.id) || 0;
  const rows = await db
    .prepare(
      `SELECT
         d.id AS id,
         d.saweria_name AS saweria_name,
         d.amount AS amount,
         d.message AS message,
         d.donation_at AS donation_at,
         d.received_at AS received_at,
         dl.roblox_username AS roblox_username,
         dl.roblox_user_id AS roblox_user_id,
         dl.roblox_display_name AS roblox_display_name,
         CAST(strftime('%s', d.received_at) AS INTEGER) AS received_unix
       FROM donations d
       LEFT JOIN donor_links dl
         ON dl.game_id = d.game_id AND dl.saweria_name_lc = d.saweria_name_lc
       WHERE d.game_id = ?
         AND d.status IN ('success', 'paid', 'completed', 'settlement')
         AND d.is_voided = 0
         AND (
           d.received_at > ?
           OR (d.received_at = ? AND d.id > ?)
         )
       ORDER BY d.received_at ASC, d.id ASC
       LIMIT ?`,
    )
    .bind(gameId, sinceDate, sinceDate, sinceId, limit)
    .all();

  const items = (rows.results || []).map((r) => {
    const receivedCursor = Number(r.received_unix) || Math.floor(Date.parse(r.received_at || "") / 1000);
    return {
      id: String(r.id),
      unix_timestamp: receivedCursor,
      donation_unix_timestamp: Math.floor(Date.parse(r.donation_at || r.received_at) / 1000),
      donator_name: r.saweria_name,
      saweria_name: r.saweria_name,
      provider_name: r.saweria_name,
      roblox_username: r.roblox_username || "",
      roblox_user_id: r.roblox_user_id != null ? Number(r.roblox_user_id) : null,
      roblox_display_name: r.roblox_display_name || "",
      amount_raw: Number(r.amount) || 0,
      message: r.message || "",
      received_at: receivedCursor,
      cursor: encodeNotificationCursor(r.received_at, r.id),
    };
  });

  const last = items[items.length - 1];
  return {
    items,
    next_cursor: last ? last.cursor : cursor ? encodeNotificationCursor(cursor.received_at, cursor.id) : "",
  };
}

export function encodeNotificationCursor(receivedAt, id) {
  const payload = JSON.stringify({
    t: cleanString(receivedAt, "1970-01-01T00:00:00.000Z"),
    i: Number(id) || 0,
  });
  return btoa(payload).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

export function decodeNotificationCursor(cursor) {
  const raw = cleanString(cursor);
  if (!raw) return null;
  try {
    const padded = raw.replace(/-/g, "+").replace(/_/g, "/");
    const pad = padded.length % 4 === 0 ? "" : "=".repeat(4 - (padded.length % 4));
    const parsed = JSON.parse(atob(padded + pad));
    if (!parsed || typeof parsed !== "object") return null;
    return {
      received_at: cleanString(parsed.t, "1970-01-01T00:00:00.000Z"),
      id: Number(parsed.i) || 0,
    };
  } catch {
    return null;
  }
}

export async function upsertDonorLink(db, gameId, saweriaName, robloxUsername) {
  const resolved = await lookupRobloxUser(robloxUsername);
  const finalUsername = resolved?.username || robloxUsername;
  const robloxUserId = resolved?.userId ?? null;
  const robloxDisplayName = resolved?.displayName || "";
  await db
    .prepare(
      `INSERT INTO donor_links (game_id, saweria_name, saweria_name_lc, roblox_username, roblox_user_id, roblox_display_name)
       VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(game_id, saweria_name_lc) DO UPDATE SET
         saweria_name = excluded.saweria_name,
         roblox_username = excluded.roblox_username,
         roblox_user_id = excluded.roblox_user_id,
         roblox_display_name = excluded.roblox_display_name,
         updated_at = (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))`,
    )
    .bind(gameId, saweriaName, saweriaName.toLowerCase(), finalUsername, robloxUserId, robloxDisplayName)
    .run();
  return { resolved: Boolean(resolved), roblox_username: finalUsername, roblox_user_id: robloxUserId };
}

export async function listDonorLinks(db, gameId) {
  const rows = await db
    .prepare(
      "SELECT saweria_name, roblox_user_id, roblox_username, roblox_display_name FROM donor_links WHERE game_id = ? ORDER BY id DESC",
    )
    .bind(gameId)
    .all();
  return rows.results || [];
}
