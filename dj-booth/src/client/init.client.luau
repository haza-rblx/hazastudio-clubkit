--!strict
-- HazaDJ client: state sync, the panel, toasts, world effects and the deck audio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vide = require(ReplicatedStorage.HazaDJ.Packages.Vide)
-- instances start exactly as Instance.new makes them (the prototype's baseline); every helper sets
-- what it needs
Vide.defaults = false

local App = require(script.App)
local Audio = require(script.Audio)
local Net = require(script.Net)
local Preload = require(script.Preload)
local Store = require(script.Store)
local Toast = require(script.Toast)
local WorldFx = require(script.WorldFx)

Net.Toast.On(Toast.show)
Net.WorldFx.On(WorldFx.play)

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
Vide.mount(function()
	return App.new()
end, playerGui)

-- the decks' Sounds exist before the first state arrives; Store.start asks the server for it
Audio.start()
Preload.start()
Store.start()
