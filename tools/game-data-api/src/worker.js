// tools/game-data-api/src/worker.js
//
// Game Data API — Cloudflare Worker
//
// Multi-game proxy for Roblox game data operations.
// Replaces slow Roblox API calls with cached KV lookups.
//
// Endpoints:
//   GET /health
//   GET /game/:gameKey/social/:userId?secret=...
//   GET /game/:gameKey/groups/:userId?secret=...&groupId=...

const CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, OPTIONS",
  "access-control-allow-headers": "content-type, authorization",
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      ...CORS_HEADERS,
    },
  });
}

// ── Config ───────────────────────────────────────────────────────────

// Games that have opted in to the /groups endpoint.
// Other games get 403 — prevents accidental cross-game impact.
// NuWA is an experimental game; add other games here when ready.
const GROUPS_ENABLED_GAMES = ["nuwa"];

// Per-game default group IDs (used when ?groupId not provided)
const DEFAULT_GROUP_IDS = { nuwa: 141321616 };

// Cache TTLs (seconds)
const GROUPS_CACHE_FRESH = 300; // 5 min — considered fresh
const GROUPS_CACHE_STALE = 900; // 15 min — stale but servable
const ROLES_KV_TTL = 86400; // 24h — roles rarely change

// ── Helpers ──────────────────────────────────────────────────────────

/** Verify game secret from query params or Authorization Bearer. */
async function authenticate(req, url, env, gameKey) {
  const authHeader = req.headers.get("authorization") || "";
  const bearerMatch = authHeader.match(/^Bearer\s+(.+)$/i);
  const secret = cleanString(url.searchParams.get("secret")) || (bearerMatch ? bearerMatch[1] : "");
  if (!secret) return false;

  if (env.DB) {
    const row = await env.DB.prepare(
      "SELECT social_secret FROM games WHERE game_key = ? LIMIT 1",
    )
      .bind(gameKey)
      .first();
    if (row && cleanString(row.social_secret) && secret === row.social_secret) {
      return true;
    }
  }

  // Legacy wrangler secret fallback (nuwa, etc.)
  const envKey = `SECRET_${gameKey.toUpperCase().replace(/-/g, "_")}`;
  return secret === env[envKey];
}

function cleanString(value, fallback = "") {
  if (value === undefined || value === null) return fallback;
  const cleaned = String(value).trim();
  return cleaned || fallback;
}

// ── Social Handler ──────────────────────────────────────────────────

async function handleHealth(env) {
  return json({ ok: true, service: "game-data-api", ts: new Date().toISOString() });
}

const SOCIAL_CACHE_TTL = 600; // 10 minutes — aligned with game server warm interval

/** Build a Cache API request key for per-user social data. */
function makeSocialCacheKey(gameKey, userId) {
  return new Request(`https://cache.internal/social/${gameKey}/${userId}`);
}

/**
 * GET /game/:gameKey/social/:userId?secret=...
 *
 * Returns connections (friends) count for a Roblox user.
 * Data is populated by game server via POST (push model).
 * Uses Cache API (free, unlimited) seeded by game server push.
 */
async function handleSocialGet(env, gameKey, userId) {
  const cache = caches.default;
  const cacheKey = makeSocialCacheKey(gameKey, userId);

  const cachedResp = await cache.match(cacheKey);
  if (cachedResp) {
    const data = await cachedResp.json();
    if (typeof data.connectionsCount === "number") {
      return json({ ok: true, fromCache: true, connectionsCount: data.connectionsCount });
    }
  }

  // No cached data — game server hasn't pushed yet
  return json({ ok: true, connectionsCount: null });
}

/**
 * POST /game/:gameKey/social/:userId?secret=...
 * Body: { "connectionsCount": 551 }
 *
 * Game server pushes resolved connections count after GetFriendsAsync.
 * Worker stores in Cache API (free, unlimited writes) for subsequent GET requests.
 */
async function handleSocialPost(env, gameKey, userId, body) {
  try {
    const connectionsCount = typeof body.connectionsCount === "number" ? body.connectionsCount : null;
    if (connectionsCount === null || connectionsCount < 0) {
      return json({ ok: false, error: "invalid connectionsCount" }, 400);
    }

    const cache = caches.default;
    const cacheKey = makeSocialCacheKey(gameKey, userId);
    const payload = JSON.stringify({ connectionsCount, pushedAt: Date.now() / 1000 });
    const resp = new Response(payload, {
      headers: {
        "content-type": "application/json",
        "cache-control": `public, max-age=${SOCIAL_CACHE_TTL}`,
      },
    });
    await cache.put(cacheKey, resp);

    return json({ ok: true, stored: true, connectionsCount });
  } catch (err) {
    return json({ ok: false, error: String(err && err.message ? err.message : err) }, 500);
  }
}

// ── Groups Handler ──────────────────────────────────────────────────

/** Fetch roles list from KV or Open Cloud API. Cached in KV for 24h. */
async function getRoles(env, groupId) {
  const kvKey = `roles:${groupId}`;
  const cached = await env.GAME_DATA_CACHE.get(kvKey, "json");
  if (cached && Array.isArray(cached.roles) && cached.roles.length > 0) {
    return cached.roles;
  }

  const apiKey = env.ROBLOX_GROUP_API_KEY;
  if (!apiKey) {
    console.error("ROBLOX_GROUP_API_KEY not configured");
    return null;
  }

  try {
    const resp = await fetch(`https://apis.roblox.com/cloud/v2/groups/${groupId}/roles?maxPageSize=50`, {
      headers: { "x-api-key": apiKey, accept: "application/json" },
    });
    if (!resp.ok) {
      console.error(`Open Cloud roles API error: ${resp.status}`);
      return null;
    }
    const data = await resp.json();
    const roles = (data.groupRoles || []).map((r) => ({
      id: r.id,
      name: r.displayName,
      rank: r.rank,
    }));

    // Store in KV — roles rarely change, 1 write/day max
    await env.GAME_DATA_CACHE.put(kvKey, JSON.stringify({ roles, fetchedAt: Date.now() / 1000 }), {
      expirationTtl: ROLES_KV_TTL,
    });
    return roles;
  } catch (err) {
    console.error("Roles fetch error:", err.message);
    return null;
  }
}

/** Fetch user membership from Open Cloud API. */
async function fetchMembership(env, groupId, userId) {
  const apiKey = env.ROBLOX_GROUP_API_KEY;
  if (!apiKey) return null;

  try {
    const filter = encodeURIComponent(`user=='users/${userId}'`);
    const resp = await fetch(
      `https://apis.roblox.com/cloud/v2/groups/${groupId}/memberships?filter=${filter}&maxPageSize=1`,
      { headers: { "x-api-key": apiKey, accept: "application/json" } },
    );
    if (!resp.ok) {
      console.error(`Open Cloud membership API error: ${resp.status} for userId=${userId}`);
      return null;
    }
    const data = await resp.json();
    const memberships = data.groupMemberships || [];
    if (memberships.length === 0) {
      return { roleId: null, inGroup: false };
    }
    // Extract role ID from path like "groups/123/roles/456"
    const rolePath = memberships[0].role || "";
    const roleId = rolePath.split("/").pop() || null;
    return { roleId, inGroup: true };
  } catch (err) {
    console.error(`Membership fetch error for userId=${userId}:`, err.message);
    return null;
  }
}

/** Resolve rank by fetching membership + mapping to roles. */
async function resolveGroupRank(env, groupId, userId) {
  const [membership, roles] = await Promise.all([fetchMembership(env, groupId, userId), getRoles(env, groupId)]);

  if (!membership) return null;
  if (!membership.inGroup) {
    return { rankId: 0, roleName: "Guest", roleId: null, fetchedAt: Date.now() / 1000 };
  }
  if (!roles || !membership.roleId) return null;

  const role = roles.find((r) => r.id === membership.roleId);
  return {
    rankId: role ? role.rank : 0,
    roleName: role ? role.name : "Unknown",
    roleId: membership.roleId,
    fetchedAt: Date.now() / 1000,
  };
}

/** Build a Cache API request key for per-user group rank. */
function makeGroupsCacheKey(gameKey, groupId, userId) {
  return new Request(`https://cache.internal/groups/${gameKey}/${groupId}/${userId}`);
}

/** Store resolved rank in Cache API (free, unlimited writes). */
async function cacheGroupRank(cache, cacheKey, data) {
  const resp = new Response(JSON.stringify(data), {
    headers: {
      "content-type": "application/json",
      "cache-control": `public, max-age=${GROUPS_CACHE_STALE}`,
    },
  });
  await cache.put(cacheKey, resp);
}

/** Background revalidation (fire-and-forget via ctx.waitUntil). */
async function revalidateGroupRank(env, cache, cacheKey, groupId, userId) {
  try {
    const result = await resolveGroupRank(env, groupId, userId);
    if (result) {
      await cacheGroupRank(cache, cacheKey, result);
    }
  } catch (err) {
    console.error(`Background revalidate failed for userId=${userId}:`, err.message);
  }
}

/**
 * GET /game/:gameKey/groups/:userId?secret=...&groupId=...
 *
 * Returns group rank for a Roblox user via Open Cloud API.
 * Cache: Cache API (free, unlimited) for per-user data.
 *        KV for roles mapping (1 write/day).
 * Pattern: stale-while-revalidate.
 */
async function handleGroups(env, gameKey, userId, groupId, ctx) {
  if (!GROUPS_ENABLED_GAMES.includes(gameKey)) {
    return json({ ok: false, error: "groups endpoint not enabled for this game" }, 403);
  }

  const resolvedGroupId = groupId || DEFAULT_GROUP_IDS[gameKey];
  if (!resolvedGroupId) {
    return json({ ok: false, error: "groupId required" }, 400);
  }

  const cache = caches.default;
  const cacheKey = makeGroupsCacheKey(gameKey, resolvedGroupId, userId);

  // 1. Check Cache API (free, unlimited, per-colo)
  const cachedResp = await cache.match(cacheKey);
  if (cachedResp) {
    const data = await cachedResp.json();
    const age = Date.now() / 1000 - (data.fetchedAt || 0);

    if (age < GROUPS_CACHE_FRESH) {
      return json({ ok: true, ...data, stale: false, fromCache: true });
    }
    if (age < GROUPS_CACHE_STALE) {
      // Stale but usable — trigger background revalidate
      if (ctx && ctx.waitUntil) {
        ctx.waitUntil(revalidateGroupRank(env, cache, cacheKey, resolvedGroupId, userId));
      }
      return json({ ok: true, ...data, stale: true, fromCache: true });
    }
  }

  // 2. Fetch fresh
  const result = await resolveGroupRank(env, resolvedGroupId, userId);
  if (result) {
    await cacheGroupRank(cache, cacheKey, result);
    return json({ ok: true, ...result, stale: false, fromCache: false });
  }

  // 3. Fallback to stale cache if fetch failed
  if (cachedResp) {
    const staleData = await cachedResp.clone().json();
    return json({ ok: true, ...staleData, stale: true, fromCache: true });
  }

  // 4. Total failure — no cache, no API
  return json({ ok: false, error: "roblox_unavailable" }, 502);
}

// ── Router ───────────────────────────────────────────────────────────

export default {
  async fetch(req, env, ctx) {
    if (req.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    const url = new URL(req.url);
    const parts = url.pathname.split("/").filter(Boolean);

    try {
      // Health
      if (req.method === "GET" && url.pathname === "/health") {
        return handleHealth(env);
      }

      // Game-specific routes: /game/:gameKey/:action/:param
      if (parts[0] === "game" && parts[1]) {
        const gameKey = parts[1];
        const action = parts[2];

        if (!(await authenticate(req, url, env, gameKey))) {
          return json({ ok: false, error: "unauthorized" }, 401);
        }

        if (action === "social" && parts[3]) {
          const userId = Number(parts[3]);
          if (!userId || userId <= 0) {
            return json({ ok: false, error: "invalid userId" }, 400);
          }
          if (req.method === "POST") {
            const body = await req.json().catch(() => ({}));
            return handleSocialPost(env, gameKey, userId, body);
          }
          return handleSocialGet(env, gameKey, userId);
        }

        if (action === "groups" && parts[3]) {
          const userId = Number(parts[3]);
          if (!userId || userId <= 0) {
            return json({ ok: false, error: "invalid userId" }, 400);
          }
          const groupIdParam = Number(url.searchParams.get("groupId")) || null;
          return handleGroups(env, gameKey, userId, groupIdParam, ctx);
        }

        return json({ ok: false, error: `unknown action: ${action}` }, 404);
      }

      return json({ ok: false, error: "not found" }, 404);
    } catch (err) {
      return json({ ok: false, error: err instanceof Error ? err.message : String(err) }, 500);
    }
  },
};
