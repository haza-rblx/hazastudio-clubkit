const apiBase = (process.env.LOCAL_API_BASE || "http://127.0.0.1:8787").replace(/\/$/, "");
const adminToken = process.env.LOCAL_ADMIN_TOKEN || "local-dev-admin-token";
const gameId = (process.env.LOCAL_GAME_ID || "rust-local").toLowerCase();
const gameName = process.env.LOCAL_GAME_NAME || "Rust Local";
const saweriaLink = process.env.LOCAL_SAWERIA_LINK || `https://saweria.co/${gameId.replace(/-/g, "")}`;
const seedName = process.env.LOCAL_SEED_NAME || "";
const seedAmount = Number(process.env.LOCAL_SEED_AMOUNT || 0);

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

async function waitForHealth(maxRetry = 30) {
  for (let attempt = 1; attempt <= maxRetry; attempt += 1) {
    try {
      const res = await fetch(`${apiBase}/health`);
      if (res.ok) {
        return;
      }
    } catch {}
    await sleep(1000);
  }
  throw new Error(`worker_unreachable: ${apiBase}/health`);
}

async function main() {
  await waitForHealth();

  const created = await request("/admin/games", {
    method: "POST",
    body: JSON.stringify({
      id: gameId,
      display_name: gameName,
      saweria_link: saweriaLink,
    }),
  });

  if (seedName && seedAmount > 0) {
    await request(`/admin/games/${gameId}/seed`, {
      method: "POST",
      body: JSON.stringify({
        saweria_name: seedName,
        total_amount: seedAmount,
        note: "local-bootstrap",
      }),
    });
  }

  const game = created.game;
  const endpoints = created.endpoints || game.endpoints;

  console.log("LOCAL_READY=1");
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
  if (seedName && seedAmount > 0) {
    console.log(`SEED_UPSERTED=${seedName}:${seedAmount}`);
  }
}

main().catch((err) => {
  console.error(`LOCAL_READY=0 ERROR=${err instanceof Error ? err.message : String(err)}`);
  process.exitCode = 1;
});
