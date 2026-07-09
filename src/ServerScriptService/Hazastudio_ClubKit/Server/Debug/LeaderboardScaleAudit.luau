--!strict
-- Studio / live-server helpers for 120 CCU leaderboard scaling checks.
-- Run via owner command: /refreshleaderboard audit

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.Logger)

local log = Logger.new("LeaderboardScaleAudit")

export type AuditMetrics = {
	buildMs: number,
	paintMs: number?,
	estimateBytes: number,
	playerCount: number,
	estimateEgressKb: number,
	robuxEntries: number,
	likesEntries: number,
	broadcastSkipped: boolean?,
}

local LeaderboardScaleAudit = {}

function LeaderboardScaleAudit.estimatePayloadBytes(payload: any): number
	if type(payload) ~= "table" then
		return 0
	end
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, payload)
	if ok and type(encoded) == "string" then
		return #encoded
	end
	return 0
end

function LeaderboardScaleAudit.metricsFromPayload(payload: any, buildMs: number, paintMs: number?): AuditMetrics
	local bytes = LeaderboardScaleAudit.estimatePayloadBytes(payload)
	local ccu = #Players:GetPlayers()
	return {
		buildMs = buildMs,
		paintMs = paintMs,
		estimateBytes = bytes,
		playerCount = ccu,
		estimateEgressKb = if ccu > 0 then (bytes * ccu) / 1024 else 0,
		robuxEntries = if type(payload.robux) == "table" then #payload.robux else 0,
		likesEntries = if type(payload.likes) == "table" then #payload.likes else 0,
	}
end

function LeaderboardScaleAudit.run(
	buildPayload: () -> any,
	paintPayload: ((any) -> ())?
): AuditMetrics
	local buildStart = os.clock()
	local payload = buildPayload()
	local buildMs = (os.clock() - buildStart) * 1000
	local paintMs: number? = nil
	if paintPayload then
		local paintStart = os.clock()
		paintPayload(payload)
		paintMs = (os.clock() - paintStart) * 1000
	end
	return LeaderboardScaleAudit.metricsFromPayload(payload, buildMs, paintMs)
end

function LeaderboardScaleAudit.runBurst(buildPayload: (boolean?) -> any, iterations: number): { AuditMetrics }
	local samples: { AuditMetrics } = {}
	for index = 1, iterations do
		local forceRefresh = index == 1
		local buildStart = os.clock()
		local payload = buildPayload(forceRefresh)
		local buildMs = (os.clock() - buildStart) * 1000
		table.insert(samples, LeaderboardScaleAudit.metricsFromPayload(payload, buildMs, nil))
	end
	return samples
end

function LeaderboardScaleAudit.formatSummary(metrics: AuditMetrics): string
	return string.format(
		"build=%.0fms paint=%s payload=%.1fKB egress@ccu=%.1fKB robux=%d likes=%d players=%d",
		metrics.buildMs,
		if metrics.paintMs then string.format("%.0fms", metrics.paintMs) else "n/a",
		metrics.estimateBytes / 1024,
		metrics.estimateEgressKb,
		metrics.robuxEntries,
		metrics.likesEntries,
		metrics.playerCount
	)
end

function LeaderboardScaleAudit.logBroadcast(metrics: AuditMetrics, skipped: boolean)
	local payload = table.clone(metrics) :: any
	payload.skipped = skipped
	log:info(if skipped then "Leaderboard paint-only (remote skipped)" else "Leaderboard broadcast", payload)
end

return LeaderboardScaleAudit
