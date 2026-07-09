# Game Data API

Multi-game Cloudflare Worker for Roblox game data operations.
Replaces slow in-game API calls with cached KV lookups.

**Separate from donation-api** — this handles game runtime data (social, ACM cache),
not donation webhooks or leaderboards.

## Endpoints

### Health

```
GET /health
```

### Social (friends count)

```
GET /game/:gameKey/social/:userId?secret=...
```

Returns friends count for a Roblox user. Replaces `Players:GetFriendsAsync()`
which paginates sequentially through up to 20 pages.

```json
{ "ok": true, "connectionsCount": 42 }
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
npx wrangler secret put OPEN_CLOUD_API_KEY

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

Then use the URL:
```
GET /game/client-game-key/social/:userId?secret=<the-secret>
```

## Local Dev

```bash
cp .dev.vars.example .dev.vars
# Fill in secrets
npm run local:up
```

## Roblox Integration

In `ProfileSocialService.luau`, the Worker is called first with a fallback
to `Players:GetFriendsAsync()` if the Worker is unavailable.

Config in `Config.luau`:
```lua
Config.GameDataApi = {
    BASE_URL = "https://hazastudio-game-data-api.hazastudio.workers.dev",
    GAME_KEY = "nuwa",
    SECRET = "ROTATE_ME_BEFORE_PUBLISH",
}
```
