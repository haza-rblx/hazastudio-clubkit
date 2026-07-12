# Game Data API

Multi-game Cloudflare Worker for Roblox game data operations.
Replaces slow in-game API calls with cached KV / Cache API lookups.

**Separate from donation-api** — this handles game runtime data (social, group ranks,
Join Commun community payload), not donation webhooks or leaderboards.

## Endpoints

### Health

```
GET /health
```

### Social (friends count)

```
GET /game/:gameKey/social/:userId?secret=...
POST /game/:gameKey/social/:userId?secret=...
```

Returns friends count for a Roblox user. Replaces `Players:GetFriendsAsync()`
which paginates sequentially through up to 20 pages.

```json
{ "ok": true, "connectionsCount": 42 }
```

### Groups (rank)

```
GET /game/:gameKey/groups/:userId?secret=...&groupId=...
```

Open Cloud group rank for overhead. Allowlisted via `GROUPS_ENABLED_GAMES` (currently `nuwa`).

### Community (Join Commun)

```
GET /game/:gameKey/community/:groupId?secret=...
```

Join Commun modal data: real `memberCount`, a sample of members (display names),
optional `emblemUrl`. Allowlisted via `COMMUNITY_ENABLED_GAMES` (`nuwa`, `the-basic`).

Auth: `?secret=` or `Authorization: Bearer …` (same as social/groups — D1 `social_secret`
or wrangler `SECRET_<GAME_KEY>`).

```json
{
  "ok": true,
  "memberCount": 10589188,
  "members": [
    { "userId": 1, "displayName": "Alice" },
    { "userId": 2, "displayName": "Bob" }
  ],
  "emblemUrl": "https://tr.rbxcdn.com/..."
}
```

Cached aggressively (~5 min). Uses Open Cloud (`ROBLOX_GROUP_API_KEY`) for group +
memberships, plus public users/thumbnails APIs for names and emblem.

## Enable for the-basic (Club Kit)

1. Deploy this worker (see below) with `ROBLOX_GROUP_API_KEY` set (Open Cloud key with
   group read scopes).
2. Ensure `the-basic` is in `COMMUNITY_ENABLED_GAMES` (already included in `worker.js`).
3. Set the game secret:
   - Preferred: D1 `games.social_secret` for `game_key = the-basic` (donation admin), or
   - `npx wrangler secret put SECRET_THE_BASIC`
4. In Studio / live place:
   - `ClubKitConfig.GameDataApi.GameKey = "the-basic"`
   - `Secrets.GameDataApiSecret` = that same secret (server-only module)
   - `HttpService.HttpEnabled = true`
5. Without `GameDataApiSecret`, the kit skips the worker (DEBUG log) and falls back to
   roproxy `MEMBER_INFO_URL` / `MEMBER_USERS_URL` — expected in Studio with empty secrets.

Test:

```bash
curl "https://hazastudio-game-data-api.hazastudio.workers.dev/game/the-basic/community/12345678?secret=YOUR_SECRET"
```

## Deploy

```bash
# 1. Install
npm install

# 2. Create KV namespace
npx wrangler kv:namespace create "GAME_DATA_CACHE"
# Copy the returned ID into wrangler.toml

# 3. Set secrets
npx wrangler secret put SECRET_NUWA
npx wrangler secret put SECRET_THE_BASIC
npx wrangler secret put ROBLOX_GROUP_API_KEY
# (OPEN_CLOUD_API_KEY is accepted as an alias in worker.js)

# 4. Deploy
npm run cf:deploy

# 5. Test
curl "https://hazastudio-game-data-api.hazastudio.workers.dev/health"
curl "https://hazastudio-game-data-api.hazastudio.workers.dev/game/nuwa/social/12345?secret=your-secret"
```

## Add a New Game

```bash
npx wrangler secret put SECRET_CLIENT_GAME_KEY
```

Then:

1. Add the game key to `COMMUNITY_ENABLED_GAMES` and/or `GROUPS_ENABLED_GAMES` in `src/worker.js`
2. Redeploy
3. Set buyer `ClubKitConfig.GameDataApi.GameKey` + `Secrets.GameDataApiSecret`

```
GET /game/client-game-key/social/:userId?secret=<the-secret>
GET /game/client-game-key/community/:groupId?secret=<the-secret>
```

## Local Dev

```bash
cp .dev.vars.example .dev.vars
# Fill in secrets (SECRET_NUWA, SECRET_THE_BASIC, ROBLOX_GROUP_API_KEY)
npm run local:up
```

## Roblox Integration

- `ProfileSocialService` — `/social` (friends count)
- `OverheadService` — `/groups` (rank; when enabled for that gameKey)
- `JoinCommunityMembersService` — `/community` preferred; roproxy fallback without secret

Config in `Config.luau` / `ClubKitConfig`:

```lua
Config.GameDataApi = {
    BASE_URL = "https://hazastudio-game-data-api.hazastudio.workers.dev",
    GAME_KEY = "the-basic", -- via ClubKitConfig.GameDataApi.GameKey
    COMMUNITY_ENDPOINT_ENABLED = true,
}
-- Secrets.GameDataApiSecret = "<social_secret>"  -- ServerScriptService only
```
