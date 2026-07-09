--!nocheck
-- ============================================================
-- MUSIC LIBRARY MIGRATION TOOL
-- ============================================================
-- Tool buat import lagu dari sistem musik lain ke THE BASIC CLUB KIT.
-- Mapping otomatis: normalPlaybackSpeed → playbackSpeed, parts → parts, dst.
--
-- CARA PAKAI:
-- 1. Edit SOURCE_DATA di bawah dengan data dari sistem lama (lihat
--    example-source.luau buat referensi format).
-- 2. Set MODE = "dry_run" dulu untuk preview tanpa nulis ke DataStore.
-- 3. Run script ini di Roblox Studio Command Bar (server-side context):
--    - Cara A: Drop ke ServerScriptService temporarily, run sekali, hapus.
--    - Cara B: Paste full content ke Command Bar di Studio (Edit Mode
--      gak akan jalan, harus Run/Play Mode supaya DataStore enabled).
-- 4. Verify output di Output window. Kalau OK, ganti MODE = "commit"
--    dan run lagi untuk write beneran.
-- 5. HAPUS script ini setelah migrasi selesai.
--
-- SAFETY:
-- - Dry-run by default. Gak bakal nyentuh DataStore kecuali MODE=="commit".
-- - Strategy "merge" (default): preserve existing tracks/playlists, cuma
--   tambah yang baru. Strategy "replace": overwrite SEMUA (HATI-HATI).
-- - Idempotent: re-run dgn data yang sama gak duplicate (pake key
--   "migrationKey" sebagai dedupe).
-- ============================================================

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

-- ============================================================
-- CONFIG (edit sebelum run)
-- ============================================================

-- "dry_run" = preview only, no DataStore writes.
-- "commit"  = actually write to DataStore.
local MODE: string = "commit"

-- "merge"   = preserve existing, append new (recommended).
-- "replace" = wipe DataStore & write only incoming (DESTRUCTIVE).
local STRATEGY: string = "merge"

-- DataStore identifiers — harus match Config.Music.
local DATASTORE_NAME = "MusicLibrary_v1"
local PLAYLIST_KEY = "Playlists"
local TRACK_KEY = "Tracks"

-- Max audio asset IDs per track. Match Config.Music.MAX_TRACK_PARTS.
local MAX_TRACK_PARTS = 9

-- Default playlist buat track yang gak punya playlist info di source.
local DEFAULT_PLAYLIST_NAME = "Imported"

-- Tag buat dedupe re-run. Track/playlist yang udah punya tag ini
-- dgn migrationKey yang sama akan di-skip pas merge.
local MIGRATION_TAG = "migration-tool-v1"

-- ============================================================
-- SOURCE DATA
-- ============================================================
-- Paste source di sini. Format fleksibel — mapper di bawah akan
-- normalize ke schema internal kit. Lihat example-source.luau buat
-- format yang didukung.
--
-- Schema yang diharapkan (semua field opsional kecuali yg ditandai *):
-- {
--   playlists = {                          -- opsional, bisa di-infer
--     { id?, name*, coverType?, coverValue?, fontFace? },
--     ...
--   },
--   tracks = {
--     {
--       id?,                               -- opsional, auto-generate
--       name*,                             -- string
--       creator?,                          -- string, default "Unknown"
--       playlistName? | playlistId?,       -- pilih salah satu
--       parts*,                            -- { string } atau { number }
--       normalPlaybackSpeed? | playbackSpeed?, -- number, opsional
--     },
--     ...
--   },
-- }
local SOURCE_DATA: { [string]: any } = {
	playlists = {
		{ name = "ACILA PLAYLIST" },
		{ name = "Stadium" },
		{ name = "3 AM" },
		{ name = "Techno/Hardstyle" },
		{ name = "Chill" },
		{ name = "Manyao" },
		{ name = "XEMEK" },
		{ name = "PLAYLIST PAW" },
		{ name = "SAD PLAYLIST" },
		{ name = "IKOK REQ" },
		{ name = "GO PAW" },
		{ name = "CNY PAW" },
		{ name = "CHEF" },
		{ name = "PAW MIX" },
		{ name = "SECTOR B" },
		{ name = "HIPPOP REMIX" },
		{ name = "ANIME EDM" },
		{ name = "NYX PLAYLIST" },
		{ name = "POP LUAR" },
		{ name = "POP EDM" },
		{ name = "ICONIC PLAYLIST" },
		{ name = "GO JAMES" },
		{ name = "JAMES PLAYLIST" },
		{ name = "RNB" },
	},
	tracks = {
		{
			name = "Justin Bieber 1",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://118701328116095" },
		},
		{
			name = "home on air mix",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://73375841073827" },
		},
		{
			name = "low mix tokyo drift",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://137125982161369" },
		},
		{
			name = "ARIANA GRANDE MIX 3",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://85352571609750" },
		},
		{
			name = "ARIANA GRANDE MIX 4",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://89022611566090" },
		},
		{
			name = "Kendrick Lamar Not Like us",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://87564015964556" },
		},
		{
			name = "LIKE A G6 x David Guetta",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://115096763935676" },
		},
		{
			name = "Justin Bieber 2",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://136605705189964" },
		},
		{
			name = "Bon Jovi its my life",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://105809276083298" },
		},
		{
			name = "Havana Camila Cabello",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://100440758621739" },
		},
		{
			name = "JKT48 fortune cookie",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://104263288070410" },
		},
		{
			name = "Welcome To The Black Parade MCR",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://79033402234527" },
		},
		{
			name = "MyChemicalRomance I Dont Love U",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://127870653544082" },
		},
		{
			name = "MyChemicalRomance Helena",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://139762230068948" },
		},
		{
			name = "Whisnu santika",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://97086182055223" },
		},
		{
			name = "Sweet Child O Mine ft. DJ Raul",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://99512429033957" },
		},
		{
			name = "Hoobastank The Reason",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://137401410195458" },
		},
		{
			name = "Wake Me up When September Ends",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://97235222818748" },
		},
		{
			name = "La Luz Del Sol Mix Bruno Mars",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://94838891388631" },
		},
		{
			name = "JB Ghost",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://94866673660756" },
		},
		{
			name = "DIE FOR YOU",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://136686951768261" },
		},
		{
			name = "Maroon 5 She Will Be Loved",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://77665126263855" },
		},
		{
			name = "JKT48 Rapsodi",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://88243067420901" },
		},
		{
			name = "JB Never Say Never",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://82055367817517" },
		},
		{
			name = "NIKI You Be In My Heart",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://111292035549103" },
		},
		{
			name = "LANY ILYSB Thisishelm",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://118748029942622" },
		},
		{
			name = "Bring Me to Life",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://111556163077365" },
		},
		{
			name = "WIBU Silhouette",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://74140021917149" },
		},
		{
			name = "WIBU InfinityCastle",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://113869254733627" },
		},
		{
			name = "WIBU AOT Redswan",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://131314326818127" },
		},
		{
			name = "KPOP Taeyang Eyes nose lip",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://97632704118524" },
		},
		{
			name = "KPOP Taeyang Wedding dress",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://99907904483750" },
		},
		{
			name = "La La Lost You",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://127577509957881" },
		},
		{
			name = "Raisa Apalah arti menunggu",
			creator = "Acila",
			playlistName = "ACILA PLAYLIST",
			parts = { "rbxassetid://97010760863727" },
		},
		{
			name = "Perfect Liar X Golden",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://101862221409871" },
		},
		{
			name = "Atlantis",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://87955266459325" },
		},
		{
			name = "Beautiful Lie",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://114020405798613" },
		},
		{
			name = "Rusty Guitar",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://88989558021681" },
		},
		{
			name = "Berdua Lebih Baik Stadium",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://89866756163244" },
		},
		{
			name = "Meriang",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://84273429518203" },
		},
		{
			name = "Aria",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://79050518541152" },
		},
		{
			name = "Kasih Aba-Aba X Rise X Shelter",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://70859487025367" },
		},
		{
			name = "Walking On Air STADIUM",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://114442273558721" },
		},
		{
			name = "Russian Roulette STADIUM",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://76817788515061" },
		},
		{
			name = "Middle of Nowhere STADIUM",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://120836619403429" },
		},
		{
			name = "Ni Yao De Ai BKB",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://95666074801870" },
		},
		{
			name = "Peng You BKB",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://79378375562712" },
		},
		{
			name = "LOVE HIS ME CRAZY BKB S",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://131418684232867" },
		},
		{
			name = "Ruo Yue Liang Mei Lai BKB",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://111828790369037" },
		},
		{
			name = "Million Stars X Gwenchana Indobounce",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://111084358456516" },
		},
		{
			name = "WIND OF CHANGE",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://79952514827895" },
		},
		{
			name = "MARVIN G WD TG",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://81962485426601" },
		},
		{
			name = "I need a doctor",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://100297909099774" },
		},
		{
			name = "Always Loving You",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://128955089402116" },
		},
		{
			name = "Sunshine Love (BKB)",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://72484100745582" },
		},
		{
			name = "Takkan Pisah BBHC (BKB)",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://137479951758633" },
		},
		{
			name = "G G DULU (BKB)",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://86021929503475" },
		},
		{
			name = "CINTA SATU MALAM (BKB)",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://118979112683030" },
		},
		{
			name = "ROSEMARY (BKB)",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://109011701024857" },
		},
		{
			name = "Industry",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://100791306432432" },
		},
		{
			name = "paboz",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://72481977505543" },
		},
		{
			name = "TOR MONITOR (BKB)",
			creator = "Unknown",
			playlistName = "Stadium",
			parts = { "rbxassetid://106539327353468" },
		},
		{
			name = "IKOK SONG",
			creator = "Unknown",
			playlistName = "3 AM",
			parts = { "rbxassetid://94172849540376" },
		},
		{
			name = "LANY - Malibu Nights",
			creator = "Unknown",
			playlistName = "3 AM",
			parts = { "rbxassetid://105512961160214" },
		},
		{
			name = "LANY - ILYSB Amapiano",
			creator = "Unknown",
			playlistName = "3 AM",
			parts = { "rbxassetid://78658480396249" },
		},
		{
			name = "LANY - XXL (UKG Edit)",
			creator = "Unknown",
			playlistName = "3 AM",
			parts = { "rbxassetid://92149324289018" },
		},
		{
			name = "back to friends (Jersey Edit)",
			creator = "Unknown",
			playlistName = "3 AM",
			parts = { "rbxassetid://132410784218664" },
		},
		{
			name = "Fix You (Salon Ver.)",
			creator = "Unknown",
			playlistName = "3 AM",
			parts = { "rbxassetid://113540442408412" },
		},
		{
			name = "Talking to the Moon",
			creator = "Unknown",
			playlistName = "3 AM",
			parts = { "rbxassetid://107450970790359" },
		},
		{
			name = "Kerispatih - Tapi Bukan Aku",
			creator = "Unknown",
			playlistName = "3 AM",
			parts = { "rbxassetid://122594563714833" },
		},
		{
			name = "Kerispatih - Demi Cinta",
			creator = "Unknown",
			playlistName = "3 AM",
			parts = { "rbxassetid://120636513903929" },
		},
		{
			name = "Kerispatih - Mengenangmu",
			creator = "Unknown",
			playlistName = "3 AM",
			parts = { "rbxassetid://89993709480858" },
		},
		{
			name = "Misellia - Akhir Tak Bahagia",
			creator = "Unknown",
			playlistName = "3 AM",
			parts = { "rbxassetid://107348347495503" },
		},
		{
			name = "Agnez Mo - Matahariku",
			creator = "Unknown",
			playlistName = "3 AM",
			parts = { "rbxassetid://94281844058750" },
		},
		{
			name = "SAMSON - Tak Bisa Memiliki",
			creator = "Unknown",
			playlistName = "3 AM",
			parts = { "rbxassetid://84945657664140" },
		},
		{
			name = "GOOD IS DJ (Intro) - JAY Techno",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://90319531481606" },
		},
		{
			name = "LP - Faint (Hardtechno)",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://119650461903108" },
		},
		{
			name = "Surfacing (Acid Techno)",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://77277966482334" },
		},
		{
			name = "Bodies (Hard Techno)",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://124643429703789" },
		},
		{
			name = "Stereo Love Techno",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://137330618189563" },
		},
		{
			name = "Caramelle x Diet Coke",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://110144100641430" },
		},
		{
			name = "Tsunami",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://76830643565730" },
		},
		{
			name = "Animals",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://121965261422321" },
		},
		{
			name = "Aria X Tremor",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://129538175579052" },
		},
		{
			name = "No Good For Me X Tembak Langit",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://96704654425176" },
		},
		{
			name = "Ternyata Pestol X Yummy X PAPA GAK BAWA UANG",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://100969882114517" },
		},
		{
			name = "We Found Love (Ray Volpe)",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://85629253532981" },
		},
		{
			name = "Golden",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://118909173648221" },
		},
		{
			name = "NewJeans - ETA (Techno)",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://74906160437466" },
		},
		{
			name = "AJ Tracey - Ladbroke Grove",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://125136999876794" },
		},
		{
			name = "Praise The Lord (Techno)",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://119078635423997" },
		},
		{
			name = "Bang Bang Bang (Techno)",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://139562038241659" },
		},
		{
			name = "Blinding Lights Hardtechno",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://125080307474747" },
		},
		{
			name = "bel mercy nokia tone intro hardtech",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://108332677522687" },
		},
		{
			name = "gam gam gam techno",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://131713618866607" },
		},
		{
			name = "No Broke Boys Hardtechno",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://71654241254125" },
		},
		{
			name = "Macarena Hardtechno",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://140609165953141" },
		},
		{
			name = "world of dreams hardtechno",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://118760641732878" },
		},
		{
			name = "NO ANGEL-JAY Techno",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://105239913123221" },
		},
		{
			name = "MARIO TIME Techno",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://118968727745359" },
		},
		{
			name = "LOVE IS GONE Techno",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://119665459305661" },
		},
		{
			name = "BRING ME TO LIFE",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://111556163077365" },
		},
		{
			name = "Psychosocial",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://121710338767724" },
		},
		{
			name = "LP - New Divide (Hardstyle)",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://119712684242104" },
		},
		{
			name = "Gangstas Paradise (Hardstyle)",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://76499268510555" },
		},
		{
			name = "On The Floor (Hard Dance)",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://105022388634049" },
		},
		{
			name = "Mockingbird (Hardstyle)",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://83297703641064" },
		},
		{
			name = "Viva La Vida (Hardstyle)",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://133442239433150" },
		},
		{
			name = "Akon - Right Now (Hard Dance)",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://124709540818201" },
		},
		{
			name = "Voices in My Head (Techno)",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://71059173431937" },
		},
		{
			name = "Moon",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://116287959058955" },
		},
		{
			name = "The Nights (Techno)",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://131205612858406" },
		},
		{
			name = "Photograph (H)",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://137616374837393" },
		},
		{
			name = "Lowkey (Techno Edit)",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://118125487107817" },
		},
		{
			name = "Hampa (Techno)",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://77806724400554" },
		},
		{
			name = "Abracadabra (Techno)",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://129054513355554" },
		},
		{
			name = "Pump It Louder (Techno)",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://104313600944179" },
		},
		{
			name = "Tell Me Why (Techno)",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://93179940669038" },
		},
		{
			name = "Skyfall (Hardtechno)",
			creator = "Unknown",
			playlistName = "Techno/Hardstyle",
			parts = { "rbxassetid://107420072607549" },
		},
		{
			name = "Aku Cinta Dia (Disco Edit)",
			creator = "Unknown",
			playlistName = "Chill",
			parts = { "rbxassetid://88458339833863" },
		},
		{
			name = "You Da One (UKG Edit)",
			creator = "Unknown",
			playlistName = "Chill",
			parts = { "rbxassetid://90264300328905" },
		},
		{
			name = "Somebody To Love X Love Me Harder",
			creator = "Unknown",
			playlistName = "Chill",
			parts = { "rbxassetid://94981296627916" },
		},
		{
			name = "Baby Doll X Cari Pacar Lagi",
			creator = "Unknown",
			playlistName = "Chill",
			parts = { "rbxassetid://90029406212084" },
		},
		{
			name = "Falling Stars Prog EDM",
			creator = "Unknown",
			playlistName = "Chill",
			parts = { "rbxassetid://102385551432331" },
		},
		{
			name = "ONE OK ROCK - Where You Are [Prog]",
			creator = "Unknown",
			playlistName = "Chill",
			parts = { "rbxassetid://129940298052569" },
		},
		{
			name = "No One Can Stop Us (Dipha Barus)",
			creator = "Unknown",
			playlistName = "Chill",
			parts = { "rbxassetid://132007487625545" },
		},
		{
			name = "Eenie Meenie (EDM)",
			creator = "Unknown",
			playlistName = "Chill",
			parts = { "rbxassetid://91548415080634" },
		},
		{
			name = "Swag (Prog)",
			creator = "Unknown",
			playlistName = "Chill",
			parts = { "rbxassetid://80685424914335" },
		},
		{
			name = "No One",
			creator = "Unknown",
			playlistName = "Chill",
			parts = { "rbxassetid://79198334134139" },
		},
		{
			name = "Redbone RnB",
			creator = "Unknown",
			playlistName = "Chill",
			parts = { "rbxassetid://134303843072560" },
		},
		{
			name = "Yummy (Bounce Edit)",
			creator = "Unknown",
			playlistName = "Chill",
			parts = { "rbxassetid://116157581392411" },
		},
		{
			name = "JABLAY AMAPIANO X 1,2 STEP",
			creator = "Unknown",
			playlistName = "Chill",
			parts = { "rbxassetid://132595833148246" },
		},
		{
			name = "Can't Take My Eyes Off You X NOKIA",
			creator = "Unknown",
			playlistName = "Chill",
			parts = { "rbxassetid://95835041367696" },
		},
		{
			name = "Luther",
			creator = "Unknown",
			playlistName = "Chill",
			parts = { "rbxassetid://136435287467211" },
		},
		{
			name = "Pon De Satisfaction (Miami Bass)",
			creator = "Unknown",
			playlistName = "Chill",
			parts = { "rbxassetid://91849485497937" },
		},
		{
			name = "CHANEL BREAKS",
			creator = "Unknown",
			playlistName = "Chill",
			parts = { "rbxassetid://76765563287964" },
		},
		{
			name = "Manyao",
			creator = "PAWWHO",
			playlistName = "Manyao",
			parts = { "rbxassetid://84280080279541" },
		},
		{
			name = "只是太爱你 BIGROOM",
			creator = "PAWWHO",
			playlistName = "Manyao",
			parts = { "rbxassetid://92936351611631" },
		},
		{
			name = "Paw Mix 1",
			creator = "PAWWHO",
			playlistName = "Manyao",
			parts = { "rbxassetid://95993251170123" },
		},
		{
			name = "Chinese Mix 8 BIGROOM",
			creator = "PAWWHO",
			playlistName = "Manyao",
			parts = { "rbxassetid://115565082142650" },
		},
		{
			name = "Chinese Mix 9",
			creator = "PAWWHO",
			playlistName = "Manyao",
			parts = { "rbxassetid://130717530186081" },
		},
		{
			name = "Ni Yao De Ai BKB",
			creator = "PAWWHO",
			playlistName = "Manyao",
			parts = { "rbxassetid://95666074801870" },
		},
		{
			name = "Peng You BKB",
			creator = "PAWWHO",
			playlistName = "Manyao",
			parts = { "rbxassetid://79378375562712" },
		},
		{
			name = "Ruo Yue Liang Mei Lai BKB",
			creator = "PAWWHO",
			playlistName = "Manyao",
			parts = { "rbxassetid://111828790369037" },
		},
		{
			name = "chns",
			creator = "PAWWHO",
			playlistName = "Manyao",
			parts = { "rbxassetid://106165469986263" },
		},
		{
			name = "chns 02",
			creator = "PAWWHO",
			playlistName = "Manyao",
			parts = { "rbxassetid://112527212980043" },
		},
		{
			name = "chns 03",
			creator = "PAWWHO",
			playlistName = "Manyao",
			parts = { "rbxassetid://114103807209146" },
		},
		{
			name = "xia bei zi bu yi",
			creator = "PAWWHO",
			playlistName = "Manyao",
			parts = { "rbxassetid://97626860274119" },
		},
		{
			name = "HUOLAI Techno",
			creator = "PAWWHO",
			playlistName = "Manyao",
			parts = { "rbxassetid://132553119513039" },
		},
		{
			name = "Faded x Alone x Sing Me To Sleep",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://121165549956000" },
		},
		{
			name = "Lily x Darkside x The Spectre",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://77626172072479" },
		},
		{
			name = "Dont Look Back In Anger x Wonderwall x Stand By Me",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://97140044150959" },
		},
		{
			name = "Sayonara x Gelang",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://135323103883291" },
		},
		{
			name = "In My Room x Legends x Kaolo x Kaolo 2",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://100861952834183" },
		},
		{
			name = "Teenagers x Welcome to The Black Parade x Disenchanted",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://97634997767032" },
		},
		{
			name = "Decade x Misery Business x Still Into You x That's What You Get",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://126036899818489" },
		},
		{
			name = "Never Forget You x Symphony x Stay",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://83586385799189" },
		},
		{
			name = "That's What I Like x 24K Magic x Congratulations x Better Now",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://129760476145797" },
		},
		{
			name = "Shape Of You x Believer x Thunder",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://89835158598558" },
		},
		{
			name = "Ride x Heathens x when the party's over",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://131961719288987" },
		},
		{
			name = "The Hills x Lucid Dreams x 1-800",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://79299732780138" },
		},
		{
			name = "I Heart You x Cukuplah Sudah x O Love You No More",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://111546991085962" },
		},
		{
			name = "Wake Me Up x Waiting For Love x If I Lose Myself",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://73035049515129" },
		},
		{
			name = "Clarity x Find You x  Beautiful x Spectrum x Rude",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://80252299939668" },
		},
		{
			name = "You Know You Like It x Get Low x Middle",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://80012670805748" },
		},
		{
			name = "Runaway x Outside x Tsunami x Dont Let Me Down",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://108298889776274" },
		},
		{
			name = "When You're Gone x Wish You Were Here x Mirros",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://98038448248022" },
		},
		{
			name = "Locked Out Of Heaven x Treat You Better x Stitches x It Ain't Me x Chandelier",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://107057352571926" },
		},
		{
			name = "Baby x Moves Like Jagger x Am I Wrong x Burn x Love Me Like You Do",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://113514169488622" },
		},
		{
			name = "Helena x The Ghost of You (MCR)",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://131684708813634" },
		},
		{
			name = "One Time x Favorite Girl (JB)",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://95302693960087" },
		},
		{
			name = "Beauty & The Beat x Never Say Never (JB)",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://85556299825033" },
		},
		{
			name = "AbaAba x mejiku x Bintang 5 x EEEEA",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://99574010529979" },
		},
		{
			name = "So Far Away x Gunslinger x Seize The Day x Dear God",
			creator = "Unknown",
			playlistName = "XEMEK",
			parts = { "rbxassetid://104653065913052" },
		},
		{
			name = "CLUB 04",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://105979524722742" },
		},
		{
			name = "WHISNU DWP",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://73765732150950" },
		},
		{
			name = "WHISNU DWP 02",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://123487291482835" },
		},
		{
			name = "WHISNU DWP 03",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://111294428515900" },
		},
		{
			name = "WHISNU DWP 04",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://72586797386027" },
		},
		{
			name = "BREAKBEAT VOL 01",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://87851989951921" },
		},
		{
			name = "BREAKBEAT VOL 02",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://138296681512966" },
		},
		{
			name = "BREAKBEAT VOL 03",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://73570849297657" },
		},
		{
			name = "BREAKBEAT VOL 04",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://89859954108173" },
		},
		{
			name = "WG Lathi - Good Life",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://124300957930147" },
		},
		{
			name = "INDOBOUNCE SET EVENT",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://80857292367083" },
		},
		{
			name = "INDOBOUNCE SET EVENT 02",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://136351215255381" },
		},
		{
			name = "INDOBOUNCE SET EVENT 03",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://85582100164434" },
		},
		{
			name = "INDOBOUNCE SET EVENT 04",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://118569215442572" },
		},
		{
			name = "INDOBOUNCE SET EVENT 05",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://100423064390711" },
		},
		{
			name = "INDOBOUNCE SET EVENT 06",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://91509787279883" },
		},
		{
			name = "INDOBOUNCE SET EVENT 07",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://129986770708641" },
		},
		{
			name = "BASSLINE BOUNCE 01",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://88952811351848" },
		},
		{
			name = "BASSLINE BOUNCE 02",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://124746262726459" },
		},
		{
			name = "BASSLINE BOUNCE 03",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://112621683432310" },
		},
		{
			name = "BASSLINE BOUNCE 04",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://131726577920685" },
		},
		{
			name = "BASSLINE BOUNCE 05",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://78687207102588" },
		},
		{
			name = "BASSLINE BOUNCE 06",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://119850510256931" },
		},
		{
			name = "BASSLINE BOUNCE 07",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://104370052644889" },
		},
		{
			name = "BASSLINE BOUNCE 08",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://102836019089423" },
		},
		{
			name = "BASSLINE BOUNCE 09",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://83508718654097" },
		},
		{
			name = "BASSLINE BOUNCE 10",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://96570434526540" },
		},
		{
			name = "BASSLINE BOUNCE 11",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://134433996374075" },
		},
		{
			name = "DWP25 01",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://117080522293694" },
		},
		{
			name = "DWP25 02",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://127008827107754" },
		},
		{
			name = "DWP25 04",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://83511432721953" },
		},
		{
			name = "DWP25 03",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://105383892732692" },
		},
		{
			name = "MIXTAPE IDB BKB - 1",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://129298703036591" },
		},
		{
			name = "MIXTAPE IDB BKB - 2",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://73758824607206" },
		},
		{
			name = "MIXTAPE IDB BKB - 3",
			creator = "Unknown",
			playlistName = "PLAYLIST PAW",
			parts = { "rbxassetid://135728286770178" },
		},
		{
			name = "Bernadya - Satu Bulan",
			creator = "Unknown",
			playlistName = "SAD PLAYLIST",
			parts = { "rbxassetid://100299374957307" },
		},
		{
			name = "Ziva Magnolya - Peri Cintaku",
			creator = "Unknown",
			playlistName = "SAD PLAYLIST",
			parts = { "rbxassetid://91957489130406" },
		},
		{
			name = "Mawar de Jongh - Lebih Dari Egoku",
			creator = "Unknown",
			playlistName = "SAD PLAYLIST",
			parts = { "rbxassetid://85169559155153" },
		},
		{
			name = "Fiersa Besari - Waktu Yang Salah",
			creator = "Unknown",
			playlistName = "SAD PLAYLIST",
			parts = { "rbxassetid://84779165708793" },
		},
		{
			name = "Hanin Dhiya - Pupus",
			creator = "Unknown",
			playlistName = "SAD PLAYLIST",
			parts = { "rbxassetid://119321746546183" },
		},
		{
			name = "Risalh Hati-hitung hari-about seorang-bunga trkhir",
			creator = "Unknown",
			playlistName = "SAD PLAYLIST",
			parts = { "rbxassetid://121944863348050" },
		},
		{
			name = "Bernadya - Kini Mereka Tahu",
			creator = "Unknown",
			playlistName = "SAD PLAYLIST",
			parts = { "rbxassetid://131105389265320" },
		},
		{
			name = "Jadi Debu -Amin Plg Serius- Sorai",
			creator = "Unknown",
			playlistName = "SAD PLAYLIST",
			parts = { "rbxassetid://132216748532588" },
		},
		{
			name = "Gala bunga-Tak Sll Memiliki-Shbt Dulu",
			creator = "Unknown",
			playlistName = "SAD PLAYLIST",
			parts = { "rbxassetid://114740146443045" },
		},
		{
			name = "Runtuh-kembali pulang-Dance WMe",
			creator = "Unknown",
			playlistName = "SAD PLAYLIST",
			parts = { "rbxassetid://125290849042794" },
		},
		{
			name = "SAD - 01",
			creator = "Unknown",
			playlistName = "SAD PLAYLIST",
			parts = { "rbxassetid://127571217150913" },
		},
		{
			name = "SAD - 02",
			creator = "Unknown",
			playlistName = "SAD PLAYLIST",
			parts = { "rbxassetid://82255159675259" },
		},
		{
			name = "SAD - 03",
			creator = "Unknown",
			playlistName = "SAD PLAYLIST",
			parts = { "rbxassetid://115097860720592" },
		},
		{
			name = "SAD - 04",
			creator = "Unknown",
			playlistName = "SAD PLAYLIST",
			parts = { "rbxassetid://113959817509221" },
		},
		{
			name = "SAD - 05",
			creator = "Unknown",
			playlistName = "SAD PLAYLIST",
			parts = { "rbxassetid://90608036640566" },
		},
		{
			name = "SAD - 06",
			creator = "Unknown",
			playlistName = "SAD PLAYLIST",
			parts = { "rbxassetid://93611960870847" },
		},
		{
			name = "SAD - 07",
			creator = "Unknown",
			playlistName = "SAD PLAYLIST",
			parts = { "rbxassetid://113893088623669" },
		},
		{
			name = "SAD - 08",
			creator = "Unknown",
			playlistName = "SAD PLAYLIST",
			parts = { "rbxassetid://98275401496616" },
		},
		{
			name = "SAD - 09",
			creator = "Unknown",
			playlistName = "SAD PLAYLIST",
			parts = { "rbxassetid://131809572214330" },
		},
		{
			name = "SAD - 10",
			creator = "Unknown",
			playlistName = "SAD PLAYLIST",
			parts = { "rbxassetid://82870800941987" },
		},
		{
			name = "Sal Priadi - Mencintaimu",
			creator = "Unknown",
			playlistName = "IKOK REQ",
			parts = { "rbxassetid://132853873182991" },
		},
		{
			name = "Ada titik-titik di ujung doa - Sal Priad",
			creator = "Unknown",
			playlistName = "IKOK REQ",
			parts = { "rbxassetid://98112707961349" },
		},
		{
			name = "Firasat - Marcell",
			creator = "Unknown",
			playlistName = "IKOK REQ",
			parts = { "rbxassetid://71042309337335" },
		},
		{
			name = "Sandiwara semu - D Ujung Jalan - Tapi Tahukah Kamu",
			creator = "Unknown",
			playlistName = "IKOK REQ",
			parts = { "rbxassetid://98915891817339" },
		},
		{
			name = "Virgou Selamat-Kesedihanku-Bahagia Lagi",
			creator = "Unknown",
			playlistName = "IKOK REQ",
			parts = { "rbxassetid://75260824005866" },
		},
		{
			name = "Siti Nurhaliza Cindai -Laksamana Raja",
			creator = "Unknown",
			playlistName = "IKOK REQ",
			parts = { "rbxassetid://130557598125592" },
		},
		{
			name = "AMAPIANO 01",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://87891634204092" },
		},
		{
			name = "AMAPIANO 02",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://137271831883881" },
		},
		{
			name = "OPENING GO",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://85843138393081" },
		},
		{
			name = "GO - 01",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://105868972310187" },
		},
		{
			name = "GO - 02",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://81064655499630" },
		},
		{
			name = "GO - 03",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://108386325043753" },
		},
		{
			name = "NENSHIN - 01",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://109821069411968" },
		},
		{
			name = "NENSHIN - 02",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://133142959645215" },
		},
		{
			name = "NENSHIN - 03",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://100275714657610" },
		},
		{
			name = "NENSHIN - 04",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://76894660473432" },
		},
		{
			name = "SOCI BAILE - 01",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://129222470793693" },
		},
		{
			name = "SOCI BAILE - 02",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://113375710791495" },
		},
		{
			name = "SOCI BAILE - 03",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://88930773001935" },
		},
		{
			name = "SMOOTH - 01",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://112822790602709" },
		},
		{
			name = "SMOOTH - 02",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://114163840181400" },
		},
		{
			name = "SMOOTH - 03",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://115188266058867" },
		},
		{
			name = "SMOOTH - 04",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://110899271153357" },
		},
		{
			name = "SMOOTH - 05",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://99732460170028" },
		},
		{
			name = "SMOOTH - 06",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://135209871313586" },
		},
		{
			name = "IDB X - 01",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://99156766998265" },
		},
		{
			name = "IDB X - 02",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://131696385415837" },
		},
		{
			name = "IDB X - 03",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://92966144631012" },
		},
		{
			name = "IDB X - 04",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://120764558637483" },
		},
		{
			name = "HIPHOP - 01",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://71798689403807" },
		},
		{
			name = "HIPHOP - 02",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://130101482767002" },
		},
		{
			name = "POP X - 01",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://89608244623873" },
		},
		{
			name = "POP X - 02",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://123693826982962" },
		},
		{
			name = "POP X - 03",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://110604269097290" },
		},
		{
			name = "POP X - 04",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://101114934768971" },
		},
		{
			name = "POP X - 05",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://134576985206004" },
		},
		{
			name = "HIP DANCE - 01",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://115170420165282" },
		},
		{
			name = "HIP DANCE - 02",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://112629203929705" },
		},
		{
			name = "HIP POP - 01",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://124732913540797" },
		},
		{
			name = "HIP POP - 02",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://111130481525459" },
		},
		{
			name = "HIP RNB - 01",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://119423339775965" },
		},
		{
			name = "HIP RNB - 02",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://89501044548302" },
		},
		{
			name = "HIP RNB - 03",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://72764514743517" },
		},
		{
			name = "HIP RNB - 04",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://112604873445730" },
		},
		{
			name = "MIXTAPE - 01",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://95268354998882" },
		},
		{
			name = "MIXTAPE - 02",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://101058549443995" },
		},
		{
			name = "MIXTAPE - 03",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://94710314017697" },
		},
		{
			name = "MIXTAPE - 04",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://131905255689169" },
		},
		{
			name = "MIXTAPE - 05",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://109912030580774" },
		},
		{
			name = "MIXTAPE - 06",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://116810101071363" },
		},
		{
			name = "SHAWT - 01",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://88633822284501" },
		},
		{
			name = "SHAWT - 02",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://84780868733381" },
		},
		{
			name = "SHAWT - 03",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://84191522929427" },
		},
		{
			name = "SHAWT - 04",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://133162419798847" },
		},
		{
			name = "SHAWT - 05",
			creator = "PAWWHO",
			playlistName = "GO PAW",
			parts = { "rbxassetid://90963463102528" },
		},
		{
			name = "CHINESE 01",
			creator = "PAWWHO",
			playlistName = "CNY PAW",
			parts = { "rbxassetid://133694273509671" },
		},
		{
			name = "CHINESE 02",
			creator = "PAWWHO",
			playlistName = "CNY PAW",
			parts = { "rbxassetid://84725645651375" },
		},
		{
			name = "CHINESE 03",
			creator = "PAWWHO",
			playlistName = "CNY PAW",
			parts = { "rbxassetid://130655428676186" },
		},
		{
			name = "CHINESE 04",
			creator = "PAWWHO",
			playlistName = "CNY PAW",
			parts = { "rbxassetid://76613108780239" },
		},
		{
			name = "CHINESE 05",
			creator = "PAWWHO",
			playlistName = "CNY PAW",
			parts = { "rbxassetid://136848744273375" },
		},
		{
			name = "CHINESE 06",
			creator = "PAWWHO",
			playlistName = "CNY PAW",
			parts = { "rbxassetid://127587019305114" },
		},
		{
			name = "CHINESE 07",
			creator = "PAWWHO",
			playlistName = "CNY PAW",
			parts = { "rbxassetid://122923486151566" },
		},
		{
			name = "CHEF - JERSEY BAILE BASS SET 1A",
			creator = "PAWWHO",
			playlistName = "CHEF",
			parts = { "rbxassetid://83642398616066" },
		},
		{
			name = "CHEF - JERSEY BAILE BASS SET 2A",
			creator = "PAWWHO",
			playlistName = "CHEF",
			parts = { "rbxassetid://86167953108468" },
		},
		{
			name = "CHEF - JERSEY BAILE BASS SET 3A",
			creator = "PAWWHO",
			playlistName = "CHEF",
			parts = { "rbxassetid://104108137787492" },
		},
		{
			name = "CHEF - JERSEY BAILE BASS SET 4",
			creator = "PAWWHO",
			playlistName = "CHEF",
			parts = { "rbxassetid://88041988117416" },
		},
		{
			name = "CHEF - PARTY HYPE MIX A",
			creator = "PAWWHO",
			playlistName = "CHEF",
			parts = { "rbxassetid://111716594600092" },
		},
		{
			name = "CHEF - PARTY HYPE MIX B",
			creator = "PAWWHO",
			playlistName = "CHEF",
			parts = { "rbxassetid://136837823078011" },
		},
		{
			name = "CHEF - PARTY HYPE MIX C",
			creator = "PAWWHO",
			playlistName = "CHEF",
			parts = { "rbxassetid://82830326136845" },
		},
		{
			name = "CHEF - PARTY HYPE MIX D",
			creator = "PAWWHO",
			playlistName = "CHEF",
			parts = { "rbxassetid://129981655509625" },
		},
		{
			name = "GENZ V2 - 1",
			creator = "PAWWHO",
			playlistName = "CHEF",
			parts = { "rbxassetid://97115057548605" },
		},
		{
			name = "GENZ V2 - 2",
			creator = "PAWWHO",
			playlistName = "CHEF",
			parts = { "rbxassetid://100969230857659" },
		},
		{
			name = "GENZ V2 - 3",
			creator = "PAWWHO",
			playlistName = "CHEF",
			parts = { "rbxassetid://135256403264233" },
		},
		{
			name = "GENZ V2 - 4",
			creator = "PAWWHO",
			playlistName = "CHEF",
			parts = { "rbxassetid://126413055980742" },
		},
		{
			name = "GENZ V3 - 1",
			creator = "PAWWHO",
			playlistName = "CHEF",
			parts = { "rbxassetid://110044063790768" },
		},
		{
			name = "GENZ V3 - 2",
			creator = "PAWWHO",
			playlistName = "CHEF",
			parts = { "rbxassetid://93650419056099" },
		},
		{
			name = "GENZ V3 - 3",
			creator = "PAWWHO",
			playlistName = "CHEF",
			parts = { "rbxassetid://120195356293422" },
		},
		{
			name = "GENZ V3 - 4",
			creator = "PAWWHO",
			playlistName = "CHEF",
			parts = { "rbxassetid://86858695998793" },
		},
		{
			name = "HIP BAILE - 01",
			creator = "PAWWHO",
			playlistName = "CHEF",
			parts = { "rbxassetid://138956368560507" },
		},
		{
			name = "HIP BAILE - 02",
			creator = "PAWWHO",
			playlistName = "CHEF",
			parts = { "rbxassetid://122633203386236" },
		},
		{
			name = "HIP BAILE - 03",
			creator = "PAWWHO",
			playlistName = "CHEF",
			parts = { "rbxassetid://131368228122181" },
		},
		{
			name = "HIP BAILE - 04",
			creator = "PAWWHO",
			playlistName = "CHEF",
			parts = { "rbxassetid://73256531629232" },
		},
		{
			name = "HIP BAILE - 05",
			creator = "PAWWHO",
			playlistName = "CHEF",
			parts = { "rbxassetid://112713722798134" },
		},
		{
			name = "HIP BAILE - 06",
			creator = "PAWWHO",
			playlistName = "CHEF",
			parts = { "rbxassetid://130090601262346" },
		},
		{
			name = "PAW MIX HIPHOP POP - 01",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://131932347779384" },
		},
		{
			name = "PAW MIX HIPHOP POP - 02",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://93660593558582" },
		},
		{
			name = "PAW MIX HIPHOP POP - 03",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://84129183197022" },
		},
		{
			name = "PAW MIX HIPHOP POP - 04",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://122938843104415" },
		},
		{
			name = "PAW MIX HIPHOP POP - 05",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://113422852596471" },
		},
		{
			name = "PAW MIX HIPHOP TRAP B - 01",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://108925540327913" },
		},
		{
			name = "PAW MIX HIPHOP TRAP B - 02",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://93848083497956" },
		},
		{
			name = "PAW MIX HIPHOP TRAP B - 03",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://77419798144679" },
		},
		{
			name = "PAW MIX HIPHOP TRAP B - 04",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://91350921009448" },
		},
		{
			name = "PAW - 01",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://121400165012142" },
		},
		{
			name = "PAW - 02",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://119333364168132" },
		},
		{
			name = "PAW - 03",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://86605068236501" },
		},
		{
			name = "PAW - 04",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://91317743641632" },
		},
		{
			name = "PAW - 05",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://92693049053888" },
		},
		{
			name = "PAW - 06",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://97204148114909" },
		},
		{
			name = "PACKAGE 1",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://118399712162798" },
		},
		{
			name = "PACKAGE 2",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://129921225917496" },
		},
		{
			name = "PACKAGE 3",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://75017340535017" },
		},
		{
			name = "PACKAGE 4",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://79567306451613" },
		},
		{
			name = "PACKAGE 5",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://130260178705696" },
		},
		{
			name = "Bounce H - 01",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://71622181024510" },
		},
		{
			name = "Bounce H - 02",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://115073608543235" },
		},
		{
			name = "Bounce H - 03",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://118218718578688" },
		},
		{
			name = "Bounce H - 04",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://107196193395084" },
		},
		{
			name = "DANCE - 01",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://74837628655784" },
		},
		{
			name = "DANCE - 02",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://118233263927268" },
		},
		{
			name = "XOAN - 01",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://107059739450818" },
		},
		{
			name = "XOAN - 02",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://80668165153575" },
		},
		{
			name = "XOAN - 03",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://78413252827794" },
		},
		{
			name = "XOAN - 04",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://139271910064058" },
		},
		{
			name = "XOAN - 05",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://108376174394858" },
		},
		{
			name = "XOAN - 06",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://92211457051494" },
		},
		{
			name = "HIPPOP - 01",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://86427900994334" },
		},
		{
			name = "HIPPOP - 02",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://75785242438363" },
		},
		{
			name = "HIPPOP - 03",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://92875500805983" },
		},
		{
			name = "GEN Z - 01",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://122686734315165" },
		},
		{
			name = "GEN Z MIX- 01",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://90613947229054" },
		},
		{
			name = "GEN Z MIX- 02",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://86435599657253" },
		},
		{
			name = "GEN Z MIX- 03",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://121924180718900" },
		},
		{
			name = "EDM - 01",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://74668509238621" },
		},
		{
			name = "EDM - 02",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://92972908830332" },
		},
		{
			name = "EDM - 03",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://104123885208694" },
		},
		{
			name = "EDM - 04",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://112458229515184" },
		},
		{
			name = "EDM - 05",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://86517389574513" },
		},
		{
			name = "EDM - 06",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://90272459511423" },
		},
		{
			name = "TRAP - 01",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://96866149253124" },
		},
		{
			name = "TRAP - 02",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://140288797433821" },
		},
		{
			name = "KIARA - 1",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://128015565546224" },
		},
		{
			name = "KIARA - 2",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://103789418979024" },
		},
		{
			name = "KIARA - 3",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://130759214751998" },
		},
		{
			name = "KIARA - 4",
			creator = "PAWWHO",
			playlistName = "PAW MIX",
			parts = { "rbxassetid://90255045824059" },
		},
		{
			name = "SECTOR B - B2B 01",
			creator = "PAWWHO",
			playlistName = "SECTOR B",
			parts = { "rbxassetid://121280969667561" },
		},
		{
			name = "SECTOR B - B2B 03",
			creator = "PAWWHO",
			playlistName = "SECTOR B",
			parts = { "rbxassetid://79354735077597" },
		},
		{
			name = "SECTOR B - ROBSTEE 01",
			creator = "PAWWHO",
			playlistName = "SECTOR B",
			parts = { "rbxassetid://100191052517606" },
		},
		{
			name = "SECTOR B - ROBSTEE 02",
			creator = "PAWWHO",
			playlistName = "SECTOR B",
			parts = { "rbxassetid://106245973758286" },
		},
		{
			name = "SECTOR B - ROBSTEE 03",
			creator = "PAWWHO",
			playlistName = "SECTOR B",
			parts = { "rbxassetid://129981906004388" },
		},
		{
			name = "SECTOR B - ROBSTEE 04",
			creator = "PAWWHO",
			playlistName = "SECTOR B",
			parts = { "rbxassetid://99176099070776" },
		},
		{
			name = "SECTOR B - DNA 01",
			creator = "PAWWHO",
			playlistName = "SECTOR B",
			parts = { "rbxassetid://139719285604291" },
		},
		{
			name = "SECTOR B - DNA 02",
			creator = "PAWWHO",
			playlistName = "SECTOR B",
			parts = { "rbxassetid://86690848572706" },
		},
		{
			name = "SECTOR B - DNA 03",
			creator = "PAWWHO",
			playlistName = "SECTOR B",
			parts = { "rbxassetid://124985830252662" },
		},
		{
			name = "SECTOR B - DNA 04",
			creator = "PAWWHO",
			playlistName = "SECTOR B",
			parts = { "rbxassetid://106511081072026" },
		},
		{
			name = "SECTOR B - DNA 05",
			creator = "PAWWHO",
			playlistName = "SECTOR B",
			parts = { "rbxassetid://87580498164681" },
		},
		{
			name = "SECTOR B - B2B 02",
			creator = "PAWWHO",
			playlistName = "SECTOR B",
			parts = { "rbxassetid://121538506430273" },
		},
		{
			name = "HIP POP - 01",
			creator = "PAWWHO",
			playlistName = "HIPPOP REMIX",
			parts = { "rbxassetid://109551061189295" },
		},
		{
			name = "HIP POP - 02",
			creator = "PAWWHO",
			playlistName = "HIPPOP REMIX",
			parts = { "rbxassetid://113775820465439" },
		},
		{
			name = "HIP POP - 03",
			creator = "PAWWHO",
			playlistName = "HIPPOP REMIX",
			parts = { "rbxassetid://130636879834914" },
		},
		{
			name = "HIP POP - 04",
			creator = "PAWWHO",
			playlistName = "HIPPOP REMIX",
			parts = { "rbxassetid://84626856927289" },
		},
		{
			name = "HIP POP - 05",
			creator = "PAWWHO",
			playlistName = "HIPPOP REMIX",
			parts = { "rbxassetid://91959561797432" },
		},
		{
			name = "HIP BANGER - 01",
			creator = "PAWWHO",
			playlistName = "HIPPOP REMIX",
			parts = { "rbxassetid://131862449230790" },
		},
		{
			name = "HIP BANGER - 02",
			creator = "PAWWHO",
			playlistName = "HIPPOP REMIX",
			parts = { "rbxassetid://88077786618202" },
		},
		{
			name = "HIP BANGER - 03",
			creator = "PAWWHO",
			playlistName = "HIPPOP REMIX",
			parts = { "rbxassetid://109895180885969" },
		},
		{
			name = "ANIME MIX - 01",
			creator = "PAWWHO",
			playlistName = "ANIME EDM",
			parts = { "rbxassetid://91914343358826" },
		},
		{
			name = "ANIME MIX - 02",
			creator = "PAWWHO",
			playlistName = "ANIME EDM",
			parts = { "rbxassetid://136835719508404" },
		},
		{
			name = "ANIME MIX - 03",
			creator = "PAWWHO",
			playlistName = "ANIME EDM",
			parts = { "rbxassetid://81358904806271" },
		},
		{
			name = "ANIME MIX - 04",
			creator = "PAWWHO",
			playlistName = "ANIME EDM",
			parts = { "rbxassetid://109631342844042" },
		},
		{
			name = "ANIME MIXT - 01",
			creator = "PAWWHO",
			playlistName = "ANIME EDM",
			parts = { "rbxassetid://84904300053078" },
		},
		{
			name = "ANIME MIXT - 02",
			creator = "PAWWHO",
			playlistName = "ANIME EDM",
			parts = { "rbxassetid://85507244624658" },
		},
		{
			name = "ANIME MIXT - 03",
			creator = "PAWWHO",
			playlistName = "ANIME EDM",
			parts = { "rbxassetid://136658418890203" },
		},
		{
			name = "ANIME MIXT - 04",
			creator = "PAWWHO",
			playlistName = "ANIME EDM",
			parts = { "rbxassetid://117632491427699" },
		},
		{
			name = "NYX 01",
			creator = "PAWWHO",
			playlistName = "NYX PLAYLIST",
			parts = { "rbxassetid://140714528066113" },
		},
		{
			name = "NYX 02",
			creator = "PAWWHO",
			playlistName = "NYX PLAYLIST",
			parts = { "rbxassetid://90675213599937" },
		},
		{
			name = "NYX 03",
			creator = "PAWWHO",
			playlistName = "NYX PLAYLIST",
			parts = { "rbxassetid://124864383413098" },
		},
		{
			name = "NYX 04",
			creator = "PAWWHO",
			playlistName = "NYX PLAYLIST",
			parts = { "rbxassetid://70498532378498" },
		},
		{
			name = "NYX 05",
			creator = "PAWWHO",
			playlistName = "NYX PLAYLIST",
			parts = { "rbxassetid://85836790369289" },
		},
		{
			name = "LANY PLAYLIST",
			creator = "PAWWHO",
			playlistName = "POP LUAR",
			parts = { "rbxassetid://136167426171120" },
		},
		{
			name = "POST MALONE PLAYLIST",
			creator = "PAWWHO",
			playlistName = "POP LUAR",
			parts = { "rbxassetid://140545336142185" },
		},
		{
			name = "JUSTIN BIEBER PLAYLIST",
			creator = "PAWWHO",
			playlistName = "POP LUAR",
			parts = { "rbxassetid://116350652866888" },
		},
		{
			name = "BRUNO MARS 01",
			creator = "PAWWHO",
			playlistName = "POP LUAR",
			parts = { "rbxassetid://103564065857673" },
		},
		{
			name = "BRUNO MARS 02",
			creator = "PAWWHO",
			playlistName = "POP LUAR",
			parts = { "rbxassetid://120372744407925" },
		},
		{
			name = "2000s 01",
			creator = "PAWWHO",
			playlistName = "POP LUAR",
			parts = { "rbxassetid://117506563527359" },
		},
		{
			name = "2000s 02",
			creator = "PAWWHO",
			playlistName = "POP LUAR",
			parts = { "rbxassetid://125381993282812" },
		},
		{
			name = "JB MIX - 01",
			creator = "PAWWHO",
			playlistName = "POP LUAR",
			parts = { "rbxassetid://130714068337535" },
		},
		{
			name = "B MIX - 02",
			creator = "PAWWHO",
			playlistName = "POP LUAR",
			parts = { "rbxassetid://86559011695923" },
		},
		{
			name = "BRUNO MIX",
			creator = "PAWWHO",
			playlistName = "POP LUAR",
			parts = { "rbxassetid://86847974415304" },
		},
		{
			name = "JB MIXTAPE 1",
			creator = "PAWWHO",
			playlistName = "POP LUAR",
			parts = { "rbxassetid://140474502351911" },
		},
		{
			name = "JB MIXTAPE 2",
			creator = "PAWWHO",
			playlistName = "POP LUAR",
			parts = { "rbxassetid://127184246882567" },
		},
		{
			name = "JB MIXTAPE 3",
			creator = "PAWWHO",
			playlistName = "POP LUAR",
			parts = { "rbxassetid://105174738530191" },
		},
		{
			name = "JB MIXTAPE 4",
			creator = "PAWWHO",
			playlistName = "POP LUAR",
			parts = { "rbxassetid://126967586899529" },
		},
		{
			name = "BRUNO MXTAPE 1",
			creator = "PAWWHO",
			playlistName = "POP LUAR",
			parts = { "rbxassetid://107965479361362" },
		},
		{
			name = "BRUNO MXTAPE 2",
			creator = "PAWWHO",
			playlistName = "POP LUAR",
			parts = { "rbxassetid://104939386447026" },
		},
		{
			name = "MIXTAPE POP INDO - 1",
			creator = "PAWWHO",
			playlistName = "POP LUAR",
			parts = { "rbxassetid://128974433957013" },
		},
		{
			name = "MIXTAPE POP INDO - 2",
			creator = "PAWWHO",
			playlistName = "POP LUAR",
			parts = { "rbxassetid://112006753837233" },
		},
		{
			name = "MIXTAPE POP INDO - 3",
			creator = "PAWWHO",
			playlistName = "POP LUAR",
			parts = { "rbxassetid://99519935816911" },
		},
		{
			name = "MIXTAPE POP INDO - 4",
			creator = "PAWWHO",
			playlistName = "POP LUAR",
			parts = { "rbxassetid://114197074365012" },
		},
		{
			name = "Heartbreak Anniv-Double Take-Skyfall-DieWithASmile",
			creator = "PAWWHO",
			playlistName = "POP EDM",
			parts = { "rbxassetid://73080633602786" },
		},
		{
			name = "Beggin-Sunflower-Take Me To Church-Die For You",
			creator = "PAWWHO",
			playlistName = "POP EDM",
			parts = { "rbxassetid://88144373916205" },
		},
		{
			name = "BTB-Me and MBH-Stay-Hey Daddy",
			creator = "PAWWHO",
			playlistName = "POP EDM",
			parts = { "rbxassetid://105259185543051" },
		},
		{
			name = "BOAF-Hall Of Fame-Animals-Your Beautiful",
			creator = "PAWWHO",
			playlistName = "POP EDM",
			parts = { "rbxassetid://103938635813019" },
		},
		{
			name = "Jumping Machine-BMTL-The Nights",
			creator = "PAWWHO",
			playlistName = "POP EDM",
			parts = { "rbxassetid://127187959840332" },
		},
		{
			name = "DJ SNAKE-Lean On-Closer-All We Know-Stay",
			creator = "PAWWHO",
			playlistName = "POP EDM",
			parts = { "rbxassetid://92294527571093" },
		},
		{
			name = "Roses-Middle-Starving-Paris-Happier-LightItUp",
			creator = "PAWWHO",
			playlistName = "POP EDM",
			parts = { "rbxassetid://111883394196706" },
		},
		{
			name = "Payphone-SomethingJLT-Call Me Maybe-Treasure",
			creator = "PAWWHO",
			playlistName = "POP EDM",
			parts = { "rbxassetid://103891108435688" },
		},
		{
			name = "ICONIC 01",
			creator = "PAWWHO",
			playlistName = "ICONIC PLAYLIST",
			parts = { "rbxassetid://99290326021334" },
		},
		{
			name = "ICONIC 02",
			creator = "PAWWHO",
			playlistName = "ICONIC PLAYLIST",
			parts = { "rbxassetid://85653022686146" },
		},
		{
			name = "ICONIC 03",
			creator = "PAWWHO",
			playlistName = "ICONIC PLAYLIST",
			parts = { "rbxassetid://117967516896441" },
		},
		{
			name = "ICONIC 04",
			creator = "PAWWHO",
			playlistName = "ICONIC PLAYLIST",
			parts = { "rbxassetid://124709720510839" },
		},
		{
			name = "ICONIC 05",
			creator = "PAWWHO",
			playlistName = "ICONIC PLAYLIST",
			parts = { "rbxassetid://122361822964776" },
		},
		{
			name = "ICONIC 06",
			creator = "PAWWHO",
			playlistName = "ICONIC PLAYLIST",
			parts = { "rbxassetid://88905305584033" },
		},
		{
			name = "ICONIC 07",
			creator = "PAWWHO",
			playlistName = "ICONIC PLAYLIST",
			parts = { "rbxassetid://88859481874361" },
		},
		{
			name = "ICONIC 08",
			creator = "PAWWHO",
			playlistName = "ICONIC PLAYLIST",
			parts = { "rbxassetid://122562857796568" },
		},
		{
			name = "ICONIC 09",
			creator = "PAWWHO",
			playlistName = "ICONIC PLAYLIST",
			parts = { "rbxassetid://82918228895128" },
		},
		{
			name = "ICONIC 10",
			creator = "PAWWHO",
			playlistName = "ICONIC PLAYLIST",
			parts = { "rbxassetid://138239415866430" },
		},
		{
			name = "GO JAMES - 01",
			creator = "PAWWHO",
			playlistName = "GO JAMES",
			parts = { "rbxassetid://121877764253010" },
		},
		{
			name = "GO JAMES - 02",
			creator = "PAWWHO",
			playlistName = "GO JAMES",
			parts = { "rbxassetid://78942627651539" },
		},
		{
			name = "GO JAMES - 03",
			creator = "PAWWHO",
			playlistName = "GO JAMES",
			parts = { "rbxassetid://102935562944391" },
		},
		{
			name = "GO JAMES - 04",
			creator = "PAWWHO",
			playlistName = "GO JAMES",
			parts = { "rbxassetid://87113600160668" },
		},
		{
			name = "GO JAMES - 05",
			creator = "PAWWHO",
			playlistName = "GO JAMES",
			parts = { "rbxassetid://104298372146559" },
		},
		{
			name = "TECHNO - 01",
			creator = "PAWWHO",
			playlistName = "GO JAMES",
			parts = { "rbxassetid://83433403369297" },
		},
		{
			name = "TECHNO - 02",
			creator = "PAWWHO",
			playlistName = "GO JAMES",
			parts = { "rbxassetid://87093303390106" },
		},
		{
			name = "TECHNO - 03",
			creator = "PAWWHO",
			playlistName = "GO JAMES",
			parts = { "rbxassetid://127758438322693" },
		},
		{
			name = "TECHNO HOUSE - 01",
			creator = "PAWWHO",
			playlistName = "GO JAMES",
			parts = { "rbxassetid://77054316583229" },
		},
		{
			name = "ECHNO HOUSE - 02",
			creator = "PAWWHO",
			playlistName = "GO JAMES",
			parts = { "rbxassetid://104150488769816" },
		},
		{
			name = "JAMS HIGH - 01",
			creator = "PAWWHO",
			playlistName = "GO JAMES",
			parts = { "rbxassetid://96552356249655" },
		},
		{
			name = "JAMS HIGH - 02",
			creator = "PAWWHO",
			playlistName = "GO JAMES",
			parts = { "rbxassetid://99040610695519" },
		},
		{
			name = "JAMS HIGH - 03",
			creator = "PAWWHO",
			playlistName = "GO JAMES",
			parts = { "rbxassetid://75111024606758" },
		},
		{
			name = "Chasing Colors x Thief x Summer x Closer x PS",
			creator = "PAWWHO",
			playlistName = "JAMES PLAYLIST",
			parts = { "rbxassetid://88593066954172" },
		},
		{
			name = "IDB JAMS - 01",
			creator = "PAWWHO",
			playlistName = "JAMES PLAYLIST",
			parts = { "rbxassetid://139198543036165" },
		},
		{
			name = "IDB JAMS - 02",
			creator = "PAWWHO",
			playlistName = "JAMES PLAYLIST",
			parts = { "rbxassetid://114978549287049" },
		},
		{
			name = "IDB JAMS - 03",
			creator = "PAWWHO",
			playlistName = "JAMES PLAYLIST",
			parts = { "rbxassetid://113671860390854" },
		},
		{
			name = "IDB J - 01",
			creator = "PAWWHO",
			playlistName = "JAMES PLAYLIST",
			parts = { "rbxassetid://114195248684580" },
		},
		{
			name = "IDB J - 02",
			creator = "PAWWHO",
			playlistName = "JAMES PLAYLIST",
			parts = { "rbxassetid://108193488708045" },
		},
		{
			name = "RNB HIPHOP JAMS - 01",
			creator = "PAWWHO",
			playlistName = "JAMES PLAYLIST",
			parts = { "rbxassetid://79631668866606" },
		},
		{
			name = "RNB HIPHOP JAMS - 02",
			creator = "PAWWHO",
			playlistName = "JAMES PLAYLIST",
			parts = { "rbxassetid://137389209582387" },
		},
		{
			name = "RNB HIPHOP JAMS - 03",
			creator = "PAWWHO",
			playlistName = "JAMES PLAYLIST",
			parts = { "rbxassetid://109817620881965" },
		},
		{
			name = "RNB HIPHOP JAMS - 04",
			creator = "PAWWHO",
			playlistName = "JAMES PLAYLIST",
			parts = { "rbxassetid://108601194272398" },
		},
		{
			name = "RNB HIPHOP JAMS - 05",
			creator = "PAWWHO",
			playlistName = "JAMES PLAYLIST",
			parts = { "rbxassetid://123366677200778" },
		},
		{
			name = "RNB POP - 01",
			creator = "PAWWHO",
			playlistName = "JAMES PLAYLIST",
			parts = { "rbxassetid://130592077020666" },
		},
		{
			name = "RNB POP - 02",
			creator = "PAWWHO",
			playlistName = "JAMES PLAYLIST",
			parts = { "rbxassetid://95197472444098" },
		},
		{
			name = "RNB POP - 03",
			creator = "PAWWHO",
			playlistName = "JAMES PLAYLIST",
			parts = { "rbxassetid://102495222067016" },
		},
		{
			name = "EDM BAILE - 01",
			creator = "PAWWHO",
			playlistName = "JAMES PLAYLIST",
			parts = { "rbxassetid://119818854083162" },
		},
		{
			name = "EDM BAILE - 02",
			creator = "PAWWHO",
			playlistName = "JAMES PLAYLIST",
			parts = { "rbxassetid://110871342873234" },
		},
		{
			name = "EDM BAILE - 03",
			creator = "PAWWHO",
			playlistName = "JAMES PLAYLIST",
			parts = { "rbxassetid://138899752344528" },
		},
		{
			name = "EDM BAILE - 04",
			creator = "PAWWHO",
			playlistName = "JAMES PLAYLIST",
			parts = { "rbxassetid://94251158934765" },
		},
		{
			name = "EDM BAILE - 05",
			creator = "PAWWHO",
			playlistName = "JAMES PLAYLIST",
			parts = { "rbxassetid://132638645041950" },
		},
		{
			name = "BKB J - 01",
			creator = "PAWWHO",
			playlistName = "JAMES PLAYLIST",
			parts = { "rbxassetid://135584724948838" },
		},
		{
			name = "BKB J - 02",
			creator = "PAWWHO",
			playlistName = "JAMES PLAYLIST",
			parts = { "rbxassetid://137856937636254" },
		},
		{
			name = "RnB - 01",
			creator = "PAWWHO",
			playlistName = "RNB",
			parts = { "rbxassetid://80110478033486" },
		},
		{
			name = "RnB - 02",
			creator = "PAWWHO",
			playlistName = "RNB",
			parts = { "rbxassetid://114863975922747" },
		},
		{
			name = "RnB INDO - 01",
			creator = "PAWWHO",
			playlistName = "RNB",
			parts = { "rbxassetid://114551208161867" },
		},
		{
			name = "RnB INDO - 02",
			creator = "PAWWHO",
			playlistName = "RNB",
			parts = { "rbxassetid://75227824736229" },
		},
		{
			name = "RnB Night - 01",
			creator = "PAWWHO",
			playlistName = "RNB",
			parts = { "rbxassetid://115993822736978" },
		},
		{
			name = "RnB Night - 02",
			creator = "PAWWHO",
			playlistName = "RNB",
			parts = { "rbxassetid://130720578754721" },
		},
		{
			name = "RnB Night - 03",
			creator = "PAWWHO",
			playlistName = "RNB",
			parts = { "rbxassetid://72355900784464" },
		},
		{
			name = "RnB indo X",
			creator = "PAWWHO",
			playlistName = "RNB",
			parts = { "rbxassetid://128064290174311" },
		},
		{
			name = "RnB indo X2",
			creator = "PAWWHO",
			playlistName = "RNB",
			parts = { "rbxassetid://97265721800039" },
		},
		{
			name = "RnB indo X3",
			creator = "PAWWHO",
			playlistName = "RNB",
			parts = { "rbxassetid://118576921627363" },
		},
		{
			name = "RnB indo X4",
			creator = "PAWWHO",
			playlistName = "RNB",
			parts = { "rbxassetid://105739255266194" },
		},
		{
			name = "HIPHOP x RnB 01x",
			creator = "PAWWHO",
			playlistName = "RNB",
			parts = { "rbxassetid://117144665787031" },
		},
		{
			name = "HIPHOP x RnB 02x",
			creator = "PAWWHO",
			playlistName = "RNB",
			parts = { "rbxassetid://123159710530164" },
		},
		{
			name = "HIPHOP x RnB 03x",
			creator = "PAWWHO",
			playlistName = "RNB",
			parts = { "rbxassetid://102718586939172" },
		},
		{
			name = "HIPHOP x RnB 04x",
			creator = "PAWWHO",
			playlistName = "RNB",
			parts = { "rbxassetid://92199791496065" },
		},
		{
			name = "HIPHOP x RnB 05x",
			creator = "PAWWHO",
			playlistName = "RNB",
			parts = { "rbxassetid://73860247068335" },
		},
		{
			name = "RnB HIPHOP - 01",
			creator = "PAWWHO",
			playlistName = "RNB",
			parts = { "rbxassetid://123147803157179" },
		},
		{
			name = "RnB HIPHOP - 02",
			creator = "PAWWHO",
			playlistName = "RNB",
			parts = { "rbxassetid://114603078735039" },
		},
		{
			name = "RnB - 03",
			creator = "PAWWHO",
			playlistName = "RNB",
			parts = { "rbxassetid://85100603709478" },
		},
	},
}

-- ============================================================
-- LOGGING
-- ============================================================

local LOG_PREFIX = "[MusicMigration]"
local stats = {
	playlistsAdded = 0,
	playlistsSkipped = 0,
	tracksAdded = 0,
	tracksSkipped = 0,
	errors = 0,
}

local function info(msg: string, ...)
	print(LOG_PREFIX, string.format(msg, ...))
end

local function warnLog(msg: string, ...)
	warn(LOG_PREFIX, string.format(msg, ...))
	stats.errors += 1
end

-- ============================================================
-- HELPERS
-- ============================================================

local function generateId(): string
	return HttpService:GenerateGUID(false)
end

local function nowSeconds(): number
	return os.time()
end

local function nowIso(): string
	return os.date("!%Y-%m-%dT%H:%M:%SZ") :: string
end

-- Normalize asset ID ke format ANGKA MENTAH (raw digits), e.g. "139198543036165".
-- PENTING: kit (MusicPlayerController) nambahin prefix "rbxassetid://" sendiri
-- saat bikin Sound.SoundId. Jadi parts di DataStore HARUS angka mentah, BUKAN
-- ber-prefix. Kalau ber-prefix, hasilnya dobel ("rbxassetid://rbxassetid://...")
-- dan asset gagal load (HTTP 404).
-- Accept: "rbxassetid://123", "123", 123, "rbx://123", "rbxasset://123".
local function normalizeAssetId(raw: any): string?
	if raw == nil then return nil end
	local s = tostring(raw):gsub("%s", "")
	if s == "" then return nil end

	-- Strip common prefixes (bisa muncul berkali-kali kalau data udah korup)
	s = s:gsub("rbxassetid://", "")
	s = s:gsub("rbxasset://", "")
	s = s:gsub("rbx://", "")
	s = s:gsub("^https?://www%.roblox%.com/asset/%?id=", "")
	s = s:gsub("^https?://www%.roblox%.com/library/", "")

	-- Take leading digits only
	local digits = s:match("^(%d+)")
	if not digits or digits == "" then
		return nil
	end
	return digits
end

local function trim(s: string): string
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function isNonEmptyString(v: any): boolean
	return type(v) == "string" and trim(v) ~= ""
end

-- Parse playback speed dari berbagai format.
-- "2.3", "2.3x", " 0.85 ", 1.25 → number
-- Empty/invalid → nil
local function parsePlaybackSpeed(raw: any): number?
	if raw == nil then return nil end
	if type(raw) == "number" then
		if raw > 0 then return raw end
		return nil
	end
	local s = tostring(raw):gsub("[xX%s]", "")
	if s == "" then return nil end
	local n = tonumber(s)
	if n and n > 0 then return n end
	return nil
end

-- ============================================================
-- MAPPERS
-- ============================================================

local function mapPlaylist(source: { [string]: any }): { [string]: any }?
	if not source then return nil end
	local name = source.name or source.playlistName or source.title
	if not isNonEmptyString(name) then
		warnLog("Playlist tanpa name di-skip: %s", HttpService:JSONEncode(source))
		return nil
	end

	return {
		id = (isNonEmptyString(source.id) and source.id) or generateId(),
		name = trim(name),
		coverType = (isNonEmptyString(source.coverType) and source.coverType) or "gradient",
		coverValue = source.coverValue or 1,
		fontFace = (isNonEmptyString(source.fontFace) and source.fontFace) or "Original",
		trackIds = {},
		syncUpdatedAt = nowIso(),
		syncRevision = 1,
		syncSource = MIGRATION_TAG,
	}
end

local function mapTrackParts(source: { [string]: any }): { string }
	local rawParts = source.parts or source.assetIds or source.audioIds or source.audios
	local parts: { string } = {}

	if type(rawParts) == "table" then
		for i, v in ipairs(rawParts) do
			if i > MAX_TRACK_PARTS then
				warnLog("Track '%s' has >%d parts, truncated", tostring(source.name), MAX_TRACK_PARTS)
				break
			end
			local norm = normalizeAssetId(v)
			if norm then
				table.insert(parts, norm)
			end
		end
	elseif rawParts ~= nil then
		-- single value fallback
		local norm = normalizeAssetId(rawParts)
		if norm then table.insert(parts, norm) end
	end

	-- Also support flat fields: assetId1..9, partA..partI, etc.
	if #parts == 0 then
		for i = 1, MAX_TRACK_PARTS do
			local v = source["assetId" .. i] or source["part" .. i] or source["audioId" .. i]
			local norm = normalizeAssetId(v)
			if norm then table.insert(parts, norm) end
		end
	end

	return parts
end

local function mapTrack(source: { [string]: any }, playlistId: string): { [string]: any }?
	if not source then return nil end
	if not isNonEmptyString(source.name) then
		warnLog("Track tanpa name di-skip: %s", HttpService:JSONEncode(source))
		return nil
	end

	local parts = mapTrackParts(source)
	if #parts == 0 then
		warnLog("Track '%s' gak punya audio asset valid, di-skip", tostring(source.name))
		return nil
	end

	local creator = source.creator or source.artist or source.author or "Unknown"
	local speed = parsePlaybackSpeed(source.playbackSpeed)
		or parsePlaybackSpeed(source.normalPlaybackSpeed)
		or parsePlaybackSpeed(source.speed)

	local now = nowSeconds()
	return {
		id = (isNonEmptyString(source.id) and source.id) or generateId(),
		name = trim(source.name),
		creator = trim(tostring(creator)),
		playlistId = playlistId,
		parts = parts,
		totalDuration = tonumber(source.totalDuration) or 0,
		playbackSpeed = speed,
		createdAt = tonumber(source.createdAt) or now,
		updatedAt = tonumber(source.updatedAt) or now,
		syncUpdatedAt = nowIso(),
		syncRevision = 1,
		syncSource = MIGRATION_TAG,
	}
end

-- ============================================================
-- DATASTORE I/O
-- ============================================================

local function jsonDecode(s: string): (boolean, any)
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(s)
	end)
	return ok, decoded
end

local function jsonEncode(t: any): (boolean, string)
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(t)
	end)
	return ok, encoded
end

local function getStoreOrNil(): any?
	if not RunService:IsServer() then
		warnLog("DataStore butuh server context. Run dari Play Mode (F5), bukan client.")
		return nil
	end
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	if not ok or not store then
		warnLog("GetDataStore failed: %s", tostring(store))
		return nil
	end
	return store
end

local function loadKey(store: any, key: string): { [string]: any }
	local ok, raw = pcall(function()
		return store:GetAsync(key)
	end)
	if not ok then
		warnLog("GetAsync(%s) failed: %s", key, tostring(raw))
		return {}
	end
	if raw == nil then
		return {}
	end
	if type(raw) == "string" then
		local decodeOk, decoded = jsonDecode(raw)
		if not decodeOk or type(decoded) ~= "table" then
			warnLog("JSONDecode failed for key %s", key)
			return {}
		end
		return decoded
	end
	if type(raw) == "table" then
		return raw
	end
	return {}
end

local function saveKey(store: any, key: string, data: any): boolean
	local encodeOk, encoded = jsonEncode(data)
	if not encodeOk then
		warnLog("JSONEncode failed for key %s: %s", key, tostring(encoded))
		return false
	end
	local ok, err = pcall(function()
		store:UpdateAsync(key, function()
			return encoded
		end)
	end)
	if not ok then
		warnLog("UpdateAsync(%s) failed: %s", key, tostring(err))
		return false
	end
	return true
end

-- ============================================================
-- PROCESSOR
-- ============================================================

local function buildPlaylistMap(existing: { [string]: any }, source: { [string]: any }): {
	byId: { [string]: { [string]: any } },
	byName: { [string]: string }, -- name(lowercase) → id
}
	local byId: { [string]: { [string]: any } } = {}
	local byName: { [string]: string } = {}

	for id, p in pairs(existing) do
		if type(p) == "table" and not p.syncDeletedAt then
			byId[id] = p
			if type(p.name) == "string" then
				byName[p.name:lower()] = id
			end
		end
	end

	local sourcePlaylists = source.playlists
	if type(sourcePlaylists) == "table" then
		for _, sp in ipairs(sourcePlaylists) do
			local mapped = mapPlaylist(sp)
			if mapped then
				local nameKey = (mapped.name :: string):lower()
				local existingId = byName[nameKey]
				if existingId then
					info("Playlist '%s' udah ada (id=%s), skip create.", mapped.name, existingId)
					stats.playlistsSkipped += 1
				else
					byId[mapped.id] = mapped
					byName[nameKey] = mapped.id
					stats.playlistsAdded += 1
					info("Playlist baru: %s (id=%s)", mapped.name, mapped.id)
				end
			end
		end
	end

	return { byId = byId, byName = byName }
end

local function ensureDefaultPlaylist(playlistMap: any): string
	local nameKey = DEFAULT_PLAYLIST_NAME:lower()
	local id = playlistMap.byName[nameKey]
	if id then return id end

	local newPlaylist = mapPlaylist({ name = DEFAULT_PLAYLIST_NAME })
	assert(newPlaylist, "failed to build default playlist")
	playlistMap.byId[newPlaylist.id] = newPlaylist
	playlistMap.byName[nameKey] = newPlaylist.id
	stats.playlistsAdded += 1
	info("Auto-create default playlist: %s (id=%s)", DEFAULT_PLAYLIST_NAME, newPlaylist.id)
	return newPlaylist.id
end

local function resolvePlaylistId(source: { [string]: any }, playlistMap: any): string
	if isNonEmptyString(source.playlistId) and playlistMap.byId[source.playlistId] then
		return source.playlistId
	end
	if isNonEmptyString(source.playlistName) then
		local byName = playlistMap.byName[(source.playlistName :: string):lower()]
		if byName then return byName end
		-- Auto-create kalau referensi playlist baru
		local newP = mapPlaylist({ name = source.playlistName })
		if newP then
			playlistMap.byId[newP.id] = newP
			playlistMap.byName[(newP.name :: string):lower()] = newP.id
			stats.playlistsAdded += 1
			info("Auto-create playlist dari track ref: %s (id=%s)", newP.name, newP.id)
			return newP.id
		end
	end
	return ensureDefaultPlaylist(playlistMap)
end

local function processTracks(
	existingTracks: { [string]: any },
	source: { [string]: any },
	playlistMap: any
): { [string]: any }
	local nextTracks: { [string]: any } = {}
	local existingByName: { [string]: { string } } = {}

	for id, t in pairs(existingTracks) do
		if type(t) == "table" and not t.syncDeletedAt then
			nextTracks[id] = t
			if type(t.name) == "string" and type(t.creator) == "string" then
				local key = (t.name:lower() .. "|" .. t.creator:lower())
				existingByName[key] = existingByName[key] or {}
				table.insert(existingByName[key], id)
			end
		end
	end

	local sourceTracks = source.tracks
	if type(sourceTracks) ~= "table" then
		warnLog("SOURCE_DATA.tracks bukan array, gak ada track yang di-import.")
		return nextTracks
	end

	for _, st in ipairs(sourceTracks) do
		local playlistId = resolvePlaylistId(st, playlistMap)
		local mapped = mapTrack(st, playlistId)
		if mapped then
			local dedupeKey = ((mapped.name :: string):lower() .. "|" .. (mapped.creator :: string):lower())
			if existingByName[dedupeKey] then
				info("Track '%s' by '%s' udah ada, skip.", mapped.name, mapped.creator)
				stats.tracksSkipped += 1
			else
				nextTracks[mapped.id] = mapped
				stats.tracksAdded += 1
				local speedNote = mapped.playbackSpeed and (" speed=" .. tostring(mapped.playbackSpeed)) or ""
				info("Track baru: '%s' by '%s' (%d parts%s)", mapped.name, mapped.creator, #(mapped.parts :: { string }), speedNote)
			end
		end
	end

	return nextTracks
end

local function rebuildPlaylistTrackIds(
	playlists: { [string]: any },
	tracks: { [string]: any }
)
	-- Reset trackIds buat playlist yang di-touch migrasi (syncSource = MIGRATION_TAG)
	-- atau yang baru ditambah. Existing playlists yang gak di-touch, biarin.
	local touchedPlaylists: { [string]: boolean } = {}
	for id, p in pairs(playlists) do
		if p.syncSource == MIGRATION_TAG then
			p.trackIds = {}
			touchedPlaylists[id] = true
		end
	end

	for _, t in pairs(tracks) do
		if t.syncSource == MIGRATION_TAG and t.playlistId and playlists[t.playlistId] then
			local target = playlists[t.playlistId]
			target.trackIds = target.trackIds or {}
			if touchedPlaylists[t.playlistId] then
				table.insert(target.trackIds, t.id)
			else
				-- Existing playlist, append kalau belum ada
				local exists = false
				for _, tid in ipairs(target.trackIds) do
					if tid == t.id then exists = true; break end
				end
				if not exists then
					table.insert(target.trackIds, t.id)
				end
			end
		end
	end
end

-- ============================================================
-- MAIN
-- ============================================================

local function main()
	info("=== START === mode=%s strategy=%s", MODE, STRATEGY)

	if MODE ~= "dry_run" and MODE ~= "commit" then
		warnLog("MODE invalid (%s). Harus 'dry_run' atau 'commit'. Abort.", MODE)
		return
	end
	if STRATEGY ~= "merge" and STRATEGY ~= "replace" then
		warnLog("STRATEGY invalid (%s). Harus 'merge' atau 'replace'. Abort.", STRATEGY)
		return
	end
	if STRATEGY == "replace" and MODE == "commit" then
		warn(LOG_PREFIX, "⚠️  STRATEGY='replace' + MODE='commit' bakal WIPE existing DataStore. Lanjut dalam 5 detik...")
		task.wait(5)
	end

	local store: any = nil
	local existingPlaylists: { [string]: any } = {}
	local existingTracks: { [string]: any } = {}

	if MODE == "commit" or STRATEGY == "merge" then
		store = getStoreOrNil()
		if store and STRATEGY == "merge" then
			existingPlaylists = loadKey(store, PLAYLIST_KEY)
			existingTracks = loadKey(store, TRACK_KEY)
			local function countTable(t: { [string]: any }): number
				local n = 0
				for _ in pairs(t) do
					n += 1
				end
				return n
			end
			info("Loaded existing: %d playlists, %d tracks",
				countTable(existingPlaylists),
				countTable(existingTracks)
			)
		end
	end

	local playlistMap = buildPlaylistMap(existingPlaylists, SOURCE_DATA)
	local nextTracks = processTracks(existingTracks, SOURCE_DATA, playlistMap)
	rebuildPlaylistTrackIds(playlistMap.byId, nextTracks)

	info("=== SUMMARY ===")
	info("Playlists added : %d", stats.playlistsAdded)
	info("Playlists skipped: %d", stats.playlistsSkipped)
	info("Tracks added    : %d", stats.tracksAdded)
	info("Tracks skipped  : %d", stats.tracksSkipped)
	info("Errors          : %d", stats.errors)

	if MODE == "dry_run" then
		info("DRY RUN — no DataStore writes performed. Set MODE='commit' untuk apply.")
		return
	end

	if not store then
		warnLog("Store unavailable, can't commit. Abort.")
		return
	end

	info("Writing to DataStore...")
	local pOk = saveKey(store, PLAYLIST_KEY, playlistMap.byId)
	local tOk = saveKey(store, TRACK_KEY, nextTracks)

	if pOk and tOk then
		info("✅ COMMIT SUCCESS — DataStore updated.")
	else
		warnLog("❌ COMMIT PARTIAL/FAILED — playlistOk=%s trackOk=%s", tostring(pOk), tostring(tOk))
	end
end

main()
