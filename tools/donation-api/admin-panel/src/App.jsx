import { useEffect, useMemo, useState } from "react";
import {
  Activity,
  AlertTriangle,
  ArrowDownUp,
  CheckCircle2,
  ClipboardList,
  Copy,
  Database,
  Download,
  Edit3,
  ExternalLink,
  Flame,
  Gamepad2,
  Gauge,
  KeyRound,
  Link2,
  ListFilter,
  Loader2,
  Moon,
  MoreHorizontal,
  Package,
  Plus,
  RefreshCw,
  RotateCcw,
  Search,
  Send,
  Server,
  Settings,
  Shield,
  Sun,
  TestTube,
  Trash2,
  Trophy,
  Users,
  X,
} from "lucide-react";
import "./App.css";

const navItems = [
  { id: "delivery", label: "New delivery", icon: Package, masterOnly: true },
  { id: "overview", label: "Overview", icon: Gauge },
  { id: "donations", label: "Donations", icon: Activity },
  { id: "leaderboard", label: "Leaderboard", icon: Trophy },
  { id: "links", label: "Donor Links", icon: Link2 },
  { id: "events", label: "Events", icon: ClipboardList },
  { id: "test", label: "Test", icon: TestTube },
  { id: "games", label: "Games", icon: Gamepad2 },
  { id: "settings", label: "Settings", icon: Settings },
];

const formatIdr = (n) => `Rp ${Number(n || 0).toLocaleString("id-ID")}`;
const formatDateTime = (value) => {
  if (!value) return "-";
  const ms = typeof value === "number" ? value * 1000 : Date.parse(value);
  if (!Number.isFinite(ms)) return "-";
  return new Date(ms).toLocaleString("id-ID", { dateStyle: "medium", timeStyle: "short" });
};
const maskToken = (value) => (value ? `${value.slice(0, 10)}...${value.slice(-5)}` : "-");

function addMonthsIso(months) {
  const d = new Date();
  d.setUTCMonth(d.getUTCMonth() + (Number(months) || 1));
  return d.toISOString();
}

function normalizeGameId(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, "-")
    .replace(/[^a-z0-9_-]/g, "")
    .replace(/^[^a-z0-9]+/, "")
    .slice(0, 49);
}

function buildClubKitConfigText(game) {
  return [
    "-- ClubKitConfig.luau (Donation + GameDataApi)",
    'ClubKitConfig.Donation = {',
    '  Provider = "bagibagi", -- atau "saweria"',
    `  ApiUrl = "${game?.clubkit?.donation_api_url || ""}",`,
    "}",
    "ClubKitConfig.GameDataApi = {",
    `  GameKey = "${game?.clubkit?.social_game_key || ""}",`,
    "}",
    "",
    "-- Secrets.luau",
    game?.clubkit?.donation_api_secret,
    game?.clubkit?.social_api_secret,
  ].join("\n");
}

function buildDeliverySetupText(game, meta = {}) {
  const { clientNote = "", maintenanceUntil = "" } = meta;
  return [
    "═══════════════════════════════════════════",
    "  Hazastudio Club Kit — Delivery Package",
    "═══════════════════════════════════════════",
    "",
    `Game key     : ${game?.id || ""}`,
    `Display name : ${game?.display_name || ""}`,
    clientNote ? `Client       : ${clientNote}` : null,
    maintenanceUntil ? `Maintenance  : until ${maintenanceUntil}` : "Maintenance  : (not scheduled)",
    "",
    "── WEBHOOK (paste ke dashboard Saweria / Bagi-Bagi) ──",
    "",
    "Saweria:",
    game?.endpoints?.saweria_webhook || "",
    "",
    "Bagi-Bagi:",
    game?.endpoints?.bagibagi_webhook || "",
    "",
    "── ROBLOX CONFIG (copy ke Studio) ──",
    "",
    buildClubKitConfigText(game),
    "",
    "── CLIENT CHECKLIST ──",
    "",
    "[ ] Import .rbxm ke universe target (1 license = 1 universe)",
    "[ ] Isi GroupId, OwnerUserId, Shop Product IDs",
    "[ ] Paste webhook URLs di provider donasi",
    "[ ] Enable HttpService di Game Settings",
    "[ ] Publish place",
    "[ ] Test donasi kecil → notifikasi masuk in-game",
    "",
    "License ter-bind otomatis saat server pertama boot (Club Kit v1.3+).",
    "Admin: https://hazastudio-donation-admin.pages.dev",
    "",
  ]
    .filter((line) => line !== null)
    .join("\n");
}

function downloadTextFile(filename, content) {
  const blob = new Blob([content], { type: "text/plain;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  URL.revokeObjectURL(url);
}

const base = (url) => String(url || "").replace(/\/$/, "");
const isLocalHost = typeof window !== "undefined" && /^(localhost|127\.0\.0\.1)$/i.test(window.location.hostname);
const localApiBase = "http://127.0.0.1:8787";
const prodApiBase = "https://hazastudio-donation-api.hazastudio.workers.dev";
const defaultApiBase = import.meta.env.VITE_DEFAULT_API_BASE || (isLocalHost ? localApiBase : prodApiBase);
const defaultAdminToken = import.meta.env.VITE_DEFAULT_ADMIN_TOKEN || (isLocalHost ? "local-dev-admin-token" : "");

function isLocalApiUrl(value) {
  return /^https?:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/i.test(String(value || "").trim());
}

function readInitialBaseUrl() {
  const saved = localStorage.getItem("admin_base_url");
  if (saved && !isLocalHost && !isLocalApiUrl(saved)) return saved;
  if (saved && isLocalHost) return saved;
  return defaultApiBase;
}

function readInitialToken() {
  const saved = localStorage.getItem("admin_token");
  if (!saved) return defaultAdminToken;
  if (!isLocalHost && saved === "local-dev-admin-token") return "";
  return saved;
}

function readInitialTheme() {
  const saved = localStorage.getItem("admin_theme");
  if (saved === "dark" || saved === "light") return saved;
  if (typeof window !== "undefined" && window.matchMedia("(prefers-color-scheme: dark)").matches) {
    return "dark";
  }
  return "light";
}

function applyTheme(theme) {
  document.documentElement.dataset.theme = theme;
  localStorage.setItem("admin_theme", theme);
}

async function api(baseUrl, token, path, options = {}) {
  const res = await fetch(`${base(baseUrl)}${path}`, {
    ...options,
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${token}`,
      ...(options.headers || {}),
    },
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok || data?.ok === false) throw new Error(data?.error || `HTTP ${res.status}`);
  return data;
}

export default function App() {
  const [baseUrl, setBaseUrl] = useState(readInitialBaseUrl);
  const [token, setToken] = useState(readInitialToken);
  const [theme, setTheme] = useState(readInitialTheme);
  const [connected, setConnected] = useState(false);
  const [games, setGames] = useState([]);
  const [selectedGame, setSelectedGame] = useState("");
  const [page, setPage] = useState("overview");
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [busy, setBusy] = useState(false);
  const [donations, setDonations] = useState([]);
  const [seedRows, setSeedRows] = useState([]);
  const [links, setLinks] = useState([]);
  const [rankings, setRankings] = useState([]);
  const [rankTotal, setRankTotal] = useState(0);
  const [rankSearch, setRankSearch] = useState("");
  const [donationSearch, setDonationSearch] = useState("");
  const [modal, setModal] = useState(null);
  const [newGame, setNewGame] = useState({ id: "", display_name: "", saweria_link: "" });
  const [linkForm, setLinkForm] = useState({ saweria_name: "", roblox_username: "", roblox_user_id: "" });
  const [adjustForm, setAdjustForm] = useState({ saweria_name: "", current_total: 0, delta_amount: "", reason: "" });
  const [tokenReveal, setTokenReveal] = useState(null);
  const [scope, setScope] = useState("");
  const [webhookEvents, setWebhookEvents] = useState([]);
  const [webhookEventsTotal, setWebhookEventsTotal] = useState(0);
  const [dailyLeaderboard, setDailyLeaderboard] = useState([]);
  const [leaderboardTab, setLeaderboardTab] = useState("alltime");
  const [testForm, setTestForm] = useState({ saweria_name: "", amount: "", message: "Test donation", roblox_username: "" });
  const [testApiResponse, setTestApiResponse] = useState(null);
  const [testApiAction, setTestApiAction] = useState("ping");
  const [gameStats, setGameStats] = useState(null);
  const [selectedDonations, setSelectedDonations] = useState(new Set());
  const [bulkLinkText, setBulkLinkText] = useState("");
  const [donorDetail, setDonorDetail] = useState(null);
  const [scopedLinkForm, setScopedLinkForm] = useState({ game_keys: [], expires_in_hours: 24 });
  const [scopedLinkResult, setScopedLinkResult] = useState(null);
  const [licenseForm, setLicenseForm] = useState({
    license_status: "active",
    license_note: "",
    maintenance_until: "",
  });
  const [deliveryForm, setDeliveryForm] = useState({
    game_id: "",
    display_name: "",
    provider_link: "",
    client_note: "",
    maintenance_months: 1,
    skip_maintenance: false,
  });
  const [deliveryResult, setDeliveryResult] = useState(null);

  useEffect(() => {
    applyTheme(theme);
  }, [theme]);

  function toggleTheme() {
    setTheme((current) => (current === "dark" ? "light" : "dark"));
  }

  const activeGame = useMemo(() => games.find((g) => g.id === selectedGame) || null, [games, selectedGame]);

  useEffect(() => {
    const license = activeGame?.license;
    if (!license) return;
    setLicenseForm({
      license_status: license.license_status || "active",
      license_note: license.license_note || "",
      maintenance_until: license.maintenance_until || "",
    });
  }, [activeGame]);

  const successfulDonations = donations.filter((row) => !row.is_voided);
  const totalDonations = successfulDonations.reduce((sum, row) => sum + Number(row.amount || 0), 0);
  const totalAdjustments = seedRows.reduce((sum, row) => sum + Number(row.total_amount || 0), 0);
  const topDonor = rankings[0] || null;
  const filteredDonations = donationSearch.trim()
    ? donations.filter((row) =>
        `${row.saweria_name} ${row.message || ""}`.toLowerCase().includes(donationSearch.trim().toLowerCase()),
      )
    : donations;

  async function run(task, success) {
    setBusy(true);
    setError("");
    setNotice("");
    try {
      await task();
      if (success) setNotice(success);
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  }

  async function loadGames(nextSelected = selectedGame) {
    const res = await api(baseUrl, token, "/admin/whoami");
    const list = res.games || [];
    const next = nextSelected && list.some((game) => game.id === nextSelected) ? nextSelected : list[0]?.id || "";
    setGames(list);
    setSelectedGame(next);
    setScope(res.scope || "");
    setConnected(true);
    return next;
  }

  async function loadPageData(targetPage = page, gameId = selectedGame) {
    if (!gameId) return;
    if (targetPage === "overview") {
      const [donationsRes, rankingsRes, linksRes, seedRes] = await Promise.all([
        api(baseUrl, token, `/admin/games/${gameId}/donations?limit=8&offset=0&voided=all`),
        api(baseUrl, token, `/admin/games/${gameId}/rankings?limit=5&offset=0&q=`),
        api(baseUrl, token, `/admin/games/${gameId}/links`),
        api(baseUrl, token, `/admin/games/${gameId}/seed`),
      ]);
      setDonations(donationsRes.donations || []);
      setRankings(rankingsRes.rankings || []);
      setRankTotal(Number(rankingsRes.total || 0));
      setLinks(linksRes.links || []);
      setSeedRows(seedRes.entries || []);
      return;
    }
    if (targetPage === "donations") {
      const res = await api(baseUrl, token, `/admin/games/${gameId}/donations?limit=100&offset=0&voided=all`);
      setDonations(res.donations || []);
      return;
    }
    if (targetPage === "leaderboard") {
      const q = encodeURIComponent(rankSearch.trim());
      const res = await api(baseUrl, token, `/admin/games/${gameId}/rankings?limit=500&offset=0&q=${q}`);
      setRankings(res.rankings || []);
      setRankTotal(Number(res.total || 0));
      return;
    }
    if (targetPage === "links") {
      const res = await api(baseUrl, token, `/admin/games/${gameId}/links`);
      setLinks(res.links || []);
      return;
    }
    if (targetPage === "events") {
      const res = await api(baseUrl, token, `/admin/games/${gameId}/webhook-events?limit=50&offset=0`);
      setWebhookEvents(res.events || []);
      setWebhookEventsTotal(Number(res.total || 0));
      return;
    }
    if (targetPage === "test") {
      setTestApiResponse(null);
      return;
    }
    if (targetPage === "games") {
      await loadGames(gameId);
      return;
    }
    if (targetPage === "settings") {
      const res = await api(baseUrl, token, `/admin/games/${gameId}/license`);
      if (res.license) {
        setLicenseForm({
          license_status: res.license.license_status || "active",
          license_note: res.license.license_note || "",
          maintenance_until: res.license.maintenance_until || "",
        });
      }
    }
  }

  async function connect() {
    if (!baseUrl || !token) {
      setError("Fill Worker URL and admin token first.");
      return;
    }
    if (!isLocalHost && isLocalApiUrl(baseUrl)) {
      setError("This is the web panel. Use the production Worker URL, not localhost.");
      return;
    }
    await run(async () => {
      localStorage.setItem("admin_base_url", baseUrl);
      localStorage.setItem("admin_token", token);
      const next = await loadGames();
      if (next) await loadPageData("overview", next);
      setPage("overview");
    }, "Connected.");
  }

  async function refreshCurrent() {
    await run(async () => {
      const next = await loadGames(selectedGame);
      await loadPageData(page, selectedGame || next);
    }, "Data refreshed.");
  }

  async function selectPage(nextPage) {
    setPage(nextPage);
    if (nextPage === "delivery") {
      if (!deliveryResult) {
        setDeliveryForm((current) => ({
          ...current,
          maintenance_months: current.maintenance_months || 1,
        }));
      }
      return;
    }
    if (!selectedGame && nextPage !== "games" && nextPage !== "settings") return;
    await run(async () => loadPageData(nextPage, selectedGame));
  }

  async function changeGame(gameId) {
    setSelectedGame(gameId);
    await run(async () => loadPageData(page, gameId), "Game changed.");
  }

  async function createGame(e) {
    e.preventDefault();
    await run(async () => {
      const res = await api(baseUrl, token, "/admin/games", { method: "POST", body: JSON.stringify(newGame) });
      setNewGame({ id: "", display_name: "", saweria_link: "" });
      const createdToken = res.admin_token;
      if (createdToken) {
        setTokenReveal({ token: createdToken, label: `Admin token for ${res.game?.display_name || newGame.id}` });
      } else {
        setModal(null);
      }
      const next = await loadGames(res.game?.id || "");
      setPage("overview");
      await loadPageData("overview", next);
    }, "Game created.");
  }

  async function createLink(e) {
    e.preventDefault();
    await run(async () => {
      await api(baseUrl, token, `/admin/games/${selectedGame}/links`, {
        method: "POST",
        body: JSON.stringify({
          saweria_name: linkForm.saweria_name,
          roblox_username: linkForm.roblox_username,
          roblox_user_id: linkForm.roblox_user_id ? Number(linkForm.roblox_user_id) : null,
        }),
      });
      setLinkForm({ saweria_name: "", roblox_username: "", roblox_user_id: "" });
      setModal(null);
      await loadPageData("links", selectedGame);
    }, "Donor link saved.");
  }

  async function toggleVoid(row) {
    await run(
      async () => {
        await api(baseUrl, token, `/admin/donations/${row.id}`, {
          method: "PATCH",
          body: JSON.stringify({ is_voided: !row.is_voided, voided_reason: row.is_voided ? "" : "manual_admin" }),
        });
        await loadPageData(page, selectedGame);
      },
      row.is_voided ? "Donation restored." : "Donation voided.",
    );
  }

  function openAdjust(row) {
    setAdjustForm({
      saweria_name: row.saweria_name,
      current_total: Number(row.total_amount || 0),
      delta_amount: "",
      reason: "",
    });
    setModal("adjust");
  }

  async function applyAdjustment(e) {
    e.preventDefault();
    const delta = Math.trunc(Number(adjustForm.delta_amount));
    if (!Number.isFinite(delta) || delta === 0) {
      setError("Adjustment amount must be a non-zero number.");
      return;
    }
    await run(async () => {
      await api(baseUrl, token, `/admin/games/${selectedGame}/rankings/adjust`, {
        method: "POST",
        body: JSON.stringify({
          saweria_name: adjustForm.saweria_name,
          delta_amount: delta,
          note: adjustForm.reason || "manual_adjustment",
        }),
      });
      setModal(null);
      await loadPageData("leaderboard", selectedGame);
    }, `Adjusted ${adjustForm.saweria_name}.`);
  }

  async function rotate(kind) {
    const labels = {
      secret: "Roblox secret",
      social: "Social API secret",
      webhook: "Saweria webhook token",
      admin: "Admin token",
    };
    const label = labels[kind] || kind;
    if (!confirm(`Rotate ${label}? Existing endpoint or token will stop working immediately.`)) return;
    const endpoint =
      kind === "secret"
        ? "rotate-secret"
        : kind === "social"
          ? "rotate-social-secret"
          : kind === "webhook"
            ? "rotate-webhook"
            : "rotate-admin-token";
    await run(async () => {
      const res = await api(baseUrl, token, `/admin/games/${selectedGame}/${endpoint}`, { method: "POST" });
      if (kind === "admin" && res.admin_token) {
        setTokenReveal({ token: res.admin_token, label: `New admin token for ${selectedGame}` });
      }
      await loadGames(selectedGame);
    }, `${label} rotated.`);
  }

  async function saveLicense(e) {
    e.preventDefault();
    if (!selectedGame) return;
    await run(async () => {
      await api(baseUrl, token, `/admin/games/${selectedGame}/license`, {
        method: "PATCH",
        body: JSON.stringify(licenseForm),
      });
      await loadGames(selectedGame);
    }, "License updated.");
  }

  async function rebindLicense() {
    if (!selectedGame) return;
    if (!confirm("Clear universe bind? Club Kit v1.3+ will bind again on next server boot.")) return;
    await run(async () => {
      await api(baseUrl, token, `/admin/games/${selectedGame}/license`, {
        method: "PATCH",
        body: JSON.stringify({ rebind: true, license_status: licenseForm.license_status }),
      });
      await loadGames(selectedGame);
      const res = await api(baseUrl, token, `/admin/games/${selectedGame}/license`);
      if (res.license) {
        setLicenseForm({
          license_status: res.license.license_status || "active",
          license_note: res.license.license_note || "",
          maintenance_until: res.license.maintenance_until || "",
        });
      }
    }, "Universe bind cleared.");
  }

  async function runDelivery(e) {
    e.preventDefault();
    const gameId = normalizeGameId(deliveryForm.game_id);
    if (!/^[a-z0-9][a-z0-9_-]{1,48}$/.test(gameId)) {
      setError("Game ID must be 2–49 chars: lowercase letters, numbers, hyphen, underscore.");
      return;
    }
    await run(async () => {
      const createRes = await api(baseUrl, token, "/admin/games", {
        method: "POST",
        body: JSON.stringify({
          id: gameId,
          display_name: deliveryForm.display_name.trim() || gameId,
          saweria_link: deliveryForm.provider_link.trim(),
        }),
      });
      const maintenanceUntil = deliveryForm.skip_maintenance
        ? ""
        : addMonthsIso(deliveryForm.maintenance_months);
      await api(baseUrl, token, `/admin/games/${gameId}/license`, {
        method: "PATCH",
        body: JSON.stringify({
          license_status: "active",
          license_note: deliveryForm.client_note.trim(),
          maintenance_until: maintenanceUntil,
        }),
      });
      const gameRes = await api(baseUrl, token, `/admin/games/${gameId}`);
      const game = gameRes.game;
      if (createRes.admin_token) {
        setTokenReveal({
          token: createRes.admin_token,
          label: `Scoped admin token for ${game.display_name || gameId}`,
        });
      }
      setDeliveryResult({
        game,
        clientNote: deliveryForm.client_note.trim(),
        maintenanceUntil,
      });
      await loadGames(gameId);
      setSelectedGame(gameId);
      setDeliveryForm({
        game_id: "",
        display_name: "",
        provider_link: "",
        client_note: "",
        maintenance_months: 1,
        skip_maintenance: false,
      });
    }, "Delivery package ready.");
  }

  function openNewDelivery() {
    setDeliveryResult(null);
    setPage("delivery");
  }

  async function copy(text, message) {
    await navigator.clipboard.writeText(text || "");
    setNotice(message || "Copied.");
  }

  function exportRankings() {
    const header = ["rank", "saweria_name", "live_total", "adjustment_total", "total_amount", "last_donation_at"];
    const rows = rankings.map((row) => [
      row.rank,
      row.saweria_name,
      row.live_total,
      row.seed_total,
      row.total_amount,
      row.last_donation_at ? new Date(row.last_donation_at * 1000).toISOString() : "",
    ]);
    const csv = [header, ...rows]
      .map((line) => line.map((cell) => `"${String(cell ?? "").replace(/"/g, '""')}"`).join(","))
      .join("\n");
    const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${selectedGame || "game"}-leaderboard.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  async function injectTestNotification(e) {
    e.preventDefault();
    await run(async () => {
      const res = await api(baseUrl, token, `/admin/games/${selectedGame}/test-notification`, {
        method: "POST",
        body: JSON.stringify(testForm),
      });
      setNotice(`Test donation injected (ID: ${res.donation_id}). Game will pick it up on next poll.`);
    });
  }

  async function testApiCall() {
    await run(async () => {
      let url = `/admin/games/${selectedGame}/test-api?action=${testApiAction}`;
      if (testApiAction === "leaderboard") url += "&type=alltime&limit=5";
      if (testApiAction === "notifications") url += "&since=0&limit=5";
      if (testApiAction === "donor_profile") url += "&user_id=0&username=test";
      const res = await api(baseUrl, token, url);
      setTestApiResponse(res);
    });
  }

  async function loadDailyLeaderboard() {
    await run(async () => {
      const res = await api(baseUrl, token, `/admin/games/${selectedGame}/daily-leaderboard?limit=100`);
      setDailyLeaderboard(res.data || []);
    });
  }

  async function loadGameStats() {
    await run(async () => {
      const res = await api(baseUrl, token, `/admin/games/${selectedGame}/stats`);
      setGameStats(res.stats || null);
    });
  }

  async function bulkVoidDonations() {
    const ids = [...selectedDonations];
    if (ids.length === 0) { setError("Select donations first."); return; }
    if (!confirm(`Void ${ids.length} donations?`)) return;
    await run(async () => {
      await api(baseUrl, token, `/admin/games/${selectedGame}/bulk-void`, {
        method: "POST",
        body: JSON.stringify({ donation_ids: ids, reason: "admin_bulk_void" }),
      });
      setSelectedDonations(new Set());
      await loadPageData("donations", selectedGame);
    }, `Voided ${ids.length} donations.`);
  }

  async function bulkAddLinks(e) {
    e.preventDefault();
    const lines = bulkLinkText.split("\n").filter(Boolean);
    const links = lines.map((line) => {
      const parts = line.split(/[=|>]+/).map((s) => s.trim());
      return { saweria_name: parts[0] || "", roblox_username: parts[1] || "" };
    }).filter((l) => l.saweria_name && l.roblox_username);
    if (links.length === 0) { setError("No valid links. Format: saweria_name => roblox_username"); return; }
    await run(async () => {
      const res = await api(baseUrl, token, `/admin/games/${selectedGame}/bulk-link`, {
        method: "POST",
        body: JSON.stringify({ links }),
      });
      setBulkLinkText("");
      setModal(null);
      await loadPageData("links", selectedGame);
    }, `Created ${res.created} links, skipped ${res.skipped}.`);
  }

  async function loadDonorDetail(donorName) {
    await run(async () => {
      const res = await api(baseUrl, token, `/admin/games/${selectedGame}/donor/${encodeURIComponent(donorName)}`);
      setDonorDetail(res);
    });
  }

  async function generateScopedLink(e) {
    e.preventDefault();
    await run(async () => {
      const res = await api(baseUrl, token, `/admin/games/${selectedGame}/generate-link`, {
        method: "POST",
        body: JSON.stringify(scopedLinkForm),
      });
      setScopedLinkResult(res);
    }, "Scoped link generated.");
  }

  function toggleDonationSelect(id) {
    setSelectedDonations((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  }

  function toggleAllDonations() {
    if (selectedDonations.size === filteredDonations.length) {
      setSelectedDonations(new Set());
    } else {
      setSelectedDonations(new Set(filteredDonations.map((r) => r.id)));
    }
  }

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <span className="brand-mark">DO</span>
          <div>
            <strong>Donation Ops</strong>
            <span>Admin dashboard</span>
          </div>
        </div>
        <nav className="side-nav" aria-label="Dashboard sections">
          {navItems
            .filter((item) => !item.masterOnly || scope !== "game")
            .map((item) => {
            const Icon = item.icon;
            return (
              <button
                key={item.id}
                className={`nav-item ${page === item.id ? "active" : ""} ${item.id === "delivery" ? "nav-item-accent" : ""}`}
                onClick={() => selectPage(item.id)}
              >
                <Icon size={18} />
                <span>{item.label}</span>
              </button>
            );
          })}
        </nav>
        <div className="sidebar-footer">
          <button
            type="button"
            className="theme-toggle"
            onClick={toggleTheme}
            aria-label={theme === "dark" ? "Switch to light mode" : "Switch to dark mode"}
            title={theme === "dark" ? "Light mode" : "Dark mode"}
          >
            <span>{theme === "dark" ? "Light mode" : "Dark mode"}</span>
            {theme === "dark" ? <Sun size={16} /> : <Moon size={16} />}
          </button>
          <StatusPill connected={connected} />
          <span>{baseUrl.replace(/^https?:\/\//, "")}</span>
        </div>
      </aside>

      <div className="main-shell">
        <header className="topbar">
          <div className="topbar-group">
            <select
              value={selectedGame}
              onChange={(e) => changeGame(e.target.value)}
              disabled={!connected || !games.length}
            >
              {!games.length ? <option value="">No games loaded</option> : null}
              {games.map((game) => (
                <option key={game.id} value={game.id}>
                  {game.display_name}
                </option>
              ))}
            </select>
            {activeGame ? <span className="game-key">{activeGame.id}</span> : null}
          </div>
          <div className="topbar-actions">
            <button
              type="button"
              className="icon-button theme-toggle-topbar"
              onClick={toggleTheme}
              aria-label={theme === "dark" ? "Switch to light mode" : "Switch to dark mode"}
              title={theme === "dark" ? "Light mode" : "Dark mode"}
            >
              {theme === "dark" ? <Sun size={17} /> : <Moon size={17} />}
            </button>
            <button
              className="icon-button"
              onClick={refreshCurrent}
              disabled={busy || !connected}
              title="Refresh data"
              aria-label="Refresh data"
            >
              {busy ? <Loader2 className="spin" size={17} /> : <RefreshCw size={17} />}
            </button>
            <button
              className="button primary"
              onClick={openNewDelivery}
              disabled={!connected}
              hidden={scope === "game"}
            >
              <Package size={16} />
              New delivery
            </button>
          </div>
        </header>

        <main className="content">
          {error ? <Banner type="error" text={error} onClose={() => setError("")} /> : null}
          {notice ? <Banner type="notice" text={notice} onClose={() => setNotice("")} /> : null}
          {!connected ? (
            <ConnectionScreen
              baseUrl={baseUrl}
              setBaseUrl={setBaseUrl}
              token={token}
              setToken={setToken}
              connect={connect}
              busy={busy}
            />
          ) : null}
          {connected && page === "delivery" ? (
            <DeliveryPage
              deliveryForm={deliveryForm}
              setDeliveryForm={setDeliveryForm}
              deliveryResult={deliveryResult}
              setDeliveryResult={setDeliveryResult}
              runDelivery={runDelivery}
              busy={busy}
              copy={copy}
              onOpenOverview={() => selectPage("overview")}
            />
          ) : null}
          {connected && page === "overview" ? (
            <OverviewPage
              activeGame={activeGame}
              donations={donations}
              links={links}
              rankings={rankings}
              rankTotal={rankTotal}
              totalDonations={totalDonations}
              totalAdjustments={totalAdjustments}
              topDonor={topDonor}
              copy={copy}
              gameStats={gameStats}
              loadGameStats={loadGameStats}
            />
          ) : null}
          {connected && page === "donations" ? (
            <DonationsPage
              rows={filteredDonations}
              total={totalDonations}
              search={donationSearch}
              setSearch={setDonationSearch}
              refresh={() => refreshCurrent()}
              toggleVoid={toggleVoid}
              selectedDonations={selectedDonations}
              toggleDonationSelect={toggleDonationSelect}
              toggleAllDonations={toggleAllDonations}
              bulkVoid={bulkVoidDonations}
            />
          ) : null}
          {connected && page === "leaderboard" ? (
            <LeaderboardPage
              rankings={rankings}
              total={rankTotal}
              search={rankSearch}
              setSearch={setRankSearch}
              applyFilter={() => run(async () => loadPageData("leaderboard", selectedGame))}
              exportRankings={exportRankings}
              openAdjust={openAdjust}
              leaderboardTab={leaderboardTab}
              setLeaderboardTab={setLeaderboardTab}
              dailyLeaderboard={dailyLeaderboard}
              loadDailyLeaderboard={loadDailyLeaderboard}
            />
          ) : null}
          {connected && page === "links" ? (
            <LinksPage
              links={links}
              openAdd={() => setModal("addLink")}
              openBulkAdd={() => setModal("bulkLink")}
              loadDonorDetail={loadDonorDetail}
            />
          ) : null}
          {connected && page === "events" ? (
            <EventsPage
              events={webhookEvents}
              total={webhookEventsTotal}
              refresh={() => run(async () => loadPageData("events", selectedGame))}
            />
          ) : null}
          {connected && page === "test" ? (
            <TestPage
              testForm={testForm}
              setTestForm={setTestForm}
              injectTestNotification={injectTestNotification}
              testApiAction={testApiAction}
              setTestApiAction={setTestApiAction}
              testApiCall={testApiCall}
              testApiResponse={testApiResponse}
              busy={busy}
            />
          ) : null}
          {connected && page === "games" ? (
            <GamesPage
              games={games}
              selectedGame={selectedGame}
              changeGame={changeGame}
              openCreate={() => setModal("createGame")}
              openDelivery={openNewDelivery}
              scope={scope}
              openGenerateLink={() => setModal("generateLink")}
            />
          ) : null}
          {connected && page === "settings" ? (
            <SettingsPage
              baseUrl={baseUrl}
              setBaseUrl={setBaseUrl}
              token={token}
              setToken={setToken}
              connect={connect}
              busy={busy}
              activeGame={activeGame}
              rotate={rotate}
              licenseForm={licenseForm}
              setLicenseForm={setLicenseForm}
              saveLicense={saveLicense}
              rebindLicense={rebindLicense}
            />
          ) : null}
        </main>
      </div>

      {modal === "createGame" ? (
        <Modal title="Create game" onClose={() => setModal(null)}>
          <form className="modal-form" onSubmit={createGame}>
            <label>
              <span>Game ID</span>
              <input
                value={newGame.id}
                onChange={(e) => setNewGame({ ...newGame, id: e.target.value })}
                placeholder="rust-main"
                required
              />
            </label>
            <label>
              <span>Display name</span>
              <input
                value={newGame.display_name}
                onChange={(e) => setNewGame({ ...newGame, display_name: e.target.value })}
                placeholder="Rust Main"
                required
              />
            </label>
            <label>
              <span>Saweria link</span>
              <input
                value={newGame.saweria_link}
                onChange={(e) => setNewGame({ ...newGame, saweria_link: e.target.value })}
                placeholder="https://saweria.co/..."
              />
            </label>
            <div className="modal-actions">
              <button className="button ghost" type="button" onClick={() => setModal(null)}>
                Cancel
              </button>
              <button className="button primary" type="submit" disabled={busy}>
                Create
              </button>
            </div>
          </form>
        </Modal>
      ) : null}

      {modal === "addLink" ? (
        <Modal title="Add donor link" onClose={() => setModal(null)}>
          <form className="modal-form" onSubmit={createLink}>
            <label>
              <span>Saweria name</span>
              <input
                value={linkForm.saweria_name}
                onChange={(e) => setLinkForm({ ...linkForm, saweria_name: e.target.value })}
                required
              />
            </label>
            <label>
              <span>Roblox username</span>
              <input
                value={linkForm.roblox_username}
                onChange={(e) => setLinkForm({ ...linkForm, roblox_username: e.target.value })}
                required
              />
            </label>
            <label>
              <span>Roblox user ID</span>
              <input
                value={linkForm.roblox_user_id}
                onChange={(e) => setLinkForm({ ...linkForm, roblox_user_id: e.target.value })}
              />
            </label>
            <div className="modal-actions">
              <button className="button ghost" type="button" onClick={() => setModal(null)}>
                Cancel
              </button>
              <button className="button primary" type="submit" disabled={busy}>
                Save link
              </button>
            </div>
          </form>
        </Modal>
      ) : null}

      {modal === "adjust" ? (
        <Modal title="Adjust donor total" onClose={() => setModal(null)}>
          <form className="modal-form" onSubmit={applyAdjustment}>
            <div className="adjust-summary">
              <span>{adjustForm.saweria_name}</span>
              <strong>{formatIdr(adjustForm.current_total)}</strong>
            </div>
            <label>
              <span>Adjustment amount</span>
              <input
                type="number"
                value={adjustForm.delta_amount}
                onChange={(e) => setAdjustForm({ ...adjustForm, delta_amount: e.target.value })}
                placeholder="100000 or -100000"
                required
              />
            </label>
            <label>
              <span>Reason</span>
              <input
                value={adjustForm.reason}
                onChange={(e) => setAdjustForm({ ...adjustForm, reason: e.target.value })}
                placeholder="Correction reason"
                required
              />
            </label>
            <div className="new-total">
              <span>New total</span>
              <strong>{formatIdr(adjustForm.current_total + Number(adjustForm.delta_amount || 0))}</strong>
            </div>
            <p className="modal-note">This updates manual adjustment only. Live donation rows stay unchanged.</p>
            <div className="modal-actions">
              <button className="button ghost" type="button" onClick={() => setModal(null)}>
                Cancel
              </button>
              <button className="button primary" type="submit" disabled={busy}>
                Apply adjustment
              </button>
            </div>
          </form>
        </Modal>
      ) : null}

      {tokenReveal ? (
        <Modal title="Save this admin token" onClose={() => setTokenReveal(null)}>
          <div className="modal-form">
            <p className="muted">
              <strong>{tokenReveal.label}</strong>. This token is shown only once. Copy it now and send it to the game
              owner through a secure channel. It will not be retrievable from the dashboard later.
            </p>
            <label>
              <span>Admin token</span>
              <div className="token-reveal-row">
                <input value={tokenReveal.token} readOnly onFocus={(e) => e.target.select()} />
                <button
                  type="button"
                  className="button secondary"
                  onClick={() => copy(tokenReveal.token, "Admin token copied.")}
                >
                  <Copy size={15} />
                  Copy
                </button>
              </div>
            </label>
            <p className="modal-note">
              The token grants full access to manage this game only. It cannot list or modify other games.
            </p>
            <div className="modal-actions">
              <button className="button primary" type="button" onClick={() => setTokenReveal(null)}>
                I have saved it
              </button>
            </div>
          </div>
        </Modal>
      ) : null}

      {modal === "bulkLink" ? (
        <Modal title="Bulk add donor links" onClose={() => setModal(null)}>
          <form className="modal-form" onSubmit={bulkAddLinks}>
            <p className="muted">One link per line. Format: <code>saweria_name =&gt; roblox_username</code></p>
            <label>
              <span>Links</span>
              <textarea
                rows={8}
                value={bulkLinkText}
                onChange={(e) => setBulkLinkText(e.target.value)}
                placeholder={"bebear_e0 => Bebear\ntestuser => TestUser123"}
                required
              />
            </label>
            <div className="modal-actions">
              <button className="button ghost" type="button" onClick={() => setModal(null)}>Cancel</button>
              <button className="button primary" type="submit" disabled={busy}>Import links</button>
            </div>
          </form>
        </Modal>
      ) : null}

      {modal === "generateLink" ? (
        <Modal title="Generate scoped admin link" onClose={() => { setModal(null); setScopedLinkResult(null); }}>
          <form className="modal-form" onSubmit={generateScopedLink}>
            <p className="muted">Generate a shareable link that grants access to selected games only.</p>
            <label>
              <span>Game keys (comma-separated)</span>
              <input
                value={scopedLinkForm.game_keys.join(", ")}
                onChange={(e) => setScopedLinkForm({
                  ...scopedLinkForm,
                  game_keys: e.target.value.split(",").map((s) => s.trim()).filter(Boolean),
                })}
                placeholder="nuwa"
                required
              />
            </label>
            <label>
              <span>Expires in (hours)</span>
              <select
                value={scopedLinkForm.expires_in_hours}
                onChange={(e) => setScopedLinkForm({ ...scopedLinkForm, expires_in_hours: Number(e.target.value) })}
              >
                <option value={1}>1 hour</option>
                <option value={24}>24 hours</option>
                <option value={168}>7 days</option>
                <option value={720}>30 days</option>
              </select>
            </label>
            <div className="modal-actions">
              <button className="button ghost" type="button" onClick={() => { setModal(null); setScopedLinkResult(null); }}>Cancel</button>
              <button className="button primary" type="submit" disabled={busy}>Generate link</button>
            </div>
          </form>
          {scopedLinkResult ? (
            <div className="modal-form" style={{ borderTop: "1px solid var(--border)", paddingTop: 16, marginTop: 8 }}>
              <label>
                <span>Generated link</span>
                <div className="token-reveal-row">
                  <input value={scopedLinkResult.link} readOnly onFocus={(e) => e.target.select()} />
                  <button type="button" className="button secondary" onClick={() => copy(scopedLinkResult.link, "Link copied.")}>
                    <Copy size={15} /> Copy
                  </button>
                </div>
              </label>
              <p className="modal-note">Expires: {formatDateTime(scopedLinkResult.expires_at)}</p>
            </div>
          ) : null}
        </Modal>
      ) : null}

      {donorDetail ? (
        <Modal title={`Donor: ${donorDetail.donor?.saweria_name || ""}`} onClose={() => setDonorDetail(null)}>
          <div className="modal-form">
            <div className="kpi-grid" style={{ marginBottom: 16 }}>
              <KpiCard label="Total" value={formatIdr(donorDetail.donor?.total_amount)} helper={`${donorDetail.donor?.total_donations} donations`} icon={Activity} />
              <KpiCard label="Rank" value={`#${donorDetail.donor?.rank || "-"}}`} helper="Leaderboard position" icon={Trophy} />
            </div>
            {donorDetail.donor?.roblox_username ? (
              <p className="muted">Linked to: <strong>{donorDetail.donor.roblox_username}</strong> (ID: {donorDetail.donor.roblox_user_id})</p>
            ) : null}
            <p className="muted">First: {formatDateTime(donorDetail.donor?.first_donation_at)} · Last: {formatDateTime(donorDetail.donor?.last_donation_at)}</p>
            <div className="table-frame" style={{ maxHeight: 300, overflow: "auto" }}>
              <table>
                <thead><tr><th>Date</th><th className="numeric">Amount</th><th>Message</th></tr></thead>
                <tbody>
                  {(donorDetail.donations || []).map((d) => (
                    <tr key={d.id}>
                      <td>{formatDateTime(d.donation_at)}</td>
                      <td className="numeric">{formatIdr(d.amount)}</td>
                      <td className="message-cell">{d.message || "-"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="modal-actions">
              <button className="button primary" type="button" onClick={() => setDonorDetail(null)}>Close</button>
            </div>
          </div>
        </Modal>
      ) : null}
    </div>
  );
}

function ConnectionScreen({ baseUrl, setBaseUrl, token, setToken, connect, busy }) {
  return (
    <section className="connection-screen">
      <div className="section-header">
        <p>Setup</p>
        <h1>Connect Worker API</h1>
      </div>
      <div className="connection-card">
        <label>
          <span>Worker URL</span>
          <input value={baseUrl} onChange={(e) => setBaseUrl(e.target.value)} />
        </label>
        <label>
          <span>Admin token</span>
          <input value={token} onChange={(e) => setToken(e.target.value)} />
        </label>
        <button className="button primary" onClick={connect} disabled={busy}>
          {busy ? <Loader2 className="spin" size={16} /> : <Shield size={16} />}
          Connect
        </button>
      </div>
    </section>
  );
}

function DeliveryPage({
  deliveryForm,
  setDeliveryForm,
  deliveryResult,
  setDeliveryResult,
  runDelivery,
  busy,
  copy,
  onOpenOverview,
}) {
  if (deliveryResult?.game) {
    const game = deliveryResult.game;
    const setupText = buildDeliverySetupText(game, {
      clientNote: deliveryResult.clientNote,
      maintenanceUntil: deliveryResult.maintenanceUntil,
    });
    return (
      <section className="page-stack">
        <div className="delivery-success-banner">
          <CheckCircle2 size={22} />
          <div>
            <strong>Delivery ready — {game.display_name}</strong>
            <p className="muted">Game <code>{game.id}</code> provisioned with license active. Copy atau download package di bawah.</p>
          </div>
        </div>
        <div className="split-grid">
          <section className="panel">
            <div className="panel-header">
              <div>
                <p>Step 2</p>
                <h2>Webhooks</h2>
              </div>
              <Link2 size={18} />
            </div>
            <EndpointRow
              label="Saweria"
              value={game.endpoints?.saweria_webhook}
              onCopy={() => copy(game.endpoints?.saweria_webhook, "Saweria webhook copied.")}
            />
            <EndpointRow
              label="Bagi-Bagi"
              value={game.endpoints?.bagibagi_webhook}
              onCopy={() => copy(game.endpoints?.bagibagi_webhook, "Bagi-Bagi webhook copied.")}
            />
          </section>
          <section className="panel">
            <div className="panel-header">
              <div>
                <p>License</p>
                <h2>v1.3+ status</h2>
              </div>
              <Shield size={18} />
            </div>
            <div className="license-meta muted" style={{ padding: "0 16px 16px" }}>
              <p>Status: <strong>{game.license?.license_status || "active"}</strong></p>
              <p>Enforced: {game.license?.license_enforced ? "after first boot" : "pending first boot"}</p>
              <p>Universe: {game.license?.universe_id || "not bound yet"}</p>
              {deliveryResult.maintenanceUntil ? (
                <p>Maintenance until: {formatDateTime(deliveryResult.maintenanceUntil)}</p>
              ) : (
                <p>Maintenance: not scheduled</p>
              )}
              {deliveryResult.clientNote ? <p>Client note: {deliveryResult.clientNote}</p> : null}
            </div>
          </section>
        </div>
        <section className="panel">
          <div className="panel-header">
            <div>
              <p>Roblox</p>
              <h2>Club Kit config lines</h2>
            </div>
            <Copy size={18} />
          </div>
          <EndpointRow label="Donation.ApiUrl" value={game.clubkit?.donation_api_url} />
          <EndpointRow label="GameDataApi.GameKey" value={game.clubkit?.social_game_key} />
          <EndpointRow label="DonationApiSecret" value={game.clubkit?.donation_api_secret} />
          <EndpointRow label="GameDataApiSecret" value={game.clubkit?.social_api_secret} />
          <div className="modal-actions" style={{ padding: "0 16px 16px", flexWrap: "wrap" }}>
            <button
              className="button primary"
              type="button"
              onClick={() => copy(setupText, "Full delivery package copied.")}
            >
              <Copy size={16} />
              Copy full package
            </button>
            <button
              className="button secondary"
              type="button"
              onClick={() => copy(buildClubKitConfigText(game), "Club Kit config copied.")}
            >
              <Copy size={16} />
              Copy config only
            </button>
            <button
              className="button secondary"
              type="button"
              onClick={() => downloadTextFile(`clubkit-${game.id}-SETUP.txt`, setupText)}
            >
              <Download size={16} />
              Download SETUP.txt
            </button>
            <button className="button ghost" type="button" onClick={onOpenOverview}>
              <Gauge size={16} />
              Open overview
            </button>
            <button className="button ghost" type="button" onClick={() => setDeliveryResult(null)}>
              <Plus size={16} />
              Create another
            </button>
          </div>
        </section>
        <section className="panel">
          <div className="panel-header">
            <div>
              <p>Preview</p>
              <h2>SETUP.txt</h2>
            </div>
            <ClipboardList size={18} />
          </div>
          <pre className="json-viewer delivery-preview">{setupText}</pre>
        </section>
      </section>
    );
  }

  return (
    <section className="page-stack">
      <PageHeader
        eyebrow="Delivery"
        title="New Club Kit delivery"
        detail="Provision game, license, and copy-paste package — no CLI required."
      />
      <section className="panel wizard-card">
        <div className="panel-header">
          <div>
            <p>Step 1</p>
            <h2>Client & game info</h2>
          </div>
          <Package size={18} />
        </div>
        <form className="settings-form delivery-form" onSubmit={runDelivery}>
          <label>
            <span>Display name</span>
            <input
              value={deliveryForm.display_name}
              onChange={(e) => {
                const displayName = e.target.value;
                setDeliveryForm((current) => {
                  const autoId = normalizeGameId(displayName);
                  const shouldSyncId =
                    !current.game_id || current.game_id === normalizeGameId(current.display_name);
                  return {
                    ...current,
                    display_name: displayName,
                    game_id: shouldSyncId ? autoId : current.game_id,
                  };
                });
              }}
              placeholder="Club Nuwa"
              required
            />
          </label>
          <label>
            <span>Game ID (unique key)</span>
            <input
              value={deliveryForm.game_id}
              onChange={(e) => setDeliveryForm({ ...deliveryForm, game_id: normalizeGameId(e.target.value) })}
              placeholder="club-nuwa"
              pattern="[a-z0-9][a-z0-9_-]{1,48}"
              required
            />
            <span className="wizard-hint">Lowercase, 2–49 chars. Used in API URL and license binding.</span>
          </label>
          <label>
            <span>Client note (internal)</span>
            <input
              value={deliveryForm.client_note}
              onChange={(e) => setDeliveryForm({ ...deliveryForm, client_note: e.target.value })}
              placeholder="Pak Budi — trusted"
            />
          </label>
          <label>
            <span>Bagi-Bagi / provider page URL</span>
            <input
              value={deliveryForm.provider_link}
              onChange={(e) => setDeliveryForm({ ...deliveryForm, provider_link: e.target.value })}
              placeholder="https://bagibagi.co/..."
            />
          </label>
          <div className="delivery-maintenance-row">
            <label className="checkbox-label">
              <input
                type="checkbox"
                checked={deliveryForm.skip_maintenance}
                onChange={(e) => setDeliveryForm({ ...deliveryForm, skip_maintenance: e.target.checked })}
              />
              <span>Skip maintenance date</span>
            </label>
            {!deliveryForm.skip_maintenance ? (
              <label>
                <span>Maintenance period (months from today)</span>
                <input
                  type="number"
                  min={1}
                  max={24}
                  value={deliveryForm.maintenance_months}
                  onChange={(e) =>
                    setDeliveryForm({ ...deliveryForm, maintenance_months: Number(e.target.value) || 1 })
                  }
                />
                <span className="wizard-hint">Default: 1 month free, then billing reminder.</span>
              </label>
            ) : null}
          </div>
          <div className="modal-actions">
            <button className="button primary" type="submit" disabled={busy}>
              {busy ? <Loader2 className="spin" size={16} /> : <Package size={16} />}
              Create delivery package
            </button>
          </div>
        </form>
      </section>
      <section className="panel">
        <div className="panel-header">
          <div>
            <p>What happens</p>
            <h2>Automated steps</h2>
          </div>
          <CheckCircle2 size={18} />
        </div>
        <ol className="delivery-steps muted">
          <li>Create game row + webhook tokens + API secrets</li>
          <li>Set license status <code>active</code> with client note</li>
          <li>Schedule maintenance until date (optional)</li>
          <li>Show copy-paste package + downloadable SETUP.txt</li>
        </ol>
      </section>
    </section>
  );
}

function OverviewPage({
  activeGame,
  donations,
  links,
  rankings,
  rankTotal,
  totalDonations,
  totalAdjustments,
  topDonor,
  copy,
  gameStats,
  loadGameStats,
}) {
  if (!activeGame) return <EmptyState title="No game selected" detail="Create or select a game to manage donations." />;
  return (
    <section className="page-stack">
      <PageHeader
        eyebrow="Overview"
        title={activeGame.display_name}
        detail="Production handoff and current donation status."
      />
      <div className="kpi-grid">
        <KpiCard
          label="Recent volume"
          value={formatIdr(totalDonations)}
          helper={`${donations.length} recent rows`}
          icon={Activity}
        />
        <KpiCard label="Ranked donors" value={rankTotal} helper="Merged leaderboard" icon={Trophy} />
        <KpiCard
          label="Manual adjustment"
          value={formatIdr(totalAdjustments)}
          helper="Seed layer total"
          icon={ArrowDownUp}
        />
        <KpiCard label="Donor links" value={links.length} helper="Saweria to Roblox" icon={Users} />
      </div>
      <section className="panel">
        <div className="panel-header">
          <div>
            <p>Game stats</p>
            <h2>Donation analytics</h2>
          </div>
          <button className="button secondary" onClick={loadGameStats}>
            <Flame size={16} />
            Load stats
          </button>
        </div>
        {gameStats ? (
          <div className="kpi-grid">
            <KpiCard label="Total donations" value={gameStats.total_donations} helper="All time" icon={Activity} />
            <KpiCard label="Total amount" value={formatIdr(gameStats.total_amount)} helper="Successful only" icon={Trophy} />
            <KpiCard label="Unique donors" value={gameStats.unique_donors} helper="Distinct names" icon={Users} />
            <KpiCard label="Combined total" value={formatIdr(gameStats.combined_total)} helper="Live + seed" icon={Database} />
          </div>
        ) : (
          <p className="muted" style={{ padding: "0 16px 16px" }}>Click "Load stats" to fetch donation analytics.</p>
        )}
      </section>
      <div className="split-grid">
        <section className="panel">
          <div className="panel-header">
            <div>
              <p>Donation API</p>
              <h2>Webhooks & Roblox</h2>
            </div>
            <ExternalLink size={18} />
          </div>
          <EndpointRow
            label="Saweria webhook"
            value={activeGame.endpoints?.saweria_webhook}
            onCopy={() => copy(activeGame.endpoints?.saweria_webhook, "Saweria webhook copied.")}
          />
          <EndpointRow
            label="Bagi-Bagi webhook"
            value={activeGame.endpoints?.bagibagi_webhook}
            onCopy={() => copy(activeGame.endpoints?.bagibagi_webhook, "Bagi-Bagi webhook copied.")}
          />
          <EndpointRow
            label="Donation.ApiUrl"
            value={activeGame.endpoints?.roblox_base}
            onCopy={() => copy(activeGame.endpoints?.roblox_base, "Donation ApiUrl copied.")}
          />
          <EndpointRow
            label="Donation secret (rbx)"
            value={activeGame.secret}
            onCopy={() => copy(activeGame.secret, "Donation secret copied.")}
          />
          <EndpointRow label="Webhook token" value={maskToken(activeGame.webhook_token)} />
        </section>
        <section className="panel">
          <div className="panel-header">
            <div>
              <p>Social API</p>
              <h2>Friends count</h2>
            </div>
            <Users size={18} />
          </div>
          <EndpointRow
            label="GameDataApi base"
            value={activeGame.clubkit?.social_base_url}
            onCopy={() => copy(activeGame.clubkit?.social_base_url, "Social API base copied.")}
          />
          <EndpointRow
            label="GameDataApi.GameKey"
            value={activeGame.id}
            onCopy={() => copy(activeGame.id, "Game key copied.")}
          />
          <EndpointRow
            label="Social secret (soc)"
            value={activeGame.social_secret}
            onCopy={() => copy(activeGame.social_secret, "Social secret copied.")}
          />
          <EndpointRow
            label="Friends endpoint"
            value={activeGame.endpoints?.social_friends_example}
            onCopy={() => copy(activeGame.endpoints?.social_friends_example, "Friends URL template copied.")}
          />
        </section>
      </div>
      <section className="panel">
        <div className="panel-header">
          <div>
            <p>Club Kit v1.3</p>
            <h2>Copy-paste config</h2>
          </div>
          <Copy size={18} />
        </div>
        <EndpointRow label="ClubKitConfig" value={activeGame.clubkit?.donation_api_url} />
        <EndpointRow label="ClubKitConfig" value={activeGame.clubkit?.social_game_key} />
        <EndpointRow label="Secrets.luau" value={activeGame.clubkit?.donation_api_secret} />
        <EndpointRow label="Secrets.luau" value={activeGame.clubkit?.social_api_secret} />
        <div className="modal-actions" style={{ padding: "0 16px 16px" }}>
          <button
            className="button secondary"
            type="button"
            onClick={() =>
              copy(
                buildClubKitConfigText(activeGame),
                "Club Kit config block copied.",
              )
            }
          >
            <Copy size={16} />
            Copy all Club Kit lines
          </button>
        </div>
      </section>
      <div className="split-grid">
        <section className="panel">
          <div className="panel-header">
            <div>
              <p>Top donor</p>
              <h2>{topDonor?.saweria_name || "No donor yet"}</h2>
            </div>
            <Trophy size={18} />
          </div>
          {rankings.length ? (
            <MiniList
              rows={rankings.map((row) => ({
                label: `#${row.rank} ${row.saweria_name}`,
                value: formatIdr(row.total_amount),
              }))}
            />
          ) : (
            <EmptyState
              compact
              title="No ranking data"
              detail="Leaderboard rows appear after donations or seed entries exist."
            />
          )}
        </section>
      </div>
      <section className="panel">
        <TableHeader title="Recent donations" detail="Latest events received by the selected game." />
        <DonationTable rows={donations} />
      </section>
    </section>
  );
}

function DonationsPage({ rows, total, search, setSearch, refresh, toggleVoid, selectedDonations, toggleDonationSelect, toggleAllDonations, bulkVoid }) {
  return (
    <section className="page-stack">
      <PageHeader
        eyebrow="Donations"
        title="Live donation events"
        detail={`${rows.length} rows loaded · ${formatIdr(total)} active amount`}
      />
      <section className="panel">
        <TableToolbar>
          <div className="search-field">
            <Search size={16} />
            <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search donor or message" />
          </div>
          {selectedDonations.size > 0 ? (
            <button className="button danger" onClick={bulkVoid}>
              <Trash2 size={16} />
              Void selected ({selectedDonations.size})
            </button>
          ) : null}
          <button className="button secondary" onClick={refresh}>
            <RefreshCw size={16} />
            Refresh
          </button>
        </TableToolbar>
        <DonationTable rows={rows} toggleVoid={toggleVoid} actions selectedDonations={selectedDonations} toggleDonationSelect={toggleDonationSelect} toggleAllDonations={toggleAllDonations} />
      </section>
    </section>
  );
}

function LeaderboardPage({ rankings, total, search, setSearch, applyFilter, exportRankings, openAdjust, leaderboardTab, setLeaderboardTab, dailyLeaderboard, loadDailyLeaderboard }) {
  const isDaily = leaderboardTab === "daily";
  const displayRankings = isDaily ? dailyLeaderboard : rankings;
  return (
    <section className="page-stack">
      <PageHeader
        eyebrow="Leaderboard"
        title="Ranked donor totals"
        detail={`${displayRankings.length} shown / ${isDaily ? "daily" : total + " donors"}`
        }
      />
      <section className="panel">
        <TableToolbar>
          <div className="tab-toggle">
            <button className={`tab-btn ${!isDaily ? "active" : ""}`} onClick={() => setLeaderboardTab("alltime")}>All-Time</button>
            <button className={`tab-btn ${isDaily ? "active" : ""}`} onClick={() => { setLeaderboardTab("daily"); if (!dailyLeaderboard.length) loadDailyLeaderboard(); }}>Daily (WIB)</button>
          </div>
          {!isDaily ? (
            <>
              <div className="search-field">
                <Search size={16} />
                <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search donor" />
              </div>
              <button className="button secondary" onClick={applyFilter}>
                <ListFilter size={16} />
                Apply filter
              </button>
              <button className="button secondary" onClick={exportRankings}>
                <Download size={16} />
                Export
              </button>
            </>
          ) : (
            <button className="button secondary" onClick={loadDailyLeaderboard}>
              <RefreshCw size={16} />
              Refresh
            </button>
          )}
        </TableToolbar>
        <div className="table-frame">
          <table>
            <thead>
              <tr>
                <th>Rank</th>
                <th>Donor</th>
                <th className="numeric">{isDaily ? "Today total" : "Live total"}</th>
                {!isDaily ? <th className="numeric">Adjustment</th> : null}
                <th className="numeric">Final total</th>
                <th>{isDaily ? "Time" : "Last donation"}</th>
                {!isDaily ? <th className="action-cell">Actions</th> : null}
              </tr>
            </thead>
            <tbody>
              {displayRankings.map((row, index) => (
                <tr key={isDaily ? `${row.saweria_name}-${index}` : row.saweria_name_lc}>
                  <td><span className="rank-badge">#{isDaily ? row.rank : row.rank}</span></td>
                  <td><strong>{row.saweria_name}</strong></td>
                  {isDaily ? (
                    <>
                      <td className="numeric">{formatIdr(row.total)}</td>
                      <td className="numeric"><strong>{formatIdr(row.total)}</strong></td>
                      <td>{row.last_at || "-"}</td>
                    </>
                  ) : (
                    <>
                      <td className="numeric">{formatIdr(row.live_total)}</td>
                      <td className="numeric">{formatIdr(row.seed_total)}</td>
                      <td className="numeric"><strong>{formatIdr(row.total_amount)}</strong></td>
                      <td>{formatDateTime(row.last_donation_at)}</td>
                      <td className="action-cell">
                        <button className="row-action" onClick={() => openAdjust(row)} title="Adjust donor total">
                          <Edit3 size={15} /> Adjust
                        </button>
                      </td>
                    </>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
          {!displayRankings.length ? (
            <EmptyState compact title="No donors found" detail="Try another search or refresh the data." />
          ) : null}
        </div>
      </section>
    </section>
  );
}

function LinksPage({ links, openAdd, openBulkAdd, loadDonorDetail }) {
  return (
    <section className="page-stack">
      <PageHeader eyebrow="Donor Links" title="Saweria to Roblox mapping" detail={`${links.length} linked donors`} />
      <section className="panel">
        <TableToolbar>
          <span className="toolbar-note">Manual mappings used by Roblox name lookup.</span>
          <button className="button secondary" onClick={openBulkAdd}>
            <ClipboardList size={16} />
            Bulk add
          </button>
          <button className="button primary" onClick={openAdd}>
            <Plus size={16} />
            Add link
          </button>
        </TableToolbar>
        <div className="table-frame">
          <table>
            <thead>
              <tr>
                <th>Saweria name</th>
                <th>Roblox username</th>
                <th>Roblox user ID</th>
                <th>Updated</th>
                <th className="action-cell">Actions</th>
              </tr>
            </thead>
            <tbody>
              {links.map((row) => (
                <tr key={row.id}>
                  <td>
                    <button className="row-action link-action" onClick={() => loadDonorDetail(row.saweria_name)}>
                      <strong>{row.saweria_name}</strong>
                    </button>
                  </td>
                  <td>{row.roblox_username}</td>
                  <td>{row.roblox_user_id || "-"}</td>
                  <td>{formatDateTime(row.updated_at)}</td>
                  <td className="action-cell">
                    <button className="row-action" onClick={() => loadDonorDetail(row.saweria_name)} title="View donor detail">
                      <ExternalLink size={15} />
                      Detail
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {!links.length ? (
            <EmptyState compact title="No donor links" detail="Add mappings when a donor needs a Roblox identity override." />
          ) : null}
        </div>
      </section>
    </section>
  );
}

function GamesPage({ games, selectedGame, changeGame, openCreate, openDelivery, scope, openGenerateLink }) {
  const canCreate = scope !== "game";
  return (
    <section className="page-stack">
      <PageHeader eyebrow="Games" title="Managed games" detail={`${games.length} games configured`} />
      <section className="panel">
        <TableToolbar>
          <span className="toolbar-note">Use New delivery for full client onboarding (recommended).</span>
          {canCreate ? (
            <>
              <button className="button secondary" onClick={openGenerateLink} disabled={!selectedGame}>
                <Link2 size={16} />
                Generate scoped link
              </button>
              <button className="button secondary" onClick={openCreate}>
                <Plus size={16} />
                Quick create
              </button>
              <button className="button primary" onClick={openDelivery}>
                <Package size={16} />
                New delivery
              </button>
            </>
          ) : null}
        </TableToolbar>
        <div className="table-frame">
          <table>
            <thead>
              <tr>
                <th>Game</th>
                <th>Game ID</th>
                <th>Saweria link</th>
                <th>Created</th>
                <th className="action-cell">Actions</th>
              </tr>
            </thead>
            <tbody>
              {games.map((game) => (
                <tr key={game.id} className={game.id === selectedGame ? "selected-row" : ""}>
                  <td>
                    <strong>{game.display_name}</strong>
                  </td>
                  <td>
                    <code>{game.id}</code>
                  </td>
                  <td>{game.saweria_link || "-"}</td>
                  <td>{formatDateTime(game.created_at)}</td>
                  <td className="action-cell">
                    <button className="row-action" onClick={() => changeGame(game.id)}>
                      <CheckCircle2 size={15} />
                      Select
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </section>
  );
}

function EventsPage({ events, total, refresh }) {
  const [detailEvent, setDetailEvent] = useState(null);
  return (
    <section className="page-stack">
      <PageHeader
        eyebrow="Events"
        title="Webhook event log"
        detail={`${events.length} / ${total} events`}
      />
      <section className="panel">
        <TableToolbar>
          <span className="toolbar-note">Raw webhook payloads and processing status.</span>
          <button className="button secondary" onClick={refresh}>
            <RefreshCw size={16} />
            Refresh
          </button>
        </TableToolbar>
        <div className="table-frame">
          <table>
            <thead>
              <tr>
                <th>ID</th>
                <th>Processed</th>
                <th>Donation ID</th>
                <th>Error</th>
                <th>Created</th>
                <th className="action-cell">Actions</th>
              </tr>
            </thead>
            <tbody>
              {events.map((ev) => (
                <tr key={ev.id} className={ev.processed ? "" : "voided-row"}>
                  <td><code>{ev.id}</code></td>
                  <td><StatusTag status={ev.processed ? "success" : "pending"} /></td>
                  <td>{ev.donation_id || "-"}</td>
                  <td className="message-cell">{ev.error || "-"}</td>
                  <td>{formatDateTime(ev.created_at)}</td>
                  <td className="action-cell">
                    <button className="row-action" onClick={() => setDetailEvent(ev)}>
                      <Server size={15} /> View payload
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {!events.length ? (
            <EmptyState compact title="No webhook events" detail="Events appear when Saweria or Bagi-Bagi webhooks are received." />
          ) : null}
        </div>
      </section>
      {detailEvent ? (
        <Modal title={`Webhook event #${detailEvent.id}`} onClose={() => setDetailEvent(null)}>
          <div className="modal-form">
            <label>
              <span>Raw payload</span>
              <pre className="json-viewer">{JSON.stringify(detailEvent.payload, null, 2)}</pre>
            </label>
            {detailEvent.error ? (
              <label>
                <span>Error</span>
                <pre className="json-viewer error">{detailEvent.error}</pre>
              </label>
            ) : null}
            <div className="modal-actions">
              <button className="button primary" type="button" onClick={() => setDetailEvent(null)}>Close</button>
            </div>
          </div>
        </Modal>
      ) : null}
    </section>
  );
}

function TestPage({ testForm, setTestForm, injectTestNotification, testApiAction, setTestApiAction, testApiCall, testApiResponse, busy }) {
  return (
    <section className="page-stack">
      <PageHeader
        eyebrow="Test"
        title="Notification & API testing"
        detail="Inject fake donations or test API responses."
      />
      <div className="split-grid">
        <section className="panel">
          <div className="panel-header">
            <div>
              <p>Inject</p>
              <h2>Test notification</h2>
            </div>
            <Send size={18} />
          </div>
          <p className="muted" style={{ padding: "0 16px 12px" }}>
            Creates a real donation entry. Game picks it up on next poll.
          </p>
          <form className="settings-form" onSubmit={injectTestNotification}>
            <label>
              <span>Donor name</span>
              <input
                value={testForm.saweria_name}
                onChange={(e) => setTestForm({ ...testForm, saweria_name: e.target.value })}
                placeholder="TestDonor"
                required
              />
            </label>
            <label>
              <span>Amount (IDR)</span>
              <input
                type="number"
                value={testForm.amount}
                onChange={(e) => setTestForm({ ...testForm, amount: e.target.value })}
                placeholder="50000"
                required
              />
            </label>
            <label>
              <span>Message</span>
              <input
                value={testForm.message}
                onChange={(e) => setTestForm({ ...testForm, message: e.target.value })}
                placeholder="Test donation"
              />
            </label>
            <label>
              <span>Roblox username (optional)</span>
              <input
                value={testForm.roblox_username}
                onChange={(e) => setTestForm({ ...testForm, roblox_username: e.target.value })}
                placeholder="PlayerName"
              />
            </label>
            <button className="button primary" type="submit" disabled={busy}>
              <Send size={16} /> Inject donation
            </button>
          </form>
        </section>
        <section className="panel">
          <div className="panel-header">
            <div>
              <p>Probe</p>
              <h2>Test API response</h2>
            </div>
            <TestTube size={18} />
          </div>
          <p className="muted" style={{ padding: "0 16px 12px" }}>
            See exactly what the game would receive from each endpoint.
          </p>
          <div className="settings-form">
            <label>
              <span>Action</span>
              <select value={testApiAction} onChange={(e) => setTestApiAction(e.target.value)}>
                <option value="ping">ping</option>
                <option value="leaderboard">leaderboard (alltime)</option>
                <option value="notifications">notifications</option>
                <option value="namemap">namemap</option>
                <option value="donor_profile">donor_profile</option>
              </select>
            </label>
            <button className="button secondary" onClick={testApiCall} disabled={busy}>
              <Search size={16} /> Call API
            </button>
          </div>
          {testApiResponse ? (
            <div style={{ padding: 16 }}>
              <label><span>Response</span></label>
              <pre className="json-viewer">{JSON.stringify(testApiResponse, null, 2)}</pre>
            </div>
          ) : null}
        </section>
      </div>
    </section>
  );
}

function SettingsPage({
  baseUrl,
  setBaseUrl,
  token,
  setToken,
  connect,
  busy,
  activeGame,
  rotate,
  licenseForm,
  setLicenseForm,
  saveLicense,
  rebindLicense,
}) {
  const license = activeGame?.license || {};
  return (
    <section className="page-stack">
      <PageHeader
        eyebrow="Settings"
        title="Connection, license, and tokens"
        detail="Operational configuration for the admin panel and selected game."
      />
      <div className="settings-grid">
        <section className="panel">
          <div className="panel-header">
            <div>
              <p>Club Kit license</p>
              <h2>v1.3+ enforcement</h2>
            </div>
            <Shield size={18} />
          </div>
          <p className="muted" style={{ padding: "0 16px 12px" }}>
            Legacy games with <code>license_enforced = false</code> keep working until Club Kit v1.3+ boots and
            verifies. Revoked or expired always blocks API.
          </p>
          <form className="settings-form" onSubmit={saveLicense}>
            <label>
              <span>Status</span>
              <select
                value={licenseForm.license_status}
                onChange={(e) => setLicenseForm({ ...licenseForm, license_status: e.target.value })}
              >
                <option value="active">active</option>
                <option value="grace">grace</option>
                <option value="expired">expired</option>
                <option value="revoked">revoked</option>
              </select>
            </label>
            <label>
              <span>Client note</span>
              <input
                value={licenseForm.license_note}
                onChange={(e) => setLicenseForm({ ...licenseForm, license_note: e.target.value })}
                placeholder="Trusted client name"
              />
            </label>
            <label>
              <span>Maintenance until (ISO, optional)</span>
              <input
                value={licenseForm.maintenance_until}
                onChange={(e) => setLicenseForm({ ...licenseForm, maintenance_until: e.target.value })}
                placeholder="2026-08-09T00:00:00.000Z"
              />
            </label>
            <div className="license-meta muted">
              <p>Enforced: {license.license_enforced ? "yes" : "no (legacy)"}</p>
              <p>Universe: {license.universe_id || "not bound"}</p>
              <p>Last seen: {formatDateTime(license.last_seen_at)}</p>
              <p>Build: {license.kit_build_id || "-"}</p>
            </div>
            <div className="danger-actions">
              <button className="button primary" type="submit" disabled={busy || !activeGame}>
                <Shield size={16} />
                Save license
              </button>
              <button className="button secondary" type="button" onClick={rebindLicense} disabled={busy || !activeGame}>
                <RotateCcw size={16} />
                Clear universe bind
              </button>
            </div>
          </form>
        </section>
        <section className="panel">
          <div className="panel-header">
            <div>
              <p>API connection</p>
              <h2>Worker admin access</h2>
            </div>
            <Database size={18} />
          </div>
          <div className="settings-form">
            <label>
              <span>Worker URL</span>
              <input value={baseUrl} onChange={(e) => setBaseUrl(e.target.value)} />
            </label>
            <label>
              <span>Admin token</span>
              <input value={token} onChange={(e) => setToken(e.target.value)} />
            </label>
            <button className="button primary" onClick={connect} disabled={busy}>
              <Shield size={16} />
              Save and reconnect
            </button>
          </div>
        </section>
        <section className="panel danger-panel">
          <div className="panel-header">
            <div>
              <p>Danger zone</p>
              <h2>Rotate selected game tokens</h2>
            </div>
            <AlertTriangle size={18} />
          </div>
          <p className="muted">
            Token rotation invalidates the old endpoint immediately. Update Saweria or Roblox after rotation. Rotating
            the admin token also invalidates the panel session that uses it.
          </p>
          <div className="danger-actions">
            <button className="button secondary" onClick={() => rotate("admin")} disabled={!activeGame}>
              <Shield size={16} />
              Rotate admin token
            </button>
            <button className="button secondary" onClick={() => rotate("secret")} disabled={!activeGame}>
              <KeyRound size={16} />
              Rotate Roblox secret
            </button>
            <button className="button secondary" onClick={() => rotate("social")} disabled={!activeGame}>
              <Users size={16} />
              Rotate social secret
            </button>
            <button className="button danger" onClick={() => rotate("webhook")} disabled={!activeGame}>
              <RotateCcw size={16} />
              Rotate webhook
            </button>
          </div>
        </section>
      </div>
    </section>
  );
}

function DonationTable({ rows, toggleVoid, actions = false, selectedDonations, toggleDonationSelect, toggleAllDonations }) {
  const hasSelection = typeof toggleDonationSelect === "function";
  const allSelected = hasSelection && rows.length > 0 && selectedDonations && selectedDonations.size === rows.length;
  return (
    <div className="table-frame">
      <table>
        <thead>
          <tr>
            {hasSelection ? (
              <th style={{ width: 40 }}>
                <input type="checkbox" checked={allSelected} onChange={toggleAllDonations} />
              </th>
            ) : null}
            <th>Received</th>
            <th>Donor</th>
            <th className="numeric">Amount</th>
            <th>Status</th>
            <th>Message</th>
            {actions ? <th className="action-cell">Actions</th> : null}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.id} className={row.is_voided ? "voided-row" : ""}>
              {hasSelection ? (
                <td>
                  <input
                    type="checkbox"
                    checked={selectedDonations?.has(row.id) || false}
                    onChange={() => toggleDonationSelect(row.id)}
                  />
                </td>
              ) : null}
              <td>{formatDateTime(row.received_at)}</td>
              <td><strong>{row.saweria_name}</strong></td>
              <td className="numeric">{formatIdr(row.amount)}</td>
              <td><StatusTag status={row.is_voided ? "voided" : row.status} /></td>
              <td className="message-cell">{row.message || "-"}</td>
              {actions ? (
                <td className="action-cell">
                  <button className="row-action" onClick={() => toggleVoid(row)}>
                    <MoreHorizontal size={15} />
                    {row.is_voided ? "Restore" : "Void"}
                  </button>
                </td>
              ) : null}
            </tr>
          ))}
        </tbody>
      </table>
      {!rows.length ? (
        <EmptyState compact title="No donations loaded" detail="Refresh the page or check the selected game." />
      ) : null}
    </div>
  );
}

function PageHeader({ eyebrow, title, detail }) {
  return (
    <div className="section-header">
      <p>{eyebrow}</p>
      <h1>{title}</h1>
      {detail ? <span>{detail}</span> : null}
    </div>
  );
}

function TableHeader({ title, detail }) {
  return (
    <div className="table-title">
      <h2>{title}</h2>
      {detail ? <p>{detail}</p> : null}
    </div>
  );
}

function TableToolbar({ children }) {
  return <div className="table-toolbar">{children}</div>;
}

function KpiCard({ label, value, helper, icon: Icon }) {
  return (
    <div className="kpi-card">
      <div className="kpi-icon">
        <Icon size={18} />
      </div>
      <span>{label}</span>
      <strong>{value}</strong>
      <p>{helper}</p>
    </div>
  );
}

function EndpointRow({ label, value, onCopy }) {
  return (
    <div className="endpoint-row">
      <span>{label}</span>
      <code>{value || "-"}</code>
      {onCopy ? (
        <button className="icon-button" onClick={onCopy} title={`Copy ${label}`} aria-label={`Copy ${label}`}>
          <Copy size={16} />
        </button>
      ) : null}
    </div>
  );
}

function MiniList({ rows }) {
  return (
    <div className="mini-list">
      {rows.map((row) => (
        <div key={row.label}>
          <span>{row.label}</span>
          <strong>{row.value}</strong>
        </div>
      ))}
    </div>
  );
}

function EmptyState({ title, detail, compact = false }) {
  return (
    <div className={`empty-state ${compact ? "compact" : ""}`}>
      <Database size={compact ? 18 : 24} />
      <strong>{title}</strong>
      <p>{detail}</p>
    </div>
  );
}

function StatusPill({ connected }) {
  return (
    <span className={`status-pill ${connected ? "connected" : ""}`}>
      <span></span>
      {connected ? "Connected" : "Not connected"}
    </span>
  );
}

function StatusTag({ status }) {
  const normalized = String(status || "unknown").toLowerCase();
  return <span className={`status-tag ${normalized}`}>{normalized}</span>;
}

function Banner({ type, text, onClose }) {
  return (
    <div className={`banner ${type}`}>
      <span>{text}</span>
      <button className="icon-button" onClick={onClose} aria-label="Close message">
        <X size={16} />
      </button>
    </div>
  );
}

function Modal({ title, onClose, children }) {
  return (
    <div className="modal-backdrop" role="dialog" aria-modal="true" aria-label={title}>
      <div className="modal-card">
        <div className="modal-header">
          <h2>{title}</h2>
          <button className="icon-button" onClick={onClose} aria-label="Close modal">
            <X size={17} />
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}
