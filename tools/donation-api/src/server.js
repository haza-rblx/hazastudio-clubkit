import http from "node:http";
import crypto from "node:crypto";
import { URL } from "node:url";
import pg from "pg";

const { Pool } = pg;

const PORT = Number(process.env.PORT || 3000);
const ADMIN_TOKEN = process.env.ADMIN_TOKEN || "";
const PUBLIC_BASE_URL = (process.env.PUBLIC_BASE_URL || "").replace(/\/$/, "");
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DATABASE_URL?.includes("railway")
    ? { rejectUnauthorized: false }
    : undefined,
});

function json(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
  });
  res.end(body);
}

function text(res, status, body) {
  res.writeHead(status, { "content-type": "text/plain; charset=utf-8" });
  res.end(body);
}

async function readBody(req) {
  const chunks = [];
  let total = 0;
  for await (const chunk of req) {
    total += chunk.length;
    if (total > 1024 * 1024) {
      throw new Error("payload_too_large");
    }
    chunks.push(chunk);
  }
  const raw = Buffer.concat(chunks).toString("utf8");
  if (!raw) return {};
  const contentType = req.headers["content-type"] || "";
  if (contentType.includes("application/json")) {
    return JSON.parse(raw);
  }
  const params = new URLSearchParams(raw);
  return Object.fromEntries(params.entries());
}

function requireAdmin(req) {
  if (!ADMIN_TOKEN) return false;
  return req.headers.authorization === `Bearer ${ADMIN_TOKEN}`;
}

function randomSecret(prefix) {
  return `${prefix}_${crypto.randomBytes(24).toString("base64url")}`;
}

function cleanString(value, fallback = "") {
  if (value === undefined || value === null) return fallback;
  const cleaned = String(value).trim();
  return cleaned || fallback;
}

function parseAmount(value) {
  if (typeof value === "number") return Math.max(0, Math.floor(value));
  const textValue = cleanString(value);
  if (!textValue) return 0;
  const digits = textValue.replace(/[^\d]/g, "");
  return Number(digits || textValue) || 0;
}

function parseUnix(value) {
  if (typeof value === "number") {
    return Math.floor(value > 1000000000000 ? value / 1000 : value);
  }
  const parsed = Date.parse(cleanString(value));
  return Number.isNaN(parsed)
    ? Math.floor(Date.now() / 1000)
    : Math.floor(parsed / 1000);
}

function normalizeDonation(raw, provider = "saweria") {
  const root = raw && typeof raw === "object" ? raw : {};
  const data = root.data && typeof root.data === "object" ? root.data : root;
  const unixTimestamp = parseUnix(
    data.created_at ||
      data.createdAt ||
      data.paid_at ||
      data.timestamp ||
      data.updated_at ||
      root.t,
  );
  const amount = parseAmount(
    data.amount_raw || data.amount || data.total || data.nominal || data.value,
  );
  const defaultDonor =
    provider === "bagibagi" ? "Bagi-Bagi Donor" : "Saweria Donor";
  const donorName = cleanString(
    data.donator_name ||
      data.donor_name ||
      data.saweria_name ||
      data.bagibagi_name ||
      data.name ||
      data.username ||
      data.donor,
    defaultDonor,
  );
  let providerTxId = cleanString(
    data.id ||
      data.transaction_id ||
      data.payment_id ||
      data.order_id ||
      data.invoice_id,
  );
  if (!providerTxId && provider === "bagibagi") {
    providerTxId = `bb:${donorName.toLowerCase()}:${amount}:${unixTimestamp}`;
  }
  if (!providerTxId) {
    providerTxId = `${donorName}:${amount}:${unixTimestamp}`;
  }

  return {
    providerTxId,
    unixTimestamp,
    createdAt: new Date(unixTimestamp * 1000),
    donatorName: donorName,
    amountRaw: amount,
    message: cleanString(
      data.message || data.note || data.support_message || data.comment,
    ),
    status: cleanString(data.status, "success").toLowerCase(),
    type: cleanString(data.type || data.payment_type, "donation"),
    source: provider,
    rawJson: { provider, payload: raw || {} },
    robloxUsername: cleanString(
      data.roblox_username || data.robloxUsername,
    ).replace(/^@/, ""),
  };
}

function isSaweriaTestDonation(normalized) {
  return normalized.providerTxId === "00000000-0000-0000-0000-000000000000";
}

function isSuccessStatus(status) {
  return ["success", "paid", "completed", "settlement"].includes(
    cleanString(status, "success").toLowerCase(),
  );
}

async function migrate() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS games (
      id BIGSERIAL PRIMARY KEY,
      game_key TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      webhook_secret TEXT NOT NULL,
      roblox_secret TEXT NOT NULL,
      provider_link TEXT NOT NULL DEFAULT '',
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS name_maps (
      id BIGSERIAL PRIMARY KEY,
      game_id BIGINT NOT NULL REFERENCES games(id) ON DELETE CASCADE,
      provider_name TEXT NOT NULL,
      roblox_username TEXT NOT NULL,
      mapped_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS donations (
      id BIGSERIAL PRIMARY KEY,
      game_id BIGINT NOT NULL REFERENCES games(id) ON DELETE CASCADE,
      provider_tx_id TEXT NOT NULL,
      unix_timestamp BIGINT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL,
      donator_name TEXT NOT NULL,
      amount_raw INTEGER NOT NULL,
      message TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT 'success',
      type TEXT NOT NULL DEFAULT 'donation',
      source TEXT NOT NULL DEFAULT 'saweria',
      raw_json JSONB NOT NULL DEFAULT '{}'::jsonb,
      roblox_username TEXT NOT NULL DEFAULT '',
      received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      UNIQUE (game_id, provider_tx_id)
    );

    CREATE INDEX IF NOT EXISTS donations_game_time_idx ON donations (game_id, unix_timestamp DESC);
    CREATE INDEX IF NOT EXISTS donations_game_donor_idx ON donations (game_id, lower(donator_name));
    CREATE UNIQUE INDEX IF NOT EXISTS name_maps_game_provider_lower_idx
      ON name_maps (game_id, lower(provider_name));
  `);

  const bootstrapKey = cleanString(process.env.BOOTSTRAP_GAME_KEY);
  if (bootstrapKey) {
    await pool.query(
      `
      INSERT INTO games (game_key, name, webhook_secret, roblox_secret)
      VALUES ($1, $2, $3, $4)
      ON CONFLICT (game_key) DO NOTHING
      `,
      [
        bootstrapKey,
        cleanString(process.env.BOOTSTRAP_GAME_NAME, bootstrapKey),
        randomSecret("wh"),
        randomSecret("rbx"),
      ],
    );
  }
}

async function getGame(gameKey) {
  const result = await pool.query("SELECT * FROM games WHERE game_key = $1", [
    gameKey,
  ]);
  return result.rows[0] || null;
}

function assertRobloxSecret(url, game) {
  return cleanString(url.searchParams.get("secret")) === game.roblox_secret;
}

async function getMappedUsername(gameId, donorName) {
  const result = await pool.query(
    "SELECT roblox_username FROM name_maps WHERE game_id = $1 AND lower(provider_name) = lower($2) LIMIT 1",
    [gameId, donorName],
  );
  return result.rows[0]?.roblox_username || "";
}

async function upsertDonation(game, normalized) {
  const mappedUsername =
    normalized.robloxUsername ||
    (await getMappedUsername(game.id, normalized.donatorName));
  const result = await pool.query(
    `
    INSERT INTO donations (
      game_id, provider_tx_id, unix_timestamp, created_at, donator_name,
      amount_raw, message, status, type, source, raw_json, roblox_username
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
    ON CONFLICT (game_id, provider_tx_id)
    DO UPDATE SET
      unix_timestamp = EXCLUDED.unix_timestamp,
      created_at = EXCLUDED.created_at,
      donator_name = EXCLUDED.donator_name,
      amount_raw = EXCLUDED.amount_raw,
      message = EXCLUDED.message,
      status = EXCLUDED.status,
      type = EXCLUDED.type,
      source = EXCLUDED.source,
      raw_json = EXCLUDED.raw_json,
      roblox_username = COALESCE(NULLIF(EXCLUDED.roblox_username, ''), donations.roblox_username),
      received_at = CASE
        WHEN $13::boolean THEN now()
        ELSE donations.received_at
      END
    RETURNING *
    `,
    [
      game.id,
      normalized.providerTxId,
      normalized.unixTimestamp,
      normalized.createdAt,
      normalized.donatorName,
      normalized.amountRaw,
      normalized.message,
      normalized.status,
      normalized.type,
      normalized.source,
      JSON.stringify(normalized.rawJson),
      mappedUsername,
      isSaweriaTestDonation(normalized),
    ],
  );
  return result.rows[0];
}

const WIB_OFFSET_SECONDS = 7 * 3600;
const SECONDS_PER_DAY = 86400;

function getWibDailyDonationWindowUnix(nowSeconds = Math.floor(Date.now() / 1000)) {
  const bucket = Math.floor((nowSeconds + WIB_OFFSET_SECONDS) / SECONDS_PER_DAY);
  const dayStart = bucket * SECONDS_PER_DAY - WIB_OFFSET_SECONDS;
  return {
    start: dayStart + 60,
    end: dayStart + SECONDS_PER_DAY - 1,
  };
}

async function buildLeaderboard(game, type, limit) {
  const params = [game.id];
  let dailyClause = "";
  if (type === "daily") {
    const { start, end } = getWibDailyDonationWindowUnix();
    // received_at = waktu record masuk API; donation_at provider bisa offset WIB salah.
    dailyClause =
      "AND EXTRACT(EPOCH FROM COALESCE(d.received_at, d.created_at))::bigint >= $2 AND EXTRACT(EPOCH FROM COALESCE(d.received_at, d.created_at))::bigint <= $3";
    params.push(start, end);
  }
  params.push(limit);
  const result = await pool.query(
    `
    WITH successful AS (
      SELECT d.*
      FROM donations d
      WHERE d.game_id = $1
        AND d.status = ANY('{success,paid,completed,settlement}'::text[])
        ${dailyClause}
    ),
    totals AS (
      SELECT
        lower(donator_name) AS donor_key,
        (array_agg(donator_name ORDER BY unix_timestamp DESC))[1] AS donor_name,
        SUM(amount_raw)::int AS total,
        MAX(unix_timestamp)::bigint AS unix_timestamp,
        (array_agg(created_at ORDER BY unix_timestamp DESC))[1] AS last_at,
        MAX(NULLIF(roblox_username, '')) AS latest_roblox_username
      FROM successful
      GROUP BY lower(donator_name)
    )
    SELECT
      donor_name,
      total,
      unix_timestamp,
      last_at,
      COALESCE(NULLIF(latest_roblox_username, ''), nm.roblox_username, '') AS roblox_username
    FROM totals t
    LEFT JOIN name_maps nm
      ON nm.game_id = $1 AND lower(nm.provider_name) = t.donor_key
    ORDER BY total DESC, unix_timestamp ASC
    LIMIT $${params.length}
    `,
    params,
  );

  return result.rows.map((row, index) => ({
    rank: index + 1,
    saweria_name: row.donor_name,
    provider_name: row.donor_name,
    donor_name: row.donor_name,
    total: Number(row.total) || 0,
    unix_timestamp: Number(row.unix_timestamp) || 0,
    last_at: row.last_at ? new Date(row.last_at).toISOString() : "",
    roblox_username: row.roblox_username || "",
  }));
}

async function getNotifications(game, since) {
  const result = await pool.query(
    `
    SELECT
      d.*,
      (EXTRACT(EPOCH FROM d.received_at) * 1000)::bigint AS notification_ms,
      COALESCE(NULLIF(d.roblox_username, ''), nm.roblox_username, '') AS mapped_roblox_username
    FROM donations d
    LEFT JOIN name_maps nm
      ON nm.game_id = d.game_id AND lower(nm.provider_name) = lower(d.donator_name)
    WHERE d.game_id = $1
      AND (EXTRACT(EPOCH FROM d.received_at) * 1000)::bigint > ($2 * 1000)
      AND d.status = ANY('{success,paid,completed,settlement}'::text[])
    ORDER BY d.received_at ASC, d.id ASC
    LIMIT 100
    `,
    [game.id, since],
  );
  return result.rows.map((row) => ({
    id: row.provider_tx_id,
    unix_timestamp:
      Math.ceil((Number(row.notification_ms) || 0) / 1000) ||
      Number(row.unix_timestamp) ||
      0,
    donation_unix_timestamp: Number(row.unix_timestamp) || 0,
    donator_name: row.donator_name,
    saweria_name: row.donator_name,
    provider_name: row.donator_name,
    amount_raw: Number(row.amount_raw) || 0,
    message: row.message || "",
    roblox_username: row.mapped_roblox_username || "",
  }));
}

async function setNameMap(game, body) {
  const providerName = cleanString(
    body.saweria_name ||
      body.provider_name ||
      body.bagibagi_name ||
      body.donator_name ||
      body.donor_name,
  );
  const robloxUsername = cleanString(
    body.roblox_username || body.robloxUsername,
  ).replace(/^@/, "");
  if (!providerName || !robloxUsername) {
    throw new Error("missing_name");
  }
  await pool.query(
    `
    INSERT INTO name_maps (game_id, provider_name, roblox_username)
    VALUES ($1, $2, $3)
    ON CONFLICT (game_id, lower(provider_name))
    DO UPDATE SET roblox_username = EXCLUDED.roblox_username, mapped_at = now()
    `,
    [game.id, providerName, robloxUsername],
  );
}

async function listNameMaps(game) {
  const result = await pool.query(
    "SELECT provider_name, roblox_username, mapped_at FROM name_maps WHERE game_id = $1 ORDER BY provider_name ASC",
    [game.id],
  );
  return result.rows.map((row) => ({
    saweria_name: row.provider_name,
    provider_name: row.provider_name,
    roblox_username: row.roblox_username,
    mapped_at: row.mapped_at,
  }));
}

function gameResponse(game) {
  const base = PUBLIC_BASE_URL || "https://<your-domain>";
  const token = game.webhook_secret;
  const key = game.game_key;
  return {
    gameKey: key,
    name: game.name,
    saweriaWebhook: `${base}/webhook/saweria/${key}/${token}`,
    bagibagiWebhook: `${base}/webhook/bagibagi/${key}/${token}`,
    robloxEndpoint: `${base}/game/${key}?secret=${game.roblox_secret}`,
  };
}

async function handleGameGet(req, res, url, gameKey) {
  const game = await getGame(gameKey);
  if (!game) return json(res, 404, { ok: false, error: "game_not_found" });
  if (!assertRobloxSecret(url, game))
    return json(res, 401, { ok: false, error: "unauthorized" });

  const action = cleanString(
    url.searchParams.get("action"),
    "ping",
  ).toLowerCase();
  if (action === "ping")
    return json(res, 200, { ok: true, now: Math.floor(Date.now() / 1000) });
  if (action === "leaderboard") {
    const type = cleanString(
      url.searchParams.get("type"),
      "alltime",
    ).toLowerCase();
    const limit = Math.max(
      1,
      Math.min(100, Number(url.searchParams.get("limit") || 10)),
    );
    return json(res, 200, {
      ok: true,
      data: await buildLeaderboard(game, type, limit),
    });
  }
  if (action === "notifications") {
    const since = Number(url.searchParams.get("since") || 0);
    return json(res, 200, {
      ok: true,
      data: await getNotifications(game, since),
    });
  }
  if (action === "namemap")
    return json(res, 200, { ok: true, data: await listNameMaps(game) });
  return json(res, 400, { ok: false, error: "unknown_action" });
}

async function handleGamePost(req, res, url, gameKey) {
  const game = await getGame(gameKey);
  if (!game) return json(res, 404, { ok: false, error: "game_not_found" });
  if (!assertRobloxSecret(url, game))
    return json(res, 401, { ok: false, error: "unauthorized" });

  const body = await readBody(req);
  const action = cleanString(body.action).toLowerCase();
  if (action === "namemap_set") {
    await setNameMap(game, body);
    return json(res, 200, { ok: true });
  }

  const normalized = normalizeDonation(body);
  if (!normalized.providerTxId)
    return json(res, 400, { ok: false, error: "missing_donation_id" });
  if (normalized.amountRaw <= 0)
    return json(res, 400, { ok: false, error: "missing_amount" });
  const row = await upsertDonation(game, normalized);
  return json(res, 200, { ok: true, data: { id: row.provider_tx_id } });
}

async function handleWebhook(req, res, gameKey, secret, provider = "saweria") {
  const game = await getGame(gameKey);
  if (!game) return json(res, 404, { ok: false, error: "game_not_found" });
  if (secret !== game.webhook_secret)
    return json(res, 401, { ok: false, error: "unauthorized" });

  const body = await readBody(req);
  const normalized = normalizeDonation(body, provider);
  if (!normalized.providerTxId)
    return json(res, 400, { ok: false, error: "missing_donation_id" });
  if (normalized.amountRaw <= 0)
    return json(res, 400, { ok: false, error: "missing_amount" });

  const row = await upsertDonation(game, normalized);
  return json(res, 200, {
    ok: true,
    data: {
      id: row.provider_tx_id,
      unix_timestamp: Number(row.unix_timestamp),
      donator_name: row.donator_name,
      amount_raw: Number(row.amount_raw),
    },
  });
}

async function handleAdmin(req, res, url) {
  if (!requireAdmin(req))
    return json(res, 401, { ok: false, error: "unauthorized" });

  if (req.method === "GET" && url.pathname === "/admin/games") {
    const result = await pool.query(
      "SELECT * FROM games ORDER BY created_at DESC",
    );
    return json(res, 200, { ok: true, data: result.rows.map(gameResponse) });
  }

  if (req.method === "POST" && url.pathname === "/admin/games") {
    const body = await readBody(req);
    const gameKey = cleanString(
      body.gameKey || body.key || body.slug,
    ).toLowerCase();
    const name = cleanString(body.name, gameKey);
    if (!/^[a-z0-9][a-z0-9_-]{1,48}$/.test(gameKey)) {
      return json(res, 400, { ok: false, error: "invalid_game_key" });
    }
    const result = await pool.query(
      `
      INSERT INTO games (game_key, name, webhook_secret, roblox_secret, provider_link)
      VALUES ($1, $2, $3, $4, $5)
      ON CONFLICT (game_key)
      DO UPDATE SET name = EXCLUDED.name, provider_link = EXCLUDED.provider_link
      RETURNING *
      `,
      [
        gameKey,
        name,
        randomSecret("wh"),
        randomSecret("rbx"),
        cleanString(body.providerLink),
      ],
    );
    return json(res, 200, { ok: true, data: gameResponse(result.rows[0]) });
  }

  return json(res, 404, { ok: false, error: "not_found" });
}

async function route(req, res) {
  const url = new URL(
    req.url || "/",
    `http://${req.headers.host || "localhost"}`,
  );
  const parts = url.pathname.split("/").filter(Boolean);

  try {
    if (req.method === "GET" && url.pathname === "/health") {
      await pool.query("SELECT 1");
      return json(res, 200, { ok: true, now: Math.floor(Date.now() / 1000) });
    }

    if (parts[0] === "admin") return await handleAdmin(req, res, url);

    if (parts[0] === "game" && parts[1]) {
      if (req.method === "GET")
        return await handleGameGet(req, res, url, parts[1]);
      if (req.method === "POST")
        return await handleGamePost(req, res, url, parts[1]);
    }

    if (parts[0] === "webhook" && parts[2] && parts[3]) {
      if (parts[1] !== "saweria" && parts[1] !== "bagibagi") {
        return text(res, 404, "not found");
      }
      if (req.method !== "POST")
        return json(res, 405, { ok: false, error: "method_not_allowed" });
      return await handleWebhook(req, res, parts[2], parts[3], parts[1]);
    }

    return text(res, 404, "not found");
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    const status = message === "payload_too_large" ? 413 : 500;
    return json(res, status, { ok: false, error: message });
  }
}

await migrate();

http.createServer(route).listen(PORT, () => {
  console.log(`donation api listening on :${PORT}`);
});
