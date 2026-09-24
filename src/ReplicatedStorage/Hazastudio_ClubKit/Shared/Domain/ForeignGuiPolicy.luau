--!strict
-- Pure rules for the "foreign GUI" signal (ADR 0012): what a client may say about a
-- GUI that appeared in its PlayerGui after boot, and what of that is safe to put in
-- the owner's Discord channel.
--
-- Both halves use this module, on purpose:
--   * the client caps and sanitises before it fires ReportTamper (cheap, honest clients);
--   * the server re-applies every rule to the payload it receives, because that payload
--     is HOSTILE — any exploiter can fire ReportTamper directly with anything at all.
-- The server's pass is the one that counts; the client's is courtesy.
--
-- The output is rendered inside a fenced code block in a Discord embed field, so the
-- sanitiser has two jobs: keep the field from being reshaped (backticks close the fence)
-- and keep the owner from being pinged by a forged report (@everyone / @here / <@id>).
-- Non-ASCII is replaced rather than passed through: it makes truncation safe (no split
-- UTF-8 sequence to break JSON encoding) and kills homoglyph / RTL-override disguises.

local ForeignGuiPolicy = {}

-- Caps. The whole detail must fit one Discord embed field (hard limit 1024) with the
-- ``` fence and room to spare, so 480 leaves better than 2x headroom.
ForeignGuiPolicy.MAX_SCRIPTS_PER_GUI = 5
ForeignGuiPolicy.MAX_NAME_CHARS = 64
ForeignGuiPolicy.MAX_DETAIL_CHARS = 480
ForeignGuiPolicy.MAX_KEY_NAME_CHARS = 48
-- Budgets (defaults; Config.AntiTamper may lower them, never raise them).
ForeignGuiPolicy.MAX_REPORTS_PER_PLAYER = 3
ForeignGuiPolicy.MAX_REPORTS_PER_SERVER = 8

local MAX_COUNT = 999999
local REASON_PREFIX = "foreign_gui:"

export type ScriptInfo = {
	name: string,
	className: string,
}

export type GuiInfo = {
	name: string,
	className: string,
	resetOnSpawn: boolean?,
	descendants: number,
	scriptCount: number,
	scripts: { ScriptInfo },
}

-- Returns nil for anything that is not a usable string, so a caller can treat
-- "nothing to say" and "junk" the same way.
function ForeignGuiPolicy.sanitize(value: any, maxChars: number?): string?
	if type(value) ~= "string" then
		return nil
	end
	local max = math.floor(tonumber(maxChars) or ForeignGuiPolicy.MAX_NAME_CHARS)
	if max < 4 then
		max = 4
	end

	-- A forged payload can be a megabyte; never walk more than we could ever keep.
	local input = value
	if #input > max * 8 then
		input = string.sub(input, 1, max * 8)
	end

	local parts: { string } = {}
	for i = 1, #input do
		local b = string.byte(input, i)
		if b == 96 then
			parts[i] = "'" -- ` would close the fenced code block
		elseif b == 64 then
			parts[i] = "(at)" -- @everyone / @here / <@id> stop being mentions
		elseif b >= 32 and b <= 126 then
			parts[i] = string.sub(input, i, i)
		elseif b < 32 or b == 127 then
			parts[i] = " " -- control characters cannot reshape the embed
		else
			parts[i] = "?" -- non-ASCII: unknown width, unknown intent
		end
	end

	local out = table.concat(parts)
	out = string.gsub(out, "%?+", "?")
	out = string.gsub(out, "%s+", " ")
	out = string.gsub(out, "^ ", "")
	out = string.gsub(out, " $", "")
	if out == "" then
		return nil
	end
	if #out > max then
		out = string.sub(out, 1, max - 3) .. "..."
	end
	return out
end

-- A hostile table in, a bounded GuiInfo (or nothing) out.
function ForeignGuiPolicy.normalize(raw: any): GuiInfo?
	if type(raw) ~= "table" then
		return nil
	end
	local name = ForeignGuiPolicy.sanitize(raw.name, ForeignGuiPolicy.MAX_NAME_CHARS)
	if not name then
		return nil
	end

	local descendants = tonumber(raw.descendants)
	if type(descendants) ~= "number" or descendants ~= descendants or descendants < 0 then
		descendants = 0
	end

	local rawScripts = if type(raw.scripts) == "table" then raw.scripts else nil
	local kept: { ScriptInfo } = {}
	if rawScripts then
		for _, entry in ipairs(rawScripts) do
			if #kept >= ForeignGuiPolicy.MAX_SCRIPTS_PER_GUI then
				break
			end
			if type(entry) == "table" then
				local scriptName = ForeignGuiPolicy.sanitize(entry.name, ForeignGuiPolicy.MAX_NAME_CHARS)
				if scriptName then
					table.insert(kept, {
						name = scriptName,
						className = ForeignGuiPolicy.sanitize(entry.className, ForeignGuiPolicy.MAX_NAME_CHARS)
							or "unknown",
					})
				end
			end
		end
	end

	local reported = tonumber(raw.scriptCount)
	if type(reported) ~= "number" or reported ~= reported then
		reported = if rawScripts then #rawScripts else 0
	end

	return {
		name = name,
		className = ForeignGuiPolicy.sanitize(raw.className, ForeignGuiPolicy.MAX_NAME_CHARS) or "unknown",
		resetOnSpawn = if type(raw.resetOnSpawn) == "boolean" then raw.resetOnSpawn else nil,
		descendants = math.floor(math.min(descendants :: number, MAX_COUNT)),
		scriptCount = math.floor(math.clamp(reported :: number, #kept, MAX_COUNT)),
		scripts = kept,
	}
end

-- Exactly what lands in the Discord code block. Every part is already sanitised;
-- this only composes and applies the whole-string cap.
function ForeignGuiPolicy.buildDetail(info: GuiInfo): string
	local head = string.format('%s "%s"', info.className, info.name)
	if info.resetOnSpawn ~= nil then
		head ..= " | ResetOnSpawn=" .. tostring(info.resetOnSpawn)
	end
	head ..= string.format(" | %d descendants", info.descendants)

	local lines: { string } = { head }
	if #info.scripts == 0 then
		table.insert(lines, "no scripts")
	else
		for _, entry in ipairs(info.scripts) do
			table.insert(lines, string.format('%s "%s"', entry.className, entry.name))
		end
		local hidden = info.scriptCount - #info.scripts
		if hidden > 0 then
			table.insert(lines, string.format("+%d more", hidden))
		end
	end

	local detail = table.concat(lines, "\n")
	if #detail > ForeignGuiPolicy.MAX_DETAIL_CHARS then
		detail = string.sub(detail, 1, ForeignGuiPolicy.MAX_DETAIL_CHARS - 3) .. "..."
	end
	return detail
end

-- Beacon dedupe key. Different GUI names must beacon separately (that is the whole
-- point of the signal) while the reason string stays short and inert.
function ForeignGuiPolicy.reasonKey(name: any): string
	return REASON_PREFIX .. (ForeignGuiPolicy.sanitize(name, ForeignGuiPolicy.MAX_KEY_NAME_CHARS) or "unknown")
end

return ForeignGuiPolicy
