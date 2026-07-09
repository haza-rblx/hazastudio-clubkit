const apiBase = (process.env.API_BASE || "https://hazastudio-donation-api.hazastudio.workers.dev").replace(/\/$/, "");
const adminToken = process.env.ADMIN_TOKEN || process.env.PROD_ADMIN_TOKEN || "";
const gameId = (process.env.GAME_ID || "rust-live").toLowerCase();
const gameName = process.env.GAME_NAME || "Rust Live";
const saweriaLink = process.env.SAWERIA_LINK || `https://saweria.co/${gameId.replace(/-/g, "")}`;
const seedName = process.env.SEED_NAME || "";
const seedAmount = Number(process.env.SEED_AMOUNT || 0);

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function request(path, options = {}) {
  const res = await fetch(`${apiBase}${path}`, {
    ...options,
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${adminToken}`,
      ...(options.headers || {}),
    },
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || body?.ok === false) {
    throw new Error(body?.error || `HTTP ${res.status}`);
  }
  return body;
}

async function waitForHealth(maxRetry = 20) {
  for (let attempt = 1; attempt <= maxRetry; attempt += 1) {
    try {
      const res = await fetch(`${apiBase}/health`);
      if (res.ok) return;
    } catch {}
    await sleep(1000);
  }
  throw new Error(`api_unreachable: ${apiBase}/health`);
}

async function createOrGetGame() {
  let createdAdminToken = "";
  try {
    const created = await request("/admin/games", {
      method: "POST",
      body: JSON.stringify({
        id: gameId,
        display_name: gameName,
        saweria_link: saweriaLink,
      }),
    });
    createdAdminToken = created.admin_token || "";
    return { game: created.game || {}, adminToken: createdAdminToken };
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    if (!/exist|duplicate|already/i.test(msg)) throw err;
    const listed = await request("/admin/games");
    const found = (listed.games || []).find((item) => item.id === gameId);
    if (!found) throw new Error(`game_lookup_failed: ${gameId}`);
    return { game: found, adminToken: "" };
  }
}

async function main() {
  if (!adminToken) {
    throw new Error("missing_admin_token: set ADMIN_TOKEN before running prod:ready");
  }

  await waitForHealth();
  const { game, adminToken: gameAdminToken } = await createOrGetGame();
  const endpoints = game.endpoints || {};

  if (!endpoints.saweria_webhook || !endpoints.roblox_base) {
    throw new Error("missing_endpoints_in_game_payload");
  }

  if (seedName && seedAmount > 0) {
    await request(`/admin/games/${gameId}/seed`, {
      method: "POST",
      body: JSON.stringify({
        saweria_name: seedName,
        total_amount: seedAmount,
        note: "prod-bootstrap",
      }),
    });
  }

  console.log("PROD_READY=1");
  console.log(`API_BASE=${apiBase}`);
  console.log(`GAME_ID=${game.id}`);
  console.log(`SAWERIA_WEBHOOK=${endpoints.saweria_webhook}`);
  if (endpoints.bagibagi_webhook) {
    console.log(`BAGIBAGI_WEBHOOK=${endpoints.bagibagi_webhook}`);
  }
  console.log(`ROBLOX_URL=${endpoints.roblox_poll}`);
  console.log(`API_URL=${endpoints.roblox_base}`);
  console.log(`DONATION_API_SECRET=${game.secret || endpoints.roblox_secret || ""}`);
  console.log(`ROBLOX_V2_BASE=${endpoints.roblox_v2_base || `${endpoints.roblox_base}/v2`}`);
  console.log(`CONFIG_LINE_ApiUrl=ApiUrl = \"${endpoints.roblox_base}\",`);
  console.log(`CONFIG_LINE_Secret=Secrets.DonationApiSecret = \"${game.secret || endpoints.roblox_secret || ""}\",`);
  console.log(`CONFIG_LINE_SocialGameKey=GameKey = \"${game.id}\",`);
  console.log(`CONFIG_LINE_SocialSecret=Secrets.GameDataApiSecret = \"${game.social_secret || ""}\",`);
  console.log(`CONFIG_LINE=SHEETS_WEB_APP_URL = \"${endpoints.roblox_poll}\",`);
  if (gameAdminToken) {
    console.log(`GAME_ADMIN_TOKEN=${gameAdminToken}`);
    console.log("NOTE=Share GAME_ADMIN_TOKEN with the game owner. It is shown only once.");
  }
  if (seedName && seedAmount > 0) {
    console.log(`SEED_UPSERTED=${seedName}:${seedAmount}`);
  }
}

main().catch((err) => {
  console.error(`PROD_READY=0 ERROR=${err instanceof Error ? err.message : String(err)}`);
  process.exitCode = 1;
});
