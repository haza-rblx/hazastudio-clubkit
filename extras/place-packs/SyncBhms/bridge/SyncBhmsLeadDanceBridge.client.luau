--!strict
--[[
  Place-pack bridge: restores the "Lead Dance" topbar icon under LegacySyncBhms
  by reusing Club Kit's own SyncLeadTopbarController module (read-only require,
  no engine changes) and routing requests through SyncBhmsAcmBridge instead of
  Club Kit's SyncController.

  Install as LocalScript:
    StarterPlayerScripts.SyncBhmsLeadDanceBridge

  Club Kit's native "Lead Dance" icon (Main.client SyncDanceBootstrap) only
  boots when clubKitOwnedSyncDance is true, which is never the case while
  LegacySyncBhms is true — so this and the native icon are mutually exclusive
  by construction, same as SyncBhmsGate covers the other pack scripts.

  Dropdown eligibility is dynamic, same as Club Kit's own version: players
  holding the LeadDance role/rank, PLUS anyone with an active BHMS follower
  (Character.IsLeader / FollowerCount attributes) — see the companion server
  script SyncBhmsLeadDanceFollowerSync.server.luau, which mirrors BHMS's own
  follower graph (Character.Syncing) onto those same attributes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local SyncBhmsGate = require(ReplicatedStorage:WaitForChild("SyncBhmsGate"))
if not SyncBhmsGate.isEnabled() then
	return
end

local Icon = require(ReplicatedStorage:WaitForChild("Icon"))
local SyncBhmsAcmBridge = require(ReplicatedStorage:WaitForChild("SyncBhmsAcmBridge"))

local player = Players.LocalPlayer
local playerScripts = player:WaitForChild("PlayerScripts")
local kitRoot = playerScripts:WaitForChild("Hazastudio_ClubKit", 30)
if not kitRoot then
	warn("[SyncBhmsLeadDanceBridge] Hazastudio_ClubKit not found under PlayerScripts within 30s.")
	return
end
local controllers = kitRoot:WaitForChild("Client", 10):WaitForChild("Controllers", 10)
local syncLeadTopbarModule = controllers:WaitForChild("SyncLeadTopbarController", 10)
local createSyncLeadTopbarController = require(syncLeadTopbarModule)

local syncLeadIcon = Icon.new()
syncLeadIcon:setLabel("Lead Dance")
syncLeadIcon:setOrder(2)
syncLeadIcon:align("Left")
if type(syncLeadIcon.setWidth) == "function" then
	syncLeadIcon:setWidth(96)
end
if type(syncLeadIcon.modifyTheme) == "function" then
	syncLeadIcon:modifyTheme({
		{ "IconImage", "Visible", false },
		{ "PaddingLeft", "Size", UDim2.fromScale(0, 1) },
		{ "PaddingRight", "Size", UDim2.fromScale(0, 1) },
	})
end

local function requestLeadDanceSync(targetUserId: number)
	SyncBhmsAcmBridge.requestSyncByUserId(targetUserId)
end

createSyncLeadTopbarController({
	icon = syncLeadIcon,
	iconFactory = function()
		return Icon.new()
	end,
	onRequestSyncToLeader = requestLeadDanceSync,
})
