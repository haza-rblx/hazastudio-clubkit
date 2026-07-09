--!strict
-- Run in Studio Command Bar (any context). Music debug + asset failure model.

print([[
========== Music playback ==========

ASSET FAILURES (stabilization model):
  Client watches ContentProvider (NOT a skip timer):
    - AssetFetchStatus.Failure → definitive (after retries if applicable)
    - AssetFetchStatus.TimedOut → RETRY first (ASSET_FAILURE_RETRY_ATTEMPTS, backoff)
      unless ASSET_FAILURE_TIMEDOUT_IS_DEFINITIVE = true
    - ContentProvider.AssetFetchFailed
    - PreloadAsync callback hard failure
    - TimeLength still 0 after Loaded (rare)

  Stall guard: client defers server report until
    ASSET_FAILURE_SKIP_MIN_STALL_SECONDS (default 60s) after playback start.
    WARN log: "Music asset failure deferred (stall guard)"

  Slow load → warn after ASSET_LOAD_STALL_LOG_SECONDS (default 120s), NO auto-skip

  Server skips on definitive report + ASSET_FAILURE_SKIP_QUORUM (default 2)
  Telegram: MUSIC_ASSET_SKIP when server confirms skip

SERVER AUTO-ADVANCE:
  ASSET_LOAD_GRACE_SECONDS (default 90s) added on initial track schedule
  (before client duration report). Removed after MusicDurationReport.
  Unknown duration fallback: AUTO_ADVANCE_UNKNOWN_DURATION_SECONDS + grace

DJ MODE (strict):
  isDjMode = true → advanceQueue never pulls autoBuffer
  Enabling DJ while system track plays → advance to user queue or stop

PREFETCH (client MusicAssetCache):
  Horizon A: current track all parts priority 1
  Horizon B: user queue lookahead; prefetchBuffer when queue <= AUTO_BUFFER_REFILL_MAX_USER_QUEUE
  Defaults: PREFETCH_TRACKS_AHEAD=2, PREFETCH_PROFILE_BALANCED=4
  Rollback: Config.Music.PREFETCH_ENABLED = false

DOUBLE AUDIO GUARDS:
  _playbackEpoch + _activeSounds[partIndex] (one audible stream per part)
  killOrphan skips MusicAssetCacheHolders + Volume=0 non-playing sounds

QA (/mdebug after each step):
  playingTracked <= 1, orphanPlaying = 0, prefetch holders playing = 0
  Queue track → slow load → no skip before 60s stall guard
  DJ ON → only user queue plays

COMMANDS: /musicdebug | /musicdebug orphans | /musicdebug kill | /mdebug

Config.Music (key tuning):
  ASSET_LOAD_GRACE_SECONDS
  ASSET_FAILURE_SKIP_MIN_STALL_SECONDS
  ASSET_FAILURE_RETRY_ATTEMPTS / ASSET_FAILURE_RETRY_BACKOFF
  ASSET_FAILURE_TIMEDOUT_IS_DEFINITIVE (keep false in production)
  ASSET_FAILURE_SKIP_QUORUM
  ASSET_LOAD_STALL_LOG_SECONDS
  PREFETCH_*, AUTO_QUEUE_DEPTH, AUTO_BUFFER_REFILL_MAX_USER_QUEUE
  ASSET_VALIDATE_USE_PRELOAD (keep false)

Rollback switches:
  PREFETCH_ENABLED = false
  ASSET_LOAD_GRACE_SECONDS = 0
  ASSET_FAILURE_SKIP_QUORUM = 1
  ASSET_FAILURE_TIMEDOUT_IS_DEFINITIVE = true (not recommended)

Files:
  Client/Services/MusicAssetCache.luau
  Client/Services/MusicAssetLoadService.luau
  MusicPlayerController.luau
  MusicSession.luau
  MusicController.luau (MUSIC_ASSET_SKIP incident)
=================================================================
]])
