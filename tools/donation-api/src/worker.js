import {
  buildDailyLeaderboard,
  buildMergedLeaderboard,
  getGameByKey,
  getRobloxDonorCashProfile,
  lookupRobloxUser,
  upsertDonorLink,
} from "./game-data.js";
import { handleGameV2, V2_VERSION } from "./v2-routes.js";
import {
  handleAdminLicenseGet,
  handleAdminLicensePatch,
  licensePayload,
} from "./license-routes.js";

function buildCorsHeaders(req, env) {
  const configured = cleanString(env.CORS_ORIGIN);
  const origin = req.headers.get("origin");
  const allowOrigin = configured || origin || "*";
  return {
    "access-control-allow-origin": allowOrigin,
    "access-control-allow-methods": "GET,POST,PATCH,DELETE,OPTIONS",
    "access-control-allow-headers": "authorization,content-type",
    "access-control-max-age": "86400",
    vary: "Origin",
  };
}

function json(req, env, payload, status = 200, headers = {}) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      ...buildCorsHeaders(req, env),
      ...headers,
    },
  });
}

function cleanString(value, fallback = "") {
  if (value === undefined || value === null) return fallback;
  const cleaned = String(value).trim();
  return cleaned || fallback;
}

function toLc(v) {
  return cleanString(v).toLowerCase();
}

function randomToken(prefix) {
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);
  const encoded = btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
  return `${prefix}_${encoded}`;
}

function parseAmount(value) {
  if (typeof value === "number") return Math.max(0, Math.floor(value));
  const raw = cleanString(value);
  if (!raw) return 0;
  const digits = raw.replace(/[^\d]/g, "");
  return Number(digits || raw) || 0;
}

function parseTsMs(value) {
  if (typeof value === "number") return value > 1000000000000 ? value : value * 1000;
  const parsed = Date.parse(cleanString(value));
  return Number.isFinite(parsed) ? parsed : Date.now();
}

function nowIso() {
  return new Date().toISOString();
}

function assertAdmin(req, env) {
  const token = cleanString(env.ADMIN_TOKEN);
  if (!token) return false;
  return req.headers.get("authorization") === `Bearer ${token}`;
}

// Accepts either the master ADMIN_TOKEN (super admin) or the per-game
// admin_token stored on the games row. Empty game token falls through to
// the master check only, preserving existing access for games that have
// not been issued a scoped token yet.
function assertGameAdmin(req, env, game) {
  const masterToken = cleanString(env.ADMIN_TOKEN);
  const gameToken = cleanString(game?.admin_token);
  const provided = req.headers.get("authorization");
  if (masterToken && provided === `Bearer ${masterToken}`) return true;
  if (gameToken && provided === `Bearer ${gameToken}`) return true;
  return false;
}

async function parseJson(req) {
  try {
    return await req.json();
  } catch {
    return {};
  }
}

function gameEndpoints(game, baseUrl, socialBaseUrl) {
  const token = game.webhook_token;
  const key = game.game_key;
  const socialSecret = cleanString(game.social_secret);
  const socialRoot = cleanString(socialBaseUrl, "https://hazastudio-game-data-api.hazastudio.workers.dev").replace(
    /\/$/,
    "",
  );
  return {
    saweria_webhook: `${baseUrl}/webhook/saweria/${key}/${token}`,
    bagibagi_webhook: `${baseUrl}/webhook/bagibagi/${key}/${token}`,
    roblox_base: `${baseUrl}/game/${key}`,
    roblox_api_url: `${baseUrl}/game/${key}`,
    roblox_secret: game.secret,
    roblox_v2_base: `${baseUrl}/game/${key}/v2`,
    roblox_poll: `${baseUrl}/game/${game.game_key}?secret=${game.secret}`,
    social_api_base: `${socialRoot}/game/${key}`,
    social_health: `${socialRoot}/health`,
    social_friends_example: `${socialRoot}/game/${key}/social/{userId}?secret=${socialSecret}`,
    social_groups_example: `${socialRoot}/game/${key}/groups/{userId}?secret=${socialSecret}&groupId={groupId}`,
  };
}

function getSocialBaseUrl(env) {
  return cleanString(env.SOCIAL_API_BASE_URL, "https://hazastudio-game-data-api.hazastudio.workers.dev").replace(
    /\/$/,
    "",
  );
}

function clubKitConfigLines(game, baseUrl, socialBaseUrl) {
  const key = game.game_key;
  const socialRoot = cleanString(socialBaseUrl, "https://hazastudio-game-data-api.hazastudio.workers.dev").replace(
    /\/$/,
    "",
  );
  return {
    donation_api_url: `ApiUrl = "${baseUrl}/game/${key}",`,
    donation_api_secret: `Secrets.DonationApiSecret = "${game.secret}",`,
    social_game_key: `GameKey = "${key}",`,
    social_api_secret: `Secrets.GameDataApiSecret = "${cleanString(game.social_secret)}",`,
    social_base_url: socialRoot,
  };
}

function gamePayload(game, baseUrl, socialBaseUrl) {
  return {
    id: game.game_key,
    display_name: game.name,
    secret: game.secret,
    social_secret: cleanString(game.social_secret),
    webhook_token: game.webhook_token,
    admin_token_set: Boolean(cleanString(game.admin_token)),
    saweria_link: game.provider_link || "",
    created_at: Math.floor(Date.parse(game.created_at || nowIso()) / 1000),
    endpoints: gameEndpoints(game, baseUrl, socialBaseUrl),
    clubkit: clubKitConfigLines(game, baseUrl, socialBaseUrl),
    license: licensePayload(game),
  };
}

async function ensureSocialSecrets(db) {
  const rows = await db
    .prepare("SELECT id FROM games WHERE social_secret IS NULL OR trim(social_secret) = ''")
    .all();
  for (const row of rows.results || []) {
    await db.prepare("UPDATE games SET social_secret = ? WHERE id = ?").bind(randomToken("soc"), row.id).run();
  }
}

function normalizeDonation(input, provider = "saweria") {
  const root = input && typeof input === "object" ? input : {};
  const data = root.data && typeof root.data === "object" ? root.data : root;
  const defaultDonor = provider === "bagibagi" ? "Bagi-Bagi Donor" : "Saweria Donor";
  const saweriaName = cleanString(
    data.donator_name ||
      data.donor_name ||
      data.saweria_name ||
      data.bagibagi_name ||
      data.name ||
      data.username ||
      data.donor,
    defaultDonor,
  );
  const donationAt = new Date(
    parseTsMs(data.created_at || data.createdAt || data.paid_at || data.timestamp || data.updated_at || root.t),
  ).toISOString();
  const amount = parseAmount(data.amount_raw || data.amount || data.total || data.nominal || data.value);
  let providerTxId = cleanString(data.id || data.transaction_id || data.payment_id || data.order_id || data.invoice_id);
  if (!providerTxId && provider === "bagibagi") {
    providerTxId = `bb:${saweriaName.toLowerCase()}:${amount}:${donationAt}`;
  }
  if (!providerTxId) {
    providerTxId = `${saweriaName}:${amount}:${donationAt}`;
  }
  return {
    providerTxId,
    saweriaName,
    saweriaNameLc: saweriaName.toLowerCase(),
    amount,
    message: cleanString(data.message || data.note || data.support_message || data.comment),
    status: cleanString(data.status, "success").toLowerCase(),
    donationAt,
    rawPayload: JSON.stringify(input || {}),
  };
}

function isSaweriaTestDonation(donation) {
  return donation.providerTxId === "00000000-0000-0000-0000-000000000000";
}

async function checkHealthDb(env) {
  await env.DB.prepare("SELECT 1").first();
}

async function handleHealth(req, env) {
  await checkHealthDb(env);
  return json(req, env, {
    ok: true,
    version: "1.0.0",
    v2_version: V2_VERSION,
    ts: Math.floor(Date.now() / 1000),
  });
}

// Resolve the caller's authorization header into the games it can manage.
// Master ADMIN_TOKEN sees every game; a game-scoped admin_token sees only
// its own game. Used by the admin panel on connect so it does not have to
// hit /admin/games (which is master-only) before knowing the scope.
async function handleAdminWhoami(req, env, baseUrl) {
  const socialBaseUrl = getSocialBaseUrl(env);
  const provided = req.headers.get("authorization") || "";
  const match = provided.match(/^Bearer (.+)$/);
  const bearer = match ? match[1] : "";
  if (!bearer) return json(req, env, { ok: false, error: "unauthorized" }, 401);

  await ensureSocialSecrets(env.DB);

  const masterToken = cleanString(env.ADMIN_TOKEN);
  if (masterToken && bearer === masterToken) {
    const rows = await env.DB.prepare("SELECT * FROM games ORDER BY id DESC").all();
    return json(req, env, {
      ok: true,
      scope: "master",
      games: (rows.results || []).map((g) => gamePayload(g, baseUrl, socialBaseUrl)),
    });
  }

  const game = await env.DB.prepare("SELECT * FROM games WHERE admin_token = ? LIMIT 1").bind(bearer).first();
  if (!game) return json(req, env, { ok: false, error: "unauthorized" }, 401);

  return json(req, env, {
    ok: true,
    scope: "game",
    games: [gamePayload(game, baseUrl, socialBaseUrl)],
  });
}

async function handleAdmin(req, env, url, parts) {
  const baseUrl = cleanString(env.PUBLIC_BASE_URL, new URL(req.url).origin).replace(/\/$/, "");
  const socialBaseUrl = getSocialBaseUrl(env);
  const isGamesCollection = url.pathname === "/admin/games" || url.pathname === "/admin/games/";

  // Global endpoints: master ADMIN_TOKEN only.
  if (isGamesCollection) {
    if (!assertAdmin(req, env)) return json(req, env, { ok: false, error: "unauthorized" }, 401);

    if (req.method === "POST" && url.pathname === "/admin/games") {
      const body = await parseJson(req);
      const gameKey = toLc(body.id || body.gameKey || body.key || body.slug);
      if (!/^[a-z0-9][a-z0-9_-]{1,48}$/.test(gameKey))
        return json(req, env, { ok: false, error: "invalid_game_key" }, 422);
      const name = cleanString(body.display_name || body.name, gameKey);
      const providerLink = cleanString(body.saweria_link || body.providerLink);
      const adminToken = randomToken("adm");
      const socialSecret = randomToken("soc");
      // On conflict, preserve the existing admin_token to avoid invalidating a
      // token that has already been shared with the game owner. Name and link
      // are still updated to match previous behaviour.
      await env.DB.prepare(
        `INSERT INTO games (game_key, name, webhook_token, secret, provider_link, admin_token, social_secret)
         VALUES (?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(game_key) DO UPDATE SET name = excluded.name, provider_link = excluded.provider_link`,
      )
        .bind(gameKey, name, randomToken("wh"), randomToken("rbx"), providerLink, adminToken, socialSecret)
        .run();
      await ensureSocialSecrets(env.DB);
      const game = await getGameByKey(env.DB, gameKey);
      return json(
        req,
        env,
        {
          ok: true,
          game: gamePayload(game, baseUrl, socialBaseUrl),
          endpoints: gameEndpoints(game, baseUrl, socialBaseUrl),
          // Raw admin_token is returned ONCE on create. Subsequent reads only
          // surface a boolean via gamePayload.admin_token_set.
          admin_token: cleanString(game.admin_token) || adminToken,
        },
        201,
      );
    }

    if (req.method === "GET" && url.pathname === "/admin/games") {
      await ensureSocialSecrets(env.DB);
      const rows = await env.DB.prepare("SELECT * FROM games ORDER BY id DESC").all();
      return json(req, env, {
        ok: true,
        games: (rows.results || []).map((g) => gamePayload(g, baseUrl, socialBaseUrl)),
      });
    }

    return json(req, env, { ok: false, error: "not_found" }, 404);
  }

  // Per-game endpoints: master OR the game's own admin_token.
  if (parts[1] !== "games" || !parts[2]) return json(req, env, { ok: false, error: "not_found" }, 404);
  const gameKey = parts[2];
  const game = await getGameByKey(env.DB, gameKey);
  if (!game) return json(req, env, { ok: false, error: "game_not_found" }, 404);
  if (!assertGameAdmin(req, env, game)) return json(req, env, { ok: false, error: "unauthorized" }, 401);

  if (req.method === "GET" && parts.length === 3)
    return json(req, env, { ok: true, game: gamePayload(game, baseUrl, socialBaseUrl) });

  if (req.method === "PATCH" && parts.length === 3) {
    const body = await parseJson(req);
    const name = cleanString(body.display_name || body.name, game.name);
    const providerLink = cleanString(body.saweria_link || body.providerLink, game.provider_link || "");
    await env.DB.prepare("UPDATE games SET name = ?, provider_link = ? WHERE id = ?")
      .bind(name, providerLink, game.id)
      .run();
    const next = await getGameByKey(env.DB, gameKey);
    return json(req, env, { ok: true, game: gamePayload(next, baseUrl, socialBaseUrl) });
  }

  if (parts[3] === "license") {
    if (req.method === "GET" && parts.length === 4) {
      return handleAdminLicenseGet(req, env, game, json);
    }
    if (req.method === "PATCH" && parts.length === 4) {
      const body = await parseJson(req);
      return handleAdminLicensePatch(req, env, gameKey, game, json, body);
    }
  }

  if (req.method === "POST" && parts[3] === "rotate-secret") {
    const secret = randomToken("rbx");
    await env.DB.prepare("UPDATE games SET secret = ? WHERE id = ?").bind(secret, game.id).run();
    const next = await getGameByKey(env.DB, gameKey);
    return json(req, env, {
      ok: true,
      game: gamePayload(next, baseUrl, socialBaseUrl),
      endpoints: gameEndpoints(next, baseUrl, socialBaseUrl),
    });
  }

  if (req.method === "POST" && parts[3] === "rotate-social-secret") {
    const socialSecret = randomToken("soc");
    await env.DB.prepare("UPDATE games SET social_secret = ? WHERE id = ?").bind(socialSecret, game.id).run();
    const next = await getGameByKey(env.DB, gameKey);
    return json(req, env, {
      ok: true,
      game: gamePayload(next, baseUrl, socialBaseUrl),
      endpoints: gameEndpoints(next, baseUrl, socialBaseUrl),
    });
  }

  if (req.method === "POST" && parts[3] === "rotate-webhook") {
    const token = randomToken("wh");
    await env.DB.prepare("UPDATE games SET webhook_token = ? WHERE id = ?").bind(token, game.id).run();
    const next = await getGameByKey(env.DB, gameKey);
    return json(req, env, {
      ok: true,
      game: gamePayload(next, baseUrl, socialBaseUrl),
      endpoints: gameEndpoints(next, baseUrl, socialBaseUrl),
    });
  }

  if (req.method === "POST" && parts[3] === "rotate-admin-token") {
    const newAdminToken = randomToken("adm");
    await env.DB.prepare("UPDATE games SET admin_token = ? WHERE id = ?").bind(newAdminToken, game.id).run();
    const next = await getGameByKey(env.DB, gameKey);
    return json(req, env, {
      ok: true,
      game: gamePayload(next, baseUrl, socialBaseUrl),
      // Raw admin_token is returned ONCE on rotation. Subsequent reads only
      // surface a boolean via gamePayload.admin_token_set.
      admin_token: newAdminToken,
    });
  }

  if (parts[3] === "seed") return handleAdminSeed(req, env, parts, game);
  if (parts[3] === "import-donations") return handleAdminImportDonations(req, env, game);
  if (parts[3] === "donations") return handleAdminDonations(req, env, url, game);
  if (parts[3] === "links") return handleAdminLinks(req, env, parts, game);
  if (parts[3] === "rankings") return handleAdminRankings(req, env, url, parts, game);
  if (parts[3] === "test-notification") return handleAdminTestNotification(req, env, game);
  if (parts[3] === "test-api") return handleAdminTestApi(req, env, url, game);
  if (parts[3] === "webhook-events") return handleAdminWebhookEvents(req, env, url, game);
  if (parts[3] === "daily-leaderboard") return handleAdminDailyLeaderboard(req, env, url, game);
  if (parts[3] === "bulk-void") return handleAdminBulkVoid(req, env, game);
  if (parts[3] === "bulk-link") return handleAdminBulkLink(req, env, game);
  if (parts[3] === "stats") return handleAdminGameStats(req, env, url, game);
  if (parts[3] === "generate-link") return handleAdminGenerateLink(req, env, url, game);
  if (parts[3] === "donor" && parts[4]) return handleAdminDonorDetail(req, env, parts, game);

  return json(req, env, { ok: false, error: "not_found" }, 404);
}

async function handleAdminSeed(req, env, parts, game) {
  if (req.method === "GET" && parts.length === 4) {
    const rows = await env.DB.prepare(
      "SELECT id, saweria_name, total_amount, rank_hint, note FROM legacy_seed_entries WHERE game_id = ? ORDER BY total_amount DESC",
    )
      .bind(game.id)
      .all();
    return json(req, env, { ok: true, entries: rows.results || [] });
  }

  if (req.method === "POST" && parts.length === 4) {
    const body = await parseJson(req);
    const saweriaName = cleanString(body.saweria_name);
    const totalAmount = Math.max(0, parseAmount(body.total_amount));
    if (!saweriaName || totalAmount < 0) return json(req, env, { ok: false, error: "validation_failed" }, 422);
    await env.DB.prepare(
      `INSERT INTO legacy_seed_entries (game_id, saweria_name, saweria_name_lc, total_amount, rank_hint, note)
       VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(game_id, saweria_name_lc) DO UPDATE SET
         total_amount = excluded.total_amount,
         rank_hint = excluded.rank_hint,
         note = excluded.note,
         updated_at = (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))`,
    )
      .bind(
        game.id,
        saweriaName,
        saweriaName.toLowerCase(),
        totalAmount,
        body.rank_hint ?? null,
        cleanString(body.note),
      )
      .run();
    const row = await env.DB.prepare(
      "SELECT id, saweria_name, total_amount, rank_hint, note FROM legacy_seed_entries WHERE game_id = ? AND saweria_name_lc = ?",
    )
      .bind(game.id, saweriaName.toLowerCase())
      .first();
    return json(req, env, { ok: true, entry: row }, 201);
  }

  if (parts[4] && req.method === "PATCH") {
    const body = await parseJson(req);
    await env.DB.prepare(
      `UPDATE legacy_seed_entries
       SET total_amount = COALESCE(?, total_amount),
           rank_hint = COALESCE(?, rank_hint),
           note = COALESCE(?, note),
           updated_at = (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
       WHERE game_id = ? AND id = ?`,
    )
      .bind(body.total_amount ?? null, body.rank_hint ?? null, body.note ?? null, game.id, Number(parts[4]))
      .run();
    const row = await env.DB.prepare(
      "SELECT id, saweria_name, total_amount, rank_hint, note FROM legacy_seed_entries WHERE game_id = ? AND id = ?",
    )
      .bind(game.id, Number(parts[4]))
      .first();
    if (!row) return json(req, env, { ok: false, error: "not_found" }, 404);
    return json(req, env, { ok: true, entry: row });
  }

  if (parts[4] && req.method === "DELETE") {
    await env.DB.prepare("DELETE FROM legacy_seed_entries WHERE game_id = ? AND id = ?")
      .bind(game.id, Number(parts[4]))
      .run();
    return json(req, env, { ok: true });
  }

  return json(req, env, { ok: false, error: "not_found" }, 404);
}

async function handleAdminImportDonations(req, env, game) {
  if (req.method !== "POST") return json(req, env, { ok: false, error: "method_not_allowed" }, 405);
  const body = await parseJson(req);
  const items = Array.isArray(body.donations) ? body.donations : [];
  if (!items.length) return json(req, env, { ok: false, error: "validation_failed" }, 422);
  if (items.length > 500) return json(req, env, { ok: false, error: "too_many_rows_max_500" }, 422);

  const statements = [];
  let skipped = 0;
  for (const item of items) {
    const providerTxId = cleanString(item.provider_tx_id || item.id);
    const saweriaName = cleanString(item.saweria_name || item.donator_name) || "Saweria Donor";
    const amount = parseAmount(item.amount);
    const donationAt = cleanString(item.donation_at) || nowIso();
    const message = cleanString(item.message);
    const status = cleanString(item.status, "success").toLowerCase();
    const rawPayload = JSON.stringify(
      item.raw_payload && typeof item.raw_payload === "object" ? item.raw_payload : item,
    );
    if (!providerTxId || amount <= 0) {
      skipped += 1;
      continue;
    }
    statements.push(
      env.DB.prepare(
        `INSERT INTO donations (
           game_id, provider_tx_id, saweria_name, saweria_name_lc, amount, message, status, donation_at, raw_payload
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(game_id, provider_tx_id) DO UPDATE SET
           saweria_name = excluded.saweria_name,
           saweria_name_lc = excluded.saweria_name_lc,
           amount = excluded.amount,
           message = excluded.message,
           status = excluded.status,
           donation_at = excluded.donation_at,
           raw_payload = excluded.raw_payload`,
      ).bind(
        game.id,
        providerTxId,
        saweriaName,
        saweriaName.toLowerCase(),
        amount,
        message,
        status,
        donationAt,
        rawPayload,
      ),
    );
  }

  const chunkSize = 40;
  for (let index = 0; index < statements.length; index += chunkSize) {
    await env.DB.batch(statements.slice(index, index + chunkSize));
  }

  return json(req, env, {
    ok: true,
    imported: statements.length,
    skipped,
  });
}

async function handleAdminDonations(req, env, url, game) {
  if (req.method !== "GET") return json(req, env, { ok: false, error: "not_found" }, 404);
  const limit = Math.max(1, Math.min(200, Number(url.searchParams.get("limit") || 50)));
  const offset = Math.max(0, Number(url.searchParams.get("offset") || 0));
  const voided = cleanString(url.searchParams.get("voided"), "0");
  const where = ["game_id = ?"];
  const bind = [game.id];
  if (voided === "0") where.push("is_voided = 0");
  if (voided === "1") where.push("is_voided = 1");
  const filterName = toLc(url.searchParams.get("saweria_name"));
  if (filterName) {
    where.push("saweria_name_lc = ?");
    bind.push(filterName);
  }
  const since = Number(url.searchParams.get("since") || 0);
  if (since > 0) {
    where.push("CAST(strftime('%s', received_at) AS INTEGER) >= ?");
    bind.push(since);
  }
  const whereSql = where.join(" AND ");
  const rows = await env.DB.prepare(
    `SELECT id, saweria_name, amount, message, status, is_voided, voided_at, voided_reason, donation_at, received_at
       FROM donations
       WHERE ${whereSql}
       ORDER BY received_at DESC, id DESC
       LIMIT ? OFFSET ?`,
  )
    .bind(...bind, limit, offset)
    .all();
  const totalRow = await env.DB.prepare(`SELECT COUNT(*) AS c FROM donations WHERE ${whereSql}`)
    .bind(...bind)
    .first();
  const total = Number(totalRow?.c || 0);
  return json(req, env, {
    ok: true,
    donations: rows.results || [],
    total,
    has_more: offset + limit < total,
  });
}

async function handleAdminLinks(req, env, parts, game) {
  if (req.method === "GET" && parts.length === 4) {
    const rows = await env.DB.prepare(
      "SELECT id, saweria_name, roblox_username, roblox_user_id, roblox_display_name, updated_at FROM donor_links WHERE game_id = ? ORDER BY id DESC",
    )
      .bind(game.id)
      .all();
    return json(req, env, { ok: true, links: rows.results || [] });
  }

  if (req.method === "POST" && parts.length === 4) {
    const body = await parseJson(req);
    const saweriaName = cleanString(body.saweria_name);
    const robloxUsername = cleanString(body.roblox_username).replace(/^@/, "");
    if (!saweriaName || !robloxUsername) return json(req, env, { ok: false, error: "validation_failed" }, 422);
    const resolved = await lookupRobloxUser(robloxUsername);
    const finalUsername = resolved?.username || robloxUsername;
    const robloxUserId = resolved?.userId ?? body.roblox_user_id ?? null;
    const robloxDisplayName = resolved?.displayName || "";
    await env.DB.prepare(
      `INSERT INTO donor_links (game_id, saweria_name, saweria_name_lc, roblox_username, roblox_user_id, roblox_display_name)
       VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(game_id, saweria_name_lc) DO UPDATE SET
         saweria_name = excluded.saweria_name,
         roblox_username = excluded.roblox_username,
         roblox_user_id = excluded.roblox_user_id,
         roblox_display_name = excluded.roblox_display_name,
         updated_at = (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))`,
    )
      .bind(game.id, saweriaName, saweriaName.toLowerCase(), finalUsername, robloxUserId, robloxDisplayName)
      .run();
    const row = await env.DB.prepare(
      "SELECT id, saweria_name, roblox_username, roblox_user_id, roblox_display_name, updated_at FROM donor_links WHERE game_id = ? AND saweria_name_lc = ?",
    )
      .bind(game.id, saweriaName.toLowerCase())
      .first();
    return json(req, env, { ok: true, link: row, resolved: Boolean(resolved) }, 201);
  }

  if (req.method === "DELETE" && parts[4]) {
    await env.DB.prepare("DELETE FROM donor_links WHERE game_id = ? AND id = ?").bind(game.id, Number(parts[4])).run();
    return json(req, env, { ok: true });
  }

  return json(req, env, { ok: false, error: "not_found" }, 404);
}

async function buildAdminRankings(db, gameId, limit, offset, searchQuery) {
  const search = toLc(searchQuery);
  const searchLike = `%${search}%`;
  const successStatuses = "'success','paid','completed','settlement'";

  const rankings = await db
    .prepare(
      `WITH live AS (
         SELECT
           saweria_name_lc,
           MAX(saweria_name) AS saweria_name,
           SUM(CASE WHEN status IN (${successStatuses}) AND is_voided = 0 THEN amount ELSE 0 END) AS live_total,
           MAX(CASE WHEN status IN (${successStatuses}) AND is_voided = 0 THEN CAST(strftime('%s', donation_at) AS INTEGER) ELSE 0 END) AS last_donation_at
         FROM donations
         WHERE game_id = ?
         GROUP BY saweria_name_lc
       ),
       seed AS (
         SELECT
           saweria_name_lc,
           MAX(saweria_name) AS saweria_name,
           SUM(total_amount) AS seed_total
         FROM legacy_seed_entries
         WHERE game_id = ?
         GROUP BY saweria_name_lc
       ),
       keys AS (
         SELECT saweria_name_lc FROM live
         UNION
         SELECT saweria_name_lc FROM seed
       ),
       merged AS (
         SELECT
           k.saweria_name_lc,
           COALESCE(l.saweria_name, s.saweria_name) AS saweria_name,
           COALESCE(l.live_total, 0) AS live_total,
           COALESCE(s.seed_total, 0) AS seed_total,
           COALESCE(l.last_donation_at, 0) AS last_donation_at,
           COALESCE(l.live_total, 0) + COALESCE(s.seed_total, 0) AS total_amount
         FROM keys k
         LEFT JOIN live l ON l.saweria_name_lc = k.saweria_name_lc
         LEFT JOIN seed s ON s.saweria_name_lc = k.saweria_name_lc
       )
       SELECT
         saweria_name_lc,
         saweria_name,
         live_total,
         seed_total,
         total_amount,
         last_donation_at
       FROM merged
       WHERE (? = '' OR saweria_name_lc LIKE ?)
       ORDER BY total_amount DESC, last_donation_at ASC, saweria_name_lc ASC
       LIMIT ? OFFSET ?`,
    )
    .bind(gameId, gameId, search, searchLike, limit, offset)
    .all();

  const countRow = await db
    .prepare(
      `WITH live AS (
         SELECT saweria_name_lc
         FROM donations
         WHERE game_id = ?
         GROUP BY saweria_name_lc
       ),
       seed AS (
         SELECT saweria_name_lc
         FROM legacy_seed_entries
         WHERE game_id = ?
         GROUP BY saweria_name_lc
       ),
       keys AS (
         SELECT saweria_name_lc FROM live
         UNION
         SELECT saweria_name_lc FROM seed
       )
       SELECT COUNT(*) AS c
       FROM keys
       WHERE (? = '' OR saweria_name_lc LIKE ?)`,
    )
    .bind(gameId, gameId, search, searchLike)
    .first();

  const rows = (rankings.results || []).map((row, index) => ({
    rank: offset + index + 1,
    saweria_name_lc: row.saweria_name_lc,
    saweria_name: row.saweria_name,
    live_total: Number(row.live_total) || 0,
    seed_total: Number(row.seed_total) || 0,
    total_amount: Number(row.total_amount) || 0,
    last_donation_at: Number(row.last_donation_at) || 0,
  }));

  return {
    rankings: rows,
    total: Number(countRow?.c || 0),
  };
}

async function handleAdminRankings(req, env, url, parts, game) {
  if (req.method === "GET" && parts.length === 4) {
    const limit = Math.max(1, Math.min(1000, Number(url.searchParams.get("limit") || 500)));
    const offset = Math.max(0, Number(url.searchParams.get("offset") || 0));
    const q = cleanString(url.searchParams.get("q"));
    const payload = await buildAdminRankings(env.DB, game.id, limit, offset, q);
    return json(req, env, {
      ok: true,
      rankings: payload.rankings,
      total: payload.total,
      has_more: offset + payload.rankings.length < payload.total,
    });
  }

  if (req.method === "POST" && parts[4] === "adjust") {
    const body = await parseJson(req);
    const saweriaName = cleanString(body.saweria_name || body.donor_name || body.provider_name);
    const rawDelta = Number(body.delta_amount);
    const deltaAmount = Number.isFinite(rawDelta) ? Math.trunc(rawDelta) : 0;
    if (!saweriaName || deltaAmount === 0 || Math.abs(deltaAmount) > 1000000000) {
      return json(req, env, { ok: false, error: "validation_failed" }, 422);
    }

    const saweriaNameLc = saweriaName.toLowerCase();
    const current = await env.DB.prepare(
      "SELECT id, total_amount, note FROM legacy_seed_entries WHERE game_id = ? AND saweria_name_lc = ? LIMIT 1",
    )
      .bind(game.id, saweriaNameLc)
      .first();

    const providedNote = cleanString(body.note);
    if (current) {
      const nextTotal = Math.max(0, Number(current.total_amount || 0) + deltaAmount);
      if (nextTotal === 0) {
        await env.DB.prepare("DELETE FROM legacy_seed_entries WHERE id = ?").bind(current.id).run();
      } else {
        const nextNote = providedNote || cleanString(current.note);
        await env.DB.prepare(
          `UPDATE legacy_seed_entries
             SET total_amount = ?, note = ?, updated_at = (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
             WHERE id = ?`,
        )
          .bind(nextTotal, nextNote, current.id)
          .run();
      }
    } else {
      const startingTotal = Math.max(0, deltaAmount);
      if (startingTotal === 0) {
        return json(req, env, { ok: false, error: "cannot_reduce_missing_donor" }, 422);
      }
      await env.DB.prepare(
        `INSERT INTO legacy_seed_entries (game_id, saweria_name, saweria_name_lc, total_amount, note)
           VALUES (?, ?, ?, ?, ?)`,
      )
        .bind(game.id, saweriaName, saweriaNameLc, startingTotal, providedNote || "manual_adjustment")
        .run();
    }

    const updated = await env.DB.prepare(
      "SELECT id, saweria_name, total_amount, rank_hint, note FROM legacy_seed_entries WHERE game_id = ? AND saweria_name_lc = ?",
    )
      .bind(game.id, saweriaNameLc)
      .first();

    return json(req, env, {
      ok: true,
      adjustment: {
        saweria_name: saweriaName,
        delta_amount: deltaAmount,
      },
      seed_entry: updated,
    });
  }

  return json(req, env, { ok: false, error: "not_found" }, 404);
}

async function handleAdminDonationPatch(req, env, donationId) {
  if (req.method !== "PATCH") return json(req, env, { ok: false, error: "not_found" }, 404);
  // Resolve the donation's game first so we can apply per-game auth.
  const ownerRow = await env.DB.prepare(
    "SELECT g.admin_token FROM donations d JOIN games g ON g.id = d.game_id WHERE d.id = ? LIMIT 1",
  )
    .bind(donationId)
    .first();
  if (!ownerRow) return json(req, env, { ok: false, error: "donation_not_found" }, 404);
  if (!assertGameAdmin(req, env, ownerRow)) return json(req, env, { ok: false, error: "unauthorized" }, 401);
  const body = await parseJson(req);
  const isVoided = Boolean(body.is_voided);
  if (isVoided) {
    await env.DB.prepare("UPDATE donations SET is_voided = 1, voided_at = ?, voided_reason = ? WHERE id = ?")
      .bind(nowIso(), cleanString(body.voided_reason, "manual_void"), donationId)
      .run();
  } else {
    await env.DB.prepare("UPDATE donations SET is_voided = 0, voided_at = NULL, voided_reason = '' WHERE id = ?")
      .bind(donationId)
      .run();
  }
  const row = await env.DB.prepare("SELECT id, is_voided, voided_at, voided_reason FROM donations WHERE id = ?")
    .bind(donationId)
    .first();
  if (!row) return json(req, env, { ok: false, error: "not_found" }, 404);
  return json(req, env, { ok: true, donation: row });
}

async function handleGame(req, env, url, gameKey) {
  const game = await getGameByKey(env.DB, gameKey);
  if (!game) return json(req, env, { ok: false, error: "game_not_found" }, 404);
  if (cleanString(url.searchParams.get("secret")) !== game.secret)
    return json(req, env, { ok: false, error: "invalid_secret" }, 403);

  if (req.method === "POST") {
    const body = await parseJson(req);
    const action = cleanString(body.action).toLowerCase();
    if (action === "namemap_set") {
      const saweriaName = cleanString(
        body.saweria_name || body.provider_name || body.bagibagi_name || body.donator_name || body.donor_name,
      );
      const robloxUsername = cleanString(body.roblox_username).replace(/^@/, "");
      if (!saweriaName || !robloxUsername) {
        return json(req, env, { ok: false, error: "validation_failed" }, 422);
      }
      const link = await upsertDonorLink(env.DB, game.id, saweriaName, robloxUsername);
      return json(req, env, { ok: true, resolved: link.resolved });
    }
    return json(req, env, { ok: false, error: "unknown_action" }, 400);
  }

  if (req.method !== "GET") return json(req, env, { ok: false, error: "method_not_allowed" }, 405);

  const action = cleanString(url.searchParams.get("action"), "ping").toLowerCase();
  if (action === "ping")
    return json(req, env, {
      ok: true,
      server_time: Math.floor(Date.now() / 1000),
    });

  if (action === "leaderboard") {
    const limit = Math.max(1, Math.min(50, Number(url.searchParams.get("limit") || 10)));
    const boardType = toLc(url.searchParams.get("type") || "alltime");
    const leaderboard =
      boardType === "daily"
        ? await buildDailyLeaderboard(env.DB, game.id, limit)
        : await buildMergedLeaderboard(env.DB, game.id, limit);
    const normalized = leaderboard.map((entry, index) => ({
      rank: index + 1,
      saweria_name: entry.saweria_name,
      donor_name: entry.saweria_name,
      provider_name: entry.saweria_name,
      total: Number(entry.total_amount) || 0,
      last_at: entry.last_donation_at ? new Date((Number(entry.last_donation_at) || 0) * 1000).toISOString() : "",
    }));
    return json(req, env, { ok: true, data: normalized, leaderboard }, 200, {
      "cache-control": "public, max-age=10",
    });
  }

  if (action === "notifications") {
    const limit = Math.max(1, Math.min(100, Number(url.searchParams.get("limit") || 10)));
    const since = url.searchParams.get("since") || "";
    // Normalize `since` to ISO string for SQL comparison.
    // Two formats are supported:
    //   1. Unix timestamp (old games, e.g. Gudang Timur): "1749200101"
    //   2. ISO 8601 (NUWA): "2026-06-06T12:00:01.000Z"
    //
    // Precision problem: received_at is stored with milliseconds (e.g. 12:00:01.500Z)
    // but unix_timestamp in the response is truncated to whole seconds. When the game
    // sends this truncated value back as `since`, converting directly to ISO gives
    // "12:00:01.000Z". The query `received_at > "12:00:01.000Z"` STILL matches the
    // donation at "12:00:01.500Z", causing the same donation to be returned on every
    // poll = infinite notification loop.
    //
    // Fix: add a cursor advance offset when converting — 1s for Unix timestamps,
    // 1ms for ISO strings — so the filter cleanly skips past the last donation.
    let sinceDate = since;
    if (/^\d+$/.test(since)) {
      // Unix timestamp (whole seconds, all-digits): advance 1 second
      sinceDate = new Date((Number(since) + 1) * 1000).toISOString();
    } else if (since) {
      // ISO string: advance 1 millisecond to skip past sub-second precision
      sinceDate = new Date(Date.parse(since) + 1).toISOString();
    }
    const rows = await env.DB.prepare(
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
               AND d.received_at > ?
             ORDER BY d.received_at ASC, d.id ASC
             LIMIT ?`,
    )
      .bind(game.id, sinceDate, limit)
      .all();
    const notifications = (rows.results || []).map((r) => {
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
      };
    });
    return json(req, env, { ok: true, data: notifications, notifications }, 200, {
      "cache-control": "public, max-age=2",
    });
  }

  if (action === "namemap") {
    const rows = await env.DB.prepare(
      "SELECT saweria_name, roblox_user_id, roblox_username, roblox_display_name FROM donor_links WHERE game_id = ? ORDER BY id DESC",
    )
      .bind(game.id)
      .all();
    return json(req, env, {
      ok: true,
      data: rows.results || [],
      links: rows.results || [],
    });
  }

  if (action === "donor_profile") {
    const userId = Number(url.searchParams.get("user_id") || 0);
    const username = cleanString(url.searchParams.get("username"));
    if (userId <= 0 && username === "") {
      return json(req, env, { ok: false, error: "validation_failed" }, 422);
    }
    const cashProfile = await getRobloxDonorCashProfile(env.DB, game.id, userId, username);
    return json(
      req,
      env,
      {
        ok: true,
        user_id: userId,
        username,
        cash_total: cashProfile.cash_total,
        cash_rank: cashProfile.cash_rank,
      },
      200,
      { "cache-control": "public, max-age=30" },
    );
  }

  return json(req, env, { ok: false, error: "unknown_action" }, 400);
}

async function handleWebhook(req, env, gameKey, webhookToken, provider = "saweria") {
  if (req.method !== "POST") return json(req, env, { ok: false, error: "method_not_allowed" }, 405);
  const game = await getGameByKey(env.DB, gameKey);
  if (!game) return json(req, env, { ok: false, error: "game_not_found" }, 404);
  if (webhookToken !== game.webhook_token) return json(req, env, { ok: false, error: "invalid_webhook_token" }, 403);

  const body = await parseJson(req);
  const eventInsert = await env.DB.prepare(
    "INSERT INTO webhook_events (game_id, raw_payload, processed) VALUES (?, ?, 0)",
  )
    .bind(game.id, JSON.stringify({ provider, payload: body || {} }))
    .run();
  const eventId = Number(eventInsert.meta.last_row_id);

  try {
    const donation = normalizeDonation(body, provider);
    if (!donation.providerTxId) return json(req, env, { ok: false, error: "missing_donation_id" }, 422);
    if (donation.amount <= 0) return json(req, env, { ok: false, error: "missing_amount" }, 422);
    const shouldReplayNotification = isSaweriaTestDonation(donation);
    const write = await env.DB.prepare(
      `INSERT INTO donations (
         game_id, provider_tx_id, saweria_name, saweria_name_lc, amount, message, status, donation_at, raw_payload
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(game_id, provider_tx_id) DO UPDATE SET
         saweria_name = excluded.saweria_name,
         saweria_name_lc = excluded.saweria_name_lc,
         amount = excluded.amount,
         message = excluded.message,
         status = excluded.status,
         donation_at = excluded.donation_at,
         raw_payload = excluded.raw_payload,
         received_at = CASE
           WHEN ? = 1 THEN (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
           ELSE donations.received_at
         END`,
    )
      .bind(
        game.id,
        donation.providerTxId,
        donation.saweriaName,
        donation.saweriaNameLc,
        donation.amount,
        donation.message,
        donation.status,
        donation.donationAt,
        donation.rawPayload,
        shouldReplayNotification ? 1 : 0,
      )
      .run();
    const donationRow = await env.DB.prepare(
      "SELECT id FROM donations WHERE game_id = ? AND provider_tx_id = ? LIMIT 1",
    )
      .bind(game.id, donation.providerTxId)
      .first();
    const donationId = Number(donationRow?.id || write.meta.last_row_id || 0);
    await env.DB.prepare("UPDATE webhook_events SET processed = 1, donation_id = ? WHERE id = ?")
      .bind(donationId || null, eventId)
      .run();
    return json(req, env, { ok: true, donation_id: donationId || null });
  } catch (err) {
    await env.DB.prepare("UPDATE webhook_events SET processed = 0, error = ? WHERE id = ?")
      .bind(err instanceof Error ? err.message : String(err), eventId)
      .run();
    throw err;
  }
}

// ── Admin: New Endpoints ─────────────────────────────────────────────

/**
 * POST /admin/games/:key/test-notification
 * Inject a fake donation. Game picks it up on next poll.
 */
async function handleAdminTestNotification(req, env, game) {
  if (req.method !== "POST") return json(req, env, { ok: false, error: "method_not_allowed" }, 405);
  const body = await parseJson(req);
  const saweriaName = cleanString(body.saweria_name);
  const amount = parseAmount(body.amount);
  const message = cleanString(body.message, "Test donation from admin panel");
  const robloxUsername = cleanString(body.roblox_username);
  if (!saweriaName || amount <= 0) {
    return json(req, env, { ok: false, error: "validation_failed — saweria_name and amount required" }, 422);
  }
  const providerTxId = `test:${game.game_key}:${saweriaName.toLowerCase()}:${amount}:${Date.now()}`;
  const donationAt = nowIso();
  await env.DB.prepare(
    `INSERT INTO donations (
       game_id, provider_tx_id, saweria_name, saweria_name_lc, amount, message, status, donation_at, raw_payload
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(game_id, provider_tx_id) DO UPDATE SET
       saweria_name = excluded.saweria_name,
       saweria_name_lc = excluded.saweria_name_lc,
       amount = excluded.amount,
       message = excluded.message,
       status = excluded.status,
       donation_at = excluded.donation_at,
       raw_payload = excluded.raw_payload,
       received_at = (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))`,
  )
    .bind(
      game.id,
      providerTxId,
      saweriaName,
      saweriaName.toLowerCase(),
      amount,
      message,
      "success",
      donationAt,
      JSON.stringify({ source: "admin_test", saweria_name: saweriaName, amount, message, roblox_username: robloxUsername }),
    )
    .run();
  const donationRow = await env.DB.prepare(
    "SELECT id FROM donations WHERE game_id = ? AND provider_tx_id = ? LIMIT 1",
  )
    .bind(game.id, providerTxId)
    .first();
  return json(req, env, {
    ok: true,
    donation_id: Number(donationRow?.id || 0),
    provider_tx_id: providerTxId,
    notification_ready: true,
  }, 201);
}

/**
 * GET /admin/games/:key/test-api?action=...&...
 * Proxy to internal game handler. Returns raw JSON the game would see.
 */
async function handleAdminTestApi(req, env, url, game) {
  if (req.method !== "GET") return json(req, env, { ok: false, error: "method_not_allowed" }, 405);
  const action = cleanString(url.searchParams.get("action"), "ping").toLowerCase();
  const gameUrl = new URL(url);
  gameUrl.pathname = `/game/${game.game_key}`;
  gameUrl.searchParams.set("secret", game.secret);
  gameUrl.searchParams.set("action", action);
  for (const [key, value] of url.searchParams.entries()) {
    if (key !== "action") gameUrl.searchParams.set(key, value);
  }
  const fakeReq = new Request(gameUrl.toString(), { method: "GET", headers: req.headers });
  return handleGame(fakeReq, env, gameUrl, game.game_key);
}

/**
 * GET /admin/games/:key/webhook-events
 * Webhook event log with pagination.
 */
async function handleAdminWebhookEvents(req, env, url, game) {
  if (req.method !== "GET") return json(req, env, { ok: false, error: "method_not_allowed" }, 405);
  const limit = Math.max(1, Math.min(200, Number(url.searchParams.get("limit") || 50)));
  const offset = Math.max(0, Number(url.searchParams.get("offset") || 0));
  const rows = await env.DB.prepare(
    `SELECT id, raw_payload, processed, donation_id, error, received_at
     FROM webhook_events
     WHERE game_id = ?
     ORDER BY id DESC
     LIMIT ? OFFSET ?`,
  )
    .bind(game.id, limit, offset)
    .all();
  const totalRow = await env.DB.prepare(
    "SELECT COUNT(*) AS c FROM webhook_events WHERE game_id = ?",
  )
    .bind(game.id)
    .first();
  const total = Number(totalRow?.c || 0);
  const events = (rows.results || []).map((r) => {
    let parsedPayload = r.raw_payload;
    try { parsedPayload = JSON.parse(r.raw_payload); } catch { /* keep raw */ }
    return {
      id: r.id,
      payload: parsedPayload,
      processed: Boolean(r.processed),
      donation_id: r.donation_id,
      error: r.error || null,
      created_at: r.received_at,
    };
  });
  return json(req, env, {
    ok: true,
    events,
    total,
    has_more: offset + limit < total,
  });
}

/**
 * GET /admin/games/:key/daily-leaderboard
 * Daily leaderboard view (WIB 00:01-23:59:59).
 */
async function handleAdminDailyLeaderboard(req, env, url, game) {
  if (req.method !== "GET") return json(req, env, { ok: false, error: "method_not_allowed" }, 405);
  const limit = Math.max(1, Math.min(500, Number(url.searchParams.get("limit") || 100)));
  const leaderboard = await buildDailyLeaderboard(env.DB, game.id, limit);
  const normalized = leaderboard.map((entry, index) => ({
    rank: index + 1,
    saweria_name: entry.saweria_name,
    total: Number(entry.total_amount) || 0,
    last_at: entry.last_donation_at ? new Date((Number(entry.last_donation_at) || 0) * 1000).toISOString() : "",
  }));
  return json(req, env, { ok: true, data: normalized, leaderboard });
}

/**
 * POST /admin/games/:key/bulk-void
 * Bulk void donations.
 */
async function handleAdminBulkVoid(req, env, game) {
  if (req.method !== "POST") return json(req, env, { ok: false, error: "method_not_allowed" }, 405);
  const body = await parseJson(req);
  const ids = Array.isArray(body.donation_ids) ? body.donation_ids.map(Number).filter((n) => n > 0) : [];
  const reason = cleanString(body.reason, "admin_bulk_void");
  if (ids.length === 0) return json(req, env, { ok: false, error: "validation_failed — donation_ids required" }, 422);
  if (ids.length > 500) return json(req, env, { ok: false, error: "too_many_ids_max_500" }, 422);
  const statements = ids.map((id) =>
    env.DB.prepare(
      "UPDATE donations SET is_voided = 1, voided_at = ?, voided_reason = ? WHERE id = ? AND game_id = ?",
    ).bind(nowIso(), reason, id, game.id),
  );
  const chunkSize = 40;
  for (let i = 0; i < statements.length; i += chunkSize) {
    await env.DB.batch(statements.slice(i, i + chunkSize));
  }
  return json(req, env, { ok: true, voided: ids.length });
}

/**
 * POST /admin/games/:key/bulk-link
 * Bulk create donor links.
 */
async function handleAdminBulkLink(req, env, game) {
  if (req.method !== "POST") return json(req, env, { ok: false, error: "method_not_allowed" }, 405);
  const body = await parseJson(req);
  const links = Array.isArray(body.links) ? body.links : [];
  if (links.length === 0) return json(req, env, { ok: false, error: "validation_failed — links array required" }, 422);
  if (links.length > 200) return json(req, env, { ok: false, error: "too_many_links_max_200" }, 422);
  let created = 0;
  let skipped = 0;
  for (const link of links) {
    const saweriaName = cleanString(link.saweria_name);
    const robloxUsername = cleanString(link.roblox_username).replace(/^@/, "");
    if (!saweriaName || !robloxUsername) { skipped += 1; continue; }
    const resolved = await lookupRobloxUser(robloxUsername);
    const finalUsername = resolved?.username || robloxUsername;
    const robloxUserId = resolved?.userId ?? null;
    const robloxDisplayName = resolved?.displayName || "";
    await env.DB.prepare(
      `INSERT INTO donor_links (game_id, saweria_name, saweria_name_lc, roblox_username, roblox_user_id, roblox_display_name)
       VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(game_id, saweria_name_lc) DO UPDATE SET
         saweria_name = excluded.saweria_name,
         roblox_username = excluded.roblox_username,
         roblox_user_id = excluded.roblox_user_id,
         roblox_display_name = excluded.roblox_display_name,
         updated_at = (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))`,
    )
      .bind(game.id, saweriaName, saweriaName.toLowerCase(), finalUsername, robloxUserId, robloxDisplayName)
      .run();
    created += 1;
  }
  return json(req, env, { ok: true, created, skipped });
}

/**
 * GET /admin/games/:key/donor/:name
 * Full donation history for a specific donor.
 */
async function handleAdminDonorDetail(req, env, parts, game) {
  if (req.method !== "GET") return json(req, env, { ok: false, error: "method_not_allowed" }, 405);
  const donorNameLc = decodeURIComponent(parts[4]).toLowerCase();
  if (!donorNameLc) return json(req, env, { ok: false, error: "donor name required" }, 422);
  const successStatuses = "'success','paid','completed','settlement'";
  const donations = await env.DB.prepare(
    `SELECT id, saweria_name, amount, message, status, is_voided, donation_at, received_at
     FROM donations
     WHERE game_id = ? AND saweria_name_lc = ? AND status IN (${successStatuses}) AND is_voided = 0
     ORDER BY donation_at DESC`,
  )
    .bind(game.id, donorNameLc)
    .all();
  const link = await env.DB.prepare(
    "SELECT roblox_username, roblox_user_id, roblox_display_name FROM donor_links WHERE game_id = ? AND saweria_name_lc = ?",
  )
    .bind(game.id, donorNameLc)
    .first();
  const totalRow = await env.DB.prepare(
    `SELECT COUNT(*) AS count, SUM(amount) AS total
     FROM donations
     WHERE game_id = ? AND saweria_name_lc = ? AND status IN (${successStatuses}) AND is_voided = 0`,
  )
    .bind(game.id, donorNameLc)
    .first();
  const rankRow = await env.DB.prepare(
    `WITH totals AS (
       SELECT saweria_name_lc, SUM(amount) AS total
       FROM donations
       WHERE game_id = ? AND status IN (${successStatuses}) AND is_voided = 0
       GROUP BY saweria_name_lc
     )
     SELECT COUNT(*) + 1 AS rank FROM totals WHERE total > (SELECT COALESCE(SUM(amount), 0) FROM donations WHERE game_id = ? AND saweria_name_lc = ? AND status IN (${successStatuses}) AND is_voided = 0)`,
  )
    .bind(game.id, game.id, donorNameLc)
    .first();
  const saweriaName = (donations.results && donations.results[0]?.saweria_name) || parts[4];
  return json(req, env, {
    ok: true,
    donor: {
      saweria_name: saweriaName,
      total_donations: Number(totalRow?.count || 0),
      total_amount: Number(totalRow?.total || 0),
      rank: Number(rankRow?.rank) || null,
      roblox_username: link?.roblox_username || null,
      roblox_user_id: link?.roblox_user_id || null,
      roblox_display_name: link?.roblox_display_name || null,
      first_donation_at: donations.results?.length ? donations.results[donations.results.length - 1].donation_at : null,
      last_donation_at: donations.results?.length ? donations.results[0].donation_at : null,
    },
    donations: donations.results || [],
  });
}

/**
 * GET /admin/games/:key/stats
 * Game stats/analytics.
 */
async function handleAdminGameStats(req, env, url, game) {
  if (req.method !== "GET") return json(req, env, { ok: false, error: "method_not_allowed" }, 405);
  const successStatuses = "'success','paid','completed','settlement'";
  const since = cleanString(url.searchParams.get("from"));
  const until = cleanString(url.searchParams.get("to"));
  const where = [`game_id = ?`, `status IN (${successStatuses})`, `is_voided = 0`];
  const bind = [game.id];
  if (since) { where.push("donation_at >= ?"); bind.push(since); }
  if (until) { where.push("donation_at <= ?"); bind.push(until); }
  const whereSql = where.join(" AND ");
  const totals = await env.DB.prepare(
    `SELECT COUNT(*) AS total_donations, COALESCE(SUM(amount), 0) AS total_amount, COUNT(DISTINCT saweria_name_lc) AS unique_donors
     FROM donations WHERE ${whereSql}`,
  )
    .bind(...bind)
    .first();
  const seedTotal = await env.DB.prepare(
    "SELECT COALESCE(SUM(total_amount), 0) AS seed_total FROM legacy_seed_entries WHERE game_id = ?",
  )
    .bind(game.id)
    .first();
  return json(req, env, {
    ok: true,
    stats: {
      total_donations: Number(totals?.total_donations || 0),
      total_amount: Number(totals?.total_amount || 0),
      unique_donors: Number(totals?.unique_donors || 0),
      seed_total: Number(seedTotal?.seed_total || 0),
      combined_total: Number(totals?.total_amount || 0) + Number(seedTotal?.seed_total || 0),
    },
  });
}

/**
 * POST /admin/games/:key/generate-link
 * Generate a scoped admin link for specific games with expiry.
 */
async function handleAdminGenerateLink(req, env, url, game) {
  if (req.method !== "POST") return json(req, env, { ok: false, error: "method_not_allowed" }, 405);
  const body = await parseJson(req);
  const gameKeys = Array.isArray(body.game_keys) ? body.game_keys.map(toLc).filter(Boolean) : [game.game_key];
  const expiresInHours = Math.max(1, Math.min(720, Number(body.expires_in_hours) || 24));
  if (gameKeys.length === 0) return json(req, env, { ok: false, error: "game_keys required" }, 422);
  const tokenBytes = new Uint8Array(32);
  crypto.getRandomValues(tokenBytes);
  const token = btoa(String.fromCharCode(...tokenBytes))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
  const tokenHash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token)).then((buf) =>
    Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join(""),
  );
  const expiresAt = new Date(Date.now() + expiresInHours * 3600 * 1000).toISOString();
  await env.DB.prepare(
    `INSERT INTO admin_scoped_tokens (token_hash, game_keys, created_by, expires_at)
     VALUES (?, ?, ?, ?)`,
  )
    .bind(tokenHash, JSON.stringify(gameKeys), game.game_key, expiresAt)
    .run();
  const baseUrl = cleanString(env.PUBLIC_BASE_URL, new URL(req.url).origin).replace(/\/$/, "");
  return json(req, env, {
    ok: true,
    link: `${baseUrl}/admin/shared/${token}`,
    game_keys: gameKeys,
    expires_at: expiresAt,
  }, 201);
}

/**
 * GET /admin/shared/:token
 * Validate a scoped admin token and return accessible games.
 */
async function handleAdminSharedToken(req, env, token) {
  if (!token) return json(req, env, { ok: false, error: "token required" }, 422);
  const tokenHash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token)).then((buf) =>
    Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join(""),
  );
  const row = await env.DB.prepare(
    "SELECT game_keys, expires_at FROM admin_scoped_tokens WHERE token_hash = ? LIMIT 1",
  )
    .bind(tokenHash)
    .first();
  if (!row) return json(req, env, { ok: false, error: "invalid_token" }, 401);
  if (new Date(row.expires_at) < new Date()) return json(req, env, { ok: false, error: "token_expired" }, 401);
  let gameKeys;
  try { gameKeys = JSON.parse(row.game_keys); } catch { gameKeys = []; }
  const baseUrl = cleanString(env.PUBLIC_BASE_URL, new URL(req.url).origin).replace(/\/$/, "");
  const socialBaseUrl = getSocialBaseUrl(env);
  await ensureSocialSecrets(env.DB);
  const games = [];
  for (const key of gameKeys) {
    const gameRow = await getGameByKey(env.DB, key);
    if (gameRow) games.push(gamePayload(gameRow, baseUrl, socialBaseUrl));
  }
  return json(req, env, {
    ok: true,
    scope: "shared",
    games,
    expires_at: row.expires_at,
  });
}

export default {
  async fetch(req, env) {
    if (req.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: buildCorsHeaders(req, env),
      });
    }

    const url = new URL(req.url);
    const parts = url.pathname.split("/").filter(Boolean);
    try {
      if (req.method === "GET" && url.pathname === "/health") return handleHealth(req, env);
      if (req.method === "GET" && url.pathname === "/admin/whoami") {
        const baseUrl = cleanString(env.PUBLIC_BASE_URL, new URL(req.url).origin).replace(/\/$/, "");
        return handleAdminWhoami(req, env, baseUrl);
      }
      if (parts[0] === "admin" && parts[1] === "donations" && parts[2])
        return handleAdminDonationPatch(req, env, Number(parts[2]));
      if (parts[0] === "admin" && parts[1] === "shared" && parts[2])
        return handleAdminSharedToken(req, env, parts[2]);
      if (parts[0] === "admin") return handleAdmin(req, env, url, parts);
      if (parts[0] === "game" && parts[1] && parts[2] === "v2") {
        return handleGameV2(req, env, url, parts[1], parts, json);
      }
      if (parts[0] === "game" && parts[1]) return handleGame(req, env, url, parts[1]);
      if (parts[0] === "webhook" && parts[2] && parts[3]) {
        if (parts[1] === "saweria" || parts[1] === "bagibagi") {
          return handleWebhook(req, env, parts[2], parts[3], parts[1]);
        }
      }
      return new Response("not found", {
        status: 404,
        headers: buildCorsHeaders(req, env),
      });
    } catch (err) {
      return json(req, env, { ok: false, error: err instanceof Error ? err.message : String(err) }, 500);
    }
  },
};
