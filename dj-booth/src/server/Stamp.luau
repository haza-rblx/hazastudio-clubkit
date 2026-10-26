--!strict
-- The download stamp (ADR 0022 §12). The licence server rewrites these values in every buyer's
-- download, so each file names the licence and the download it came from. The values here are the
-- release template's placeholders. Server only: the client never sees them.
return {
	licenseId = "TEMPLATE",
	buyerId = 0,
	downloadId = "TEMPLATE",
	fingerprint = "TEMPLATE",
}
