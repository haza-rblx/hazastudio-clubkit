--!strict
-- The DJ deck's data model. Everything here is plain data (JSON-safe), so the same shapes are stored
-- in the DataStore, synced to clients by CharmSync and read by the UI.

export type TrackStatus = "ready" | "unavailable" | "checking"

export type Track = {
	id: string,
	assetId: number,
	title: string,
	artist: string,
	bpm: number?,
	key: string?, -- Camelot, "1A" .. "12B"
	len: number?, -- seconds at 1.00x
	speed: number, -- playback speed the decks use, 0.05 .. 3 (ruler reads 0 .. 3)
	gain: number, -- dB, -6 .. +6
	start: number, -- seconds to start at
	status: TrackStatus,
	added: number, -- insertion order (newest = highest)
	cues: { [string]: number }?, -- hot cue "1".."8" -> seconds
}

export type Playlist = {
	id: string,
	name: string,
	coverText: string?,
	image: number?,
	color: string?, -- hex "e41024"; nil = the default red
	shuffle: boolean,
	tracks: { string }, -- track ids, in playlist order
}

export type Sound = {
	id: string,
	assetId: number,
	name: string,
	len: number?,
	status: TrackStatus?, -- nil = ready
}

export type PadKind = "sfx" | "world"

export type Pad = {
	label: string,
	kind: PadKind?, -- nil = an empty pad
	sound: string?, -- Sound id
	effect: number?, -- 1 shake, 2 rotate, 3 darken, 4 low gravity
	volume: number?, -- 0 .. 100
	reach: number?, -- 1 everyone, 2 near the DJ deck
	intensity: number?, -- 0 .. 100
	duration: number?, -- seconds
	cooldown: number,
}

export type Library = {
	tracks: { [string]: Track },
	playlists: { Playlist },
	sounds: { Sound },
	pads: { Pad },
	nextAdded: number,
}

export type Role = "Owner" | "Resident" | "Guest"

export type Person = {
	userId: number,
	name: string, -- display name
	handle: string, -- username
	role: Role,
	since: number?, -- unix seconds
	ends: number?, -- guests: 1 server closes, 2 in 1 hour, 3 at 23:00
	endsAt: number?, -- guests: unix seconds for 2 / 3
	sets: number,
	seconds: number, -- time on the decks
	lastSet: number?, -- unix seconds
	added: number, -- list order (the owner is 0)
}

export type Gates = {
	group: { on: boolean, id: string, rank: string },
	pass: { on: boolean, id: string },
	takeOver: number, -- 1 owner, 2 residents, 3 any DJ
}

export type Access = {
	people: { [string]: Person }, -- userId string -> person (residents persist, guests are session only)
	gates: Gates,
}

export type Settings = {
	volume: number,
	normalize: boolean,
	limiter: boolean,
	fadeOut: number,
	crossfade: number,
	pitch: number, -- 1 ±8%, 2 ±16%, 3 ±50%, 4 0–3x
	keyLock: boolean,
	syncOnLoad: boolean,
	autoCue: boolean,
	playOnLoad: boolean, -- a track the DJ loads starts right away (Auto mix loads stay paused)
	busyDeck: number, -- 1 ask, 2 block, 3 allow
	padCooldown: number, -- 1 none, 2 short, 3 long
	deckOff: string, -- deck-off brake preset name, "" = instant stop
	speakers: number, -- 1 whole map, 2 club zone, 3 DJ deck area
	openAtDjDeck: boolean,
	standLock: boolean,
	maxSet: number, -- 1 none, 2 30 min, 3 1 h, 4 2 h
	idle: number, -- 1 never, 2 5 min, 3 10 min, 4 15 min
	announce: boolean,
	nowPlaying: boolean,
	billboard: boolean,
	lights: boolean,
	camFx: boolean,
	camFxAmount: number,
	accent: string, -- 6 hex digits, no "#"; "" = the default red
}

export type Prefs = {
	panelSize: number, -- 1 small, 2 normal, 3 large
	reduceMotion: boolean,
	hotkey: number, -- 1 J, 2 K, 3 B, 4 none
	view: string, -- "deck" | "window" | "full"
}

export type Deck = {
	trackId: string?,
	playing: boolean,
	pos: number, -- track seconds at `at`
	at: number, -- server time the position was taken
	cue: number, -- the CUE point, seconds
	pitch: number, -- fraction, -0.95 .. 2
	synced: boolean,
	eq: { number }, -- high, mid, low; 0..1, 0.5 = flat
	filter: number, -- 0..1, 0.5 = off
	vol: number, -- 0..1
	fx: { number }, -- echo, reverb, flanger; 0..1
	lastCue: number?, -- the hot cue last jumped to
	brake: { preset: string, at: number, from: number }?, -- deck-off brake: server time it began, track second it began from; cleared by any move
}

export type QueueEntry = { trackId: string, key: string }

export type Session = {
	live: number?, -- userId of the live DJ
	liveSince: number?,
	online: { [string]: boolean }, -- userId string -> in this server
	decks: { Deck },
	xfader: number,
	curve: number,
	master: number,
	queue: { QueueEntry },
	automix: boolean, -- runtime only (not stored): the next queued track goes to the idle deck
	padReady: { number }, -- server time each pad is ready again
	fade: { at: number, dur: number }?, -- room fade-out: server time it started, length in seconds
}

-- what every player gets (ADR 0021): the tracks on the decks and in the queue, by id
export type Stage = {
	tracks: { [string]: Track },
	hints: { string }, -- tracks the live DJ is about to play, newest first (preload only)
}

export type Me = {
	role: Role?,
	canOpen: boolean,
	canEditLibrary: boolean,
	canEditAccess: boolean,
	canEditSettings: boolean,
	prefs: Prefs,
}

return nil
