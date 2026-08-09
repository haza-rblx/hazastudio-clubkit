# -*- coding: utf-8 -*-
"""Build docs/reference.html and wire nav + locale keys."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(r"c:\Users\haza\Documents\Pull Studio The Basic Club Kit v1.3")
DOCS = ROOT / "docs"

# Matches CommandLibraryDomain registry + gates (English = in-game copy)
COMMANDS = [
    # Profile
    ("/setbio <text>", "public", "Set your profile bio."),
    ("/clearbio", "public", "Remove your current profile bio."),
    ("/status <text>", "public", "Set your profile status."),
    ("/clearstatus", "public", "Remove your current profile status."),
    # Community
    ("/setcommun <name>", "public", "Set your community badge."),
    ("/clearcommun", "public", "Remove your current community badge."),
    # Session
    ("/re", "public", "Refresh your avatar without leaving this server."),
    ("/rejoin", "public", "Rejoin this server and return to your last saved position."),
    ("/bring <player>", "canTeleport", "Bring another player to your position."),
    ("/to <player>", "canTeleport", "Move yourself to another player."),
    # Admin
    ("/gravity", "admin", "Restore gravity for everyone. Shift+G also works."),
    ("/ungravity [1-10]", "admin", "Float everyone. Optional speed 1–10. Shift+U / /gravity to restore."),
    ("/drone start|stop", "admin", "Shared freecam — you pilot, everyone sees your view."),
    ("/crowd <text>", "admin", "Make every player show the same chat bubble."),
    ("/announce <msg>", "canAnnounce", "Broadcast a server announcement (alias /a)."),
    ("/gift <player|all> <tier>", "admin", "Give a membership tier (or gift everyone with all)."),
    ("/ungift <player> <tier>", "admin", "Remove a gifted membership."),
    ("/setrole <player> <role>", "admin", "Set a role override for another player."),
    ("/unsetrole <player>", "admin", "Remove a role override."),
    ("/fakecash [player] <idr> [message]", "admin", "Preview IDR donation (notif + aura + world VFX) — does not persist."),
    ("/fakerobux [player] <robux> [message]", "admin", "Preview Robux donation (notif + aura) — does not persist."),
    ("/testcash / /testsaweria / /testdonate", "admin", "Deprecated aliases → /fakecash."),
    ("/testrobux", "admin", "Deprecated alias → /fakerobux."),
    # Owner
    ("/setrobux <player> <amount>", "owner", "Add Robux to a player's leaderboard total (persist)."),
    ("/removerobux <player|me> [amount]", "owner", "Remove Robux adjustment. me = Studio-only self clear."),
    ("/donatecash <player> <amount> [message]", "owner", "Persist IDR + notif + VFX."),
    ("/addcash <player> <amount>", "owner", "Persist IDR to leaderboard only (no VFX)."),
    ("/removecash <player|me> [amount]", "owner", "Remove IDR manual adjustment."),
    ("/donatebagibagi / /addbagibagi / /removebagibagi", "owner", "Deprecated aliases → /donatecash / /addcash / /removecash."),
    ("/refreshleaderboard <type>", "owner", "Refresh boards: all | robux | community | bagibagi | likes | audit."),
    ("/showcase on|off|status", "owner", "Dev/demo only if ClubKitShowcase is present — not required for go-live."),
]

FEATURES = [
    ("Music & dance", [
        ("MusicPlayer", "Music player"),
        ("MusicCatalogSeed", "Default playlist"),
        ("SyncDance", "Sync dance"),
        ("LegacySyncBhms", "Legacy SyncBhms place-pack"),
    ]),
    ("Interface", [
        ("Hotbar", "Hotbar"),
        ("LoadingScreen", "Loading screen"),
        ("Settings", "Settings menu"),
        ("JoinGreetings", "Join greetings"),
        ("PromptJoinCommunityOnLoad", "Join community prompt"),
        ("AdminHub", "Admin Hub (04-AdminHub)"),
    ]),
    ("Social & progression", [
        ("Couples", "Couple system"),
        ("Stickers", "Stickers"),
        ("LevelSystem", "Level & XP"),
    ]),
    ("Monetization", [
        ("Shop", "Shop"),
        ("Leaderboards", "Donation boards"),
        ("DonationCash", "Cash donations"),
        ("DonationRobux", "Robux donations"),
        ("DonationWorldEffects", "Donation world effects"),
    ]),
    ("More", [
        ("Gravity", "Gravity tool"),
        ("VipOnCommunityJoin", "Free VIP for group members"),
        ("DonationRankGradientAnim", "Donor rank animation"),
    ]),
]

PRIVILEGES = [
    ("canGift", " /setrole, /gift, /ungift (also gated by admin panel roles)"),
    ("canAnnounce", "/announce and paid broadcast icon"),
    ("canTeleport", "/bring, /to"),
    ("adminPanel", "Admin panel + cinematic dock"),
    ("musicManage", "DJ / music player management"),
]

REF_DOCK_SVG = (
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" '
    'stroke-linecap="round" stroke-linejoin="round">'
    '<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/>'
    '<path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>'
    '<path d="M8 7h8"/><path d="M8 11h8"/><path d="M8 15h5"/>'
    "</svg>"
)


def ref_dock(active: bool = False) -> str:
    cls = "dock-item is-active" if active else "dock-item"
    return (
        f'      <a class="{cls}" href="reference.html">'
        f"{REF_DOCK_SVG}"
        '<span data-i18n="nav.reference">Reference</span></a>\n'
    )


DOCK_UPDATES = re.compile(
    r'(      <a class="dock-item(?: is-active)?" href="updates\.html">)',
)


def esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def cmd_rows() -> str:
    rows = []
    for cmd, gate, desc in COMMANDS:
        rows.append(
            f"              <tr><td><code>{esc(cmd)}</code></td>"
            f'<td data-i18n="ref.gate.{gate}">{gate}</td>'
            f"<td>{esc(desc)}</td></tr>"
        )
    return "\n".join(rows)


def feature_sections() -> str:
    blocks = []
    for i, (group, items) in enumerate(FEATURES, 1):
        rows = "\n".join(
            f"              <tr><td><code>{esc(k)}</code></td><td>{esc(lab)}</td></tr>"
            for k, lab in items
        )
        blocks.append(
            f"""        <h3 class="ref-subhead" data-i18n="ref.feat.g{i}">{esc(group)}</h3>
        <div class="table-wrap">
          <table>
            <thead><tr><th data-i18n="ref.feat.th.key">Key</th><th data-i18n="ref.feat.th.label">Label (plugin)</th></tr></thead>
            <tbody>
{rows}
            </tbody>
          </table>
        </div>"""
        )
    return "\n".join(blocks)


def priv_rows() -> str:
    rows = []
    for key, effect in PRIVILEGES:
        rows.append(
            f"              <tr><td><code>{esc(key)}</code></td>"
            f'<td data-i18n="ref.priv.{key}">{esc(effect)}</td></tr>'
        )
    return "\n".join(rows)


def write_reference_html() -> None:
    html = f"""<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title data-i18n-meta="meta.reference.title">Reference — Hazastudio Clubkit</title>
  <meta name="description" data-i18n-meta="meta.reference.description" content="Daftar command, feature toggle, dan privilege Hazastudio Club Kit." />
  <meta name="color-scheme" content="light dark" />
  <script>
    (function () {{
      try {{
        var key = "clubkit-docs-theme";
        var saved = localStorage.getItem(key);
        var theme = saved === "light" || saved === "dark" ? saved : "dark";
        document.documentElement.setAttribute("data-theme", theme);
      }} catch (_) {{
        document.documentElement.setAttribute("data-theme", "dark");
      }}
    }})();
  </script>
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400&display=swap" rel="stylesheet" />
  <link rel="stylesheet" href="theme.css" />
</head>
<body data-page="reference" class="dock-page">

  <div class="read-progress" id="readProgress" aria-hidden="true"></div>

  <nav class="dock" data-i18n-aria-label="nav.site" aria-label="Navigasi situs">
      <a class="dock-item" href="index.html"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/></svg><span>Docs</span></a>
      <a class="dock-item" href="setup.html"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H20v20H6.5a2.5 2.5 0 0 1 0-5H20"/></svg><span>Setup</span></a>
{ref_dock(True).rstrip()}
      <a class="dock-item" href="updates.html"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"/><path d="M8 16H3v5"/></svg><span>Updates</span></a>
      <div class="dock-divider"></div>
      <div class="dock-actions">
      <div class="lang-switch" id="langSwitch" role="group" data-i18n-aria-label="lang.label" aria-label="Bahasa">
          <button type="button" class="lang-btn" data-lang="id" aria-pressed="true">ID</button>
          <button type="button" class="lang-btn" data-lang="en" aria-pressed="false">EN</button>
          <button type="button" class="lang-btn" data-lang="ja" aria-pressed="false">JA</button>
          <button type="button" class="lang-btn" data-lang="es" aria-pressed="false">ES</button>
        </div>
      <button type="button" class="dock-item theme-toggle" id="themeToggle" aria-label="Toggle theme" title="Toggle theme">
      <span class="icon-sun"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/></svg></span>
      <span class="icon-moon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/></svg></span>
    </button>
      </div>
    </nav>

  <div class="doc-shell doc-shell--ref">

    <aside class="sidebar" data-i18n-aria-label="ref.side.aria" aria-label="Reference">
      <div class="sidebar-group">
        <div class="sidebar-label" data-i18n="ref.side.label">Reference</div>
        <a class="sidebar-link" href="#commands" data-i18n="ref.side.commands">Commands</a>
        <a class="sidebar-link" href="#features" data-i18n="ref.side.features">Features</a>
        <a class="sidebar-link" href="#privileges" data-i18n="ref.side.privileges">Privileges</a>
      </div>
    </aside>

    <main class="main">
      <header class="page-header">
        <h1 class="page-title" data-i18n="ref.title">Reference</h1>
        <p class="section-lead" data-i18n-html="ref.lead">Daftar command, toggle <code>Features</code> (sama dengan plugin Config → Features), dan privilege per kategori role. Untuk panduan setup, lihat <a href="setup.html">Setup</a>.</p>
      </header>

      <section id="commands">
        <h2 class="section-title" data-i18n="ref.cmd.title">Commands</h2>
        <p class="section-body" data-i18n-html="ref.cmd.lead">Sumber: Command Library in-game. Deskripsi di bawah ikut copy English engine. Access = gate permission (bukan nama role mentah).</p>
        <div class="table-wrap">
          <table>
            <thead>
              <tr>
                <th data-i18n="ref.cmd.th.cmd">Command</th>
                <th data-i18n="ref.cmd.th.access">Access</th>
                <th data-i18n="ref.cmd.th.desc">Description</th>
              </tr>
            </thead>
            <tbody>
{cmd_rows()}
            </tbody>
          </table>
        </div>
        <div class="card">
          <div class="card-title" data-i18n="ref.cmd.note.title">Preview vs persist</div>
          <p data-i18n-html="ref.cmd.note.body"><code>/fakecash</code> &amp; <code>/fakerobux</code> = preview saja (board tidak berubah). Persist: <code>/addcash</code>, <code>/donatecash</code>, <code>/setrobux</code>.</p>
        </div>
      </section>

      <section id="features">
        <h2 class="section-title" data-i18n="ref.feat.title">Feature manifest</h2>
        <p class="section-body" data-i18n-html="ref.feat.lead">Sama dengan <code>ClubKitConfigSchema.FEATURE_MANIFEST</code> — daftar yang muncul di plugin <strong>Config → Features</strong>. Set di <code>ClubKitConfig.Features</code> (<code>true</code>/<code>false</code>). Alias legacy <code>DonationSaweria</code> tidak ditampilkan di panel (tetap dibaca runtime sebagai alias <code>DonationCash</code>).</p>
{feature_sections()}
      </section>

      <section id="privileges">
        <h2 class="section-title" data-i18n="ref.priv.title">Privileges</h2>
        <p class="section-body" data-i18n-html="ref.priv.lead">Privilege diatur per <strong>kategori role</strong> di <code>ClubKitConfig</code>, bukan per role individual. Command admin/owner juga memakai gate terpisah (lihat kolom Access di atas).</p>
        <div class="table-wrap">
          <table>
            <thead><tr><th>Key</th><th data-i18n="ref.priv.th.effect">Effect</th></tr></thead>
            <tbody>
{priv_rows()}
            </tbody>
          </table>
        </div>
      </section>
    </main>
  </div>

  <script>
    const sections = document.querySelectorAll("section[id]");
    const sidebarLinks = document.querySelectorAll(".sidebar-link");
    const progressBar = document.getElementById("readProgress");
    const navObserver = new IntersectionObserver((entries) => {{
      entries.forEach((entry) => {{
        if (!entry.isIntersecting) return;
        const id = entry.target.id;
        sidebarLinks.forEach((link) => {{
          link.classList.toggle("active", link.getAttribute("href") === "#" + id);
        }});
      }});
    }}, {{ rootMargin: "-15% 0px -75% 0px" }});
    sections.forEach((s) => navObserver.observe(s));
    function updateProgress() {{
      const doc = document.documentElement;
      const scrollTop = doc.scrollTop || document.body.scrollTop;
      const height = doc.scrollHeight - doc.clientHeight;
      if (progressBar && height > 0) progressBar.style.width = ((scrollTop / height) * 100) + "%";
    }}
    window.addEventListener("scroll", updateProgress, {{ passive: true }});
    updateProgress();
  </script>
  <script src="docs.js"></script>
  <script src="i18n.js"></script>
</body>
</html>
"""
    (DOCS / "reference.html").write_text(html, encoding="utf-8")
    print("wrote reference.html")


LOCALE = {
    "id": {
        "nav.reference": "Reference",
        "meta.reference.title": "Reference — Hazastudio Clubkit",
        "meta.reference.description": "Daftar command, feature toggle, dan privilege Hazastudio Club Kit.",
        "ref.side.aria": "Daftar isi reference",
        "ref.side.label": "Reference",
        "ref.side.commands": "Commands",
        "ref.side.features": "Features",
        "ref.side.privileges": "Privileges",
        "ref.title": "Reference",
        "ref.lead": 'Daftar command, toggle <code>Features</code> (sama dengan plugin Config → Features), dan privilege per kategori role. Untuk panduan setup, lihat <a href="setup.html">Setup</a>.',
        "ref.cmd.title": "Commands",
        "ref.cmd.lead": "Sumber: Command Library in-game. Deskripsi di bawah ikut copy English engine. Access = gate permission (bukan nama role mentah).",
        "ref.cmd.th.cmd": "Command",
        "ref.cmd.th.access": "Access",
        "ref.cmd.th.desc": "Description",
        "ref.cmd.note.title": "Preview vs persist",
        "ref.cmd.note.body": "<code>/fakecash</code> &amp; <code>/fakerobux</code> = preview saja (board tidak berubah). Persist: <code>/addcash</code>, <code>/donatecash</code>, <code>/setrobux</code>.",
        "ref.gate.public": "semua",
        "ref.gate.canTeleport": "canTeleport",
        "ref.gate.canAnnounce": "canAnnounce",
        "ref.gate.admin": "admin",
        "ref.gate.owner": "owner",
        "ref.feat.title": "Feature manifest",
        "ref.feat.lead": "Sama dengan <code>ClubKitConfigSchema.FEATURE_MANIFEST</code> — daftar di plugin <strong>Config → Features</strong>. Toggle di <code>ClubKitConfig.Features</code>. Alias legacy <code>DonationSaweria</code> tidak di panel (tetap alias runtime untuk <code>DonationCash</code>).",
        "ref.feat.th.key": "Key",
        "ref.feat.th.label": "Label (plugin)",
        "ref.feat.g1": "Music & dance",
        "ref.feat.g2": "Interface",
        "ref.feat.g3": "Social & progression",
        "ref.feat.g4": "Monetization",
        "ref.feat.g5": "More",
        "ref.priv.title": "Privileges",
        "ref.priv.lead": "Privilege per <strong>kategori role</strong> di <code>ClubKitConfig</code>. Gate command (admin/owner) tetap terpisah — lihat kolom Access.",
        "ref.priv.th.effect": "Effect",
        "ref.priv.canGift": "/setrole, /gift, /ungift (juga ikut gate admin panel)",
        "ref.priv.canAnnounce": "/announce dan ikon paid broadcast",
        "ref.priv.canTeleport": "/bring, /to",
        "ref.priv.adminPanel": "Admin panel + cinematic dock",
        "ref.priv.musicManage": "Kontrol DJ / music player",
        "home.topics.reference.title": "Commands & Features",
        "home.topics.reference.desc": "Daftar lengkap command, feature toggle plugin, dan privilege.",
    },
    "en": {
        "nav.reference": "Reference",
        "meta.reference.title": "Reference — Hazastudio Clubkit",
        "meta.reference.description": "Club Kit commands, feature toggles, and privileges.",
        "ref.side.aria": "Reference contents",
        "ref.side.label": "Reference",
        "ref.side.commands": "Commands",
        "ref.side.features": "Features",
        "ref.side.privileges": "Privileges",
        "ref.title": "Reference",
        "ref.lead": 'Commands, <code>Features</code> toggles (same as plugin Config → Features), and role-category privileges. For the setup guide, see <a href="setup.html">Setup</a>.',
        "ref.cmd.title": "Commands",
        "ref.cmd.lead": "Source: in-game Command Library. Descriptions match the English engine copy. Access is the permission gate (not a raw role name).",
        "ref.cmd.th.cmd": "Command",
        "ref.cmd.th.access": "Access",
        "ref.cmd.th.desc": "Description",
        "ref.cmd.note.title": "Preview vs persist",
        "ref.cmd.note.body": "<code>/fakecash</code> &amp; <code>/fakerobux</code> are preview only (boards unchanged). Persist with <code>/addcash</code>, <code>/donatecash</code>, <code>/setrobux</code>.",
        "ref.gate.public": "everyone",
        "ref.gate.canTeleport": "canTeleport",
        "ref.gate.canAnnounce": "canAnnounce",
        "ref.gate.admin": "admin",
        "ref.gate.owner": "owner",
        "ref.feat.title": "Feature manifest",
        "ref.feat.lead": "Matches <code>ClubKitConfigSchema.FEATURE_MANIFEST</code> — what appears in plugin <strong>Config → Features</strong>. Toggle via <code>ClubKitConfig.Features</code>. Legacy alias <code>DonationSaweria</code> is hidden from the panel (still a runtime alias for <code>DonationCash</code>).",
        "ref.feat.th.key": "Key",
        "ref.feat.th.label": "Label (plugin)",
        "ref.feat.g1": "Music & dance",
        "ref.feat.g2": "Interface",
        "ref.feat.g3": "Social & progression",
        "ref.feat.g4": "Monetization",
        "ref.feat.g5": "More",
        "ref.priv.title": "Privileges",
        "ref.priv.lead": "Privileges are set per <strong>role category</strong> in <code>ClubKitConfig</code>. Command gates (admin/owner) stay separate — see the Access column.",
        "ref.priv.th.effect": "Effect",
        "ref.priv.canGift": "/setrole, /gift, /ungift (also tied to admin panel gate)",
        "ref.priv.canAnnounce": "/announce and paid broadcast icon",
        "ref.priv.canTeleport": "/bring, /to",
        "ref.priv.adminPanel": "Admin panel + cinematic dock",
        "ref.priv.musicManage": "DJ / music player controls",
        "home.topics.reference.title": "Commands & Features",
        "home.topics.reference.desc": "Full command list, plugin feature toggles, and privileges.",
    },
    "ja": {
        "nav.reference": "Reference",
        "meta.reference.title": "Reference — Hazastudio Clubkit",
        "meta.reference.description": "Club Kit のコマンド、機能トグル、特権一覧。",
        "ref.side.aria": "リファレンス目次",
        "ref.side.label": "Reference",
        "ref.side.commands": "Commands",
        "ref.side.features": "Features",
        "ref.side.privileges": "Privileges",
        "ref.title": "Reference",
        "ref.lead": 'コマンド、<code>Features</code> トグル（プラグイン Config → Features と同じ）、ロールカテゴリ特権。セットアップは <a href="setup.html">Setup</a>。',
        "ref.cmd.title": "Commands",
        "ref.cmd.lead": "出典: ゲーム内 Command Library。説明はエンジン英語コピーに合わせています。Access は permission gate（生のロール名ではありません）。",
        "ref.cmd.th.cmd": "Command",
        "ref.cmd.th.access": "Access",
        "ref.cmd.th.desc": "Description",
        "ref.cmd.note.title": "Preview vs persist",
        "ref.cmd.note.body": "<code>/fakecash</code> &amp; <code>/fakerobux</code> はプレビューのみ（ボードは変わらない）。永続化は <code>/addcash</code>、<code>/donatecash</code>、<code>/setrobux</code>。",
        "ref.gate.public": "全員",
        "ref.gate.canTeleport": "canTeleport",
        "ref.gate.canAnnounce": "canAnnounce",
        "ref.gate.admin": "admin",
        "ref.gate.owner": "owner",
        "ref.feat.title": "Feature manifest",
        "ref.feat.lead": "<code>ClubKitConfigSchema.FEATURE_MANIFEST</code> と同じ — プラグイン <strong>Config → Features</strong> の一覧。<code>ClubKitConfig.Features</code> で切替。レガシー別名 <code>DonationSaweria</code> はパネル非表示（実行時は <code>DonationCash</code> の別名）。",
        "ref.feat.th.key": "Key",
        "ref.feat.th.label": "Label (plugin)",
        "ref.feat.g1": "Music & dance",
        "ref.feat.g2": "Interface",
        "ref.feat.g3": "Social & progression",
        "ref.feat.g4": "Monetization",
        "ref.feat.g5": "More",
        "ref.priv.title": "Privileges",
        "ref.priv.lead": "特権は <code>ClubKitConfig</code> の<strong>ロールカテゴリ</strong>単位。コマンド gate（admin/owner）は別 — Access 列を参照。",
        "ref.priv.th.effect": "Effect",
        "ref.priv.canGift": "/setrole, /gift, /ungift（admin panel gate にも紐づく）",
        "ref.priv.canAnnounce": "/announce と有料 broadcast アイコン",
        "ref.priv.canTeleport": "/bring, /to",
        "ref.priv.adminPanel": "Admin panel + cinematic dock",
        "ref.priv.musicManage": "DJ / music player 操作",
        "home.topics.reference.title": "Commands & Features",
        "home.topics.reference.desc": "コマンド一覧、プラグイン機能トグル、特権。",
    },
    "es": {
        "nav.reference": "Reference",
        "meta.reference.title": "Reference — Hazastudio Clubkit",
        "meta.reference.description": "Comandos, toggles de Features y privilegios del Club Kit.",
        "ref.side.aria": "Contenido de reference",
        "ref.side.label": "Reference",
        "ref.side.commands": "Commands",
        "ref.side.features": "Features",
        "ref.side.privileges": "Privileges",
        "ref.title": "Reference",
        "ref.lead": 'Comandos, toggles de <code>Features</code> (igual que Config → Features del plugin) y privilegios por categoría de rol. Para el setup, ve <a href="setup.html">Setup</a>.',
        "ref.cmd.title": "Commands",
        "ref.cmd.lead": "Fuente: Command Library in-game. Las descripciones siguen el copy en inglés del motor. Access es el permission gate (no el nombre crudo del rol).",
        "ref.cmd.th.cmd": "Command",
        "ref.cmd.th.access": "Access",
        "ref.cmd.th.desc": "Description",
        "ref.cmd.note.title": "Preview vs persist",
        "ref.cmd.note.body": "<code>/fakecash</code> y <code>/fakerobux</code> son solo preview (boards sin cambio). Persistir con <code>/addcash</code>, <code>/donatecash</code>, <code>/setrobux</code>.",
        "ref.gate.public": "todos",
        "ref.gate.canTeleport": "canTeleport",
        "ref.gate.canAnnounce": "canAnnounce",
        "ref.gate.admin": "admin",
        "ref.gate.owner": "owner",
        "ref.feat.title": "Feature manifest",
        "ref.feat.lead": "Igual que <code>ClubKitConfigSchema.FEATURE_MANIFEST</code> — lo que sale en plugin <strong>Config → Features</strong>. Toggle en <code>ClubKitConfig.Features</code>. Alias legacy <code>DonationSaweria</code> no aparece en el panel (sigue siendo alias runtime de <code>DonationCash</code>).",
        "ref.feat.th.key": "Key",
        "ref.feat.th.label": "Label (plugin)",
        "ref.feat.g1": "Music & dance",
        "ref.feat.g2": "Interface",
        "ref.feat.g3": "Social & progression",
        "ref.feat.g4": "Monetization",
        "ref.feat.g5": "More",
        "ref.priv.title": "Privileges",
        "ref.priv.lead": "Los privilegios van por <strong>categoría de rol</strong> en <code>ClubKitConfig</code>. Los gates de comando (admin/owner) son aparte — mira la columna Access.",
        "ref.priv.th.effect": "Effect",
        "ref.priv.canGift": "/setrole, /gift, /ungift (también ligado al gate del admin panel)",
        "ref.priv.canAnnounce": "/announce e icono de paid broadcast",
        "ref.priv.canTeleport": "/bring, /to",
        "ref.priv.adminPanel": "Admin panel + cinematic dock",
        "ref.priv.musicManage": "Controles DJ / music player",
        "home.topics.reference.title": "Commands & Features",
        "home.topics.reference.desc": "Lista de comandos, toggles del plugin y privilegios.",
    },
}


def esc_js(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def patch_locales() -> None:
    for lang, keys in LOCALE.items():
        path = DOCS / "locales" / f"{lang}.js"
        text = path.read_text(encoding="utf-8")

        # Drop previous reference keys (idempotent re-run)
        drop_prefixes = (
            "nav.reference",
            "meta.reference.",
            "ref.",
            "home.topics.reference.",
        )
        out_lines = []
        for line in text.splitlines(keepends=True):
            skip = False
            for pref in drop_prefixes:
                if re.match(rf'\s*"{re.escape(pref)}', line) or (
                    pref.endswith(".") and re.match(rf'\s*"{re.escape(pref[:-1])}\.', line)
                ):
                    # only skip exact key lines
                    mkey = re.match(r'\s*"([^"]+)":', line)
                    if mkey and (
                        mkey.group(1) == pref.rstrip(".")
                        or mkey.group(1).startswith(pref)
                    ):
                        skip = True
                        break
            if line.strip() == "/* ── Reference ── */" or line.strip() == "/* ── Reference */":
                skip = True
            if skip:
                continue
            out_lines.append(line)
        text = "".join(out_lines)

        # Ensure nav.reference after nav.updates
        if '"nav.reference"' not in text:
            m = re.search(r'("nav\.updates":\s*"[^"]*",\n)', text)
            if not m:
                raise SystemExit(f"nav.updates missing in {lang}")
            text = (
                text[: m.end()]
                + f'    "nav.reference": "{esc_js(keys["nav.reference"])}",\n'
                + text[m.end() :]
            )

        # Insert / replace remaining keys as a block after setup check/toast area — before Home
        rest = {k: v for k, v in keys.items() if k != "nav.reference"}
        block = ["\n    /* ── Reference ── */\n"]
        for k, v in rest.items():
            block.append(f'    "{k}": "{esc_js(v)}",\n')
        block_s = "".join(block)

        # Remove stale Reference block if present
        text = re.sub(
            r"\n    /\* ── Reference ── \*/\n(?:    \"[^\"]+\": \".*?\",\n)+",
            "\n",
            text,
            count=1,
        )

        idx = text.find("    /* ── Home")
        if idx < 0:
            idx = text.find('"meta.home.title"')
        if idx < 0:
            raise SystemExit(f"insert point missing {lang}")
        text = text[:idx] + block_s + text[idx:]

        path.write_text(text, encoding="utf-8")
        print(f"patched locales/{lang}.js")


def patch_docks() -> None:
    for name in ("index.html", "setup.html", "updates.html", "404.html"):
        path = DOCS / name
        text = path.read_text(encoding="utf-8")
        if "reference.html" in text and 'href="reference.html"' in text:
            # ensure present once before updates
            if text.count('href="reference.html"') >= 1:
                print(f"dock already has reference: {name}")
                # still ensure nav.reference span if missing
                pass
        # Remove existing reference dock links to avoid dupes
        text = re.sub(
            r'\n\s*<a class="dock-item(?: is-active)?" href="reference\.html">.*?</a>',
            "",
            text,
            flags=re.S,
        )
        text2, n = DOCK_UPDATES.subn(ref_dock(False) + r"\1", text, count=1)
        if n != 1:
            print(f"WARN: could not insert dock in {name} (n={n})")
        else:
            path.write_text(text2, encoding="utf-8")
            print(f"patched dock {name}")


def patch_index_topic() -> None:
    path = DOCS / "index.html"
    text = path.read_text(encoding="utf-8")
    if "home.topics.reference" in text:
        print("index topic already present")
        return
    needle = """        <li class="hub-topic-item">
          <a href="updates.html" data-i18n="home.topics.updates.title">Update Engine &amp; changelog</a>
          <p data-i18n="home.topics.updates.desc">Cara menarik engine terbaru dari plugin dan ringkasan perubahan per versi.</p>
        </li>"""
    add = needle + """
        <li class="hub-topic-item">
          <a href="reference.html" data-i18n="home.topics.reference.title">Commands &amp; Features</a>
          <p data-i18n="home.topics.reference.desc">Daftar lengkap command, feature toggle plugin, dan privilege.</p>
        </li>"""
    if needle not in text:
        raise SystemExit("index topic needle missing")
    path.write_text(text.replace(needle, add, 1), encoding="utf-8")
    print("patched index topic")


def patch_css() -> None:
    css = DOCS / "theme.css"
    text = css.read_text(encoding="utf-8")
    if ".doc-shell--ref" in text:
        return
    text += """

/* Reference page */
.doc-shell--ref {
  max-width: 1100px;
}
.ref-subhead {
  font-size: var(--text-heading-sm);
  font-weight: 600;
  margin: var(--spacing-24) 0 var(--spacing-12);
  color: var(--text-primary);
}
"""
    css.write_text(text, encoding="utf-8")
    print("patched theme.css")


def main() -> None:
    write_reference_html()
    patch_docks()
    patch_locales()
    patch_index_topic()
    patch_css()
    print("done")


if __name__ == "__main__":
    main()
