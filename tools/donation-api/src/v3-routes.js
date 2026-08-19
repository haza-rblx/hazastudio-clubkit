/**
 * Donation API v3 — enterprise-grade notification delivery.
 *
 * Extends v2 with a durable delivery ledger so a donation notification is
 * never silently lost between the Worker and a player's screen:
 *
 *   POST /game/:key/v3/deliveries            — game server registers the
 *                                              intended recipients of a
 *                                              donation notification
 *                                              (idempotent per donation+user)
 *   POST /game/:key/v3/delivery-ack          — game server reports client acks
 *                                              (batch; append-only audit log)
 *   GET  /game/:key/v3/delivery-status       — server polls pending/unacked
 *                                              deliveries for retry scheduling
 *
 * Auth matches v2: ?secret=rbx_... OR Authorization: Bearer rbx_... against
 * games.secret. Admin (game or master token) gets:
 *
 *   GET /admin/games/:key/delivery-report    — per-donation ack/fail counts
 *   GET /admin/games/:key/dlq                — deliveries that exhausted retries
 *
 * Design notes:
 * - At-least-once delivery + client-side dedup by donation id. The ledger is
 *   the source of truth for "who confirmed what"; the game server drives
 *   retries, the Worker never pushes.
 * - All writes are idempotent: registering the same (donation, user) twice is
 *   an upsert-noop; acking twice appends a second audit row but leaves the
 *   delivery 'acked'.
 */

import { getGameByKey } from "./game-data.js";
import { isLicenseBlocked } from "./license-routes.js";

export const V3_VERSION = "3.0.0";

const MAX_BATCH = 200;
const DELIVERY_STATUSES = new Set(["pending", "sent", "acked", "dlq", "failed_resolve"]);

function cleanString(value, fallback = "") {
  if (value === undefined || value === null) return fallback;
  const cleaned = String(value).trim();
  return cleaned || fallback;
}

function nowIso() {
  return new Date().toISOString();
}

function assertGameSecret(req, url, gameSecret) {
  const querySecret = cleanString(url.searchParams.get("secret"));
  if (querySecret && querySecret === gameSecret) return true;
  const auth = req.headers.get("authorization") || "";
  const match = auth.match(/^Bearer\s+(.+)$/i);
  return Boolean(match && match[1] === gameSecret);
}

async function parseJson(req) {
  try {
    return await req.json();
  } catch {
    return {};
  }
}

async function resolveGameV3(req, env, url, gameKey, json) {
  const game = await getGameByKey(env.DB, gameKey);
  if (!game) return { error: json(req, env, { ok: false, error: "game_not_found" }, 404) };
  if (!assertGameSecret(req, url, game.secret)) {
    return { error: json(req, env, { ok: false, error: "invalid_secret" }, 403) };
  }
  const licenseBlock = isLicenseBlocked(game);
  if (licenseBlock.blocked) {
    return { error: json(req, env, { ok: false, error: licenseBlock.error }, 403) };
  }
  return { game };
}

function toPositiveInt(value) {
  const n = Number(value);
  return Number.isInteger(n) && n > 0 ? n : 0;
}

/**
 * POST /game/:key/v3/deliveries
 * Body: { donation_id, roblox_user_ids: number[] }
 * Registers (donation, user) delivery rows as 'pending'. Idempotent.
 */
async function handleRegisterDeliveries(req, env, game, json) {
  const body = await parseJson(req);
  const donationId = toPositiveInt(body.donation_id);
  const userIds = Array.isArray(body.roblox_user_ids)
    ? [...new Set(body.roblox_user_ids.map(toPositiveInt).filter((n) => n > 0))]
    : [];
  if (!donationId || userIds.length === 0) {
    return json(req, env, { ok: false, error: "validation_failed — donation_id and roblox_user_ids required" }, 422);
  }
  if (userIds.length > MAX_BATCH) {
    return json(req, env, { ok: false, error: `too_many_recipients_max_${MAX_BATCH}` }, 422);
  }

  // Verify the donation belongs to this game before writing ledger rows.
  const donation = await env.DB.prepare(
    "SELECT id FROM donations WHERE id = ? AND game_id = ? LIMIT 1",
  )
    .bind(donationId, game.id)
    .first();
  if (!donation) return json(req, env, { ok: false, error: "donation_not_found" }, 404);

  const ts = nowIso();
  const statements = userIds.map((userId) =>
    env.DB.prepare(
      `INSERT INTO notification_deliveries (game_id, donation_id, roblox_user_id, status, first_sent_at, last_sent_at)
       VALUES (?, ?, ?, 'sent', ?, ?)
       ON CONFLICT(game_id, donation_id, roblox_user_id) DO UPDATE SET
         last_sent_at = excluded.last_sent_at,
         attempts = notification_deliveries.attempts + 1,
         updated_at = excluded.last_sent_at`,
    ).bind(game.id, donationId, userId, ts, ts),
  );
  const chunkSize = 40;
  for (let i = 0; i < statements.length; i += chunkSize) {
    await env.DB.batch(statements.slice(i, i + chunkSize));
  }
  return json(req, env, { ok: true, registered: userIds.length }, 201);
}

/**
 * POST /game/:key/v3/delivery-ack
 * Body: { acks: [{ donation_id, roblox_user_id, displayed_at? }] }
 * Marks deliveries 'acked' and appends to the audit log. Idempotent-ish:
 * duplicate acks append audit rows but do not change terminal state.
 */
async function handleDeliveryAck(req, env, game, json) {
  const body = await parseJson(req);
  const acks = Array.isArray(body.acks) ? body.acks : [];
  if (acks.length === 0) {
    return json(req, env, { ok: false, error: "validation_failed — acks array required" }, 422);
  }
  if (acks.length > MAX_BATCH) {
    return json(req, env, { ok: false, error: `too_many_acks_max_${MAX_BATCH}` }, 422);
  }

  const ts = nowIso();
  const statements = [];
  let accepted = 0;
  for (const ack of acks) {
    const donationId = toPositiveInt(ack?.donation_id);
    const userId = toPositiveInt(ack?.roblox_user_id);
    if (!donationId || !userId) continue;
    const displayedAt = cleanString(ack?.displayed_at) || null;
    // UPSERT, not UPDATE: under burst load a client ack can beat the server's
    // registerDeliveries call (the ack fires at enqueue; registration is a
    // separate HTTP round-trip). A plain UPDATE would find no row and silently
    // leave the delivery 'sent' forever even though the client confirmed receipt.
    // The INSERT branch creates the row already-acked; the ON CONFLICT branch
    // upgrades an existing sent/pending row without touching a prior acked_at.
    statements.push(
      env.DB.prepare(
        `INSERT INTO notification_deliveries (game_id, donation_id, roblox_user_id, status, attempts, first_sent_at, last_sent_at, acked_at)
         VALUES (?, ?, ?, 'acked', 0, ?, ?, ?)
         ON CONFLICT(game_id, donation_id, roblox_user_id) DO UPDATE SET
           status = 'acked',
           acked_at = COALESCE(notification_deliveries.acked_at, excluded.acked_at),
           updated_at = excluded.acked_at`,
      ).bind(game.id, donationId, userId, ts, ts, ts),
      env.DB.prepare(
        `INSERT INTO delivery_acks (game_id, donation_id, roblox_user_id, displayed_at)
         VALUES (?, ?, ?, ?)`,
      ).bind(game.id, donationId, userId, displayedAt),
    );
    accepted += 1;
  }
  if (statements.length === 0) {
    return json(req, env, { ok: false, error: "validation_failed — no valid acks" }, 422);
  }
  const chunkSize = 40;
  for (let i = 0; i < statements.length; i += chunkSize) {
    await env.DB.batch(statements.slice(i, i + chunkSize));
  }
  return json(req, env, { ok: true, acked: accepted });
}

/**
 * GET /game/:key/v3/delivery-status?status=pending|sent|dlq&older_than_secs=5&limit=200
 * Returns deliveries the server should consider for retry. Default view:
 * status='sent' (registered but unacked).
 */
async function handleDeliveryStatus(req, env, url, game, json) {
  const status = cleanString(url.searchParams.get("status"), "sent").toLowerCase();
  if (!DELIVERY_STATUSES.has(status)) {
    return json(req, env, { ok: false, error: "invalid_status" }, 422);
  }
  const limit = Math.max(1, Math.min(MAX_BATCH, Number(url.searchParams.get("limit") || 200)));
  const olderThanSecs = Math.max(0, Number(url.searchParams.get("older_than_secs") || 0));
  const rows = await env.DB.prepare(
    `SELECT
       nd.donation_id AS donation_id,
       nd.roblox_user_id AS roblox_user_id,
       nd.status AS status,
       nd.attempts AS attempts,
       nd.first_sent_at AS first_sent_at,
       nd.last_sent_at AS last_sent_at,
       d.saweria_name AS saweria_name,
       d.amount AS amount,
       d.message AS message
     FROM notification_deliveries nd
     JOIN donations d ON d.id = nd.donation_id
     WHERE nd.game_id = ?
       AND nd.status = ?
       AND (CAST(strftime('%s', nd.last_sent_at) AS INTEGER) <= CAST(strftime('%s', 'now') AS INTEGER) - ?)
     ORDER BY nd.last_sent_at ASC, nd.id ASC
     LIMIT ?`,
  )
    .bind(game.id, status, olderThanSecs, limit)
    .all();
  return json(req, env, { ok: true, deliveries: rows.results || [] }, 200, {
    "cache-control": "no-store",
  });
}

/**
 * Route: /game/:key/v3/*
 * parts[0]=game, parts[1]=gameKey, parts[2]=v3, parts[3]=resource
 */
export async function handleGameV3(req, env, url, gameKey, parts, json) {
  if (parts[2] !== "v3") {
    return json(req, env, { ok: false, error: "not_found" }, 404);
  }
  const resolved = await resolveGameV3(req, env, url, gameKey, json);
  if (resolved.error) return resolved.error;
  const { game } = resolved;

  const resource = parts[3] || "health";

  if (resource === "health" && req.method === "GET") {
    return json(req, env, {
      ok: true,
      version: V3_VERSION,
      server_time: Math.floor(Date.now() / 1000),
      game_key: game.game_key,
    });
  }

  if (resource === "deliveries" && req.method === "POST") {
    return handleRegisterDeliveries(req, env, game, json);
  }

  if (resource === "delivery-ack" && req.method === "POST") {
    return handleDeliveryAck(req, env, game, json);
  }

  if (resource === "delivery-status" && req.method === "GET") {
    return handleDeliveryStatus(req, env, url, game, json);
  }

  if (resource === "delivery-dlq" && req.method === "POST") {
    return handleDeliveryDlq(req, env, game, json);
  }

  return json(req, env, { ok: false, error: "not_found" }, 404);
}

/**
 * GET /admin/games/:key/delivery-report?since=<ISO>&limit=<n>
 * Per-donation delivery counts: registered / acked / pending / dlq.
 * Auth is handled by the caller (handleAdmin already asserted game admin).
 */
export async function handleAdminDeliveryReport(req, env, url, game, json) {
  if (req.method !== "GET") return json(req, env, { ok: false, error: "method_not_allowed" }, 405);
  const limit = Math.max(1, Math.min(500, Number(url.searchParams.get("limit") || 100)));
  const since = cleanString(url.searchParams.get("since"));
  const where = ["nd.game_id = ?"];
  const bind = [game.id];
  if (since) {
    where.push("nd.created_at >= ?");
    bind.push(since);
  }
  const rows = await env.DB.prepare(
    `SELECT
       nd.donation_id AS donation_id,
       d.saweria_name AS saweria_name,
       d.amount AS amount,
       d.received_at AS received_at,
       COUNT(*) AS registered,
       SUM(CASE WHEN nd.status = 'acked' THEN 1 ELSE 0 END) AS acked,
       SUM(CASE WHEN nd.status IN ('pending','sent') THEN 1 ELSE 0 END) AS pending,
       SUM(CASE WHEN nd.status = 'dlq' THEN 1 ELSE 0 END) AS dlq,
       MAX(nd.attempts) AS max_attempts
     FROM notification_deliveries nd
     JOIN donations d ON d.id = nd.donation_id
     WHERE ${where.join(" AND ")}
     GROUP BY nd.donation_id
     ORDER BY nd.donation_id DESC
     LIMIT ?`,
  )
    .bind(...bind, limit)
    .all();
  return json(req, env, { ok: true, report: rows.results || [] });
}

/**
 * GET /admin/games/:key/dlq?limit=<n>
 * Deliveries needing manual attention: per-user retry exhaustion ('dlq') plus
 * whole-donation failures ('failed_resolve' sentinel rows, roblox_user_id = 0).
 */
export async function handleAdminDlq(req, env, url, game, json) {
  if (req.method !== "GET") return json(req, env, { ok: false, error: "method_not_allowed" }, 405);
  const limit = Math.max(1, Math.min(500, Number(url.searchParams.get("limit") || 100)));
  const rows = await env.DB.prepare(
    `SELECT
       nd.id AS delivery_id,
       nd.donation_id AS donation_id,
       nd.roblox_user_id AS roblox_user_id,
       nd.status AS status,
       nd.attempts AS attempts,
       nd.first_sent_at AS first_sent_at,
       nd.last_sent_at AS last_sent_at,
       d.saweria_name AS saweria_name,
       d.amount AS amount
     FROM notification_deliveries nd
     JOIN donations d ON d.id = nd.donation_id
     WHERE nd.game_id = ? AND nd.status IN ('dlq', 'failed_resolve')
     ORDER BY nd.last_sent_at DESC
     LIMIT ?`,
  )
    .bind(game.id, limit)
    .all();
  return json(req, env, { ok: true, dlq: rows.results || [] });
}

/**
 * POST /game/:key/v3/delivery-dlq
 * Body: { entries: [{ donation_id, roblox_user_id, reason? }] }
 * Server reports undeliverable notifications → terminal ledger state.
 *   - Per-user retry exhaustion: roblox_user_id = the player, reason omitted → 'dlq'
 *   - Whole-donation failure (e.g. phase-2 resolve crashed before any recipient
 *     was known): roblox_user_id = 0 (sentinel), reason = 'failed_resolve' → the
 *     row is INSERTed (no per-user rows exist yet) with status 'failed_resolve'.
 * Either way the donation is auditable instead of silently lost.
 */
export async function handleDeliveryDlq(req, env, game, json) {
  const body = await parseJson(req);
  const entries = Array.isArray(body.entries) ? body.entries : [];
  if (entries.length === 0) {
    return json(req, env, { ok: false, error: "validation_failed — entries array required" }, 422);
  }
  if (entries.length > MAX_BATCH) {
    return json(req, env, { ok: false, error: `too_many_entries_max_${MAX_BATCH}` }, 422);
  }
  const ts = nowIso();
  const statements = [];
  let accepted = 0;
  for (const entry of entries) {
    const donationId = toPositiveInt(entry?.donation_id);
    const userId = Number(entry?.roblox_user_id);
    const reason = cleanString(entry?.reason);
    if (!donationId || !Number.isInteger(userId) || userId < 0) continue;
    if (userId === 0) {
      // Whole-donation failure sentinel: insert a marker row so ops can see the
      // donation never reached any client. ON CONFLICT keeps the first report.
      statements.push(
        env.DB.prepare(
          `INSERT INTO notification_deliveries (game_id, donation_id, roblox_user_id, status, attempts, first_sent_at, last_sent_at)
           VALUES (?, ?, 0, ?, 0, ?, ?)
           ON CONFLICT(game_id, donation_id, roblox_user_id) DO NOTHING`,
        ).bind(game.id, donationId, reason || "failed_resolve", ts, ts),
      );
    } else {
      statements.push(
        env.DB.prepare(
          `UPDATE notification_deliveries
             SET status = 'dlq', updated_at = ?
           WHERE game_id = ? AND donation_id = ? AND roblox_user_id = ? AND status != 'acked'`,
        ).bind(ts, game.id, donationId, userId),
      );
    }
    accepted += 1;
  }
  if (statements.length === 0) {
    return json(req, env, { ok: false, error: "validation_failed — no valid entries" }, 422);
  }
  const chunkSize = 40;
  for (let i = 0; i < statements.length; i += chunkSize) {
    await env.DB.batch(statements.slice(i, i + chunkSize));
  }
  return json(req, env, { ok: true, dlq_marked: accepted });
}
