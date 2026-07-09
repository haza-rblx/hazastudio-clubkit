--!strict
-- Shared/Utils/Logger.lua
local RunService = game:GetService("RunService")
local Types = require(script.Parent.Parent.Domain.Types)

local IS_STUDIO  = RunService:IsStudio()
local LEVELS = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }
-- Di production, hanya tampilkan ERROR untuk menghindari game owner panik melihat log WARN (kuning).
-- Jika ingin benar-benar tanpa log di production, ubah menjadi `math.huge`.
local MIN_LEVEL = IS_STUDIO and LEVELS.DEBUG or LEVELS.ERROR
local Logger = {}
Logger.__index = Logger

type ILogger = Types.ILogger
type LoggerImpl = {
	_module : string,
	debug   : (self: LoggerImpl, msg: string, ctx: {[string]: any}?) -> (),
	info    : (self: LoggerImpl, msg: string, ctx: {[string]: any}?) -> (),
	warn    : (self: LoggerImpl, msg: string, ctx: {[string]: any}?) -> (),
	error   : (self: LoggerImpl, msg: string, ctx: {[string]: any}?) -> (),
}
local function serialize(ctx: {[string]: any}?): string
	if not ctx then return "" end
	local parts = {}
	for k, v in pairs(ctx) do
		table.insert(parts, tostring(k).."="..tostring(v))
	end
	return " | {"..table.concat(parts, ",").."}"
end
local function log(module: string, level: string, levelNum: number, msg: string, ctx: {[string]: any}?)
	if levelNum < MIN_LEVEL then return end
	local line = ("[%s][%s] %s%s"):format(level, module, msg, serialize(ctx))
	if levelNum >= LEVELS.ERROR then
		warn(line)  -- Jangan error() - ini throw exception dan crash script kalau tidak di-pcall
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
function Logger:debug(msg: string, ctx: {[string]: any}?)
	log(self._module, "DEBUG", LEVELS.DEBUG, msg, ctx)
end
function Logger:info(msg: string, ctx: {[string]: any}?)
	log(self._module, "INFO", LEVELS.INFO, msg, ctx)
end
function Logger:warn(msg: string, ctx: {[string]: any}?)
	log(self._module, "WARN", LEVELS.WARN, msg, ctx)
end
function Logger:error(msg: string, ctx: {[string]: any}?)
	log(self._module, "ERROR", LEVELS.ERROR, msg, ctx)
end
return Logger
