/*
 * Saweria -> Google Sheets -> Roblox donation bridge.
 *
 * Deploy:
 * 1. Create a Google Sheet.
 * 2. Extensions -> Apps Script.
 * 3. Paste this file.
 * 4. Run setup() once and authorize.
 * 5. Deploy -> New deployment -> Web app.
 * 6. Execute as: Me. Who has access: Anyone.
 * 7. Copy /exec URL to Config.Donation.SHEETS_WEB_APP_URL.
 * 8. Set Saweria webhook URL to the same /exec URL.
 */

const CONFIG = {
  SPREADSHEET_ID: "", // blank = active spreadsheet
  OPTIONAL_SECRET: "", // optional. If set, POST/GET must include ?secret=...
  TIMEZONE: "Asia/Jakarta",
  SHEETS: {
    donations: "Donations",
    nameMap: "NameMap",
  },
  HEADERS: {
    donations: [
      "id",
      "unix_timestamp",
      "created_at",
      "donator_name",
      "amount_raw",
      "message",
      "status",
      "type",
      "source",
      "raw_json",
      "roblox_username",
    ],
    nameMap: ["saweria_name", "roblox_username", "mapped_at"],
  },
};

function setup() {
  const ss = getSpreadsheet_();
  ensureSheet_(ss, CONFIG.SHEETS.donations, CONFIG.HEADERS.donations);
  ensureSheet_(ss, CONFIG.SHEETS.nameMap, CONFIG.HEADERS.nameMap);
  return json_({ ok: true, message: "Sheets ready" });
}

function doGet(e) {
  try {
    assertSecret_(e);
    const action = String((e.parameter && e.parameter.action) || "ping").toLowerCase();

    if (action === "ping") {
      return json_({ ok: true, now: unixNow_() });
    }

    if (action === "leaderboard") {
      const type = String(e.parameter.type || "alltime").toLowerCase();
      const limit = clamp_(Number(e.parameter.limit || 10), 1, 100);
      return json_({ ok: true, data: buildLeaderboard_(type, limit) });
    }

    if (action === "notifications") {
      const since = Number(e.parameter.since || 0);
      return json_({ ok: true, data: getNotifications_(since) });
    }

    if (action === "namemap") {
      return json_({ ok: true, data: readNameMapList_() });
    }

    return json_({ ok: false, error: "unknown_action" });
  } catch (err) {
    return json_({ ok: false, error: String(err && err.message ? err.message : err) });
  }
}

function doPost(e) {
  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    assertSecret_(e);
    const body = parseBody_(e);
    const action = String(body.action || "").toLowerCase();

    if (action === "namemap_set") {
      const saweriaName = cleanName_(body.saweria_name || body.provider_name || body.bagibagi_name);
      const robloxUsername = cleanName_(body.roblox_username);
      if (!saweriaName || !robloxUsername) {
        return json_({ ok: false, error: "missing_name" });
      }
      setNameMap_(saweriaName, robloxUsername);
      return json_({ ok: true });
    }

    const normalized = normalizeDonation_(body);
    if (!normalized.id) {
      return json_({ ok: false, error: "missing_donation_id" });
    }
    if (normalized.amount_raw <= 0) {
      return json_({ ok: false, error: "missing_amount" });
    }

    upsertDonation_(normalized);
    return json_({ ok: true, data: normalized });
  } catch (err) {
    return json_({ ok: false, error: String(err && err.message ? err.message : err) });
  } finally {
    lock.releaseLock();
  }
}

function getSpreadsheet_() {
  if (CONFIG.SPREADSHEET_ID) {
    return SpreadsheetApp.openById(CONFIG.SPREADSHEET_ID);
  }
  const active = SpreadsheetApp.getActiveSpreadsheet();
  if (!active) {
    throw new Error("No active spreadsheet. Set CONFIG.SPREADSHEET_ID.");
  }
  return active;
}

function ensureSheet_(ss, name, headers) {
  let sheet = ss.getSheetByName(name);
  if (!sheet) {
    sheet = ss.insertSheet(name);
  }
  const range = sheet.getRange(1, 1, 1, headers.length);
  const existing = range.getValues()[0];
  const needsHeader = existing.every((value) => value === "");
  if (needsHeader) {
    range.setValues([headers]);
    sheet.setFrozenRows(1);
  } else {
    const missingHeaders = headers.filter((header) => existing.indexOf(header) === -1);
    if (missingHeaders.length > 0) {
      sheet.getRange(1, existing.length + 1, 1, missingHeaders.length).setValues([missingHeaders]);
      sheet.setFrozenRows(1);
    }
  }
  return sheet;
}

function getSheet_(name, headers) {
  return ensureSheet_(getSpreadsheet_(), name, headers);
}

function parseBody_(e) {
  const text = e && e.postData && e.postData.contents ? e.postData.contents : "";
  if (!text) {
    return {};
  }
  try {
    return JSON.parse(text);
  } catch (_err) {
    const params = {};
    text.split("&").forEach((pair) => {
      const parts = pair.split("=");
      const key = decodeURIComponent(parts[0] || "");
      const value = decodeURIComponent((parts[1] || "").replace(/\+/g, " "));
      if (key) params[key] = value;
    });
    return params;
  }
}

function assertSecret_(e) {
  if (!CONFIG.OPTIONAL_SECRET) {
    return;
  }
  const secret = e && e.parameter ? String(e.parameter.secret || "") : "";
  if (secret !== CONFIG.OPTIONAL_SECRET) {
    throw new Error("unauthorized");
  }
}

function normalizeDonation_(raw) {
  const data = raw.data && typeof raw.data === "object" ? raw.data : raw;
  const createdAt = data.created_at || data.createdAt || data.paid_at || data.timestamp || new Date().toISOString();
  const unixTimestamp = toUnix_(createdAt) || unixNow_();
  const amount = parseAmount_(
    data.amount_raw ||
      data.amount ||
      data.total ||
      data.nominal ||
      data.value ||
      0
  );
  const donorName = cleanName_(
    data.donator_name ||
      data.donor_name ||
      data.saweria_name ||
      data.name ||
      data.username ||
      "Saweria Donor"
  );
  const id = String(
    data.id ||
      data.transaction_id ||
      data.payment_id ||
      data.order_id ||
      [donorName, amount, unixTimestamp].join(":")
  );
  const message = String(data.message || data.note || data.support_message || "");
  const status = String(data.status || "success").toLowerCase();
  const type = String(data.type || data.payment_type || "donation");
  const robloxUsername = cleanName_(data.roblox_username || data.robloxUsername || "");

  return {
    id,
    unix_timestamp: unixTimestamp,
    created_at: formatDate_(unixTimestamp),
    donator_name: donorName,
    amount_raw: amount,
    message,
    status,
    type,
    source: "saweria",
    raw_json: JSON.stringify(raw),
    roblox_username: robloxUsername || getMappedRobloxUsername_(donorName) || "",
  };
}

function upsertDonation_(donation) {
  const sheet = getSheet_(CONFIG.SHEETS.donations, CONFIG.HEADERS.donations);
  const values = sheet.getDataRange().getValues();
  const headers = values[0];
  const idCol = headers.indexOf("id");
  let targetRow = values.length + 1;

  for (let i = 1; i < values.length; i++) {
    if (String(values[i][idCol]) === donation.id) {
      targetRow = i + 1;
      break;
    }
  }

  const row = headers.map((header) => donation[header] !== undefined ? donation[header] : "");
  sheet.getRange(targetRow, 1, 1, row.length).setValues([row]);
}

function buildLeaderboard_(type, limit) {
  const donations = readDonationRows_().filter((row) => isSuccess_(row.status));
  const mapped = readNameMap_();
  const today = Utilities.formatDate(new Date(), CONFIG.TIMEZONE, "yyyy-MM-dd");
  const totals = {};

  donations.forEach((row) => {
    if (type === "daily") {
      const rowDay = Utilities.formatDate(new Date(Number(row.unix_timestamp) * 1000), CONFIG.TIMEZONE, "yyyy-MM-dd");
      if (rowDay !== today) return;
    }
    const name = cleanName_(row.donator_name || "Saweria Donor");
    const key = name.toLowerCase();
    if (!totals[key]) {
      totals[key] = {
        saweria_name: name,
        provider_name: name,
        donor_name: name,
        total: 0,
        last_at: "",
        unix_timestamp: 0,
        roblox_username: row.roblox_username || mapped[key] || "",
      };
    }
    totals[key].total += Number(row.amount_raw) || 0;
    const ts = Number(row.unix_timestamp) || 0;
    if (ts >= totals[key].unix_timestamp) {
      totals[key].unix_timestamp = ts;
      totals[key].last_at = row.created_at || formatDate_(ts);
      totals[key].roblox_username = row.roblox_username || mapped[key] || totals[key].roblox_username || "";
    }
  });

  return Object.keys(totals)
    .map((key) => totals[key])
    .sort((a, b) => b.total - a.total)
    .slice(0, limit)
    .map((row, index) => Object.assign({ rank: index + 1 }, row));
}

function getNotifications_(since) {
  const mapped = readNameMap_();
  return readDonationRows_()
    .filter((row) => isSuccess_(row.status))
    .filter((row) => Number(row.unix_timestamp) > since)
    .sort((a, b) => Number(a.unix_timestamp) - Number(b.unix_timestamp))
    .map((row) => {
      const name = cleanName_(row.donator_name || "Saweria Donor");
      return {
        id: row.id,
        unix_timestamp: Number(row.unix_timestamp) || 0,
        donator_name: name,
        saweria_name: name,
        provider_name: name,
        amount_raw: Number(row.amount_raw) || 0,
        message: row.message || "",
        roblox_username: row.roblox_username || mapped[name.toLowerCase()] || "",
      };
    });
}

function readDonationRows_() {
  const sheet = getSheet_(CONFIG.SHEETS.donations, CONFIG.HEADERS.donations);
  return rowsToObjects_(sheet.getDataRange().getValues());
}

function readNameMap_() {
  const result = {};
  readNameMapList_().forEach((row) => {
    const name = cleanName_(firstValue_(row, ["saweria_name", "provider_name", "bagibagi_name", "donator_name", "donor_name", "name"]));
    const username = cleanName_(firstValue_(row, ["roblox_username", "robloxUsername", "username", "roblox_name", "robloxName", "player_name"])).replace(/^@/, "");
    if (name && username) {
      result[name.toLowerCase()] = username;
    }
  });
  return result;
}

function readNameMapList_() {
  const sheet = getSheet_(CONFIG.SHEETS.nameMap, CONFIG.HEADERS.nameMap);
  return rowsToObjects_(sheet.getDataRange().getValues());
}

function setNameMap_(saweriaName, robloxUsername) {
  const sheet = getSheet_(CONFIG.SHEETS.nameMap, CONFIG.HEADERS.nameMap);
  const values = sheet.getDataRange().getValues();
  const headers = values[0];
  const nameCol = headers.indexOf("saweria_name");
  let rowIndex = values.length + 1;
  for (let i = 1; i < values.length; i++) {
    if (String(values[i][nameCol]).toLowerCase() === saweriaName.toLowerCase()) {
      rowIndex = i + 1;
      break;
    }
  }
  const row = headers.map((header) => {
    if (header === "saweria_name") return saweriaName;
    if (header === "roblox_username") return robloxUsername;
    if (header === "mapped_at") return formatDate_(unixNow_());
    return "";
  });
  sheet.getRange(rowIndex, 1, 1, row.length).setValues([row]);
}

function getMappedRobloxUsername_(saweriaName) {
  const mapped = readNameMap_();
  return mapped[cleanName_(saweriaName).toLowerCase()] || "";
}

function rowsToObjects_(values) {
  if (!values || values.length < 2) return [];
  const headers = values[0].map((header) => String(header));
  return values.slice(1).filter((row) => row.some((value) => value !== "")).map((row) => {
    const object = {};
    headers.forEach((header, index) => {
      object[header] = row[index];
    });
    return object;
  });
}

function firstValue_(object, keys) {
  for (let i = 0; i < keys.length; i++) {
    const value = object[keys[i]];
    if (value !== undefined && value !== null && String(value).trim() !== "") {
      return value;
    }
  }
  return "";
}

function isSuccess_(status) {
  const value = String(status || "success").toLowerCase();
  return value === "success" || value === "paid" || value === "completed" || value === "settlement";
}

function cleanName_(value) {
  return String(value || "").trim();
}

function parseAmount_(value) {
  if (typeof value === "number") {
    return value;
  }
  const text = String(value || "").trim();
  if (!text) {
    return 0;
  }
  const digitsOnly = text.replace(/[^\d]/g, "");
  if (digitsOnly) {
    return Number(digitsOnly);
  }
  return Number(text) || 0;
}

function clamp_(value, min, max) {
  return Math.max(min, Math.min(max, Math.floor(value || min)));
}

function toUnix_(value) {
  if (typeof value === "number") {
    return Math.floor(value > 1000000000000 ? value / 1000 : value);
  }
  const parsed = Date.parse(String(value || ""));
  if (Number.isNaN(parsed)) {
    return 0;
  }
  return Math.floor(parsed / 1000);
}

function unixNow_() {
  return Math.floor(Date.now() / 1000);
}

function formatDate_(unixTimestamp) {
  return Utilities.formatDate(new Date(Number(unixTimestamp) * 1000), CONFIG.TIMEZONE, "yyyy-MM-dd HH:mm:ss");
}

function json_(payload) {
  return ContentService
    .createTextOutput(JSON.stringify(payload))
    .setMimeType(ContentService.MimeType.JSON);
}
