# -*- coding: utf-8 -*-
"""Setup-flow i18n strings for Club Kit docs (id / en / ja / es).

FLOW keys are consumed by the single-page setup guide (setup.html).
HOME_PATCHES overlays home + updates strings that point at the flow.
"""

from __future__ import annotations

FLOW: dict[str, dict[str, str]] = {
    "id": {
        # ── Meta ──
        "meta.setup.title": "Setup — Hazastudio Clubkit",
        "meta.setup.description": "Satu panduan setup Hazastudio Club Kit — dari place kosong sampai publish.",
        # ── Sidebar ──
        "setup.side.aria": "Langkah setup",
        "setup.side.label": "Langkah",
        "setup.side.s1": "Insert kit",
        "setup.side.s2": "Branding",
        "setup.side.s3": "Membership",
        "setup.side.s4": "Broadcast",
        "setup.side.s5": "Donasi cash",
        "setup.side.s6": "Nuke posisi",
        "setup.side.s7": "Roles & tools",
        "setup.side.s8": "Play test",
        "setup.side.s9": "Publish",
        "setup.side.checklist": "Checklist",
        # ── Page chrome ──
        "setup.flow.title": "Setup place kamu",
        "setup.flow.lead": "Satu panduan dari place kosong sampai siap publish. Ikuti langkah 1–9 di bawah; centang progress di checklist kanan saat kamu menyelesaikan tiap poin.",
        # ── Checklist dock ──
        "setup.check.aria": "Deploy checklist",
        "setup.check.title": "Deploy checklist",
        "setup.check.hint": "Klik untuk centang. Progress tersimpan otomatis.",
        "setup.check.i1": "<code>Branding.LogoImage</code> diganti (bukan logo bawaan kit)",
        "setup.check.i2": "<code>ClubKitConfig</code> GroupId + Owner",
        "setup.check.i3": "<code>Secrets</code> (jika API cash)",
        "setup.check.i4": "<code>Donation.Provider</code> + API",
        "setup.check.i5": "<code>Shop.Products</code> BuyGamePassId + GiftId",
        "setup.check.i6": "<code>PaidBroadcast.ProductId</code>",
        "setup.check.i7": "Robux donation products",
        "setup.check.i8": "<code>Donation.NukeWorldPosition</code> (jika world FX)",
        "setup.check.i9": "<code>ServerStorage/Tools/</code>",
        "setup.check.i10": "Fitur tidak dipakai off",
        "setup.check.i11": "Test di Studio",
        "setup.check.i12": "Publish place",
        "setup.check.toast": "Semua selesai — siap publish!",
        "setup.check.note": "Samakan dengan plugin <strong>Diagnostics</strong>: GroupId, logo, donation API, Game Pass. Jalankan Diagnostics setelah langkah 2–3. Nuke position &amp; PaidBroadcast diedit lewat Source (belum di panel plugin).",
        # ── Steps ──
        "setup.flow.s1.title": "Insert Club Kit ke place",
        "setup.flow.s1.html": """<p>Mulai dari place kosong atau place venue kamu. Tujuan langkah ini: semua folder kit muncul di Explorer supaya engine, config, GUI, tools, dan board siap dikonfigurasi.</p>
<ol>
<li>Buka <strong>Roblox Studio</strong> → buka place venue kamu (atau buat place baru).</li>
<li>Insert kit dengan salah satu cara:
  <ul>
  <li><strong>Tanpa plugin:</strong> menu <strong>Home → Insert from File</strong> → pilih <code>ClubKit.rbxm</code>. Tunggu sampai unpack selesai.</li>
  <li><strong>Dengan Club Kit plugin:</strong> buka plugin → pakai aksi unpack / insert kit dari panel (sama hasilnya: hierarchy muncul di place).</li>
  </ul>
</li>
<li>Di Explorer, pastikan path berikut ada:
  <ul>
  <li><code>ReplicatedStorage/Hazastudio_ClubKit</code> — engine (diganti saat Update Engine)</li>
  <li><code>ReplicatedStorage/Hazastudio_ClubKitConfig</code> + <code>ClubKitConfig</code> — <strong>milikmu selamanya</strong>; Update Engine tidak mengganti utuh</li>
  <li><code>ServerScriptService/Hazastudio_ClubKitSecrets</code> + <code>Secrets</code> — <strong>milikmu selamanya</strong>; jangan di-overwrite saat update</li>
  <li><code>ServerScriptService/Hazastudio_ClubKit</code>, <code>StarterPlayer/StarterPlayerScripts/Hazastudio_ClubKit</code>, <code>ReplicatedFirst/Hazastudio_ClubKit</code></li>
  <li><code>StarterGui</code> folder GUI <code>01-</code> … <code>15-</code></li>
  <li><code>ServerStorage/Tools</code></li>
  <li>Board leaderboard di <code>Workspace</code></li>
  <li><code>ReplicatedStorage/WorldEffects</code> (model VFX Nuke/Smite/BlackHole)</li>
  </ul>
</li>
</ol>
<p><strong>Catatan singkat:</strong> <code>ClubKitShowcase</code> tidak ikut engine sync default — hanya untuk place demo, tidak perlu untuk go-live.</p>
<div class="tutorial-verify"><strong>Berhasil jika:</strong> path di atas terlihat di Explorer, dan Play test tidak error karena folder kit hilang. <code>ClubKitConfig</code> + <code>Secrets</code> siap diedit di langkah berikutnya.</div>""",
        "setup.flow.s2.title": "Branding, Group &amp; Owner",
        "setup.flow.s2.html": """<p>Tanpa Group/Owner banyak fitur (command owner, community board) tidak jalan. Logo community wajib diganti sebelum go-live — jangan biarkan logo bawaan kit di place live.</p>
<ol>
<li>Cara termudah: buka <strong>Club Kit plugin → Config → General</strong> dan <strong>Branding</strong>. Isi <code>GameName</code>, greeting, dan <strong>LogoImage</strong> (asset logo venue kamu).</li>
<li>Set <code>GroupId</code> = ID group Roblox venue kamu, dan <code>OwnerUserId</code> = UserId owner. Opsional: tambah admin di <code>AdminUserIds</code>.</li>
<li>Alternatif Source: Explorer → <code>ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig</code> → edit langsung.</li>
<li>Jalankan plugin <strong>Diagnostics</strong>. Fail paling umum: <code>GROUP_ID</code> invalid / masih <code>0</code>.</li>
</ol>
<pre><code><span class="key">ClubKitConfig</span>.<span class="key">Branding</span> = {
    <span class="key">GameName</span> = <span class="str">"Nama Club Kamu"</span>,
    <span class="key">LogoImage</span> = <span class="str">"rbxassetid://YOUR_COMMUNITY_LOGO_ID"</span>,
}
<span class="key">ClubKitConfig</span>.<span class="key">Group</span> = {
    <span class="key">GroupId</span> = <span class="num">12345678</span>,
    <span class="key">OwnerUserId</span> = <span class="num">987654321</span>,
}
<span class="key">ClubKitConfig</span>.<span class="key">AdminUserIds</span> = {
    [<span class="num">111111111</span>] = <span class="kw">true</span>,
}</code></pre>
<div class="tutorial-verify"><strong>Berhasil jika:</strong> Diagnostics lolos GroupId + logo; Play test tidak warn <code>GROUP_ID tidak valid</code>; loading / Join Community sudah pakai logo venue.</div>""",
        "setup.flow.s3.title": "Membership (Game Pass + gift)",
        "setup.flow.s3.html": """<p>Membership self-buy lewat <strong>Game Pass</strong>; gift ke player lain lewat <strong>Developer Product</strong> per tier. Shop harus aktif agar prompt beli muncul.</p>
<ol>
<li>Creator Dashboard → <strong>Monetization → Game Passes</strong> → buat pass per tier (mis. VIP / VVIP / Supreme) untuk self-buy.</li>
<li>Creator Dashboard → <strong>Developer Products</strong> → buat product gift per tier yang sama.</li>
<li>Plugin → <strong>Config → Membership</strong>: tempel <code>BuyGamePassId</code> + <code>GiftId</code> per produk. <code>BuyId</code> hanya legacy — isi <code>BuyGamePassId</code>.</li>
<li>Pastikan <code>Features.Shop = true</code> (plugin Config → Features).</li>
<li>Jalankan <strong>Diagnostics</strong> lagi — plugin akan warn kalau Game Pass / ID shop masih kosong atau <code>0</code>.</li>
</ol>
<pre><code><span class="key">ClubKitConfig</span>.<span class="key">Shop</span>.<span class="key">Products</span> = {
    {
        <span class="key">Key</span> = <span class="str">"VIP"</span>,
        <span class="key">BuyGamePassId</span> = <span class="num">123456789</span>,
        <span class="key">GiftId</span> = <span class="num">987654321</span>,
        <span class="key">Price</span> = <span class="num">399</span>, <span class="cmt">-- tampilan UI (opsional)</span>
    },
}
<span class="key">ClubKitConfig</span>.<span class="key">Features</span>.<span class="key">Shop</span> = <span class="kw">true</span></code></pre>
<div class="tutorial-verify"><strong>Berhasil jika:</strong> Diagnostics tidak warn pass hilang; di Play test prompt shop muncul dengan harga benar; Output tidak spam <code>BuyGamePassId</code> = <code>0</code>. Lanjut ke <a href="#step-4">broadcast</a> setelah ini.</div>""",
        "setup.flow.s4.title": "Paid broadcast",
        "setup.flow.s4.html": """<p>Broadcast berbayar memakai <strong>Developer Product terpisah</strong> — bukan Game Pass membership dan bukan entri di <code>Shop.Products</code>. Field ini belum ada di panel plugin Membership; edit lewat Source.</p>
<ol>
<li>Creator Dashboard → <strong>Developer Products</strong> → buat <strong>satu</strong> product khusus paid broadcast (nama bebas, harga Robux yang kamu mau).</li>
<li>Copy Product ID → Explorer → <code>ClubKitConfig</code> → set <code>PaidBroadcast.ProductId</code>.</li>
<li>Pastikan fitur broadcast aktif di venue kamu (topbar Broadcast terlihat saat Play).</li>
<li>Play test: klik ikon <strong>Broadcast</strong> di topbar → harus muncul purchase prompt Robux, bukan silent fail.</li>
</ol>
<pre><code><span class="key">ClubKitConfig</span>.<span class="key">PaidBroadcast</span> = {
    <span class="key">ProductId</span> = <span class="num">1122334455</span>, <span class="cmt">-- Developer Product, bukan Game Pass</span>
}</code></pre>
<div class="tutorial-verify"><strong>Berhasil jika:</strong> Output tidak warn <code>PaidBroadcast.PRODUCT_ID masih 0</code>; ikon Broadcast menampilkan harga; prompt beli muncul. Kalau ID masih <code>0</code>, kembali edit Source lalu re-test.</div>""",
        "setup.flow.s5.title": "Donasi cash (opsional)",
        "setup.flow.s5.html": """<p>Lewati langkah ini jika venue tidak pakai donasi IDR / cash. Kalau pakai Bagi-Bagi, Saweria, atau SociaBuzz, isi provider + API + secret.</p>
<ol>
<li>Plugin → tab <strong>Donations</strong> (atau edit Source <code>ClubKitConfig.Donation</code>): set <code>Provider</code> = <code>bagibagi</code> | <code>saweria</code> | <code>sociabuzz</code>.</li>
<li>Isi <code>ProviderLink</code> (URL halaman donasi publik) dan <code>ApiUrl</code> (endpoint worker kamu).</li>
<li>Explorer → <code>ServerScriptService/Hazastudio_ClubKitSecrets/Secrets</code> → isi <code>DonationApiSecret</code> agar sama dengan secret di worker.</li>
<li><strong>SociaBuzz:</strong> dari admin panel, paste webhook ke integrasi TRIBE → isi Webhook Token → <strong>Test Notification</strong>.</li>
<li>Jika <code>ApiUrl</code> dikosongkan: board cash tetap bisa tampil mode boards-only (tanpa live feed API) — normal kalau kamu belum siap API.</li>
<li>Donasi Robux (opsional): buat Developer Products donasi, atau biarkan server auto-load product yang sudah ada di experience.</li>
</ol>
<pre><code><span class="key">ClubKitConfig</span>.<span class="key">Donation</span> = {
    <span class="key">Provider</span> = <span class="str">"saweria"</span>,
    <span class="key">ProviderLink</span> = <span class="str">"https://saweria.co/yourpage"</span>,
    <span class="key">ApiUrl</span> = <span class="str">"https://your-worker.example/api"</span>,
}
<span class="cmt">-- Secrets (server-only)</span>
<span class="key">Secrets</span>.<span class="key">DonationApiSecret</span> = <span class="str">"your-donation-worker-secret"</span></code></pre>
<div class="tutorial-verify"><strong>Berhasil jika:</strong> board cash tidak stuck di &quot;API not configured&quot; saat <code>ApiUrl</code> terisi; donasi test masuk ke board. Kalau belum pakai cash API, centang checklist item terkait sebagai N/A dan lanjut ke <a href="#step-6">Nuke</a>.</div>""",
        "setup.flow.s6.title": "NukeWorldPosition (world effects)",
        "setup.flow.s6.html": """<p>VFX stage (Nuke / Smite / BlackHole) spawn di <strong>satu</strong> koordinat dunia. Field <code>Donation.NukeWorldPosition</code> <strong>belum</strong> ada di UI Donations plugin — edit Source. Model VFX datang dari rbxm (<code>WorldEffects</code>); Update Engine tidak mengganti model ini.</p>
<ol>
<li>Set <code>Features.DonationWorldEffects = true</code> (plugin Config → Features) jika kamu pakai efek panggung.</li>
<li>Di Workspace, pilih Part di atas panggung → Properties → salin <strong>Position</strong> X, Y, Z.</li>
<li>Edit Source: <code>ClubKitConfig.Donation.NukeWorldPosition = Vector3.new(X, Y, Z)</code>.</li>
<li>Threshold default cash: <strong>100k</strong> Nuke · <strong>250k</strong> Smite · <strong>500k</strong> BlackHole.</li>
<li>Play test: <code>/fakecash 100000</code> (preview) — efek harus muncul di stage, bukan di koordinat template bawaan.</li>
</ol>
<pre><code><span class="key">ClubKitConfig</span>.<span class="key">Features</span>.<span class="key">DonationWorldEffects</span> = <span class="kw">true</span>
<span class="key">ClubKitConfig</span>.<span class="key">Donation</span>.<span class="key">NukeWorldPosition</span> = <span class="kw">Vector3</span>.<span class="key">new</span>(<span class="num">0</span>, <span class="num">12</span>, <span class="num">-40</span>)</code></pre>
<div class="tutorial-verify"><strong>Berhasil jika:</strong> efek muncul di panggung venue. Kalau jauh di luar map, Position masih salah — salin ulang dari Part. Tidak pakai world FX? Matikan Features-nya dan lewati item Nuke di checklist.</div>""",
        "setup.flow.s7.title": "Roles, tools &amp; features",
        "setup.flow.s7.html": """<p>Sesuaikan role, folder tools, dan toggle fitur agar cocok dengan venue kamu. Setiap <code>toolFolder</code> di role harus punya folder matching di <code>ServerStorage/Tools/</code>.</p>
<ol>
<li>Edit <code>RoleCategories</code> di <code>ClubKitConfig</code> (atau plugin Config bila tersedia): label, <code>chatTag</code>, <code>teamColor</code>, <code>toolFolder</code>.</li>
<li>Cek Explorer → <code>ServerStorage/Tools/&lt;nama&gt;/</code> (contoh <code>STAFF</code>, <code>VIP</code>, <code>DONOR</code>) berisi Tool yang ingin diberikan.</li>
<li>Plugin → <strong>Config → Features</strong>: set <code>false</code> untuk modul yang tidak dipakai (shop, broadcast, cash, world FX, dll.).</li>
<li><code>SpenderRoles</code> opsional — matikan tier spender yang tidak relevan.</li>
<li>Privilege singkat: flag seperti <code>canGift</code>, <code>canAnnounce</code>, <code>adminPanel</code> menentukan siapa boleh gift / announce / buka panel — set per kategori role, bukan per player.</li>
</ol>
<pre><code><span class="key">roles</span> = {
    {
        <span class="key">key</span> = <span class="str">"Staff"</span>,
        <span class="key">label</span> = <span class="str">"Staff"</span>,
        <span class="key">chatTag</span> = <span class="str">"STAFF"</span>,
        <span class="key">toolFolder</span> = <span class="str">"STAFF"</span>, <span class="cmt">-- harus ada ServerStorage/Tools/STAFF</span>
        <span class="key">teamColor</span> = <span class="str">"Royal purple"</span>,
    },
}</code></pre>
<div class="tutorial-verify"><strong>Berhasil jika:</strong> <code>/setrole</code> assign role benar dan tools muncul di backpack. Fitur mati tidak memunculkan GUI/command yang tidak kamu mau.</div>""",
        "setup.flow.s8.title": "Play test di Studio",
        "setup.flow.s8.html": """<p>Uji flow penting sebelum publish. Studio memakai DataStore terisolasi (<code>Studio_*</code>) — aman, tidak menulis data live player. Bedakan command <strong>preview</strong> (tidak persist) vs yang menulis data.</p>
<ol>
<li><strong>Game Settings → Security</strong> → Enable Studio Access to API Services = <strong>ON</strong>.</li>
<li>Play (F5). Uji: shop / gift, ikon Broadcast, panel donasi, leaderboard boards (kosong = normal di place baru).</li>
<li>Command berguna (owner/admin):
  <ul>
  <li><code>/fakecash 100000</code> / <code>/fakerobux 10</code> — <strong>preview</strong> notif + VFX, tidak persist ke leaderboard live</li>
  <li><code>/setrole</code>, <code>/gift</code> — uji role &amp; gift flow</li>
  <li>Alias lama <code>/testcash</code> / <code>/testrobux</code> masih jalan</li>
  </ul>
</li>
<li>Perbaikan cepat jika gagal:
  <ul>
  <li>Pass / shop tidak prompt → <code>BuyGamePassId</code> masih <code>0</code> (<a href="#step-3">langkah 3</a>)</li>
  <li>Broadcast silent → <code>PaidBroadcast.ProductId</code> masih <code>0</code> (<a href="#step-4">langkah 4</a>)</li>
  <li>Board &quot;API not configured&quot; → isi <code>ApiUrl</code> + secret atau kosongkan sengaja (<a href="#step-5">langkah 5</a>)</li>
  <li>Nuke salah tempat → Position (<a href="#step-6">langkah 6</a>)</li>
  </ul>
</li>
</ol>
<div class="tutorial-verify"><strong>Berhasil jika:</strong> tidak ada error merah di Output; GUI load; shop/broadcast/fakecash merespons sesuai config. Centang &quot;Test di Studio&quot; di checklist kanan.</div>""",
        "setup.flow.s9.title": "Checklist &amp; publish",
        "setup.flow.s9.html": """<p>Go-live = checklist 12/12 + publish. Setelah live, kebiasaan harian: <strong>Update Engine</strong> dari plugin (config &amp; secrets aman).</p>
<ol>
<li>Review kartu <strong>Deploy checklist</strong> di kanan — klik tiap baris yang sudah selesai. Target: <strong>12 / 12</strong>.</li>
<li><strong>File → Publish to Roblox</strong> (atau Publish as kalau place baru).</li>
<li><strong>Habit setelah go-live:</strong> plugin → <strong>Engine → Check Update → Update Engine</strong> → Save. <code>ClubKitConfig</code> &amp; <code>Secrets</code> tidak diganti utuh; key baru di-fill-forward.</li>
<li><code>.rbxm</code> jarang dipakai lagi — hanya fresh install atau saat GUI / board / WorldEffects model berubah. Update Luau harian cukup lewat Update Engine.</li>
</ol>
<div class="tutorial-verify"><strong>Siap publish jika:</strong> checklist 12/12, Diagnostics bersih untuk Group/logo/pass/API yang kamu pakai, sudah play test di Studio, Nuke &amp; PaidBroadcast terisi jika fiturnya on.</div>""",
    },
    "en": {
        "meta.setup.title": "Setup — Hazastudio Clubkit",
        "meta.setup.description": "Single setup guide for Hazastudio Club Kit — from empty place to publish.",
        "setup.side.aria": "Setup steps",
        "setup.side.label": "Steps",
        "setup.side.s1": "Insert kit",
        "setup.side.s2": "Branding",
        "setup.side.s3": "Membership",
        "setup.side.s4": "Broadcast",
        "setup.side.s5": "Cash donations",
        "setup.side.s6": "Nuke position",
        "setup.side.s7": "Roles & tools",
        "setup.side.s8": "Play test",
        "setup.side.s9": "Publish",
        "setup.side.checklist": "Checklist",
        "setup.flow.title": "Setup your place",
        "setup.flow.lead": "One guide from an empty place to ready-to-publish. Follow steps 1–9 below; tick the checklist on the right as you finish each item.",
        "setup.check.aria": "Deploy checklist",
        "setup.check.title": "Deploy checklist",
        "setup.check.hint": "Click to tick. Progress is saved automatically.",
        "setup.check.i1": "<code>Branding.LogoImage</code> replaced (not the kit default logo)",
        "setup.check.i2": "<code>ClubKitConfig</code> GroupId + Owner",
        "setup.check.i3": "<code>Secrets</code> (if using cash API)",
        "setup.check.i4": "<code>Donation.Provider</code> + API",
        "setup.check.i5": "<code>Shop.Products</code> BuyGamePassId + GiftId",
        "setup.check.i6": "<code>PaidBroadcast.ProductId</code>",
        "setup.check.i7": "Robux donation products",
        "setup.check.i8": "<code>Donation.NukeWorldPosition</code> (if world FX)",
        "setup.check.i9": "<code>ServerStorage/Tools/</code>",
        "setup.check.i10": "Unused features off",
        "setup.check.i11": "Tested in Studio",
        "setup.check.i12": "Publish place",
        "setup.check.toast": "All done — ready to publish!",
        "setup.check.note": "Match plugin <strong>Diagnostics</strong>: GroupId, logo, donation API, Game Pass. Run Diagnostics after steps 2–3. Nuke position &amp; PaidBroadcast are edited via Source (not in the plugin panels yet).",
        "setup.flow.s1.title": "Insert Club Kit into your place",
        "setup.flow.s1.html": """<p>Start from an empty place or your venue place. Goal: every kit folder appears in Explorer so engine, config, GUI, tools, and boards are ready to configure.</p>
<ol>
<li>Open <strong>Roblox Studio</strong> → open your venue place (or create a new one).</li>
<li>Insert the kit one of two ways:
  <ul>
  <li><strong>Without the plugin:</strong> <strong>Home → Insert from File</strong> → choose <code>ClubKit.rbxm</code>. Wait until unpack finishes.</li>
  <li><strong>With the Club Kit plugin:</strong> open the plugin → use unpack / insert kit from the panel (same result: hierarchy lands in the place).</li>
  </ul>
</li>
<li>In Explorer, confirm these paths exist:
  <ul>
  <li><code>ReplicatedStorage/Hazastudio_ClubKit</code> — engine (replaced on Update Engine)</li>
  <li><code>ReplicatedStorage/Hazastudio_ClubKitConfig</code> + <code>ClubKitConfig</code> — <strong>yours forever</strong>; Update Engine never fully replaces it</li>
  <li><code>ServerScriptService/Hazastudio_ClubKitSecrets</code> + <code>Secrets</code> — <strong>yours forever</strong>; never overwrite on update</li>
  <li><code>ServerScriptService/Hazastudio_ClubKit</code>, <code>StarterPlayer/StarterPlayerScripts/Hazastudio_ClubKit</code>, <code>ReplicatedFirst/Hazastudio_ClubKit</code></li>
  <li><code>StarterGui</code> GUI folders <code>01-</code> … <code>15-</code></li>
  <li><code>ServerStorage/Tools</code></li>
  <li>Leaderboard boards in <code>Workspace</code></li>
  <li><code>ReplicatedStorage/WorldEffects</code> (Nuke / Smite / BlackHole models)</li>
  </ul>
</li>
</ol>
<p><strong>Short note:</strong> <code>ClubKitShowcase</code> is not in default engine sync — demo places only; you do not need it to go live.</p>
<div class="tutorial-verify"><strong>Success when:</strong> the paths above show in Explorer, and Play test does not fail because kit folders are missing. <code>ClubKitConfig</code> + <code>Secrets</code> are ready for the next steps.</div>""",
        "setup.flow.s2.title": "Branding, Group &amp; Owner",
        "setup.flow.s2.html": """<p>Without Group/Owner, many features (owner commands, community board) will not work. Replace the community logo before go-live — do not leave the kit default logo on a live place.</p>
<ol>
<li>Easiest path: open <strong>Club Kit plugin → Config → General</strong> and <strong>Branding</strong>. Fill <code>GameName</code>, greeting, and <strong>LogoImage</strong> (your venue logo asset).</li>
<li>Set <code>GroupId</code> to your Roblox group ID and <code>OwnerUserId</code> to the owner’s UserId. Optional: add admins in <code>AdminUserIds</code>.</li>
<li>Source alternative: Explorer → <code>ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig</code> → edit directly.</li>
<li>Run plugin <strong>Diagnostics</strong>. Most common fail: invalid / still <code>0</code> <code>GROUP_ID</code>.</li>
</ol>
<pre><code><span class="key">ClubKitConfig</span>.<span class="key">Branding</span> = {
    <span class="key">GameName</span> = <span class="str">"Your Club Name"</span>,
    <span class="key">LogoImage</span> = <span class="str">"rbxassetid://YOUR_COMMUNITY_LOGO_ID"</span>,
}
<span class="key">ClubKitConfig</span>.<span class="key">Group</span> = {
    <span class="key">GroupId</span> = <span class="num">12345678</span>,
    <span class="key">OwnerUserId</span> = <span class="num">987654321</span>,
}
<span class="key">ClubKitConfig</span>.<span class="key">AdminUserIds</span> = {
    [<span class="num">111111111</span>] = <span class="kw">true</span>,
}</code></pre>
<div class="tutorial-verify"><strong>Success when:</strong> Diagnostics passes GroupId + logo; Play test does not warn invalid <code>GROUP_ID</code>; loading / Join Community uses your venue logo.</div>""",
        "setup.flow.s3.title": "Membership (Game Pass + gift)",
        "setup.flow.s3.html": """<p>Self-buy membership uses a <strong>Game Pass</strong>; gifting another player uses a <strong>Developer Product</strong> per tier. Shop must be on for buy prompts to appear.</p>
<ol>
<li>Creator Dashboard → <strong>Monetization → Game Passes</strong> → create a pass per tier (e.g. VIP / VVIP / Supreme) for self-buy.</li>
<li>Creator Dashboard → <strong>Developer Products</strong> → create a gift product per matching tier.</li>
<li>Plugin → <strong>Config → Membership</strong>: paste <code>BuyGamePassId</code> + <code>GiftId</code> per product. <code>BuyId</code> is legacy only — fill <code>BuyGamePassId</code>.</li>
<li>Ensure <code>Features.Shop = true</code> (plugin Config → Features).</li>
<li>Run <strong>Diagnostics</strong> again — the plugin warns if Game Pass / shop IDs are still empty or <code>0</code>.</li>
</ol>
<pre><code><span class="key">ClubKitConfig</span>.<span class="key">Shop</span>.<span class="key">Products</span> = {
    {
        <span class="key">Key</span> = <span class="str">"VIP"</span>,
        <span class="key">BuyGamePassId</span> = <span class="num">123456789</span>,
        <span class="key">GiftId</span> = <span class="num">987654321</span>,
        <span class="key">Price</span> = <span class="num">399</span>, <span class="cmt">-- UI display (optional)</span>
    },
}
<span class="key">ClubKitConfig</span>.<span class="key">Features</span>.<span class="key">Shop</span> = <span class="kw">true</span></code></pre>
<div class="tutorial-verify"><strong>Success when:</strong> Diagnostics does not warn about missing passes; Play test shop prompt shows the right price; Output is not spamming <code>BuyGamePassId</code> = <code>0</code>. Continue to <a href="#step-4">broadcast</a> next.</div>""",
        "setup.flow.s4.title": "Paid broadcast",
        "setup.flow.s4.html": """<p>Paid broadcast uses a <strong>separate Developer Product</strong> — not a membership Game Pass and not an entry in <code>Shop.Products</code>. This field is not in the Membership plugin panel yet; edit it in Source.</p>
<ol>
<li>Creator Dashboard → <strong>Developer Products</strong> → create <strong>one</strong> product for paid broadcast (any name, Robux price you want).</li>
<li>Copy the Product ID → Explorer → <code>ClubKitConfig</code> → set <code>PaidBroadcast.ProductId</code>.</li>
<li>Make sure broadcast is enabled for your venue (Broadcast topbar visible in Play).</li>
<li>Play test: click the topbar <strong>Broadcast</strong> icon → a Robux purchase prompt must appear (not a silent fail).</li>
</ol>
<pre><code><span class="key">ClubKitConfig</span>.<span class="key">PaidBroadcast</span> = {
    <span class="key">ProductId</span> = <span class="num">1122334455</span>, <span class="cmt">-- Developer Product, not a Game Pass</span>
}</code></pre>
<div class="tutorial-verify"><strong>Success when:</strong> Output does not warn that PaidBroadcast ProductId is still <code>0</code>; Broadcast shows a price; the purchase prompt appears. If the ID is still <code>0</code>, edit Source again and re-test.</div>""",
        "setup.flow.s5.title": "Cash donations (optional)",
        "setup.flow.s5.html": """<p>Skip this step if your venue does not use IDR / cash donations. If you use Bagi-Bagi, Saweria, or SociaBuzz, fill provider + API + secret.</p>
<ol>
<li>Plugin → <strong>Donations</strong> tab (or edit Source <code>ClubKitConfig.Donation</code>): set <code>Provider</code> = <code>bagibagi</code> | <code>saweria</code> | <code>sociabuzz</code>.</li>
<li>Fill <code>ProviderLink</code> (public donation page URL) and <code>ApiUrl</code> (your worker endpoint).</li>
<li>Explorer → <code>ServerScriptService/Hazastudio_ClubKitSecrets/Secrets</code> → set <code>DonationApiSecret</code> to match the worker secret.</li>
<li><strong>SociaBuzz:</strong> from the admin panel, paste the webhook into TRIBE integrations → fill Webhook Token → <strong>Test Notification</strong>.</li>
<li>If <code>ApiUrl</code> is empty: cash boards can still run boards-only (no live API feed) — fine if the API is not ready yet.</li>
<li>Robux donations (optional): create donation Developer Products, or let the server auto-load products already on the experience.</li>
</ol>
<pre><code><span class="key">ClubKitConfig</span>.<span class="key">Donation</span> = {
    <span class="key">Provider</span> = <span class="str">"saweria"</span>,
    <span class="key">ProviderLink</span> = <span class="str">"https://saweria.co/yourpage"</span>,
    <span class="key">ApiUrl</span> = <span class="str">"https://your-worker.example/api"</span>,
}
<span class="cmt">-- Secrets (server-only)</span>
<span class="key">Secrets</span>.<span class="key">DonationApiSecret</span> = <span class="str">"your-donation-worker-secret"</span></code></pre>
<div class="tutorial-verify"><strong>Success when:</strong> the cash board is not stuck on &quot;API not configured&quot; when <code>ApiUrl</code> is set; a test donation reaches the board. Not using cash API? Treat related checklist items as N/A and continue to <a href="#step-6">Nuke</a>.</div>""",
        "setup.flow.s6.title": "NukeWorldPosition (world effects)",
        "setup.flow.s6.html": """<p>Stage VFX (Nuke / Smite / BlackHole) spawn at <strong>one</strong> world coordinate. <code>Donation.NukeWorldPosition</code> is <strong>not</strong> in the Donations plugin UI yet — edit Source. VFX models come from the rbxm (<code>WorldEffects</code>); Update Engine does not replace those models.</p>
<ol>
<li>Set <code>Features.DonationWorldEffects = true</code> (plugin Config → Features) if you use stage effects.</li>
<li>In Workspace, select a Part above the stage → Properties → copy <strong>Position</strong> X, Y, Z.</li>
<li>Edit Source: <code>ClubKitConfig.Donation.NukeWorldPosition = Vector3.new(X, Y, Z)</code>.</li>
<li>Default cash thresholds: <strong>100k</strong> Nuke · <strong>250k</strong> Smite · <strong>500k</strong> BlackHole.</li>
<li>Play test: <code>/fakecash 100000</code> (preview) — effects must appear on your stage, not at the template default coordinate.</li>
</ol>
<pre><code><span class="key">ClubKitConfig</span>.<span class="key">Features</span>.<span class="key">DonationWorldEffects</span> = <span class="kw">true</span>
<span class="key">ClubKitConfig</span>.<span class="key">Donation</span>.<span class="key">NukeWorldPosition</span> = <span class="kw">Vector3</span>.<span class="key">new</span>(<span class="num">0</span>, <span class="num">12</span>, <span class="num">-40</span>)</code></pre>
<div class="tutorial-verify"><strong>Success when:</strong> effects appear on your venue stage. Far off-map means Position is wrong — copy again from the Part. Not using world FX? Turn the Feature off and skip the Nuke checklist item.</div>""",
        "setup.flow.s7.title": "Roles, tools &amp; features",
        "setup.flow.s7.html": """<p>Tune roles, tool folders, and feature toggles for your venue. Every role <code>toolFolder</code> must have a matching folder under <code>ServerStorage/Tools/</code>.</p>
<ol>
<li>Edit <code>RoleCategories</code> in <code>ClubKitConfig</code> (or plugin Config when available): labels, <code>chatTag</code>, <code>teamColor</code>, <code>toolFolder</code>.</li>
<li>Check Explorer → <code>ServerStorage/Tools/&lt;name&gt;/</code> (e.g. <code>STAFF</code>, <code>VIP</code>, <code>DONOR</code>) holds the Tools you want granted.</li>
<li>Plugin → <strong>Config → Features</strong>: set unused modules to <code>false</code> (shop, broadcast, cash, world FX, etc.).</li>
<li><code>SpenderRoles</code> is optional — disable spender tiers you do not use.</li>
<li>Privileges in brief: flags like <code>canGift</code>, <code>canAnnounce</code>, <code>adminPanel</code> control who may gift / announce / open the panel — set per role category, not per player.</li>
</ol>
<pre><code><span class="key">roles</span> = {
    {
        <span class="key">key</span> = <span class="str">"Staff"</span>,
        <span class="key">label</span> = <span class="str">"Staff"</span>,
        <span class="key">chatTag</span> = <span class="str">"STAFF"</span>,
        <span class="key">toolFolder</span> = <span class="str">"STAFF"</span>, <span class="cmt">-- must exist: ServerStorage/Tools/STAFF</span>
        <span class="key">teamColor</span> = <span class="str">"Royal purple"</span>,
    },
}</code></pre>
<div class="tutorial-verify"><strong>Success when:</strong> <code>/setrole</code> assigns the right role and tools appear in the backpack. Disabled features do not surface GUIs/commands you do not want.</div>""",
        "setup.flow.s8.title": "Play test in Studio",
        "setup.flow.s8.html": """<p>Exercise the critical flows before publish. Studio uses isolated DataStores (<code>Studio_*</code>) — safe, does not write live player data. Distinguish <strong>preview</strong> commands (non-persistent) from ones that write data.</p>
<ol>
<li><strong>Game Settings → Security</strong> → Enable Studio Access to API Services = <strong>ON</strong>.</li>
<li>Play (F5). Test: shop / gift, Broadcast icon, donation panel, leaderboard boards (empty is normal on a new place).</li>
<li>Useful commands (owner/admin):
  <ul>
  <li><code>/fakecash 100000</code> / <code>/fakerobux 10</code> — <strong>preview</strong> notifs + VFX; does not persist to the live leaderboard</li>
  <li><code>/setrole</code>, <code>/gift</code> — role &amp; gift flow</li>
  <li>Legacy aliases <code>/testcash</code> / <code>/testrobux</code> still work</li>
  </ul>
</li>
<li>Quick fixes when something fails:
  <ul>
  <li>Pass / shop no prompt → <code>BuyGamePassId</code> still <code>0</code> (<a href="#step-3">step 3</a>)</li>
  <li>Broadcast silent → <code>PaidBroadcast.ProductId</code> still <code>0</code> (<a href="#step-4">step 4</a>)</li>
  <li>Board &quot;API not configured&quot; → fill <code>ApiUrl</code> + secret, or leave empty on purpose (<a href="#step-5">step 5</a>)</li>
  <li>Nuke in the wrong place → Position (<a href="#step-6">step 6</a>)</li>
  </ul>
</li>
</ol>
<div class="tutorial-verify"><strong>Success when:</strong> no red errors in Output; GUIs load; shop / broadcast / fakecash respond per your config. Tick &quot;Tested in Studio&quot; on the right checklist.</div>""",
        "setup.flow.s9.title": "Checklist &amp; publish",
        "setup.flow.s9.html": """<p>Go-live = checklist 12/12 + publish. After launch, daily habit: <strong>Update Engine</strong> from the plugin (config &amp; secrets stay safe).</p>
<ol>
<li>Review the <strong>Deploy checklist</strong> on the right — click each finished row. Target: <strong>12 / 12</strong>.</li>
<li><strong>File → Publish to Roblox</strong> (or Publish as for a new place).</li>
<li><strong>After go-live habit:</strong> plugin → <strong>Engine → Check Update → Update Engine</strong> → Save. <code>ClubKitConfig</code> &amp; <code>Secrets</code> are never fully replaced; new keys fill-forward.</li>
<li><code>.rbxm</code> is rare afterward — only for a fresh install or when GUI / board / WorldEffects models change. Daily Luau updates are Update Engine only.</li>
</ol>
<div class="tutorial-verify"><strong>Ready to publish when:</strong> checklist 12/12, Diagnostics clean for the Group/logo/pass/API pieces you use, Studio play test done, Nuke &amp; PaidBroadcast filled if those features are on.</div>""",
    },
    "ja": {
        "meta.setup.title": "セットアップ — Hazastudio Clubkit",
        "meta.setup.description": "Hazastudio Club Kit の単一セットアップガイド — 空のプレイスから公開まで。",
        "setup.side.aria": "セットアップ手順",
        "setup.side.label": "手順",
        "setup.side.s1": "キット挿入",
        "setup.side.s2": "ブランディング",
        "setup.side.s3": "メンバーシップ",
        "setup.side.s4": "ブロードキャスト",
        "setup.side.s5": "キャッシュ寄付",
        "setup.side.s6": "Nuke 位置",
        "setup.side.s7": "ロールとツール",
        "setup.side.s8": "プレイテスト",
        "setup.side.s9": "公開",
        "setup.side.checklist": "チェックリスト",
        "setup.flow.title": "プレイスをセットアップ",
        "setup.flow.lead": "空のプレイスから公開準備までの一本のガイドです。下の手順 1–9 を進め、終わった項目は右のチェックリストでチェックしてください。",
        "setup.check.aria": "Deploy チェックリスト",
        "setup.check.title": "Deploy checklist",
        "setup.check.hint": "クリックでチェック。進捗は自動保存されます。",
        "setup.check.i1": "<code>Branding.LogoImage</code> を差し替え（kit 既定ロゴではない）",
        "setup.check.i2": "<code>ClubKitConfig</code> GroupId + Owner",
        "setup.check.i3": "<code>Secrets</code>（キャッシュ API を使う場合）",
        "setup.check.i4": "<code>Donation.Provider</code> + API",
        "setup.check.i5": "<code>Shop.Products</code> BuyGamePassId + GiftId",
        "setup.check.i6": "<code>PaidBroadcast.ProductId</code>",
        "setup.check.i7": "Robux ドネーション商品",
        "setup.check.i8": "<code>Donation.NukeWorldPosition</code>（ワールド演出を使う場合）",
        "setup.check.i9": "<code>ServerStorage/Tools/</code>",
        "setup.check.i10": "未使用機能をオフ",
        "setup.check.i11": "Studio でテスト済み",
        "setup.check.i12": "プレイスを公開",
        "setup.check.toast": "すべて完了 — 公開できます！",
        "setup.check.note": "プラグインの <strong>Diagnostics</strong> と揃える: GroupId、ロゴ、寄付 API、Game Pass。手順 2–3 のあと Diagnostics を実行。Nuke 位置と PaidBroadcast は Source で編集（プラグインパネルには未実装）。",
        "setup.flow.s1.title": "プレイスに Club Kit を挿入",
        "setup.flow.s1.html": """<p>空のプレイス、または会場プレイスから始めます。目標は Explorer にキットのフォルダーがすべて現れ、エンジン・設定・GUI・ツール・ボードを構成できる状態にすることです。</p>
<ol>
<li><strong>Roblox Studio</strong> を開き、会場プレイスを開く（または新規作成）。</li>
<li>次のいずれかでキットを挿入します:
  <ul>
  <li><strong>プラグインなし:</strong> <strong>Home → Insert from File</strong> → <code>ClubKit.rbxm</code> を選択。展開が終わるまで待つ。</li>
  <li><strong>Club Kit プラグインあり:</strong> プラグインを開き、パネルから unpack / insert kit（結果は同じ: 階層がプレイスに入る）。</li>
  </ul>
</li>
<li>Explorer で次のパスがあることを確認:
  <ul>
  <li><code>ReplicatedStorage/Hazastudio_ClubKit</code> — エンジン（Update Engine で置換）</li>
  <li><code>ReplicatedStorage/Hazastudio_ClubKitConfig</code> + <code>ClubKitConfig</code> — <strong>あなたのもの（永久）</strong>；Update Engine は丸ごと置換しない</li>
  <li><code>ServerScriptService/Hazastudio_ClubKitSecrets</code> + <code>Secrets</code> — <strong>あなたのもの（永久）</strong>；更新時に上書きしない</li>
  <li><code>ServerScriptService/Hazastudio_ClubKit</code>、<code>StarterPlayer/StarterPlayerScripts/Hazastudio_ClubKit</code>、<code>ReplicatedFirst/Hazastudio_ClubKit</code></li>
  <li><code>StarterGui</code> の GUI フォルダー <code>01-</code> … <code>15-</code></li>
  <li><code>ServerStorage/Tools</code></li>
  <li><code>Workspace</code> 内のリーダーボード</li>
  <li><code>ReplicatedStorage/WorldEffects</code>（Nuke / Smite / BlackHole モデル）</li>
  </ul>
</li>
</ol>
<p><strong>短い注:</strong> <code>ClubKitShowcase</code> は既定のエンジン同期に含まれません — デモ用のみ。本番公開には不要です。</p>
<div class="tutorial-verify"><strong>✓ 成功の目安:</strong> 上記パスが Explorer にあり、キット欠落で Play が落ちない。<code>ClubKitConfig</code> と <code>Secrets</code> の編集準備ができている。</div>""",
        "setup.flow.s2.title": "ブランディング・Group・Owner",
        "setup.flow.s2.html": """<p>Group/Owner がないと、多くの機能（owner コマンド、コミュニティボード）が動きません。公開前にコミュニティロゴを必ず差し替え — kit 既定ロゴを本番に残さないでください。</p>
<ol>
<li>いちばん簡単: <strong>Club Kit プラグイン → Config → General</strong> と <strong>Branding</strong>。<code>GameName</code>、greeting、<strong>LogoImage</strong>（会場ロゴ）を入力。</li>
<li><code>GroupId</code> に Roblox グループ ID、<code>OwnerUserId</code> にオーナーの UserId。任意で <code>AdminUserIds</code> に管理者を追加。</li>
<li>Source の別手順: Explorer → <code>ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig</code> を直接編集。</li>
<li>プラグイン <strong>Diagnostics</strong> を実行。最多の失敗は無効 / まだ <code>0</code> の <code>GROUP_ID</code>。</li>
</ol>
<pre><code><span class="key">ClubKitConfig</span>.<span class="key">Branding</span> = {
    <span class="key">GameName</span> = <span class="str">"Your Club Name"</span>,
    <span class="key">LogoImage</span> = <span class="str">"rbxassetid://YOUR_COMMUNITY_LOGO_ID"</span>,
}
<span class="key">ClubKitConfig</span>.<span class="key">Group</span> = {
    <span class="key">GroupId</span> = <span class="num">12345678</span>,
    <span class="key">OwnerUserId</span> = <span class="num">987654321</span>,
}
<span class="key">ClubKitConfig</span>.<span class="key">AdminUserIds</span> = {
    [<span class="num">111111111</span>] = <span class="kw">true</span>,
}</code></pre>
<div class="tutorial-verify"><strong>✓ 成功の目安:</strong> Diagnostics で GroupId + ロゴが OK。Play で無効な <code>GROUP_ID</code> 警告なし。ローディング / Join Community が会場ロゴ。</div>""",
        "setup.flow.s3.title": "メンバーシップ（Game Pass + ギフト）",
        "setup.flow.s3.html": """<p>自分用購入は <strong>Game Pass</strong>、他プレイヤーへのギフトは tier ごとの <strong>Developer Product</strong>。ショップをオンにしないと購入プロンプトが出ません。</p>
<ol>
<li>Creator Dashboard → <strong>Monetization → Game Passes</strong> → tier ごと（例: VIP / VVIP / Supreme）にセルフ購入用パスを作成。</li>
<li>Creator Dashboard → <strong>Developer Products</strong> → 同じ tier のギフト商品を作成。</li>
<li>プラグイン → <strong>Config → Membership</strong>: 商品ごとに <code>BuyGamePassId</code> + <code>GiftId</code> を貼り付け。<code>BuyId</code> はレガシーのみ — <code>BuyGamePassId</code> を使う。</li>
<li><code>Features.Shop = true</code> を確認（プラグイン Config → Features）。</li>
<li>もう一度 <strong>Diagnostics</strong> — Game Pass / ショップ ID が空または <code>0</code> だと警告します。</li>
</ol>
<pre><code><span class="key">ClubKitConfig</span>.<span class="key">Shop</span>.<span class="key">Products</span> = {
    {
        <span class="key">Key</span> = <span class="str">"VIP"</span>,
        <span class="key">BuyGamePassId</span> = <span class="num">123456789</span>,
        <span class="key">GiftId</span> = <span class="num">987654321</span>,
        <span class="key">Price</span> = <span class="num">399</span>, <span class="cmt">-- UI 表示用（任意）</span>
    },
}
<span class="key">ClubKitConfig</span>.<span class="key">Features</span>.<span class="key">Shop</span> = <span class="kw">true</span></code></pre>
<div class="tutorial-verify"><strong>✓ 成功の目安:</strong> Diagnostics がパス欠落を警告しない。Play でショッププロンプトと正しい価格。Output が <code>BuyGamePassId</code> = <code>0</code> を連発しない。次は <a href="#step-4">ブロードキャスト</a>。</div>""",
        "setup.flow.s4.title": "有料ブロードキャスト",
        "setup.flow.s4.html": """<p>有料ブロードキャストは<strong>別の Developer Product</strong> です — メンバーシップ Game Pass でも <code>Shop.Products</code> の項目でもありません。Membership プラグインパネルには未掲載なので Source で編集します。</p>
<ol>
<li>Creator Dashboard → <strong>Developer Products</strong> → 有料ブロードキャスト用に<strong>1つ</strong>作成（名前自由、希望の Robux 価格）。</li>
<li>Product ID をコピー → Explorer → <code>ClubKitConfig</code> → <code>PaidBroadcast.ProductId</code> を設定。</li>
<li>会場でブロードキャストが有効か確認（Play 時にトップバー Broadcast が見える）。</li>
<li>Play テスト: トップバーの <strong>Broadcast</strong> → Robux 購入プロンプトが出ること（無言失敗にしない）。</li>
</ol>
<pre><code><span class="key">ClubKitConfig</span>.<span class="key">PaidBroadcast</span> = {
    <span class="key">ProductId</span> = <span class="num">1122334455</span>, <span class="cmt">-- Developer Product（Game Pass ではない）</span>
}</code></pre>
<div class="tutorial-verify"><strong>✓ 成功の目安:</strong> Output が PaidBroadcast ProductId = <code>0</code> を警告しない。Broadcast に価格表示、購入プロンプトが出る。ID がまだ <code>0</code> なら Source を直し再テスト。</div>""",
        "setup.flow.s5.title": "キャッシュ寄付（任意）",
        "setup.flow.s5.html": """<p>会場で IDR / キャッシュ寄付を使わない場合はこの手順をスキップ。Bagi-Bagi、Saweria、SociaBuzz を使う場合は provider・API・secret を設定します。</p>
<ol>
<li>プラグイン → <strong>Donations</strong> タブ（または Source の <code>ClubKitConfig.Donation</code>）: <code>Provider</code> = <code>bagibagi</code> | <code>saweria</code> | <code>sociabuzz</code>。</li>
<li><code>ProviderLink</code>（公開寄付ページ URL）と <code>ApiUrl</code>（ワーカーエンドポイント）を入力。</li>
<li>Explorer → <code>ServerScriptService/Hazastudio_ClubKitSecrets/Secrets</code> → <code>DonationApiSecret</code> をワーカー secret と一致させる。</li>
<li><strong>SociaBuzz:</strong> 管理パネルの webhook を TRIBE 連携に貼り、Webhook Token を入れて <strong>Test Notification</strong>。</li>
<li><code>ApiUrl</code> が空でも: キャッシュボードは boards-only（ライブ API なし）で動ける — API 準備前なら問題ありません。</li>
<li>Robux 寄付（任意）: 寄付用 Developer Products を作る、または経験に既にある商品の自動読み込みに任せる。</li>
</ol>
<pre><code><span class="key">ClubKitConfig</span>.<span class="key">Donation</span> = {
    <span class="key">Provider</span> = <span class="str">"saweria"</span>,
    <span class="key">ProviderLink</span> = <span class="str">"https://saweria.co/yourpage"</span>,
    <span class="key">ApiUrl</span> = <span class="str">"https://your-worker.example/api"</span>,
}
<span class="cmt">-- Secrets（サーバー専用）</span>
<span class="key">Secrets</span>.<span class="key">DonationApiSecret</span> = <span class="str">"your-donation-worker-secret"</span></code></pre>
<div class="tutorial-verify"><strong>✓ 成功の目安:</strong> <code>ApiUrl</code> 設定時にキャッシュボードが &quot;API not configured&quot; のままにならない。テスト寄付がボードに届く。キャッシュ API を使わない場合は該当チェックを N/A として <a href="#step-6">Nuke</a> へ。</div>""",
        "setup.flow.s6.title": "NukeWorldPosition（ワールド演出）",
        "setup.flow.s6.html": """<p>ステージ VFX（Nuke / Smite / BlackHole）は<strong>1つ</strong>のワールド座標に出現します。<code>Donation.NukeWorldPosition</code> は Donations プラグイン UI に<strong>まだありません</strong> — Source で編集。VFX モデルは rbxm（<code>WorldEffects</code>）由来で、Update Engine では置換されません。</p>
<ol>
<li>ステージ演出を使うなら <code>Features.DonationWorldEffects = true</code>（プラグイン Config → Features）。</li>
<li>Workspace でステージ上の Part を選び → Properties → <strong>Position</strong> の X, Y, Z をコピー。</li>
<li>Source を編集: <code>ClubKitConfig.Donation.NukeWorldPosition = Vector3.new(X, Y, Z)</code>。</li>
<li>既定のキャッシュ閾値: <strong>100k</strong> Nuke · <strong>250k</strong> Smite · <strong>500k</strong> BlackHole。</li>
<li>Play テスト: <code>/fakecash 100000</code>（プレビュー）— テンプレ座標ではなく会場ステージに出ること。</li>
</ol>
<pre><code><span class="key">ClubKitConfig</span>.<span class="key">Features</span>.<span class="key">DonationWorldEffects</span> = <span class="kw">true</span>
<span class="key">ClubKitConfig</span>.<span class="key">Donation</span>.<span class="key">NukeWorldPosition</span> = <span class="kw">Vector3</span>.<span class="key">new</span>(<span class="num">0</span>, <span class="num">12</span>, <span class="num">-40</span>)</code></pre>
<div class="tutorial-verify"><strong>✓ 成功の目安:</strong> 演出が会場ステージに出る。マップ外なら Position が違う — Part から再コピー。ワールド演出を使わない場合は Feature をオフし Nuke チェックをスキップ。</div>""",
        "setup.flow.s7.title": "ロール・ツール・機能",
        "setup.flow.s7.html": """<p>会場に合わせてロール、ツールフォルダー、機能トグルを調整します。ロールの各 <code>toolFolder</code> は <code>ServerStorage/Tools/</code> 配下に同名フォルダーが必要です。</p>
<ol>
<li><code>ClubKitConfig</code> の <code>RoleCategories</code> を編集（またはプラグイン Config）: label、<code>chatTag</code>、<code>teamColor</code>、<code>toolFolder</code>。</li>
<li>Explorer → <code>ServerStorage/Tools/&lt;名前&gt;/</code>（例: <code>STAFF</code>、<code>VIP</code>、<code>DONOR</code>）に付与したい Tool があるか確認。</li>
<li>プラグイン → <strong>Config → Features</strong>: 使わないモジュールを <code>false</code>（ショップ、ブロードキャスト、キャッシュ、ワールド演出など）。</li>
<li><code>SpenderRoles</code> は任意 — 使わないスペンダー tier をオフ。</li>
<li>権限の要点: <code>canGift</code>、<code>canAnnounce</code>、<code>adminPanel</code> などはカテゴリ単位。プレイヤー単位ではありません。</li>
</ol>
<pre><code><span class="key">roles</span> = {
    {
        <span class="key">key</span> = <span class="str">"Staff"</span>,
        <span class="key">label</span> = <span class="str">"Staff"</span>,
        <span class="key">chatTag</span> = <span class="str">"STAFF"</span>,
        <span class="key">toolFolder</span> = <span class="str">"STAFF"</span>, <span class="cmt">-- ServerStorage/Tools/STAFF が必要</span>
        <span class="key">teamColor</span> = <span class="str">"Royal purple"</span>,
    },
}</code></pre>
<div class="tutorial-verify"><strong>✓ 成功の目安:</strong> <code>/setrole</code> で正しいロールとバックパックのツール。オフにした機能の GUI/コマンドが出ない。</div>""",
        "setup.flow.s8.title": "Studio でプレイテスト",
        "setup.flow.s8.html": """<p>公開前に重要フローを試します。Studio は分離 DataStore（<code>Studio_*</code>）を使うため安全で、ライブプレイヤーデータは書きません。<strong>プレビュー</strong>（非永続）コマンドとデータ書き込みを区別してください。</p>
<ol>
<li><strong>Game Settings → Security</strong> → Enable Studio Access to API Services = <strong>ON</strong>。</li>
<li>Play（F5）。ショップ / ギフト、Broadcast、寄付パネル、リーダーボード（新規プレイスで空は正常）を確認。</li>
<li>便利なコマンド（owner/admin）:
  <ul>
  <li><code>/fakecash 100000</code> / <code>/fakerobux 10</code> — 通知 + VFX の<strong>プレビュー</strong>。ライブリーダーボードには永続しない</li>
  <li><code>/setrole</code>、<code>/gift</code> — ロールとギフト</li>
  <li>旧エイリアス <code>/testcash</code> / <code>/testrobux</code> も有効</li>
  </ul>
</li>
<li>失敗時の近道:
  <ul>
  <li>パス / ショップが出ない → <code>BuyGamePassId</code> がまだ <code>0</code>（<a href="#step-3">手順 3</a>）</li>
  <li>Broadcast が無反応 → <code>PaidBroadcast.ProductId</code> がまだ <code>0</code>（<a href="#step-4">手順 4</a>）</li>
  <li>ボードが &quot;API not configured&quot; → <code>ApiUrl</code> + secret を入れるか、意図的に空のまま（<a href="#step-5">手順 5</a>）</li>
  <li>Nuke が違う場所 → Position（<a href="#step-6">手順 6</a>）</li>
  </ul>
</li>
</ol>
<div class="tutorial-verify"><strong>✓ 成功の目安:</strong> Output に赤いエラーなし。GUI が載る。ショップ / ブロードキャスト / fakecash が設定どおり。右の「Studio でテスト済み」をチェック。</div>""",
        "setup.flow.s9.title": "チェックリストと公開",
        "setup.flow.s9.html": """<p>本番公開 = チェックリスト 12/12 + Publish。公開後の日課はプラグインの <strong>Update Engine</strong>（設定と Secrets は安全）。</p>
<ol>
<li>右の <strong>Deploy checklist</strong> を確認し、終わった行をクリック。目標: <strong>12 / 12</strong>。</li>
<li><strong>File → Publish to Roblox</strong>（新規なら Publish as）。</li>
<li><strong>公開後の習慣:</strong> プラグイン → <strong>Engine → Check Update → Update Engine</strong> → Save。<code>ClubKitConfig</code> と <code>Secrets</code> は丸ごと置換されず、新しいキーは fill-forward。</li>
<li>その後の <code>.rbxm</code> は稀 — 新規導入や GUI / ボード / WorldEffects モデル変更のときだけ。普段の Luau 更新は Update Engine のみ。</li>
</ol>
<div class="tutorial-verify"><strong>✓ 公開できるとき:</strong> チェックリスト 12/12、使う Group/ロゴ/パス/API で Diagnostics がきれい、Studio テスト済み、オンにしているなら Nuke と PaidBroadcast が入っている。</div>""",
    },
    "es": {
        "meta.setup.title": "Configuración — Hazastudio Clubkit",
        "meta.setup.description": "Guía única de setup de Hazastudio Club Kit — de un place vacío hasta publicar.",
        "setup.side.aria": "Pasos de setup",
        "setup.side.label": "Pasos",
        "setup.side.s1": "Insertar kit",
        "setup.side.s2": "Branding",
        "setup.side.s3": "Membresía",
        "setup.side.s4": "Broadcast",
        "setup.side.s5": "Donaciones cash",
        "setup.side.s6": "Posición Nuke",
        "setup.side.s7": "Roles y tools",
        "setup.side.s8": "Play test",
        "setup.side.s9": "Publicar",
        "setup.side.checklist": "Checklist",
        "setup.flow.title": "Configura tu place",
        "setup.flow.lead": "Una sola guía desde un place vacío hasta listo para publicar. Sigue los pasos 1–9; marca el checklist de la derecha al terminar cada punto.",
        "setup.check.aria": "Checklist de despliegue",
        "setup.check.title": "Deploy checklist",
        "setup.check.hint": "Haz clic para marcar. El progreso se guarda automáticamente.",
        "setup.check.i1": "<code>Branding.LogoImage</code> reemplazado (no el logo predeterminado del kit)",
        "setup.check.i2": "<code>ClubKitConfig</code> GroupId + Owner",
        "setup.check.i3": "<code>Secrets</code> (si usas API de efectivo)",
        "setup.check.i4": "<code>Donation.Provider</code> + API",
        "setup.check.i5": "<code>Shop.Products</code> BuyGamePassId + GiftId",
        "setup.check.i6": "<code>PaidBroadcast.ProductId</code>",
        "setup.check.i7": "Productos de donación de Robux",
        "setup.check.i8": "<code>Donation.NukeWorldPosition</code> (si hay world FX)",
        "setup.check.i9": "<code>ServerStorage/Tools/</code>",
        "setup.check.i10": "Funciones no usadas desactivadas",
        "setup.check.i11": "Probado en Studio",
        "setup.check.i12": "Publicar place",
        "setup.check.toast": "Todo listo: ¡preparado para publicar!",
        "setup.check.note": "Alinea con <strong>Diagnostics</strong> del plugin: GroupId, logo, API de donación, Game Pass. Ejecuta Diagnostics tras los pasos 2–3. Nuke y PaidBroadcast se editan por Source (aún no están en los paneles del plugin).",
        "setup.flow.s1.title": "Inserta Club Kit en tu place",
        "setup.flow.s1.html": """<p>Empieza desde un place vacío o el de tu venue. Objetivo: que todas las carpetas del kit aparezcan en Explorer para poder configurar motor, config, GUI, tools y boards.</p>
<ol>
<li>Abre <strong>Roblox Studio</strong> → abre el place del venue (o crea uno nuevo).</li>
<li>Inserta el kit de una de estas formas:
  <ul>
  <li><strong>Sin plugin:</strong> <strong>Home → Insert from File</strong> → elige <code>ClubKit.rbxm</code>. Espera a que termine el unpack.</li>
  <li><strong>Con el plugin Club Kit:</strong> abre el plugin → unpack / insert kit desde el panel (mismo resultado: la jerarquía entra al place).</li>
  </ul>
</li>
<li>En Explorer, confirma estas rutas:
  <ul>
  <li><code>ReplicatedStorage/Hazastudio_ClubKit</code> — motor (se reemplaza con Update Engine)</li>
  <li><code>ReplicatedStorage/Hazastudio_ClubKitConfig</code> + <code>ClubKitConfig</code> — <strong>tuyos para siempre</strong>; Update Engine no los reemplaza enteros</li>
  <li><code>ServerScriptService/Hazastudio_ClubKitSecrets</code> + <code>Secrets</code> — <strong>tuyos para siempre</strong>; no los sobrescribas al actualizar</li>
  <li><code>ServerScriptService/Hazastudio_ClubKit</code>, <code>StarterPlayer/StarterPlayerScripts/Hazastudio_ClubKit</code>, <code>ReplicatedFirst/Hazastudio_ClubKit</code></li>
  <li>Carpetas GUI en <code>StarterGui</code> <code>01-</code> … <code>15-</code></li>
  <li><code>ServerStorage/Tools</code></li>
  <li>Boards de leaderboard en <code>Workspace</code></li>
  <li><code>ReplicatedStorage/WorldEffects</code> (modelos Nuke / Smite / BlackHole)</li>
  </ul>
</li>
</ol>
<p><strong>Nota breve:</strong> <code>ClubKitShowcase</code> no va en el sync de motor por defecto — solo demos; no lo necesitas para salir en vivo.</p>
<div class="tutorial-verify"><strong>Éxito si:</strong> las rutas anteriores están en Explorer y el Play test no falla por carpetas del kit ausentes. <code>ClubKitConfig</code> + <code>Secrets</code> listos para los siguientes pasos.</div>""",
        "setup.flow.s2.title": "Branding, Group y Owner",
        "setup.flow.s2.html": """<p>Sin Group/Owner muchas funciones (comandos de owner, community board) no funcionan. Sustituye el logo de la comunidad antes de salir en vivo — no dejes el logo por defecto del kit en un place live.</p>
<ol>
<li>Lo más fácil: abre <strong>plugin Club Kit → Config → General</strong> y <strong>Branding</strong>. Rellena <code>GameName</code>, greeting y <strong>LogoImage</strong> (logo de tu venue).</li>
<li>Pon <code>GroupId</code> = ID de tu grupo Roblox y <code>OwnerUserId</code> = UserId del owner. Opcional: admins en <code>AdminUserIds</code>.</li>
<li>Alternativa por Source: Explorer → <code>ReplicatedStorage/Hazastudio_ClubKitConfig/ClubKitConfig</code> → edita directo.</li>
<li>Ejecuta <strong>Diagnostics</strong> del plugin. Fallo más común: <code>GROUP_ID</code> inválido o todavía <code>0</code>.</li>
</ol>
<pre><code><span class="key">ClubKitConfig</span>.<span class="key">Branding</span> = {
    <span class="key">GameName</span> = <span class="str">"Nombre de tu club"</span>,
    <span class="key">LogoImage</span> = <span class="str">"rbxassetid://YOUR_COMMUNITY_LOGO_ID"</span>,
}
<span class="key">ClubKitConfig</span>.<span class="key">Group</span> = {
    <span class="key">GroupId</span> = <span class="num">12345678</span>,
    <span class="key">OwnerUserId</span> = <span class="num">987654321</span>,
}
<span class="key">ClubKitConfig</span>.<span class="key">AdminUserIds</span> = {
    [<span class="num">111111111</span>] = <span class="kw">true</span>,
}</code></pre>
<div class="tutorial-verify"><strong>Éxito si:</strong> Diagnostics aprueba GroupId + logo; el Play test no avisa de <code>GROUP_ID</code> inválido; loading / Join Community usa el logo del venue.</div>""",
        "setup.flow.s3.title": "Membresía (Game Pass + regalo)",
        "setup.flow.s3.html": """<p>La compra para uno mismo usa un <strong>Game Pass</strong>; regalar a otro jugador usa un <strong>Developer Product</strong> por tier. La tienda debe estar activa para que salga el prompt de compra.</p>
<ol>
<li>Creator Dashboard → <strong>Monetization → Game Passes</strong> → crea un pass por tier (p. ej. VIP / VVIP / Supreme) para self-buy.</li>
<li>Creator Dashboard → <strong>Developer Products</strong> → crea un product de regalo por el mismo tier.</li>
<li>Plugin → <strong>Config → Membership</strong>: pega <code>BuyGamePassId</code> + <code>GiftId</code> por producto. <code>BuyId</code> es solo legacy — usa <code>BuyGamePassId</code>.</li>
<li>Asegura <code>Features.Shop = true</code> (plugin Config → Features).</li>
<li>Vuelve a ejecutar <strong>Diagnostics</strong> — avisa si los Game Pass / IDs de shop siguen vacíos o en <code>0</code>.</li>
</ol>
<pre><code><span class="key">ClubKitConfig</span>.<span class="key">Shop</span>.<span class="key">Products</span> = {
    {
        <span class="key">Key</span> = <span class="str">"VIP"</span>,
        <span class="key">BuyGamePassId</span> = <span class="num">123456789</span>,
        <span class="key">GiftId</span> = <span class="num">987654321</span>,
        <span class="key">Price</span> = <span class="num">399</span>, <span class="cmt">-- visualización UI (opcional)</span>
    },
}
<span class="key">ClubKitConfig</span>.<span class="key">Features</span>.<span class="key">Shop</span> = <span class="kw">true</span></code></pre>
<div class="tutorial-verify"><strong>Éxito si:</strong> Diagnostics no avisa pases faltantes; en Play el prompt de shop muestra el precio correcto; Output no spamea <code>BuyGamePassId</code> = <code>0</code>. Sigue con <a href="#step-4">broadcast</a>.</div>""",
        "setup.flow.s4.title": "Broadcast de pago",
        "setup.flow.s4.html": """<p>El broadcast de pago usa un <strong>Developer Product aparte</strong> — no un Game Pass de membresía ni una entrada de <code>Shop.Products</code>. Este campo aún no está en el panel Membership del plugin; edítalo en Source.</p>
<ol>
<li>Creator Dashboard → <strong>Developer Products</strong> → crea <strong>uno</strong> para paid broadcast (nombre libre, precio en Robux).</li>
<li>Copia el Product ID → Explorer → <code>ClubKitConfig</code> → <code>PaidBroadcast.ProductId</code>.</li>
<li>Asegura que el broadcast esté activo en tu venue (icono Broadcast visible en Play).</li>
<li>Play test: clic en <strong>Broadcast</strong> de la topbar → debe salir el prompt de compra Robux (no un fallo silencioso).</li>
</ol>
<pre><code><span class="key">ClubKitConfig</span>.<span class="key">PaidBroadcast</span> = {
    <span class="key">ProductId</span> = <span class="num">1122334455</span>, <span class="cmt">-- Developer Product, no Game Pass</span>
}</code></pre>
<div class="tutorial-verify"><strong>Éxito si:</strong> Output no avisa ProductId de PaidBroadcast en <code>0</code>; Broadcast muestra precio; aparece el prompt. Si el ID sigue en <code>0</code>, edita Source y re-prueba.</div>""",
        "setup.flow.s5.title": "Donaciones cash (opcional)",
        "setup.flow.s5.html": """<p>Omite este paso si tu venue no usa donaciones IDR / cash. Si usas Bagi-Bagi, Saweria o SociaBuzz, rellena provider + API + secret.</p>
<ol>
<li>Plugin → pestaña <strong>Donations</strong> (o Source <code>ClubKitConfig.Donation</code>): <code>Provider</code> = <code>bagibagi</code> | <code>saweria</code> | <code>sociabuzz</code>.</li>
<li>Rellena <code>ProviderLink</code> (URL pública de donación) y <code>ApiUrl</code> (endpoint de tu worker).</li>
<li>Explorer → <code>ServerScriptService/Hazastudio_ClubKitSecrets/Secrets</code> → <code>DonationApiSecret</code> igual al secret del worker.</li>
<li><strong>SociaBuzz:</strong> desde el panel admin, pega el webhook en la integración TRIBE → Webhook Token → <strong>Test Notification</strong>.</li>
<li>Si <code>ApiUrl</code> está vacío: los boards cash pueden ir en modo boards-only (sin feed API) — bien si la API aún no está lista.</li>
<li>Donaciones Robux (opcional): crea Developer Products de donación, o deja que el servidor autocargue los del experience.</li>
</ol>
<pre><code><span class="key">ClubKitConfig</span>.<span class="key">Donation</span> = {
    <span class="key">Provider</span> = <span class="str">"saweria"</span>,
    <span class="key">ProviderLink</span> = <span class="str">"https://saweria.co/yourpage"</span>,
    <span class="key">ApiUrl</span> = <span class="str">"https://your-worker.example/api"</span>,
}
<span class="cmt">-- Secrets (solo servidor)</span>
<span class="key">Secrets</span>.<span class="key">DonationApiSecret</span> = <span class="str">"your-donation-worker-secret"</span></code></pre>
<div class="tutorial-verify"><strong>Éxito si:</strong> con <code>ApiUrl</code> relleno el board cash no se queda en &quot;API not configured&quot;; una donación de prueba llega al board. ¿Sin API cash? Marca esos ítems del checklist como N/A y sigue a <a href="#step-6">Nuke</a>.</div>""",
        "setup.flow.s6.title": "NukeWorldPosition (efectos de mundo)",
        "setup.flow.s6.html": """<p>Los VFX de escenario (Nuke / Smite / BlackHole) aparecen en <strong>una</strong> coordenada del mundo. <code>Donation.NukeWorldPosition</code> <strong>aún no</strong> está en la UI Donations del plugin — edita Source. Los modelos vienen del rbxm (<code>WorldEffects</code>); Update Engine no los reemplaza.</p>
<ol>
<li>Pon <code>Features.DonationWorldEffects = true</code> (plugin Config → Features) si usas efectos de escenario.</li>
<li>En Workspace, selecciona un Part sobre el escenario → Properties → copia <strong>Position</strong> X, Y, Z.</li>
<li>Edita Source: <code>ClubKitConfig.Donation.NukeWorldPosition = Vector3.new(X, Y, Z)</code>.</li>
<li>Umbrales cash por defecto: <strong>100k</strong> Nuke · <strong>250k</strong> Smite · <strong>500k</strong> BlackHole.</li>
<li>Play test: <code>/fakecash 100000</code> (preview) — el efecto debe salir en tu escenario, no en la coordenada plantilla.</li>
</ol>
<pre><code><span class="key">ClubKitConfig</span>.<span class="key">Features</span>.<span class="key">DonationWorldEffects</span> = <span class="kw">true</span>
<span class="key">ClubKitConfig</span>.<span class="key">Donation</span>.<span class="key">NukeWorldPosition</span> = <span class="kw">Vector3</span>.<span class="key">new</span>(<span class="num">0</span>, <span class="num">12</span>, <span class="num">-40</span>)</code></pre>
<div class="tutorial-verify"><strong>Éxito si:</strong> el efecto aparece en el escenario del venue. Si sale fuera del mapa, la Position está mal — vuelve a copiar del Part. ¿Sin world FX? Apaga el Feature y omite el ítem Nuke del checklist.</div>""",
        "setup.flow.s7.title": "Roles, tools y features",
        "setup.flow.s7.html": """<p>Ajusta roles, carpetas de tools y toggles de features a tu venue. Cada <code>toolFolder</code> del rol debe tener una carpeta gemela en <code>ServerStorage/Tools/</code>.</p>
<ol>
<li>Edita <code>RoleCategories</code> en <code>ClubKitConfig</code> (o plugin Config si está): labels, <code>chatTag</code>, <code>teamColor</code>, <code>toolFolder</code>.</li>
<li>Revisa Explorer → <code>ServerStorage/Tools/&lt;nombre&gt;/</code> (p. ej. <code>STAFF</code>, <code>VIP</code>, <code>DONOR</code>) con los Tools a otorgar.</li>
<li>Plugin → <strong>Config → Features</strong>: pon <code>false</code> en módulos que no uses (shop, broadcast, cash, world FX, etc.).</li>
<li><code>SpenderRoles</code> es opcional — desactiva tiers spender que no uses.</li>
<li>Privilegios en breve: flags como <code>canGift</code>, <code>canAnnounce</code>, <code>adminPanel</code> se definen por categoría de rol, no por jugador.</li>
</ol>
<pre><code><span class="key">roles</span> = {
    {
        <span class="key">key</span> = <span class="str">"Staff"</span>,
        <span class="key">label</span> = <span class="str">"Staff"</span>,
        <span class="key">chatTag</span> = <span class="str">"STAFF"</span>,
        <span class="key">toolFolder</span> = <span class="str">"STAFF"</span>, <span class="cmt">-- debe existir ServerStorage/Tools/STAFF</span>
        <span class="key">teamColor</span> = <span class="str">"Royal purple"</span>,
    },
}</code></pre>
<div class="tutorial-verify"><strong>Éxito si:</strong> <code>/setrole</code> asigna el rol correcto y los tools aparecen en la mochila. Las features apagadas no muestran GUI/comandos no deseados.</div>""",
        "setup.flow.s8.title": "Play test en Studio",
        "setup.flow.s8.html": """<p>Prueba los flujos críticos antes de publicar. Studio usa DataStores aislados (<code>Studio_*</code>) — seguro, no escribe datos live. Distingue comandos de <strong>preview</strong> (no persisten) de los que escriben datos.</p>
<ol>
<li><strong>Game Settings → Security</strong> → Enable Studio Access to API Services = <strong>ON</strong>.</li>
<li>Play (F5). Prueba: shop / gift, icono Broadcast, panel de donación, boards (vacíos = normal en place nuevo).</li>
<li>Comandos útiles (owner/admin):
  <ul>
  <li><code>/fakecash 100000</code> / <code>/fakerobux 10</code> — <strong>preview</strong> de notifs + VFX; no persiste al leaderboard live</li>
  <li><code>/setrole</code>, <code>/gift</code> — flujo de rol y gift</li>
  <li>Alias legacy <code>/testcash</code> / <code>/testrobux</code> siguen funcionando</li>
  </ul>
</li>
<li>Arreglos rápidos si falla:
  <ul>
  <li>Pass / shop sin prompt → <code>BuyGamePassId</code> aún <code>0</code> (<a href="#step-3">paso 3</a>)</li>
  <li>Broadcast silencioso → <code>PaidBroadcast.ProductId</code> aún <code>0</code> (<a href="#step-4">paso 4</a>)</li>
  <li>Board &quot;API not configured&quot; → rellena <code>ApiUrl</code> + secret, o déjalo vacío a propósito (<a href="#step-5">paso 5</a>)</li>
  <li>Nuke en el lugar equivocado → Position (<a href="#step-6">paso 6</a>)</li>
  </ul>
</li>
</ol>
<div class="tutorial-verify"><strong>Éxito si:</strong> sin errores rojos en Output; cargan las GUI; shop / broadcast / fakecash responden según tu config. Marca &quot;Probado en Studio&quot; en el checklist de la derecha.</div>""",
        "setup.flow.s9.title": "Checklist y publicar",
        "setup.flow.s9.html": """<p>Salir en vivo = checklist 12/12 + Publish. Después, hábito diario: <strong>Update Engine</strong> desde el plugin (config y secrets seguros).</p>
<ol>
<li>Revisa el <strong>Deploy checklist</strong> de la derecha — marca cada fila hecha. Meta: <strong>12 / 12</strong>.</li>
<li><strong>File → Publish to Roblox</strong> (o Publish as si el place es nuevo).</li>
<li><strong>Hábito post go-live:</strong> plugin → <strong>Engine → Check Update → Update Engine</strong> → Save. <code>ClubKitConfig</code> y <code>Secrets</code> no se reemplazan enteros; claves nuevas hacen fill-forward.</li>
<li>El <code>.rbxm</code> después es raro — solo instalación nueva o cuando cambien GUI / boards / modelos WorldEffects. El Luau diario basta con Update Engine.</li>
</ol>
<div class="tutorial-verify"><strong>Listo para publicar si:</strong> checklist 12/12, Diagnostics limpio en Group/logo/pass/API que uses, play test en Studio hecho, Nuke y PaidBroadcast rellenados si esas features están on.</div>""",
    },
}

HOME_PATCHES: dict[str, dict[str, str]] = {
    "id": {
        "home.topics.setup.title": "Setup place (satu alur)",
        "home.topics.setup.desc": "Satu panduan dari insert kit sampai publish — branding, membership, donasi, play test, checklist.",
        "home.card.setup.desc": "Alur setup tunggal: insert kit → config → play test → publish. Checklist di kanan halaman.",
        "home.topics.config.title": "Membership & donations",
        "home.topics.config.desc": "Sudah dicakup di alur setup — mulai dari <a href=\"setup.html#step-3\">langkah 3 (Membership)</a> dan donasi di langkah 5.",
        "home.topics.commands.title": "Play test & commands",
        "home.topics.commands.desc": "Sudah dicakup di alur setup — lihat <a href=\"setup.html#step-8\">langkah 8 (Play test)</a> untuk perintah dan perbaikan cepat.",
        "home.topics.trouble.title": "Diagnostics tips",
        "home.topics.trouble.desc": "Tips Diagnostics &amp; perbaikan umum ada di <a href=\"setup.html#step-8\">langkah 8</a> dalam alur setup.",
        "updates.how.note": "Fresh install atau saat GUI/board berubah → insert <code>.rbxm</code> (jarang). Detail: <a href=\"setup.html#step-9\">Setup → Publish</a>.",
    },
    "en": {
        "home.topics.setup.title": "Setup your place (single flow)",
        "home.topics.setup.desc": "One guide from insert kit to publish — branding, membership, donations, play test, checklist.",
        "home.card.setup.desc": "Single setup flow: insert kit → configure → play test → publish. Checklist sits on the right of the page.",
        "home.topics.config.title": "Membership & donations",
        "home.topics.config.desc": "Covered inside the setup flow — start at <a href=\"setup.html#step-3\">step 3 (Membership)</a> and donations in step 5.",
        "home.topics.commands.title": "Play test & commands",
        "home.topics.commands.desc": "Covered inside the setup flow — see <a href=\"setup.html#step-8\">step 8 (Play test)</a> for commands and quick fixes.",
        "home.topics.trouble.title": "Diagnostics tips",
        "home.topics.trouble.desc": "Diagnostics tips and common fixes live in <a href=\"setup.html#step-8\">step 8</a> of the setup flow.",
        "updates.how.note": "Fresh install or when GUI/board models change → insert the <code>.rbxm</code> (rare). Details: <a href=\"setup.html#step-9\">Setup → Publish</a>.",
    },
    "ja": {
        "home.topics.setup.title": "プレイス設定（単一フロー）",
        "home.topics.setup.desc": "キット挿入から公開までの一本のガイド — ブランディング、メンバーシップ、寄付、プレイテスト、チェックリスト。",
        "home.card.setup.desc": "単一セットアップフロー: 挿入 → 設定 → プレイテスト → 公開。チェックリストはページ右側。",
        "home.topics.config.title": "Membership & donations",
        "home.topics.config.desc": "セットアップフロー内で扱います — <a href=\"setup.html#step-3\">手順 3（メンバーシップ）</a> と手順 5 の寄付から。",
        "home.topics.commands.title": "Play test & commands",
        "home.topics.commands.desc": "セットアップフロー内で扱います — コマンドと近道は <a href=\"setup.html#step-8\">手順 8（プレイテスト）</a>。",
        "home.topics.trouble.title": "Diagnostics tips",
        "home.topics.trouble.desc": "Diagnostics のヒントとよくある修正はセットアップ <a href=\"setup.html#step-8\">手順 8</a> にあります。",
        "updates.how.note": "新規導入や GUI/ボード変更時 → <code>.rbxm</code> を挿入（稀）。詳細: <a href=\"setup.html#step-9\">Setup → Publish</a>。",
    },
    "es": {
        "home.topics.setup.title": "Configura tu place (un solo flujo)",
        "home.topics.setup.desc": "Una guía desde insertar el kit hasta publicar — branding, membresía, donaciones, play test, checklist.",
        "home.card.setup.desc": "Flujo de setup único: insertar kit → configurar → play test → publicar. El checklist está a la derecha.",
        "home.topics.config.title": "Membership & donations",
        "home.topics.config.desc": "Cubierto en el flujo de setup — empieza en <a href=\"setup.html#step-3\">paso 3 (Membresía)</a> y donaciones en el paso 5.",
        "home.topics.commands.title": "Play test & commands",
        "home.topics.commands.desc": "Cubierto en el flujo de setup — ver <a href=\"setup.html#step-8\">paso 8 (Play test)</a> para comandos y arreglos rápidos.",
        "home.topics.trouble.title": "Diagnostics tips",
        "home.topics.trouble.desc": "Tips de Diagnostics y arreglos comunes están en el <a href=\"setup.html#step-8\">paso 8</a> del flujo de setup.",
        "updates.how.note": "Instalación nueva o cuando cambien GUI/boards → inserta el <code>.rbxm</code> (raro). Detalle: <a href=\"setup.html#step-9\">Setup → Publish</a>.",
    },
}


if __name__ == "__main__":
    import json

    for lang in FLOW:
        assert set(FLOW["id"]) == set(FLOW[lang]), lang
    for lang in HOME_PATCHES:
        assert set(HOME_PATCHES["id"]) == set(HOME_PATCHES[lang]), lang
    print("ok", len(FLOW["id"]), "keys")
    print("home_patches", len(HOME_PATCHES["id"]), "keys", json.dumps(list(HOME_PATCHES["id"].keys())))
