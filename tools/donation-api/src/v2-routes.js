/**
 * Donation API v2 — REST routes for Club Kit v1.3 architecture.
 *
 * Config pattern (matches Game Data API):
 *   Donation.ApiUrl = "https://host/game/{gameKey}"   -- no secret in URL
 *   Secrets.DonationApiSecret = "rbx_..."
 *
 * Auth: ?secret=rbx_... OR Authorization: Bearer rbx_...
 */

import {
  buildDailyLeaderboard,
  buildMergedLeaderboard,
  cleanString,
  decodeNotificationCursor,
  enrichLeaderboardWithLinks,
  fetchNotificationsAfterCursor,
  getGameByKey,
  getRobloxDonorCashProfile,
  listDonorLinks,
  upsertDonorLink,
} from "./game-data.js";
import { handleLicenseVerify, isLicenseBlocked } from "./license-routes.js";

export const V2_VERSION = "2.0.0";

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

async function resolveGame(req, env, url, gameKey, json) {
  const game = await getGameByKey(env.DB, gameKey);
  if (!game) return { error: json(req, env, { ok: false, error: "game_not_found" }, 404) };
  if (!assertGameSecret(req, url, game.secret)) {
    return { error: json(req, env, { ok: false, error: "invalid_secret" }, 403) };
  }
  return { game };
}

function parseBoardList(url) {
  const raw = cleanString(url.searchParams.get("boards"), "alltime,daily");
  const boards = raw
    .split(",")
    .map((b) => b.trim().toLowerCase())
    .filter(Boolean);
  return boards.length ? boards : ["alltime", "daily"];
}

/**
 * Route: /game/:gameKey/v2/*
 * parts[0]=game, parts[1]=gameKey, parts[2]=v2, parts[3+]=resource
 */
export async function handleGameV2(req, env, url, gameKey, parts, json) {
  if (parts[2] !== "v2") {
    return json(req, env, { ok: false, error: "not_found" }, 404);
  }

  const resolved = await resolveGame(req, env, url, gameKey, json);
  if (resolved.error) return resolved.error;
  const { game } = resolved;

  const resource = parts[3] || "health";
  const sub = parts[4] || "";

  if (resource === "license" && sub === "verify" && req.method === "POST") {
    const body = await parseJson(req);
    return handleLicenseVerify(req, env, game, json, body);
  }

  const licenseBlock = isLicenseBlocked(game);
  if (licenseBlock.blocked) {
    return json(req, env, { ok: false, error: licenseBlock.error }, 403);
  }

  if (resource === "health" && req.method === "GET") {
    return json(req, env, {
      ok: true,
      version: V2_VERSION,
      server_time: Math.floor(Date.now() / 1000),
      game_key: game.game_key,
    });
  }

  if (resource === "leaderboards" && req.method === "GET") {
    const limit = Math.max(1, Math.min(50, Number(url.searchParams.get("limit") || 10)));
    const boards = parseBoardList(url);
    const result = {};

    if (boards.includes("alltime")) {
      const rows = await buildMergedLeaderboard(env.DB, game.id, limit);
      result.alltime = await enrichLeaderboardWithLinks(env.DB, game.id, rows);
    }
    if (boards.includes("daily")) {
      const rows = await buildDailyLeaderboard(env.DB, game.id, limit);
      result.daily = await enrichLeaderboardWithLinks(env.DB, game.id, rows);
    }

    return json(req, env, { ok: true, boards: result }, 200, {
      "cache-control": "public, max-age=10",
    });
  }

  if (resource === "notifications" && req.method === "GET") {
    const limit = Math.max(1, Math.min(100, Number(url.searchParams.get("limit") || 50)));
    const cursorParam = cleanString(url.searchParams.get("cursor"));
    const cursor = cursorParam ? decodeNotificationCursor(cursorParam) : null;
    if (cursorParam && !cursor) {
      return json(req, env, { ok: false, error: "invalid_cursor" }, 400);
    }

    const { items, next_cursor } = await fetchNotificationsAfterCursor(env.DB, game.id, cursor, limit);
    return json(
      req,
      env,
      {
        ok: true,
        items,
        next_cursor,
        // GAS-compat aliases for gradual Club Kit migration
        data: items,
        notifications: items,
      },
      200,
      { "cache-control": "public, max-age=2" },
    );
  }

  if (resource === "players" && sub && req.method === "GET" && parts[5] === "cash") {
    const userId = Number(sub) || 0;
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

  if (resource === "donor-links") {
    if (req.method === "GET") {
      const links = await listDonorLinks(env.DB, game.id);
      return json(req, env, { ok: true, links, data: links });
    }
    if (req.method === "PUT" || req.method === "POST") {
      const body = await parseJson(req);
      const saweriaName = cleanString(
        body.provider_name || body.saweria_name || body.bagibagi_name || body.donator_name || body.donor_name,
      );
      const robloxUsername = cleanString(body.roblox_username).replace(/^@/, "");
      if (!saweriaName || !robloxUsername) {
        return json(req, env, { ok: false, error: "validation_failed" }, 422);
      }
      const link = await upsertDonorLink(env.DB, game.id, saweriaName, robloxUsername);
      return json(req, env, { ok: true, resolved: link.resolved, link });
    }
  }

  return json(req, env, { ok: false, error: "not_found" }, 404);
}
