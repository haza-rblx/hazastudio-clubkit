--!strict
-- Shared/Utils/Logger.lua
-- Studio: DEBUG..ERROR. Production: hanya ERROR (merah via TestService), DEBUG/INFO/WARN di-gate.
local RunService = game:GetService("RunService")
local Types = require(script.Parent.Parent.Domain.Types)

local IS_STUDIO = RunService:IsStudio()
local LEVELS = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
-- Production: hide semua kecuali ERROR (log merah). Studio tetap verbose.
local MIN_LEVEL = if IS_STUDIO then LEVELS.DEBUG else LEVELS.ERROR

local Logger = {}
Logger.__index = Logger

type ILogger = Types.ILogger
type LoggerImpl = {
	_module: string,
	debug: (self: LoggerImpl, msg: string, ctx: { [string]: any }?) -> (),
	info: (self: LoggerImpl, msg: string, ctx: { [string]: any }?) -> (),
	warn: (self: LoggerImpl, msg: string, ctx: { [string]: any }?) -> (),
	error: (self: LoggerImpl, msg: string, ctx: { [string]: any }?) -> (),
}

local function serialize(ctx: { [string]: any }?): string
	if not ctx then
		return ""
	end
	local parts = {}
	for k, v in pairs(ctx) do
		table.insert(parts, tostring(k) .. "=" .. tostring(v))
	end
	return " | {" .. table.concat(parts, ",") .. "}"
end

-- Merah di Developer Console tanpa throw / crash script (error() akan throw).
local function emitError(line: string)
	local ok = pcall(function()
		game:GetService("TestService"):Error(line)
	end)
	if not ok then
		warn(line)
	end
end

local function log(module: string, level: string, levelNum: number, msg: string, ctx: { [string]: any }?)
	if levelNum < MIN_LEVEL then
		return
	end
	local line = ("[%s][%s] %s%s"):format(level, module, msg, serialize(ctx))
	if levelNum >= LEVELS.ERROR then
		emitError(line)
	elseif levelNum >= LEVELS.WARN then
		warn(line)
	else
		print(line)
	end
end

function Logger.new(moduleName: string): ILogger
	local self = setmetatable({
		_module = moduleName,
	}, Logger) :: any
	return self :: any
end

function Logger:debug(msg: string, ctx: { [string]: any }?)
	log(self._module, "DEBUG", LEVELS.DEBUG, msg, ctx)
end

function Logger:info(msg: string, ctx: { [string]: any }?)
	log(self._module, "INFO", LEVELS.INFO, msg, ctx)
end

function Logger:warn(msg: string, ctx: { [string]: any }?)
	log(self._module, "WARN", LEVELS.WARN, msg, ctx)
end

function Logger:error(msg: string, ctx: { [string]: any }?)
	log(self._module, "ERROR", LEVELS.ERROR, msg, ctx)
end

function Logger.isStudio(): boolean
	return IS_STUDIO
end

function Logger.isProductionQuiet(): boolean
	return not IS_STUDIO
end

return Logger
