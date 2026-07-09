/**
 * License routes for Club Kit v1.3+.
 *
 * Backward compatibility:
 * - license_enforced = 0 → v2 API behaves as before (only explicit revoked/expired blocks).
 * - license_enforced = 1 → set on first verify; universe bind + maintenance checks apply.
 */

import { cleanString, getGameByKey } from "./game-data.js";

const VALID_STATUSES = new Set(["active", "grace", "expired", "revoked"]);

function nowIso() {
  return new Date().toISOString();
}

export function licensePayload(game) {
  return {
    license_status: cleanString(game?.license_status, "active"),
    license_enforced: Number(game?.license_enforced) === 1,
    universe_id: cleanString(game?.universe_id),
    place_id: cleanString(game?.place_id),
    license_note: cleanString(game?.license_note),
    maintenance_until: cleanString(game?.maintenance_until),
    last_seen_at: cleanString(game?.last_seen_at),
    last_seen_universe_id: cleanString(game?.last_seen_universe_id),
    kit_build_id: cleanString(game?.kit_build_id),
  };
}

/**
 * Returns whether v2 game API calls should be blocked.
 * Legacy games (license_enforced = 0) are only blocked on explicit revoked/expired.
 */
export function isLicenseBlocked(game) {
  const status = cleanString(game?.license_status, "active");
  if (status === "revoked" || status === "expired") {
    return { blocked: true, error: `license_${status}` };
  }

  const enforced = Number(game?.license_enforced) === 1;
  if (!enforced) {
    return { blocked: false };
  }

  if (status === "grace") {
    return { blocked: true, error: "license_expired" };
  }

  const until = cleanString(game?.maintenance_until);
  if (until && status === "active") {
    const untilMs = Date.parse(until);
    if (Number.isFinite(untilMs) && Date.now() > untilMs) {
      return { blocked: true, error: "license_expired" };
    }
  }

  return { blocked: false };
}

export function licenseFeatures(game) {
  const block = isLicenseBlocked(game);
  const ok = !block.blocked;
  return {
    donation_http: ok,
    shop_grant: ok,
    admin_commands: ok,
  };
}

export async function handleLicenseVerify(req, env, game, json, body) {
  const universeId = String(Math.floor(Number(body?.universe_id) || 0));
  const placeId = String(Math.floor(Number(body?.place_id) || 0));
  const kitBuildId = cleanString(body?.build_id);

  if (universeId === "0") {
    return json(req, env, { ok: false, error: "validation_failed" }, 422);
  }

  let boundUniverse = cleanString(game.universe_id);
  if (boundUniverse === "") {
    await env.DB.prepare(
      "UPDATE games SET universe_id = ?, place_id = ?, license_enforced = 1 WHERE id = ?",
    )
      .bind(universeId, placeId, game.id)
      .run();
    boundUniverse = universeId;
  } else if (boundUniverse !== universeId) {
    return json(req, env, { ok: false, error: "universe_mismatch", status: cleanString(game.license_status, "active") }, 403);
  } else if (Number(game.license_enforced) !== 1) {
    await env.DB.prepare("UPDATE games SET license_enforced = 1 WHERE id = ?").bind(game.id).run();
  }

  await env.DB.prepare(
    "UPDATE games SET last_seen_at = ?, last_seen_universe_id = ?, kit_build_id = ? WHERE id = ?",
  )
    .bind(nowIso(), universeId, kitBuildId, game.id)
    .run();

  const refreshed = await getGameByKey(env.DB, game.game_key);
  const block = isLicenseBlocked(refreshed);
  const features = licenseFeatures(refreshed);
  const status = cleanString(refreshed.license_status, "active");

  return json(req, env, {
    ok: !block.blocked,
    status,
    universe_bound: boundUniverse !== "",
    features,
    checked_at: nowIso(),
    next_check_seconds: 1800,
    error: block.blocked ? block.error : undefined,
  });
}

export async function handleAdminLicenseGet(req, env, game, json) {
  return json(req, env, { ok: true, license: licensePayload(game) });
}

export async function handleAdminLicensePatch(req, env, gameKey, game, json, body) {
  const nextStatus = cleanString(body?.license_status, cleanString(game.license_status, "active"));
  if (!VALID_STATUSES.has(nextStatus)) {
    return json(req, env, { ok: false, error: "invalid_license_status" }, 422);
  }

  const note = body?.license_note !== undefined ? cleanString(body.license_note) : cleanString(game.license_note);
  const maintenanceUntil =
    body?.maintenance_until !== undefined
      ? cleanString(body.maintenance_until)
      : cleanString(game.maintenance_until);

  let universeId = cleanString(game.universe_id);
  let placeId = cleanString(game.place_id);
  let licenseEnforced = Number(game.license_enforced) === 1 ? 1 : 0;

  if (body?.rebind === true) {
    universeId = "";
    placeId = "";
    licenseEnforced = 0;
  } else {
    if (body?.universe_id !== undefined) {
      universeId = cleanString(body.universe_id);
    }
    if (body?.place_id !== undefined) {
      placeId = cleanString(body.place_id);
    }
    if (body?.license_enforced === true) {
      licenseEnforced = 1;
    } else if (body?.license_enforced === false) {
      licenseEnforced = 0;
    }
  }

  await env.DB.prepare(
    `UPDATE games SET
      license_status = ?,
      license_note = ?,
      maintenance_until = ?,
      universe_id = ?,
      place_id = ?,
      license_enforced = ?
    WHERE id = ?`,
  )
    .bind(nextStatus, note, maintenanceUntil, universeId, placeId, licenseEnforced, game.id)
    .run();

  const refreshed = await getGameByKey(env.DB, gameKey);
  return json(req, env, { ok: true, license: licensePayload(refreshed), game_key: gameKey });
}
