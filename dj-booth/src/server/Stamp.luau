--!strict
-- The download stamp (ADR 0022 §12). The licence server rewrites these values in every buyer's
-- download, so each file names the licence, the download it came from, and the game it was
-- pre-bound to. universeId = 0 means not pre-bound (a dev download), so the game check is skipped.
-- The values here are the release template's placeholders; the stamp CLI rewrites the whole file
-- per download. Server only: the client never sees them.
return {
	licenseId = "TEMPLATE",
	buyerId = 0,
	downloadId = "TEMPLATE",
	fingerprint = "TEMPLATE",
	universeId = 0,
	placeId = 0,
	ownerId = 0,
	ownerType = "User", -- "User" | "Group"
}
