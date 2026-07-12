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
//   GET /game/:gameKey/community/:groupId?secret=...

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
const GROUPS_ENABLED_GAMES = ["nuwa"];

// Games that have opted in to the /community endpoint (Join Commun modal data).
// Includes every groups-enabled game plus the-basic (Club Kit).
const COMMUNITY_ENABLED_GAMES = ["nuwa", "the-basic"];

// Per-game default group IDs (used when ?groupId not provided on /groups)
const DEFAULT_GROUP_IDS = { nuwa: 141321616 };

// Cache TTLs (seconds)
const GROUPS_CACHE_FRESH = 300; // 5 min — considered fresh
const GROUPS_CACHE_STALE = 900; // 15 min — stale but servable
const COMMUNITY_CACHE_TTL = 300; // 5 min — Join Commun payload (memberCount + sample)
const COMMUNITY_MEMBER_SAMPLE = 40; // enough for kit to pick 8
const ROLES_KV_TTL = 86400; // 24h — roles rarely change

/** Open Cloud group API key (wrangler secret ROBLOX_GROUP_API_KEY). */
function getGroupApiKey(env) {
  return cleanString(env.ROBLOX_GROUP_API_KEY) || cleanString(env.OPEN_CLOUD_API_KEY);
}

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

  const apiKey = getGroupApiKey(env);
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
  const apiKey = getGroupApiKey(env);
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

// ── Community Handler (Join Commun modal) ────────────────────────────

/** Build a Cache API request key for group community payload. */
function makeCommunityCacheKey(gameKey, groupId) {
  return new Request(`https://cache.internal/community/${gameKey}/${groupId}`);
}

/** Fetch group metadata (memberCount) from Open Cloud. */
async function fetchGroupMeta(env, groupId) {
  const apiKey = getGroupApiKey(env);
  if (!apiKey) return null;

  try {
    const resp = await fetch(`https://apis.roblox.com/cloud/v2/groups/${groupId}`, {
      headers: { "x-api-key": apiKey, accept: "application/json" },
    });
    if (!resp.ok) {
      console.error(`Open Cloud group API error: ${resp.status} for groupId=${groupId}`);
      return null;
    }
    const data = await resp.json();
    const memberCount = typeof data.memberCount === "number" ? data.memberCount : Number(data.memberCount);
    return {
      memberCount: Number.isFinite(memberCount) && memberCount >= 0 ? Math.floor(memberCount) : null,
      displayName: cleanString(data.displayName),
    };
  } catch (err) {
    console.error(`Group meta fetch error for groupId=${groupId}:`, err.message);
    return null;
  }
}

/** List a page of group membership user IDs via Open Cloud. */
async function fetchMembershipUserIds(env, groupId, maxPageSize) {
  const apiKey = getGroupApiKey(env);
  if (!apiKey) return null;

  const pageSize = Math.min(100, Math.max(8, maxPageSize || COMMUNITY_MEMBER_SAMPLE));
  try {
    const resp = await fetch(
      `https://apis.roblox.com/cloud/v2/groups/${groupId}/memberships?maxPageSize=${pageSize}`,
      { headers: { "x-api-key": apiKey, accept: "application/json" } },
    );
    if (!resp.ok) {
      console.error(`Open Cloud memberships API error: ${resp.status} for groupId=${groupId}`);
      return null;
    }
    const data = await resp.json();
    const memberships = data.groupMemberships || [];
    const userIds = [];
    const seen = new Set();
    for (const row of memberships) {
      const userPath = cleanString(row && row.user);
      // "users/123456"
      const match = userPath.match(/users\/(\d+)/i);
      const userId = match ? Number(match[1]) : 0;
      if (userId > 0 && !seen.has(userId)) {
        seen.add(userId);
        userIds.push(userId);
      }
    }
    return userIds;
  } catch (err) {
    console.error(`Memberships fetch error for groupId=${groupId}:`, err.message);
    return null;
  }
}

/** Resolve display names via public users multi-get (no Open Cloud key needed). */
async function fetchDisplayNames(userIds) {
  if (!userIds || userIds.length === 0) return {};

  try {
    const resp = await fetch("https://users.roblox.com/v1/users", {
      method: "POST",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({ userIds, excludeBannedUsers: true }),
    });
    if (!resp.ok) {
      console.error(`Users multi-get error: ${resp.status}`);
      return {};
    }
    const data = await resp.json();
    const map = {};
    for (const row of data.data || []) {
      const id = Number(row.id);
      if (!id) continue;
      const displayName = cleanString(row.displayName) || cleanString(row.name) || `User ${id}`;
      map[id] = displayName;
    }
    return map;
  } catch (err) {
    console.error("Users multi-get error:", err.message);
    return {};
  }
}

/** Optional group emblem via thumbnails API. */
async function fetchGroupEmblemUrl(groupId) {
  try {
    const resp = await fetch(
      `https://thumbnails.roblox.com/v1/groups/icons?groupIds=${groupId}&size=150x150&format=Png&isCircular=false`,
      { headers: { accept: "application/json" } },
    );
    if (!resp.ok) return null;
    const data = await resp.json();
    const row = (data.data || [])[0];
    if (row && row.state === "Completed" && cleanString(row.imageUrl)) {
      return cleanString(row.imageUrl);
    }
    return null;
  } catch (err) {
    console.error(`Group emblem fetch error for groupId=${groupId}:`, err.message);
    return null;
  }
}

/** Store community payload in Cache API. */
async function cacheCommunityPayload(cache, cacheKey, data) {
  const resp = new Response(JSON.stringify(data), {
    headers: {
      "content-type": "application/json",
      "cache-control": `public, max-age=${COMMUNITY_CACHE_TTL}`,
    },
  });
  await cache.put(cacheKey, resp);
}

/**
 * Resolve JoinCommun payload: memberCount + member sample + optional emblem.
 * Uses Open Cloud for group/memberships; users.roblox.com for display names.
 */
async function resolveCommunityPayload(env, groupId) {
  const apiKey = getGroupApiKey(env);
  if (!apiKey) {
    return { error: "roblox_api_key_missing" };
  }

  const [meta, userIds, emblemUrl] = await Promise.all([
    fetchGroupMeta(env, groupId),
    fetchMembershipUserIds(env, groupId, COMMUNITY_MEMBER_SAMPLE),
    fetchGroupEmblemUrl(groupId),
  ]);

  if (!meta && (!userIds || userIds.length === 0)) {
    return { error: "roblox_unavailable" };
  }

  const nameMap = await fetchDisplayNames(userIds || []);
  const members = (userIds || []).map((userId) => ({
    userId,
    displayName: nameMap[userId] || `User ${userId}`,
  }));

  return {
    memberCount: meta && meta.memberCount != null ? meta.memberCount : 0,
    members,
    emblemUrl: emblemUrl || null,
    fetchedAt: Date.now() / 1000,
  };
}

/**
 * GET /game/:gameKey/community/:groupId?secret=...
 *
 * Join Commun modal data for a Roblox group.
 * Cache: Cache API, 5 min TTL.
 */
async function handleCommunity(env, gameKey, groupId) {
  if (!COMMUNITY_ENABLED_GAMES.includes(gameKey)) {
    return json({ ok: false, error: "community endpoint not enabled for this game" }, 403);
  }

  if (!groupId || groupId <= 0) {
    return json({ ok: false, error: "invalid groupId" }, 400);
  }

  const cache = caches.default;
  const cacheKey = makeCommunityCacheKey(gameKey, groupId);

  const cachedResp = await cache.match(cacheKey);
  if (cachedResp) {
    const data = await cachedResp.json();
    if (data && Array.isArray(data.members)) {
      return json({
        ok: true,
        memberCount: typeof data.memberCount === "number" ? data.memberCount : 0,
        members: data.members,
        emblemUrl: data.emblemUrl || null,
        fromCache: true,
      });
    }
  }

  const result = await resolveCommunityPayload(env, groupId);
  if (result.error) {
    if (cachedResp) {
      const stale = await cachedResp.clone().json();
      return json({
        ok: true,
        memberCount: typeof stale.memberCount === "number" ? stale.memberCount : 0,
        members: Array.isArray(stale.members) ? stale.members : [],
        emblemUrl: stale.emblemUrl || null,
        fromCache: true,
        stale: true,
      });
    }
    const status = result.error === "roblox_api_key_missing" ? 503 : 502;
    return json({ ok: false, error: result.error }, status);
  }

  await cacheCommunityPayload(cache, cacheKey, result);
  return json({
    ok: true,
    memberCount: result.memberCount,
    members: result.members,
    emblemUrl: result.emblemUrl,
    fromCache: false,
  });
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

        if (action === "community" && parts[3] && req.method === "GET") {
          const groupId = Number(parts[3]);
          if (!groupId || groupId <= 0) {
            return json({ ok: false, error: "invalid groupId" }, 400);
          }
          return handleCommunity(env, gameKey, groupId);
        }

        return json({ ok: false, error: `unknown action: ${action}` }, 404);
      }

      return json({ ok: false, error: "not found" }, 404);
    } catch (err) {
      return json({ ok: false, error: err instanceof Error ? err.message : String(err) }, 500);
    }
  },
};
