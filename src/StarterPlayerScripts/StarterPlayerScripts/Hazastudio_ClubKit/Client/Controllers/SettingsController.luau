--!strict

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local SettingsDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.SettingsDomain)
local DeltaCompressor = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.DeltaCompressor)
local GraphicsQuality = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.GraphicsQuality)
local NotifService = require(script.Parent.Parent.Services.NotifService)
local OverheadController = require(script.Parent.OverheadController)
local PhoneLayout = require(script.Parent.Parent.Utils.PhoneLayout)

type SettingsPayload = Types.SettingsPayload
type SettingsStoredData = Types.SettingsStoredData
type SettingsSessionData = Types.SettingsSessionData
type ProfileMenuPayload = Types.ProfileMenuPayload
type OverheadPayload = Types.OverheadPayload
type ILogger = Types.ILogger
type EffectiveGraphics = GraphicsQuality.EffectiveGraphics

local graphicsCfg = Config.Graphics
local SETTINGS_DEPTH_OF_FIELD_NAME = "RuntimeSettingsDepthOfField"
local SETTINGS_COLOR_TUNE_NAME = "RuntimeSettingsColorTune"
local SETTINGS_BACKGROUND_BLUR_ATTRIBUTE = "SettingsBackgroundBlurEnabled"
local SETTINGS_SHADOWS_ATTRIBUTE = "SettingsShadowsEnabled"
local SETTINGS_TEXTURES_ATTRIBUTE = "SettingsTexturesEnabled"
local SETTINGS_HIDE_ALL_GUI_ORIGINAL = "RuntimeSettingsOriginalEnabled_HideAllGui"
local SETTINGS_GUI_NAME = "07-MenuGUI"

local ORIGINAL_CAST_SHADOW_ATTRIBUTE = "RuntimeSettingsOriginalCastShadow"
local ORIGINAL_LIGHT_SHADOWS_ATTRIBUTE = "RuntimeSettingsOriginalLightShadows"
local ORIGINAL_MATERIAL_ATTRIBUTE = "RuntimeSettingsOriginalMaterial"
local ORIGINAL_MATERIAL_VARIANT_ATTRIBUTE = "RuntimeSettingsOriginalMaterialVariant"
local ORIGINAL_TEXTURE_ID_ATTRIBUTE = "RuntimeSettingsOriginalTextureId"
local ORIGINAL_TEXTURE_ATTRIBUTE = "RuntimeSettingsOriginalTexture"
local ORIGINAL_TRANSPARENCY_ATTRIBUTE = "RuntimeSettingsOriginalTransparency"
local ORIGINAL_TERRAIN_DECORATION_ATTRIBUTE = "RuntimeSettingsOriginalTerrainDecoration"
local ORIGINAL_SURFACE_COLOR_MAP_ATTRIBUTE = "RuntimeSettingsOriginalSurfaceColorMap"
local ORIGINAL_SURFACE_METALNESS_MAP_ATTRIBUTE = "RuntimeSettingsOriginalSurfaceMetalnessMap"
local ORIGINAL_SURFACE_NORMAL_MAP_ATTRIBUTE = "RuntimeSettingsOriginalSurfaceNormalMap"
local ORIGINAL_SURFACE_ROUGHNESS_MAP_ATTRIBUTE = "RuntimeSettingsOriginalSurfaceRoughnessMap"
local ORIGINAL_PARTICLE_RATE_ATTRIBUTE = graphicsCfg.ORIGINAL_PARTICLE_RATE_ATTRIBUTE
local ORIGINAL_LIGHT_RANGE_ATTRIBUTE = graphicsCfg.ORIGINAL_LIGHT_RANGE_ATTRIBUTE
local ORIGINAL_POSTFX_ENABLED_ATTRIBUTE = graphicsCfg.ORIGINAL_POSTFX_ENABLED_ATTRIBUTE
local ORIGINAL_ATMOSPHERE_DENSITY_ATTRIBUTE = "RuntimeSettingsOriginalAtmosphereDensity"
local ORIGINAL_WORKSPACE_LIGHT_SHADOWS_ATTRIBUTE = "RuntimeSettingsOriginalWorkspaceLightShadows"

local POST_PROCESSING_CLASSES: { string } = {
	"BloomEffect",
	"SunRaysEffect",
}

local WORKSPACE_VFX_CLASSES: { string } = {
	"ParticleEmitter",
	"Beam",
	"Trail",
	"Fire",
	"Smoke",
	"Sparkles",
}

local MANAGED_BLUR_EFFECT_NAMES = {
	MusicPlayerMainBlur = true,
	MusicPlayerAddToQueueBlur = true,
	MusicPlayerPlaylistRelatedBlur = true,
	MusicPlayerTrackRelatedBlur = true,
	TopMenuUIBlur = true,
	SettingsUIBlur = true,
	PaidBroadcastUIBlur = true,
	CoupleUIBlur = true,
	GiftUIBlur = true,
	ShopUIBlur = true,
	DonationUIBlur = true,
	AdminPanelUIBlur = true,
}
local CHAT_BUBBLE_NEARBY_DISTANCE = 16
local CHAT_BUBBLE_EVERYONE_DISTANCE = 150

local function createSettingsController(deps: {
	logger: ILogger,
	ui: any,
	icon: any?,
	remotes: Folder,
})
	local log = deps.logger
	local ui = deps.ui
	local icon = deps.icon
	local remotes = deps.remotes
	local requestRemote = remotes:WaitForChild(Config.Settings.REMOTE_REQUEST) :: RemoteEvent
	local syncRemote = remotes:WaitForChild(Config.Settings.REMOTE_SYNC) :: RemoteEvent
	local updateRemote = remotes:WaitForChild(Config.Settings.REMOTE_UPDATE) :: RemoteEvent
	local resetRemote = remotes:WaitForChild(Config.Settings.REMOTE_RESET) :: RemoteEvent
	local profileRequestRemote = remotes:WaitForChild(Config.ProfileMenu.REMOTE_REQUEST) :: RemoteEvent
	local profileSyncRemote = remotes:WaitForChild(Config.ProfileMenu.REMOTE_SYNC) :: RemoteEvent
	local profileUpdateRemote = remotes:WaitForChild(Config.ProfileMenu.REMOTE_UPDATE) :: RemoteEvent
	local overheadUpdateRemote = remotes:WaitForChild("OverheadUpdate") :: RemoteEvent
	local localPlayer = Players.LocalPlayer
	local currentPayload: SettingsPayload = SettingsDomain.merge(nil, nil)
	local currentProfilePayload: ProfileMenuPayload? = nil
	local currentLocalOverheadPayload: OverheadPayload? = nil
	local overheadPayloadBaselines: { [number]: any } = {}
	local overheadNilSentinel = DeltaCompressor.NIL_SENTINEL
	local saveDebounceActive = false
	local saveToken = 0
	local settingsEditSeq = 0
	local settingsAckSeq = 0
	local lastSentEditSeq = 0
	local settingsHydratedFromServer = false
	local localSession: SettingsSessionData = SettingsDomain.defaultSessionData()
	local panelOpen = false
	local lastSettingsEditAt = 0
	local SAVE_DEBOUNCE_SEC = 0.55
	local SETTINGS_RECONCILE_TIMEOUT_SEC = 2
	local profileEditSeq = 0
	local profileAckSeq = 0
	local profileDebounceToken = 0
	local profilePendingByField: { [string]: any } = {}
	local PROFILE_RELATIONSHIP_DEBOUNCE_SEC = 0.18
	local optimisticRelationshipMode: string? = nil
	local pendingSettingsForceRebuild = false
	local pendingSaveNotifField: string? = nil
	local pendingSaveNotifValue: any = nil
	local fovSliderDragDepth = 0
	local SETTINGS_NOTIF_DEDUPE_PENDING = "settings_save_pending"
	local SETTINGS_NOTIF_DEDUPE_OK = "settings_save_ok"

	local OVERHEAD_LAYER_LABELS: { [string]: string } = {
		SpecialTitle = "Custom Title",
		BadgeGroup = "Badges",
		SpecialRank = "Special Rank",
		TopSpender = "Top Rupiah",
		TopDonate = "Top Robux",
		Rank = "Role",
		DisplayName = "Player Name",
		CoupleName = "Couple Status",
	}
	local OVERHEAD_BADGE_LABELS: { [string]: string } = {
		OwnerCoOwner = "Owner / Co-Owner",
		Developer = "Developer",
		Admin = "Admin",
		Member = "Membership",
		VIP = Config.Membership.Tiers.Tier1.label,
		VVIP = Config.Membership.Tiers.Tier2.label,
		Elite = Config.Membership.Tiers.Tier3.label,
		Streak = "Streak",
		LikeCounter = "Likes",
		Community = "Community",
	}
	local cameraTween: Tween? = nil
	local humanoidConn: RBXScriptConnection? = nil
	local menuPreviewVisible = false
	local trackedEffectCharacterConns = {} :: { [Player]: RBXScriptConnection }
	local trackedEffectDescendantConns = {} :: { [Player]: RBXScriptConnection }
	local renderSettingsGeneration = 0
	local workspaceVfxGeneration = 0
	local appliedShadowsEnabled: boolean? = nil
	local appliedTexturesEnabled: boolean? = nil
	local appliedWorkspaceVfxMode: string? = nil
	local appliedPostProcessing: string? = nil
	local provisionalPreset = if PhoneLayout.isPhoneLayout() then "Low" else "Balanced"
	local effectiveGraphics: EffectiveGraphics = GraphicsQuality.getEffective({
		graphicsPreset = provisionalPreset,
		textures = 2,
		depthOfField = 0,
		hideAllParticles = provisionalPreset == "Low",
		shadowQuality = if provisionalPreset == "Low" then "Off" else "Balanced",
		graphicsOverrides = {},
	})
	local HOTBAR_STATE_B_BASE_SCALE = 1.12
	local HOTBAR_STATE_C_BASE_SCALE = 1.34

	local controller = {}
	controller._connections = {} :: { RBXScriptConnection }

	local function trackConnection(conn: RBXScriptConnection): RBXScriptConnection
		table.insert(controller._connections, conn)
		return conn
	end

	local function resolveIconWidget(candidateIcon: any): GuiButton?
		local function asGuiButton(value: any): GuiButton?
			if typeof(value) == "Instance" and value:IsA("GuiButton") then
				return value :: GuiButton
			end
			return nil
		end

		local directCandidates = {
			candidateIcon.widget,
			candidateIcon._widget,
			candidateIcon.widgetInstance,
			candidateIcon._widgetInstance,
			candidateIcon.buttonInstance,
			candidateIcon._buttonInstance,
		}
		for _, candidate in ipairs(directCandidates) do
			local widget = asGuiButton(candidate)
			if widget then
				return widget
			end
		end

		local methodCandidates = {
			"getInstance",
			"getWidget",
			"getButton",
			"getIconInstance",
		}
		for _, methodName in ipairs(methodCandidates) do
			local method = candidateIcon[methodName]
			if type(method) == "function" then
				local ok, result = pcall(function()
					return method(candidateIcon, "Widget")
				end)
				if ok then
					local widget = asGuiButton(result)
					if widget then
						return widget
					end
				end
				ok, result = pcall(function()
					return method(candidateIcon)
				end)
				if ok then
					local widget = asGuiButton(result)
					if widget then
						return widget
					end
				end
			end
		end

		return nil
	end

	local function setAttr(name: string, value: any)
		if localPlayer then
			localPlayer:SetAttribute(name, value)
		end
	end

	local function setSessionAttrs(session: SettingsSessionData)
		setAttr("SettingsOverheadVisible", session.overheadVisible)
		setAttr("SettingsHideAllGui", session.hideAllGui)
		for key, value in pairs(session.overheadLayerVisible) do
			setAttr("SettingsOverheadLayerVisible_" .. key, value)
		end
		for key, value in pairs(session.overheadBadgeVisible) do
			setAttr("SettingsOverheadBadgeVisible_" .. key, value)
		end
	end

	local function applyLocalOverheadForUi(payload: OverheadPayload)
		if payload.userId ~= localPlayer.UserId then
			return
		end
		currentLocalOverheadPayload = payload
		if type(ui.setLocalOverheadData) == "function" then
			ui:setLocalOverheadData(payload)
		end
		if currentProfilePayload and type(ui.patchProfileFromPayload) == "function" then
			ui:patchProfileFromPayload(currentProfilePayload, payload)
		end
	end

	local function patchLocalOverheadFromProfileField(field: string, value: any)
		if not localPlayer then
			return
		end

		local base = currentLocalOverheadPayload
		if not base then
			base = OverheadController.getCachedPayload(localPlayer.UserId)
		end
		if not base then
			return
		end

		local patch: { [string]: any } = {}
		if field == "relationshipMode" then
			if value ~= "Single" and value ~= "Taken" and value ~= "Fun" then
				return
			end
			patch.relationshipMode = value
			local publicLayers = table.clone(base.publicOverheadLayerVisible or {})
			publicLayers.CoupleName = true
			patch.publicOverheadLayerVisible = publicLayers
		elseif field == "showCoupleName" then
			if type(value) ~= "boolean" then
				return
			end
			patch.showCoupleName = value
		else
			return
		end

		local merged = table.clone(base :: any)
		for patchField, patchValue in patch do
			merged[patchField] = patchValue
		end
		merged.userId = localPlayer.UserId

		currentLocalOverheadPayload = merged :: OverheadPayload
		OverheadController.applyLocalPayloadPatch(localPlayer.UserId, patch)
		if type(ui.setLocalOverheadData) == "function" then
			ui:setLocalOverheadData(merged)
		end
		if currentProfilePayload then
			local profilePatch = table.clone(currentProfilePayload :: any)
			if field == "relationshipMode" then
				profilePatch.relationshipMode = value
			elseif field == "showCoupleName" then
				profilePatch.showCoupleName = value == true
			end
			currentProfilePayload = profilePatch :: ProfileMenuPayload
			if type(ui.patchProfileFromPayload) == "function" then
				ui:patchProfileFromPayload(currentProfilePayload, merged)
			end
		end
	end

	local function mergeOverheadDelta(base: any, delta: any): any
		local result: any = if base then table.clone(base) else {}
		for field, value in delta do
			if value == overheadNilSentinel then
				result[field] = nil
			else
				result[field] = value
			end
		end
		return result
	end

	local function applyResolvedOverheadPayload(payload: any)
		if type(payload) ~= "table" or type(payload.userId) ~= "number" then
			return
		end
		if type(payload.displayName) ~= "string" or type(payload.role) ~= "string" then
			return
		end
		applyLocalOverheadForUi(payload :: OverheadPayload)
	end

	local function ingestOverheadFullPayload(payload: any)
		if type(payload) ~= "table" or type(payload.userId) ~= "number" then
			return
		end
		overheadPayloadBaselines[payload.userId] = payload
		applyResolvedOverheadPayload(payload)
	end

	local function ingestOverheadDelta(message: any)
		local userId = if type(message) == "table" then message.userId else nil
		local delta = if type(message) == "table" then message.delta else nil
		if type(userId) ~= "number" or type(delta) ~= "table" then
			return
		end
		local base = overheadPayloadBaselines[userId]
		if not base then
			if type(delta.userId) == "number" and type(delta.displayName) == "string" and type(delta.role) == "string" then
				ingestOverheadFullPayload(delta)
			end
			return
		end
		local merged = mergeOverheadDelta(base, delta)
		merged.userId = userId
		overheadPayloadBaselines[userId] = merged
		applyResolvedOverheadPayload(merged)
	end

	local function handleOverheadUpdate(payload: any)
		if type(payload) ~= "table" then
			return
		end

		if payload.kind == Config.Overhead.BATCH_MESSAGE_KIND then
			local payloads = payload.payloads
			if type(payloads) ~= "table" then
				return
			end
			for _, item in ipairs(payloads) do
				ingestOverheadFullPayload(item)
			end
			return
		end

		if payload.kind == Config.Overhead.DELTA_MESSAGE_KIND then
			ingestOverheadDelta(payload)
			return
		end

		ingestOverheadFullPayload(payload)
	end

	local function readLocalSessionFromAttributes()
		if not localPlayer then
			return
		end
		local overheadVisible = localPlayer:GetAttribute("SettingsOverheadVisible")
		if type(overheadVisible) == "boolean" then
			localSession.overheadVisible = overheadVisible
		end
		local hideAllGui = localPlayer:GetAttribute("SettingsHideAllGui")
		if type(hideAllGui) == "boolean" then
			localSession.hideAllGui = hideAllGui
		end
	end

	local function syncSessionFromPayload(payload: SettingsPayload)
		setSessionAttrs({
			overheadVisible = localSession.overheadVisible,
			overheadLayerVisible = payload.overheadLayerVisible,
			overheadBadgeVisible = payload.overheadBadgeVisible,
			hideAllGui = localSession.hideAllGui,
		})
	end

	local function mergePayloadWithLocalSession(serverPayload: SettingsPayload): SettingsPayload
		return SettingsDomain.mergeStoredPreservingSession(localSession, SettingsDomain.sanitizeStored(serverPayload))
	end

	local function payloadForUi(): SettingsPayload
		local uiPayload = table.clone(currentPayload) :: any
		uiPayload.overheadVisible = localSession.overheadVisible
		uiPayload.hideAllGui = localSession.hideAllGui
		uiPayload.hotbarZoom = 35
		uiPayload.graphicsOverrides = table.clone(currentPayload.graphicsOverrides or {})
		return uiPayload :: SettingsPayload
	end

	local function shouldDeferProfileUiSync(): boolean
		-- Only defer authoritative server syncs while a relationship-mode edit is
		-- genuinely in-flight (optimistic value on screen or a debounced send
		-- still pending). Non-relationship edits (title/bio/status/displayName)
		-- fire immediately and the server echoes the saved value, so deferring
		-- them based on profileEditSeq caused a permanent deadlock: the edit's own
		-- ack sync was itself deferred, so profileAckSeq never caught up and every
		-- later authoritative sync (e.g. an admin removing a title) was dropped.
		return panelOpen and (optimisticRelationshipMode ~= nil or next(profilePendingByField) ~= nil)
	end

	local function syncProfileUiFromPayload(forceRebuild: boolean?)
		if forceRebuild == true and type(ui.setProfileData) == "function" then
			ui:setProfileData(currentProfilePayload, { forceRebuild = true })
			return
		end
		if type(ui.patchProfileFromPayload) == "function" then
			ui:patchProfileFromPayload(currentProfilePayload, currentLocalOverheadPayload)
		elseif type(ui.setProfileData) == "function" then
			ui:setProfileData(currentProfilePayload)
		end
	end

	local function hasPendingSettingsEdits(): boolean
		return settingsEditSeq > settingsAckSeq
	end

	local function shouldDeferSettingsUiSync(): boolean
		return panelOpen or hasPendingSettingsEdits() or saveDebounceActive
	end

	local function syncPayloadMirrorToUi()
		if type(ui.syncPayloadMirror) == "function" then
			ui:syncPayloadMirror(payloadForUi())
		end
	end

	local function syncSettingsUiFromPayload(forceRebuild: boolean?)
		local uiPayload = payloadForUi()
		if forceRebuild == true and type(ui.setData) == "function" then
			ui:setData(uiPayload, { forceRebuild = true })
			return
		end
		if type(ui.patchFromPayload) == "function" then
			ui:patchFromPayload(uiPayload)
		elseif type(ui.setData) == "function" then
			ui:setData(uiPayload)
		end
	end

	local function reconcileSettingsAfterClose()
		local deadline = os.clock() + SETTINGS_RECONCILE_TIMEOUT_SEC
		while hasPendingSettingsEdits() and os.clock() < deadline do
			task.wait(0.05)
		end
		syncSettingsUiFromPayload(false)
	end

	local function cloneMutablePayload(payload: SettingsPayload): SettingsPayload
		return {
			cameraFocus = payload.cameraFocus,
			fov = payload.fov,
			smooth = payload.smooth,
			uiScaleMode = payload.uiScaleMode,
			eyeComfortMode = payload.eyeComfortMode,
			colorBrightness = payload.colorBrightness,
			colorContrast = payload.colorContrast,
			colorSaturation = payload.colorSaturation,
			depthOfField = payload.depthOfField,
			playerEffects = payload.playerEffects,
			hideAllParticles = payload.hideAllParticles,
			textures = payload.textures,
			musicVolume = payload.musicVolume,
			_musicVolBase = payload._musicVolBase,
			graphicsPreset = payload.graphicsPreset,
			shadowQuality = payload.shadowQuality,
			overheadDistance = payload.overheadDistance,
			overheadLayerVisible = table.clone(payload.overheadLayerVisible),
			overheadBadgeVisible = table.clone(payload.overheadBadgeVisible),
			chatBubbleVisibility = payload.chatBubbleVisibility,
			hideAdminAnnounce = payload.hideAdminAnnounce,
			hideCoupleAnnounce = payload.hideCoupleAnnounce,
			hideDonationAnnounce = payload.hideDonationAnnounce,
			hideDonationWorldEffect = payload.hideDonationWorldEffect,
			hideDonationAura = payload.hideDonationAura,
			hideDonatorHighlight = payload.hideDonatorHighlight,
			hideSystemAnnounce = payload.hideSystemAnnounce,
			graphicsOverrides = table.clone(payload.graphicsOverrides or {}),
			_version = payload._version,
			overheadVisible = payload.overheadVisible,
			hideAllGui = (payload :: any).hideAllGui == true,
		}
	end

	local function payloadGraphicsSource()
		return {
			graphicsPreset = currentPayload.graphicsPreset,
			textures = currentPayload.textures,
			depthOfField = currentPayload.depthOfField,
			hideAllParticles = currentPayload.hideAllParticles,
			shadowQuality = currentPayload.shadowQuality,
			graphicsOverrides = currentPayload.graphicsOverrides or {},
		}
	end

	local function refreshEffectiveGraphics()
		effectiveGraphics = GraphicsQuality.getEffective(payloadGraphicsSource())
	end

	local function getCurrentCamera(): Camera?
		local cam = Workspace.CurrentCamera
		if cam and cam:IsA("Camera") then
			return cam
		end
		return nil
	end

	local function getPlayerGui(): PlayerGui?
		if not localPlayer then
			return nil
		end
		local gui = localPlayer:FindFirstChildOfClass("PlayerGui")
		if gui then
			return gui
		end
		return nil
	end

	local function getGlobalScaleValue(): number
		return 1
	end

	-- Returns existing RuntimeGlobalUIScale if present. Does NOT create one at
	-- runtime — Instance.new("UIScale") triggers costly layout recalculation for
	-- every child in the ScreenGui. Scale value 1.0 is a no-op anyway. Rely on
	-- templates having the UIScale pre-baked during build.
	local function ensureGlobalScale(screenGui: ScreenGui): UIScale?
		local existing = screenGui:FindFirstChild("RuntimeGlobalUIScale")
		if existing and existing:IsA("UIScale") then
			return existing
		end
		return nil
	end

	local function getBubbleChatConfiguration(): BubbleChatConfiguration?
		local byClass = TextChatService:FindFirstChildOfClass("BubbleChatConfiguration")
		if byClass and byClass:IsA("BubbleChatConfiguration") then
			return byClass
		end
		local byName = TextChatService:FindFirstChild("BubbleChatConfiguration")
		if byName and byName:IsA("BubbleChatConfiguration") then
			return byName
		end
		return nil
	end

	local function getProperty(instance: Instance, propertyName: string): (boolean, any)
		return pcall(function()
			return (instance :: any)[propertyName]
		end)
	end

	local function setProperty(instance: Instance, propertyName: string, value: any)
		pcall(function()
			(instance :: any)[propertyName] = value
		end)
	end

	local function rememberBoolean(instance: Instance, attributeName: string, value: boolean)
		if instance:GetAttribute(attributeName) == nil then
			instance:SetAttribute(attributeName, value)
		end
	end

	local function rememberNumber(instance: Instance, attributeName: string, value: number)
		if instance:GetAttribute(attributeName) == nil then
			instance:SetAttribute(attributeName, value)
		end
	end

	local function rememberString(instance: Instance, attributeName: string, value: string)
		if instance:GetAttribute(attributeName) == nil then
			instance:SetAttribute(attributeName, value)
		end
	end

	local function rememberStringProperty(instance: Instance, attributeName: string, propertyName: string)
		local ok, value = getProperty(instance, propertyName)
		if ok and type(value) == "string" then
			rememberString(instance, attributeName, value)
		end
	end

	local function restoreStringProperty(instance: Instance, attributeName: string, propertyName: string)
		local original = instance:GetAttribute(attributeName)
		if type(original) == "string" then
			setProperty(instance, propertyName, original)
		end
	end

	local function isManagedBlurEffect(instance: Instance): boolean
		if not instance:IsA("BlurEffect") then
			return false
		end
		if MANAGED_BLUR_EFFECT_NAMES[instance.Name] == true then
			return true
		end
		return string.find(instance.Name, "Blur") ~= nil
	end

	local function suppressManagedBlurEffect(instance: Instance)
		if not isManagedBlurEffect(instance) then
			return
		end

		local blur = instance :: BlurEffect
		blur.Size = 0
		blur.Enabled = false
	end

	local function suppressManagedBlurEffects()
		for _, child in ipairs(Lighting:GetChildren()) do
			suppressManagedBlurEffect(child)
		end
	end

	local function shouldEnableShadows(): boolean
		return effectiveGraphics.globalShadows
	end

	local function shouldEnableTextures(): boolean
		return effectiveGraphics.textures > 0
	end

	local function applyShadowSettingToInstance(instance: Instance, enabled: boolean)
		if instance:IsA("BasePart") then
			local part = instance :: BasePart
			rememberBoolean(part, ORIGINAL_CAST_SHADOW_ATTRIBUTE, part.CastShadow)
			local original = part:GetAttribute(ORIGINAL_CAST_SHADOW_ATTRIBUTE)
			part.CastShadow = if enabled and type(original) == "boolean" then original else false
			return
		end

		if instance:IsA("PointLight") or instance:IsA("SpotLight") or instance:IsA("SurfaceLight") then
			local ok, current = getProperty(instance, "Shadows")
			if ok and type(current) == "boolean" then
				rememberBoolean(instance, ORIGINAL_LIGHT_SHADOWS_ATTRIBUTE, current)
				local original = instance:GetAttribute(ORIGINAL_LIGHT_SHADOWS_ATTRIBUTE)
				setProperty(instance, "Shadows", if enabled and type(original) == "boolean" then original else false)
			end
		end
	end

	local function applyTextureSettingToInstance(instance: Instance, enabled: boolean)
		if instance:IsA("BasePart") then
			local part = instance :: BasePart
			rememberString(part, ORIGINAL_MATERIAL_ATTRIBUTE, part.Material.Name)
			rememberStringProperty(part, ORIGINAL_MATERIAL_VARIANT_ATTRIBUTE, "MaterialVariant")

			if enabled then
				local materialName = part:GetAttribute(ORIGINAL_MATERIAL_ATTRIBUTE)
				if type(materialName) == "string" then
					local material = (Enum.Material :: any)[materialName]
					if material then
						part.Material = material
					end
				end
				restoreStringProperty(part, ORIGINAL_MATERIAL_VARIANT_ATTRIBUTE, "MaterialVariant")
			else
				if part.Anchored then
					part.Material = Enum.Material.SmoothPlastic
				end
				setProperty(part, "MaterialVariant", "")
			end

			if instance:IsA("MeshPart") then
				rememberStringProperty(instance, ORIGINAL_TEXTURE_ID_ATTRIBUTE, "TextureID")
				if enabled then
					restoreStringProperty(instance, ORIGINAL_TEXTURE_ID_ATTRIBUTE, "TextureID")
				else
					setProperty(instance, "TextureID", "")
				end
			end
		end

		if instance:IsA("Decal") or instance:IsA("Texture") then
			rememberStringProperty(instance, ORIGINAL_TEXTURE_ATTRIBUTE, "Texture")
			local ok, transparency = getProperty(instance, "Transparency")
			if ok and type(transparency) == "number" then
				rememberNumber(instance, ORIGINAL_TRANSPARENCY_ATTRIBUTE, transparency)
			end

			if enabled then
				restoreStringProperty(instance, ORIGINAL_TEXTURE_ATTRIBUTE, "Texture")
				local originalTransparency = instance:GetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE)
				if type(originalTransparency) == "number" then
					setProperty(instance, "Transparency", originalTransparency)
				end
			else
				setProperty(instance, "Texture", "")
				setProperty(instance, "Transparency", 1)
			end
		end

		if instance:IsA("SpecialMesh") then
			rememberStringProperty(instance, ORIGINAL_TEXTURE_ID_ATTRIBUTE, "TextureId")
			if enabled then
				restoreStringProperty(instance, ORIGINAL_TEXTURE_ID_ATTRIBUTE, "TextureId")
			else
				setProperty(instance, "TextureId", "")
			end
		end

		if instance:IsA("SurfaceAppearance") then
			rememberStringProperty(instance, ORIGINAL_SURFACE_COLOR_MAP_ATTRIBUTE, "ColorMap")
			rememberStringProperty(instance, ORIGINAL_SURFACE_METALNESS_MAP_ATTRIBUTE, "MetalnessMap")
			rememberStringProperty(instance, ORIGINAL_SURFACE_NORMAL_MAP_ATTRIBUTE, "NormalMap")
			rememberStringProperty(instance, ORIGINAL_SURFACE_ROUGHNESS_MAP_ATTRIBUTE, "RoughnessMap")

			if enabled then
				restoreStringProperty(instance, ORIGINAL_SURFACE_COLOR_MAP_ATTRIBUTE, "ColorMap")
				restoreStringProperty(instance, ORIGINAL_SURFACE_METALNESS_MAP_ATTRIBUTE, "MetalnessMap")
				restoreStringProperty(instance, ORIGINAL_SURFACE_NORMAL_MAP_ATTRIBUTE, "NormalMap")
				restoreStringProperty(instance, ORIGINAL_SURFACE_ROUGHNESS_MAP_ATTRIBUTE, "RoughnessMap")
			else
				setProperty(instance, "ColorMap", "")
				setProperty(instance, "MetalnessMap", "")
				setProperty(instance, "NormalMap", "")
				setProperty(instance, "RoughnessMap", "")
			end
		end

		if instance:IsA("Terrain") then
			local ok, decoration = getProperty(instance, "Decoration")
			if ok and type(decoration) == "boolean" then
				rememberBoolean(instance, ORIGINAL_TERRAIN_DECORATION_ATTRIBUTE, decoration)
				local original = instance:GetAttribute(ORIGINAL_TERRAIN_DECORATION_ATTRIBUTE)
				setProperty(instance, "Decoration", if enabled and type(original) == "boolean" then original else false)
			end
		end
	end

	local function applyRenderSettingToInstance(instance: Instance)
		applyShadowSettingToInstance(instance, shouldEnableShadows())
		applyTextureSettingToInstance(instance, shouldEnableTextures())
	end

	local function collectTaggedRoots(tagName: string): { Instance }
		local roots: { Instance } = {}
		for _, instance in ipairs(CollectionService:GetTagged(tagName)) do
			table.insert(roots, instance)
		end
		return roots
	end

	local function getGeometryApplyRoots(): { Instance }
		local tagged = collectTaggedRoots(graphicsCfg.SCALABLE_GEOMETRY_TAG)
		if #tagged > 0 then
			return tagged
		end

		local fallbackNames = graphicsCfg.GEOMETRY_FALLBACK_ROOT_NAMES or {}
		local fallbackRoots: { Instance } = {}
		for _, name in ipairs(fallbackNames) do
			local child = Workspace:FindFirstChild(name)
			if child then
				table.insert(fallbackRoots, child)
			end
		end
		if #fallbackRoots > 0 then
			return fallbackRoots
		end

		return {}
	end

	local function applyWorkspaceRenderSettings()
		local shadowsEnabled = shouldEnableShadows()
		local texturesEnabled = shouldEnableTextures()

		if appliedShadowsEnabled == shadowsEnabled and appliedTexturesEnabled == texturesEnabled then
			return
		end
		appliedShadowsEnabled = shadowsEnabled
		appliedTexturesEnabled = texturesEnabled

		local roots = getGeometryApplyRoots()
		if #roots == 0 then
			return
		end

		renderSettingsGeneration += 1
		local generation = renderSettingsGeneration

		task.spawn(function()
			local processed = 0
			for _, root in ipairs(roots) do
				if generation ~= renderSettingsGeneration then
					return
				end
				applyShadowSettingToInstance(root, shadowsEnabled)
				applyTextureSettingToInstance(root, texturesEnabled)
				processed += 1
				for _, descendant in ipairs(root:GetDescendants()) do
					if generation ~= renderSettingsGeneration then
						return
					end
					applyShadowSettingToInstance(descendant, shadowsEnabled)
					applyTextureSettingToInstance(descendant, texturesEnabled)
					processed += 1
					if processed % 250 == 0 then
						task.wait()
					end
				end
			end
		end)
	end

	local function rememberPostFxEnabled(instance: Instance)
		if not instance:IsA("PostEffect") then
			return
		end
		local postEffect = instance :: PostEffect
		if instance:GetAttribute(ORIGINAL_POSTFX_ENABLED_ATTRIBUTE) == nil then
			instance:SetAttribute(ORIGINAL_POSTFX_ENABLED_ATTRIBUTE, postEffect.Enabled)
		end
	end

	local function applyAtmosphereSetting(instance: Instance, mode: GraphicsQuality.PostProcessingMode)
		if not instance:IsA("Atmosphere") then
			return
		end
		local atmosphere = instance :: Atmosphere
		if atmosphere:GetAttribute(ORIGINAL_ATMOSPHERE_DENSITY_ATTRIBUTE) == nil then
			atmosphere:SetAttribute(ORIGINAL_ATMOSPHERE_DENSITY_ATTRIBUTE, atmosphere.Density)
		end
		local originalDensity = atmosphere:GetAttribute(ORIGINAL_ATMOSPHERE_DENSITY_ATTRIBUTE)
		local baseDensity = if type(originalDensity) == "number" then originalDensity else atmosphere.Density
		if mode == "Minimal" then
			atmosphere.Density = 0
		else
			atmosphere.Density = baseDensity
		end
	end

	local function applyPostProcessingSetting(instance: Instance, mode: GraphicsQuality.PostProcessingMode)
		if instance.Name == SETTINGS_DEPTH_OF_FIELD_NAME
			or instance.Name == "RuntimeSettingsEyeComfort"
			or instance.Name == SETTINGS_COLOR_TUNE_NAME
			or instance.Name == "RuntimeSettingsMenuBackdrop"
		then
			return
		end
		if instance:IsA("BlurEffect") and MANAGED_BLUR_EFFECT_NAMES[instance.Name] then
			return
		end

		if instance:IsA("Atmosphere") then
			applyAtmosphereSetting(instance, mode)
			return
		end

		local classEnabled = false
		for _, className in ipairs(POST_PROCESSING_CLASSES) do
			if instance:IsA(className) then
				classEnabled = true
				break
			end
		end
		if not classEnabled then
			if instance:IsA("BlurEffect") then
				classEnabled = true
			else
				return
			end
		end

		if not instance:IsA("PostEffect") then
			return
		end

		rememberPostFxEnabled(instance)
		local postEffect = instance :: PostEffect
		local original = instance:GetAttribute(ORIGINAL_POSTFX_ENABLED_ATTRIBUTE)
		local originalEnabled = type(original) == "boolean" and original or postEffect.Enabled

		if mode == "Minimal" then
			postEffect.Enabled = false
			return
		end

		postEffect.Enabled = originalEnabled
	end

	local function applyPostProcessing(mode: GraphicsQuality.PostProcessingMode)
		if appliedPostProcessing == mode then
			return
		end
		appliedPostProcessing = mode
		for _, child in ipairs(Lighting:GetChildren()) do
			applyPostProcessingSetting(child, mode)
		end
	end

	local function rememberParticleRate(emitter: ParticleEmitter)
		if emitter:GetAttribute(ORIGINAL_PARTICLE_RATE_ATTRIBUTE) == nil then
			emitter:SetAttribute(ORIGINAL_PARTICLE_RATE_ATTRIBUTE, emitter.Rate)
		end
	end

	local function applyWorkspaceVfxInstance(instance: Instance, mode: GraphicsQuality.WorkspaceVfxMode)
		local rateScale = (graphicsCfg.WORKSPACE_VFX_RATE :: any)[mode] or 1

		if instance:IsA("ParticleEmitter") then
			local emitter = instance :: ParticleEmitter
			rememberParticleRate(emitter)
			local originalRate = emitter:GetAttribute(ORIGINAL_PARTICLE_RATE_ATTRIBUTE)
			local baseRate = if type(originalRate) == "number" then originalRate else emitter.Rate
			emitter.Rate = math.max(0, baseRate * rateScale)
			emitter.Enabled = emitter.Rate > 0.01
			return
		end

		for _, className in ipairs(WORKSPACE_VFX_CLASSES) do
			if className ~= "ParticleEmitter" and instance:IsA(className) then
				local effect = instance :: any
				if instance:GetAttribute("RuntimeSettingsOriginalEnabled") == nil then
					instance:SetAttribute("RuntimeSettingsOriginalEnabled", effect.Enabled == true)
				end
				local original = instance:GetAttribute("RuntimeSettingsOriginalEnabled")
				local originalEnabled = type(original) == "boolean" and original or effect.Enabled == true
				effect.Enabled = originalEnabled and rateScale > 0.15
				return
			end
		end

		if instance:IsA("PointLight") or instance:IsA("SpotLight") or instance:IsA("SurfaceLight") then
			local light = instance :: any
			if light:GetAttribute(ORIGINAL_LIGHT_RANGE_ATTRIBUTE) == nil then
				light:SetAttribute(ORIGINAL_LIGHT_RANGE_ATTRIBUTE, light.Range)
			end
			if light:GetAttribute(ORIGINAL_WORKSPACE_LIGHT_SHADOWS_ATTRIBUTE) == nil then
				light:SetAttribute(ORIGINAL_WORKSPACE_LIGHT_SHADOWS_ATTRIBUTE, light.Shadows == true)
			end
			local originalRange = light:GetAttribute(ORIGINAL_LIGHT_RANGE_ATTRIBUTE)
			local baseRange = if type(originalRange) == "number" then originalRange else light.Range
			if mode == "Off" then
				light.Shadows = false
				light.Range = baseRange * 0.75
			elseif mode == "Reduced" then
				light.Shadows = false
				light.Range = baseRange * 0.9
			else
				local originalShadows = light:GetAttribute(ORIGINAL_WORKSPACE_LIGHT_SHADOWS_ATTRIBUTE)
				light.Shadows = if type(originalShadows) == "boolean" then originalShadows else light.Shadows
				light.Range = baseRange
			end
		end
	end

	local function applyWorkspaceVfx(mode: GraphicsQuality.WorkspaceVfxMode)
		if appliedWorkspaceVfxMode == mode then
			return
		end
		appliedWorkspaceVfxMode = mode
		workspaceVfxGeneration += 1
		local generation = workspaceVfxGeneration
		local roots = collectTaggedRoots(graphicsCfg.SCALABLE_VFX_TAG)

		task.spawn(function()
			local processed = 0
			for _, root in ipairs(roots) do
				if generation ~= workspaceVfxGeneration then
					return
				end
				local batch = { root }
				for _, descendant in ipairs(root:GetDescendants()) do
					table.insert(batch, descendant)
				end
				for _, instance in ipairs(batch) do
					if generation ~= workspaceVfxGeneration then
						return
					end
					applyWorkspaceVfxInstance(instance, mode)
					processed += 1
					if processed % 200 == 0 then
						task.wait()
					end
				end
			end
		end)
	end

	local function getDonationAuraScale(): number
		if currentPayload.hideDonationAura then
			return 0
		end
		return effectiveGraphics.donationVfxScale
	end

	local function applyDonationEffectScale(root: Instance, scale: number)
		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("ParticleEmitter") then
				local emitter = descendant :: ParticleEmitter
				rememberParticleRate(emitter)
				local originalRate = emitter:GetAttribute(ORIGINAL_PARTICLE_RATE_ATTRIBUTE)
				local baseRate = if type(originalRate) == "number" then originalRate else emitter.Rate
				if scale <= 0.05 then
					emitter.Enabled = false
				else
					emitter.Enabled = baseRate > 0
					emitter.Rate = math.max(0, baseRate * scale)
				end
			elseif descendant:IsA("Beam") or descendant:IsA("Trail") then
				local effect = descendant :: any
				if scale <= 0.05 then
					effect.Enabled = false
				end
			elseif descendant:IsA("PointLight") or descendant:IsA("SpotLight") or descendant:IsA("SurfaceLight") then
				local light = descendant :: PointLight | SpotLight | SurfaceLight
				rememberBoolean(light, "RuntimeSettingsOriginalLightEnabled", light.Enabled)
				if scale <= 0.05 then
					light.Enabled = false
				else
					local original = light:GetAttribute("RuntimeSettingsOriginalLightEnabled")
					if type(original) == "boolean" then
						light.Enabled = original
					end
				end
			end
		end
	end

	local function applyAllDonationEffects()
		local scale = getDonationAuraScale()
		for _, effect in ipairs(CollectionService:GetTagged("DonationEffect")) do
			applyDonationEffectScale(effect, scale)
		end
	end

	local function isManagedPlayerEffect(inst: Instance): boolean
		return inst:IsA("ParticleEmitter")
			or inst:IsA("Trail")
			or inst:IsA("Beam")
			or inst:IsA("Fire")
			or inst:IsA("Smoke")
			or inst:IsA("Sparkles")
	end

	local function shouldShowCharacterEffects(_player: Player): boolean
		return not effectiveGraphics.hideAllParticles
	end

	local function getManagedEffectOriginalEnabled(inst: Instance): boolean
		local original = inst:GetAttribute("RuntimeSettingsOriginalEnabled")
		if type(original) == "boolean" then
			return original
		end

		local enabled = false
		if isManagedPlayerEffect(inst) then
			enabled = (inst :: any).Enabled == true
		end
		inst:SetAttribute("RuntimeSettingsOriginalEnabled", enabled)
		return enabled
	end

	local function setManagedPlayerEffectEnabled(inst: Instance, visible: boolean)
		if not isManagedPlayerEffect(inst) then
			return
		end

		local effect = inst :: any
		local originalEnabled = getManagedEffectOriginalEnabled(inst)
		if visible then
			effect.Enabled = originalEnabled
		else
			effect.Enabled = false
			if inst:IsA("ParticleEmitter") then
				pcall(function()
					(inst :: ParticleEmitter):Clear()
				end)
			end
		end
	end

	local function applyCharacterEffectVisibility(player: Player, character: Model)
		local shouldShowEffects = shouldShowCharacterEffects(player)
		for _, desc in ipairs(character:GetDescendants()) do
			setManagedPlayerEffectEnabled(desc, shouldShowEffects)
		end
	end

	local function trackPlayerEffectCharacter(player: Player)
		local previousCharacterConn = trackedEffectCharacterConns[player]
		if previousCharacterConn then
			previousCharacterConn:Disconnect()
			trackedEffectCharacterConns[player] = nil
		end

		local previousDescendantConn = trackedEffectDescendantConns[player]
		if previousDescendantConn then
			previousDescendantConn:Disconnect()
			trackedEffectDescendantConns[player] = nil
		end

		local function bindCharacter(character: Model)
			local previous = trackedEffectDescendantConns[player]
			if previous then
				previous:Disconnect()
			end

			applyCharacterEffectVisibility(player, character)
			trackedEffectDescendantConns[player] = character.DescendantAdded:Connect(function(desc)
				setManagedPlayerEffectEnabled(desc, shouldShowCharacterEffects(player))
			end)
		end

		trackedEffectCharacterConns[player] = player.CharacterAdded:Connect(function(character)
			task.defer(function()
				if character.Parent then
					bindCharacter(character)
				end
			end)
		end)

		if player.Character then
			bindCharacter(player.Character)
		end
	end

	local function trackAllPlayerEffectCharacters()
		for _, player in ipairs(Players:GetPlayers()) do
			trackPlayerEffectCharacter(player)
		end
	end

	local function focusOffset(mode: string): Vector3
		if mode == "Head" then
			return Vector3.new(0, 2.4, 0.4)
		elseif mode == "FullBody" then
			return Vector3.new(0, 0.8, 2.6)
		end
		return Vector3.new(0, 1.5, 0.8)
	end

	local function getMenuPreviewOffset(): Vector3?
		if not menuPreviewVisible then
			return nil
		end

		local camera = getCurrentCamera()
		if not camera then
			return Vector3.new(0.75, 2.0, 1.8)
		end

		local panelLeftX = nil
		if type(ui.getPanelLeftScreenX) == "function" then
			panelLeftX = ui:getPanelLeftScreenX()
		end

		local viewportWidth = camera.ViewportSize.X
		if not panelLeftX or viewportWidth <= 0 then
			return Vector3.new(0.75, 2.0, 1.8)
		end

		local desiredCenterX = panelLeftX * 0.5
		local screenCenterX = viewportWidth * 0.5
		local shiftRatio = math.clamp((screenCenterX - desiredCenterX) / viewportWidth, 0, 0.25)
		local horizontalOffset = 0.4 + (shiftRatio * 6.5)
		return Vector3.new(horizontalOffset, 2.0, 1.8)
	end

	local function getSmoothFactor(): number
		return 0.5
	end

	local function applyHotbarZoom(_percent: number?)
		Config.Hotbar.STATE_A.SCALE = 1.0
		if Config.Hotbar.DOCK_ZOOM_ENABLED ~= true then
			Config.Hotbar.STATE_B.SCALE = 1.0
			Config.Hotbar.STATE_C.SCALE = 1.0
			return
		end
		local multiplier = 0.35
		Config.Hotbar.STATE_B.SCALE = 1.0 + ((HOTBAR_STATE_B_BASE_SCALE - 1.0) * multiplier)
		Config.Hotbar.STATE_C.SCALE = 1.0 + ((HOTBAR_STATE_C_BASE_SCALE - 1.0) * multiplier)
	end

	local function applyCameraFocus()
		-- DISABLED 2026-05-23: "Follow" (cameraFocus) di-revert ke Roblox default.
		-- Reset CameraOffset ke zero supaya kalau session sebelumnya nge-set offset
		-- (Torso/Head/FullBody), efeknya ilang. FOV slider tetep di-apply di sini
		-- karena FOV beda dari follow offset.
		if cameraTween then
			cameraTween:Cancel()
			cameraTween = nil
		end
		local player = localPlayer
		local character = player and player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.CameraOffset = Vector3.zero
		end

		local camera = getCurrentCamera()
		if camera then
			local targetFov = math.clamp(currentPayload.fov, 60, 100)
			if math.abs(camera.FieldOfView - targetFov) > 0.05 then
				camera.FieldOfView = targetFov
			end
		end
	end

	local function applyDepthOfField()
		if fovSliderDragDepth > 0 then
			local suspended = Lighting:FindFirstChild(SETTINGS_DEPTH_OF_FIELD_NAME)
			if suspended and suspended:IsA("DepthOfFieldEffect") then
				suspended.Enabled = false
			end
			return
		end

		local depthOfField = effectiveGraphics.depthOfField
		local backgroundBlurEnabled = depthOfField > 0
		setAttr(SETTINGS_BACKGROUND_BLUR_ATTRIBUTE, backgroundBlurEnabled)

		local existing = Lighting:FindFirstChild(SETTINGS_DEPTH_OF_FIELD_NAME)
		if depthOfField <= 0 then
			if existing then
				existing:Destroy()
			end
			suppressManagedBlurEffects()
			return
		end

		local effect = existing
		if not effect or not effect:IsA("DepthOfFieldEffect") then
			effect = Instance.new("DepthOfFieldEffect")
			effect.Name = SETTINGS_DEPTH_OF_FIELD_NAME
			effect.Parent = Lighting
		end

		local ratio = depthOfField / 3
		local depthOfFieldEffect = effect :: DepthOfFieldEffect
		depthOfFieldEffect.Enabled = true
		depthOfFieldEffect.FarIntensity = 0.24 * ratio
		depthOfFieldEffect.NearIntensity = 0
		depthOfFieldEffect.FocusDistance = 14
		depthOfFieldEffect.InFocusRadius = 18 - 6 * ratio
	end

	local function sliderToColorCorrection(sliderValue: number): number
		return math.clamp((sliderValue - 50) / 50, -1, 1)
	end

	local function isColorTuneNeutral(): boolean
		return currentPayload.colorSaturation == 50
			and currentPayload.colorContrast == 50
			and currentPayload.colorBrightness == 50
	end

	local function applyColorTune()
		local existing = Lighting:FindFirstChild(SETTINGS_COLOR_TUNE_NAME)
		if isColorTuneNeutral() then
			if existing then
				existing:Destroy()
			end
			return
		end

		local effect = existing
		if not effect or not effect:IsA("ColorCorrectionEffect") then
			effect = Instance.new("ColorCorrectionEffect")
			effect.Name = SETTINGS_COLOR_TUNE_NAME
			effect.Parent = Lighting
		end

		local cc = effect :: ColorCorrectionEffect
		cc.Enabled = true
		cc.TintColor = Color3.fromRGB(255, 255, 255)
		cc.Saturation = sliderToColorCorrection(currentPayload.colorSaturation)
		cc.Contrast = sliderToColorCorrection(currentPayload.colorContrast)
		cc.Brightness = sliderToColorCorrection(currentPayload.colorBrightness)
	end

	local function applyEyeComfort()
		local existing = Lighting:FindFirstChild("RuntimeSettingsEyeComfort")
		if not currentPayload.eyeComfortMode then
			if existing then
				existing:Destroy()
			end
			return
		end

		local effect = existing
		if not effect or not effect:IsA("ColorCorrectionEffect") then
			effect = Instance.new("ColorCorrectionEffect")
			effect.Name = "RuntimeSettingsEyeComfort"
			effect.Parent = Lighting
		end

		local cc = effect :: ColorCorrectionEffect
		cc.Enabled = true
		cc.Brightness = -0.05
		cc.Contrast = 0.04
		cc.Saturation = -0.12
		cc.TintColor = Color3.fromRGB(255, 238, 214)
	end

	local function applyUiScale()
		local playerGui = getPlayerGui()
		if not playerGui then
			return
		end

		local scaleValue = getGlobalScaleValue()
			for _, child in ipairs(playerGui:GetChildren()) do
				if child:IsA("ScreenGui") then
					local uiscale = ensureGlobalScale(child)
					if uiscale then
						uiscale.Scale = scaleValue
					end
				end
			end
	end

	local function applyGraphicsPreset()
		local shadowsEnabled = shouldEnableShadows()
		local texturesEnabled = shouldEnableTextures()
		local shadowSoftness = effectiveGraphics.shadowSoftness
		if effectiveGraphics.shadowQuality == "Off" then
			shadowSoftness = 0
		end

		setAttr(SETTINGS_SHADOWS_ATTRIBUTE, shadowsEnabled)
		setAttr(SETTINGS_TEXTURES_ATTRIBUTE, texturesEnabled)
		setAttr("SettingsGraphicsPreset", effectiveGraphics.graphicsPreset)
		setAttr("SettingsGraphicsTier", effectiveGraphics.graphicsTier)
		setAttr("SettingsDonationVfxScale", effectiveGraphics.donationVfxScale)
		setAttr("SettingsCinematicExtras", effectiveGraphics.cinematicExtras)
		setAttr("SettingsHideAllParticles", effectiveGraphics.hideAllParticles == true)

		-- Only set Lighting properties if values actually changed
		-- to avoid triggering engine re-render unnecessarily.
		if Lighting.GlobalShadows ~= shadowsEnabled then
			Lighting.GlobalShadows = shadowsEnabled
		end
		local currentShadowSoftness = Lighting.ShadowSoftness
		if math.abs(currentShadowSoftness - shadowSoftness) > 0.001 then
			Lighting.ShadowSoftness = shadowSoftness
		end

		local textureScale = math.clamp(effectiveGraphics.textures / 2, 0, 1)
		local diffuseScale = 0.45 + (0.55 * textureScale)
		local specularScale = 0.4 + (0.6 * textureScale)
		if math.abs(Lighting.EnvironmentDiffuseScale - diffuseScale) > 0.001 then
			Lighting.EnvironmentDiffuseScale = diffuseScale
		end
		if math.abs(Lighting.EnvironmentSpecularScale - specularScale) > 0.001 then
			Lighting.EnvironmentSpecularScale = specularScale
		end

		applyPostProcessing(effectiveGraphics.postProcessing)
		applyWorkspaceVfx(effectiveGraphics.workspaceVfxMode)
		applyAllDonationEffects()

		if appliedShadowsEnabled ~= shadowsEnabled or appliedTexturesEnabled ~= texturesEnabled then
			applyWorkspaceRenderSettings()
		end
	end

	local function setMenuBackdropEffectEnabled(enabled: boolean)
		local existing = Lighting:FindFirstChild("RuntimeSettingsMenuBackdrop")
		if not enabled then
			if existing then
				existing:Destroy()
			end
			return
		end

		local effect = existing
		if not effect or not effect:IsA("ColorCorrectionEffect") then
			effect = Instance.new("ColorCorrectionEffect")
			effect.Name = "RuntimeSettingsMenuBackdrop"
			effect.Parent = Lighting
		end

		local cc = effect :: ColorCorrectionEffect
		cc.Enabled = true
		cc.Brightness = -0.04
		cc.Contrast = 0.02
		cc.Saturation = -1
		cc.TintColor = Color3.fromRGB(255, 255, 255)
	end

	local function applyPlayerEffects()
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			if character then
				applyCharacterEffectVisibility(player, character)
			end
		end
	end

	local function applyChatBubbleVisibility()
		local bubbleConfig = getBubbleChatConfiguration()
		if not bubbleConfig then
			return
		end

		if currentPayload.chatBubbleVisibility == "Off" then
			bubbleConfig.Enabled = false
			return
		end

		bubbleConfig.Enabled = true
		if currentPayload.chatBubbleVisibility == "Nearby" then
			bubbleConfig.MaxDistance = CHAT_BUBBLE_NEARBY_DISTANCE
		else
			bubbleConfig.MaxDistance = CHAT_BUBBLE_EVERYONE_DISTANCE
		end
	end

	local function applySessionAttrs()
		syncSessionFromPayload(currentPayload)
		setAttr("SettingsOverheadDistance", currentPayload.overheadDistance)
		setAttr("SettingsHideAdminAnnounce", currentPayload.hideAdminAnnounce)
		setAttr("SettingsHideCoupleAnnounce", currentPayload.hideCoupleAnnounce)
		setAttr("SettingsHideDonationAnnounce", currentPayload.hideDonationAnnounce)
		setAttr("SettingsHideDonationWorldEffect", currentPayload.hideDonationWorldEffect)
		setAttr("SettingsHideDonationAura", currentPayload.hideDonationAura)
		setAttr("SettingsHideDonatorHighlight", currentPayload.hideDonatorHighlight)
		setAttr("SettingsHideSystemAnnounce", currentPayload.hideSystemAnnounce)
		setAttr("SettingsMusicVolume", math.clamp((tonumber(currentPayload.musicVolume) or 100) / 100, 0, 1))
	end

	local function applyHideAllGui()
		local hide = currentPayload.hideAllGui == true
		pcall(function()
			StarterGui:SetCore("TopbarEnabled", not hide)
		end)
		local playerGui = getPlayerGui()
		if not playerGui then
			return
		end
		for _, child in ipairs(playerGui:GetChildren()) do
			if child:IsA("ScreenGui") and child.Name ~= SETTINGS_GUI_NAME then
				if hide then
					if child:GetAttribute(SETTINGS_HIDE_ALL_GUI_ORIGINAL) == nil then
						child:SetAttribute(SETTINGS_HIDE_ALL_GUI_ORIGINAL, child.Enabled)
					end
					child.Enabled = false
				else
					local original = child:GetAttribute(SETTINGS_HIDE_ALL_GUI_ORIGINAL)
					if type(original) == "boolean" then
						child.Enabled = original
						child:SetAttribute(SETTINGS_HIDE_ALL_GUI_ORIGINAL, nil)
					end
				end
			end
		end
	end

	local function applyAllEffects()
		refreshEffectiveGraphics()
		applyUiScale()
		applyCameraFocus()
		applyDepthOfField()
		applyColorTune()
		applyEyeComfort()
		applyGraphicsPreset()
		applyPlayerEffects()
		applyChatBubbleVisibility()
		applySessionAttrs()
		applyHideAllGui()
	end

	-- Lighter version of applyAllEffects that skips player effects scan.
	-- Called for fields that don't affect particle visibility (fov, music, chat, etc.).
	local function applyEffectsWithoutPlayerScan()
		refreshEffectiveGraphics()
		applyUiScale()
		applyCameraFocus()
		applyDepthOfField()
		applyColorTune()
		applyEyeComfort()
		applyGraphicsPreset()
		applyChatBubbleVisibility()
		applySessionAttrs()
		applyHideAllGui()
	end

	local function fieldNeedsSaveNotif(field: string): boolean
		if field == "__reset__" then
			return true
		end
		return field:match("^overheadLayerVisible%.") ~= nil or field:match("^overheadBadgeVisible%.") ~= nil
	end

	local function overheadDetailLabel(field: string): string?
		local layerKey = string.match(field, "^overheadLayerVisible%.(.+)$")
		if layerKey then
			return OVERHEAD_LAYER_LABELS[layerKey] or layerKey
		end
		local badgeKey = string.match(field, "^overheadBadgeVisible%.(.+)$")
		if badgeKey then
			return OVERHEAD_BADGE_LABELS[badgeKey] or badgeKey
		end
		return nil
	end

	local function buildSettingsNotifCopy(field: string, value: any, phase: "pending" | "ok"): { title: string, message: string, description: string }
		if field == "reset" or field == "__reset__" then
			if phase == "pending" then
				return {
					title = "Settings",
					message = "Resetting everything...",
					description = "Bringing all settings back to default.",
				}
			end
			return {
				title = "Settings",
				message = "All set — defaults restored",
				description = "Your settings are back to the original setup.",
			}
		end

		local overheadLabel = overheadDetailLabel(field)
		if overheadLabel then
			if phase == "pending" then
				return {
					title = "Name Tags",
					message = "Updating " .. overheadLabel:lower() .. " on name tags...",
					description = "Syncing this with what others can see above your head.",
				}
			end
			return {
				title = "Name Tags",
				message = overheadLabel .. " updated on name tags",
				description = "Name tag visibility saved.",
			}
		end

		return {
			title = "Name Tags",
			message = if phase == "pending" then "Updating name tags..." else "Name tags updated",
			description = if phase == "pending"
				then "Syncing visibility with the server."
				else "Visibility is saved.",
		}
	end

	local function showSettingsSaveNotif(field: string, value: any, phase: "pending" | "ok")
		local copy = buildSettingsNotifCopy(field, value, phase)
		NotifService.show({
			message = copy.message,
			title = copy.title,
			description = copy.description,
			notifType = if phase == "pending" then "INFO" else "SUCCESS",
			domain = "settings",
			dedupeKey = if phase == "pending" then SETTINGS_NOTIF_DEDUPE_PENDING else SETTINGS_NOTIF_DEDUPE_OK,
			duration = if phase == "pending" then 2.8 else nil,
		})
	end

	local function markPendingSaveNotif(field: string, value: any)
		if not fieldNeedsSaveNotif(field) then
			return
		end
		pendingSaveNotifField = field
		pendingSaveNotifValue = value
		showSettingsSaveNotif(field, value, "pending")
	end

	local function showSettingsSaveAcknowledged(overrideField: string?, overrideValue: any?)
		local field = overrideField or pendingSaveNotifField
		local value = if overrideField ~= nil then overrideValue else pendingSaveNotifValue
		if not field then
			return
		end
		pendingSaveNotifField = nil
		pendingSaveNotifValue = nil
		showSettingsSaveNotif(field, value, "ok")
	end

	local function buildStoredPayload(): SettingsStoredData
		return {
			cameraFocus = currentPayload.cameraFocus,
			fov = currentPayload.fov,
			smooth = currentPayload.smooth,
			uiScaleMode = currentPayload.uiScaleMode,
			eyeComfortMode = currentPayload.eyeComfortMode,
			colorBrightness = currentPayload.colorBrightness,
			colorContrast = currentPayload.colorContrast,
			colorSaturation = currentPayload.colorSaturation,
			depthOfField = currentPayload.depthOfField,
			playerEffects = currentPayload.playerEffects,
			hideAllParticles = currentPayload.hideAllParticles,
			textures = currentPayload.textures,
			musicVolume = currentPayload.musicVolume,
			_musicVolBase = math.max(
				tonumber(currentPayload._musicVolBase) or 0,
				SettingsDomain.MUSIC_VOLUME_BASE_SCHEMA
			),
			graphicsPreset = currentPayload.graphicsPreset,
			shadowQuality = currentPayload.shadowQuality,
			overheadDistance = currentPayload.overheadDistance,
			overheadLayerVisible = table.clone(currentPayload.overheadLayerVisible),
			overheadBadgeVisible = table.clone(currentPayload.overheadBadgeVisible),
			chatBubbleVisibility = currentPayload.chatBubbleVisibility,
			hideAdminAnnounce = currentPayload.hideAdminAnnounce,
			hideCoupleAnnounce = currentPayload.hideCoupleAnnounce,
			hideDonationAnnounce = currentPayload.hideDonationAnnounce,
			hideDonationWorldEffect = currentPayload.hideDonationWorldEffect,
			hideDonationAura = currentPayload.hideDonationAura,
			hideDonatorHighlight = currentPayload.hideDonatorHighlight,
			hideSystemAnnounce = currentPayload.hideSystemAnnounce,
			graphicsOverrides = table.clone(currentPayload.graphicsOverrides or {}),
			_version = math.max(currentPayload._version, GraphicsQuality.STORED_VERSION),
		}
	end

	local function fireSettingsSave()
		if not updateRemote or not updateRemote:IsA("RemoteEvent") then
			log:warn("Settings update remote unavailable")
			return
		end
		lastSentEditSeq = settingsEditSeq
		updateRemote:FireServer(buildStoredPayload())
	end

	local function flushSettingsSave()
		if saveDebounceActive then
			saveToken += 1
			saveDebounceActive = false
		end
		if settingsEditSeq > settingsAckSeq or settingsEditSeq > lastSentEditSeq then
			fireSettingsSave()
		end
	end

	local function queueSave()
		saveToken += 1
		local myToken = saveToken
		if saveDebounceActive then
			return
		end
		saveDebounceActive = true
		task.delay(SAVE_DEBOUNCE_SEC, function()
			saveDebounceActive = false
			if myToken ~= saveToken then
				queueSave()
				return
			end
			fireSettingsSave()
		end)
	end

	local function bumpSettingsEditSeq()
		settingsEditSeq += 1
	end

	local function setField(field: string, value: any)
		lastSettingsEditAt = os.clock()

		if field == "overheadVisible" then
			localSession.overheadVisible = value == true
			currentPayload = cloneMutablePayload(currentPayload)
			currentPayload.overheadVisible = localSession.overheadVisible
			applyEffectsWithoutPlayerScan()
			syncPayloadMirrorToUi()
			if type(ui.patchField) == "function" then
				ui:patchField(field, localSession.overheadVisible)
			end
			return
		end

		if field == "hideAllGui" then
			localSession.hideAllGui = value == true
			currentPayload = cloneMutablePayload(currentPayload)
			;(currentPayload :: any).hideAllGui = localSession.hideAllGui
			applyEffectsWithoutPlayerScan()
			syncPayloadMirrorToUi()
			if type(ui.patchField) == "function" then
				ui:patchField(field, localSession.hideAllGui)
			end
			return
		end

		if field:match("^overheadLayerVisible%.") then
			local key = string.match(field, "^overheadLayerVisible%.(.+)$")
			if key then
				markPendingSaveNotif(field, value == true)
				bumpSettingsEditSeq()
				local nextPayload = cloneMutablePayload(currentPayload)
				nextPayload.overheadLayerVisible[key] = value == true
				currentPayload = nextPayload
				applyEffectsWithoutPlayerScan()
				syncPayloadMirrorToUi()
				if type(ui.patchField) == "function" then
					ui:patchField(field, value == true)
				end
				queueSave()
			end
			return
		end

		if field:match("^overheadBadgeVisible%.") then
			local key = string.match(field, "^overheadBadgeVisible%.(.+)$")
			if key then
				markPendingSaveNotif(field, value == true)
				bumpSettingsEditSeq()
				local nextPayload = cloneMutablePayload(currentPayload)
				nextPayload.overheadBadgeVisible[key] = value == true
				currentPayload = nextPayload
				applyEffectsWithoutPlayerScan()
				syncPayloadMirrorToUi()
				if type(ui.patchField) == "function" then
					ui:patchField(field, value == true)
				end
				queueSave()
			end
			return
		end

		-- Local-only: store zoom multiplier on Config.Hotbar.
		-- HotbarUIBinder reads STATE scale values multiplied by this factor every frame.
		if field == "hotbarZoom" then
			applyHotbarZoom(value)
			return
		end

		bumpSettingsEditSeq()
		local nextPayload = cloneMutablePayload(currentPayload)
		local payloadAny = nextPayload :: any

		if field == "graphicsPreset" then
			payloadAny.graphicsPreset = value
			local cascaded = GraphicsQuality.cascadePresetToStored({
				graphicsPreset = payloadAny.graphicsPreset,
				textures = payloadAny.textures,
				depthOfField = payloadAny.depthOfField,
				hideAllParticles = payloadAny.hideAllParticles,
				shadowQuality = payloadAny.shadowQuality,
				graphicsOverrides = payloadAny.graphicsOverrides or {},
			})
			payloadAny.textures = cascaded.textures
			payloadAny.depthOfField = cascaded.depthOfField
			payloadAny.hideAllParticles = cascaded.hideAllParticles
			payloadAny.shadowQuality = cascaded.shadowQuality
			payloadAny.graphicsOverrides = cascaded.graphicsOverrides
		else
			payloadAny[field] = value
			if GraphicsQuality.isOverrideField(field) then
				payloadAny.graphicsOverrides =
					GraphicsQuality.markOverride(payloadAny.graphicsOverrides or {}, field)
			end
		end

		currentPayload = nextPayload
		-- Only run full player effects scan for fields that affect particle visibility
		if field == "playerEffects" or field == "hideAllParticles" or field == "graphicsPreset" or field == "hideDonationAura" then
			applyAllEffects()
		else
			applyEffectsWithoutPlayerScan()
		end
		syncPayloadMirrorToUi()
		if type(ui.patchFromPayload) == "function" then
			ui:patchFromPayload(payloadForUi())
		elseif type(ui.patchField) == "function" then
			ui:patchField(field, value)
		end
		queueSave()
	end

	local function applyPayload(payload: SettingsPayload)
		if hasPendingSettingsEdits() then
			return
		end

		currentPayload = mergePayloadWithLocalSession(payload)
		local previousZoom = (currentPayload :: any).hotbarZoom
		applyHotbarZoom(if type(previousZoom) == "number" then previousZoom else 35)
		applyAllEffects()

		if shouldDeferSettingsUiSync() then
			return
		end

		local forceRebuild = pendingSettingsForceRebuild
		pendingSettingsForceRebuild = false
		syncSettingsUiFromPayload(forceRebuild)
		trackAllPlayerEffectCharacters()
	end

	local function restoreCharacterHooks()
		if humanoidConn then
			humanoidConn:Disconnect()
			humanoidConn = nil
		end
		if localPlayer.Character then
			applyCameraFocus()
		end
		humanoidConn = localPlayer.CharacterAdded:Connect(function()
			task.wait(0.25)
			applyCameraFocus()
			applyPlayerEffects()
		end)
	end

	function controller:init()
		readLocalSessionFromAttributes()
		currentPayload = mergePayloadWithLocalSession(currentPayload)

		local playerGui = getPlayerGui()
		if playerGui then
			trackConnection(playerGui.ChildAdded:Connect(function(child)
				if child:IsA("ScreenGui") and child.Enabled then
					task.defer(function()
						if child.Parent then
							local uiscale = ensureGlobalScale(child)
							if uiscale then
								uiscale.Scale = getGlobalScaleValue()
							end
							if currentPayload.hideAllGui == true and child.Name ~= SETTINGS_GUI_NAME then
								if child:GetAttribute(SETTINGS_HIDE_ALL_GUI_ORIGINAL) == nil then
									child:SetAttribute(SETTINGS_HIDE_ALL_GUI_ORIGINAL, child.Enabled)
								end
								child.Enabled = false
							end
						end
					end)
				end
			end))
		end
		trackConnection(Lighting.ChildAdded:Connect(function(child)
			-- Only process relevant types; skip Sound, Folder, Configuration, etc.
			if not child:IsA("BlurEffect") and not child:IsA("PostEffect") and not child:IsA("Atmosphere") then
				return
			end
			task.defer(function()
				if child.Parent then
					if effectiveGraphics.depthOfField <= 0 then
						suppressManagedBlurEffect(child)
					end
					applyPostProcessingSetting(child, effectiveGraphics.postProcessing)
				end
			end)
		end))

		local function onGeometryInstanceAdded(instance: Instance)
			if appliedShadowsEnabled == nil and appliedTexturesEnabled == nil then
				return
			end
			task.defer(function()
				if instance.Parent then
					applyRenderSettingToInstance(instance)
				end
			end)
		end

		-- REMOVED: Workspace.DescendantAdded onGeometryInstanceAdded is redundant — bindScalableTag below uses CollectionService

		local function bindScalableTag(tagName: string, handler: (Instance) -> ())
			for _, instance in ipairs(CollectionService:GetTagged(tagName)) do
				handler(instance)
			end
			trackConnection(CollectionService:GetInstanceAddedSignal(tagName):Connect(handler))
		end

		bindScalableTag(graphicsCfg.SCALABLE_GEOMETRY_TAG, onGeometryInstanceAdded)
		bindScalableTag(graphicsCfg.SCALABLE_VFX_TAG, function(instance)
			task.defer(function()
				if instance.Parent then
					applyWorkspaceVfxInstance(instance, effectiveGraphics.workspaceVfxMode)
					for _, descendant in ipairs(instance:GetDescendants()) do
						applyWorkspaceVfxInstance(descendant, effectiveGraphics.workspaceVfxMode)
					end
				end
			end)
		end)

		-- Replace Workspace.DescendantAdded with CollectionService tag for donation VFX
		local DONATION_VFX_TAG = "DonationEffect"
		trackConnection(CollectionService:GetInstanceAddedSignal(DONATION_VFX_TAG):Connect(function(instance)
			task.defer(function()
				if instance.Parent then
					applyDonationEffectScale(instance, getDonationAuraScale())
				end
			end)
		end))

		for _, player in ipairs(Players:GetPlayers()) do
			trackPlayerEffectCharacter(player)
		end
		trackConnection(Players.PlayerAdded:Connect(function(player)
			trackPlayerEffectCharacter(player)
		end))
		trackConnection(Players.PlayerRemoving:Connect(function(player)
			local characterConn = trackedEffectCharacterConns[player]
			if characterConn then
				characterConn:Disconnect()
				trackedEffectCharacterConns[player] = nil
			end
			local descendantConn = trackedEffectDescendantConns[player]
			if descendantConn then
				descendantConn:Disconnect()
				trackedEffectDescendantConns[player] = nil
			end
			overheadPayloadBaselines[player.UserId] = nil
		end))

		trackConnection(syncRemote.OnClientEvent:Connect(function(payload: any)
			if type(payload) ~= "table" then
				return
			end

			local mergedPayload = SettingsDomain.merge(payload, payload)

			if not settingsHydratedFromServer then
				settingsHydratedFromServer = true
				settingsAckSeq = settingsEditSeq
				lastSentEditSeq = settingsEditSeq
				applyPayload(mergedPayload)
				restoreCharacterHooks()
				return
			end

			if pendingSettingsForceRebuild then
				settingsAckSeq = settingsEditSeq
				lastSentEditSeq = settingsEditSeq
				showSettingsSaveAcknowledged("__reset__", nil)
				applyPayload(mergedPayload)
				restoreCharacterHooks()
				return
			end

			if settingsEditSeq == lastSentEditSeq then
				settingsAckSeq = lastSentEditSeq
				if pendingSaveNotifField then
					showSettingsSaveAcknowledged()
				end
			end

			if panelOpen then
				if settingsEditSeq > lastSentEditSeq then
					queueSave()
				end
				return
			end

			if hasPendingSettingsEdits() then
				if settingsEditSeq > lastSentEditSeq then
					queueSave()
				end
				return
			end

			applyPayload(mergedPayload)
			restoreCharacterHooks()
		end))

		trackConnection(profileSyncRemote.OnClientEvent:Connect(function(payload: any)
			if type(payload) ~= "table" then
				return
			end

			if optimisticRelationshipMode ~= nil then
				if payload.relationshipMode == optimisticRelationshipMode then
					profileAckSeq = profileEditSeq
					optimisticRelationshipMode = nil
					currentProfilePayload = payload :: ProfileMenuPayload
				elseif profilePendingByField["relationshipMode"] == nil then
					optimisticRelationshipMode = nil
					currentProfilePayload = payload :: ProfileMenuPayload
					profileAckSeq = profileEditSeq
					syncProfileUiFromPayload(false)
				end
				return
			end

			if shouldDeferProfileUiSync() then
				return
			end

			currentProfilePayload = payload :: ProfileMenuPayload
			profileAckSeq = profileEditSeq
			syncProfileUiFromPayload(false)
		end))

		trackConnection(overheadUpdateRemote.OnClientEvent:Connect(handleOverheadUpdate))

		ui:bindChange(function(field, value)
			setField(field, value)
		end)
		if type(ui.setSliderDragHandler) == "function" then
			ui:setSliderDragHandler("fov", function(active: boolean)
				if active then
					fovSliderDragDepth += 1
				else
					fovSliderDragDepth = math.max(0, fovSliderDragDepth - 1)
				end
				applyDepthOfField()
			end)
		end
		if type(ui.bindProfileChange) == "function" then
			ui:bindProfileChange(function(field, value)
				lastSettingsEditAt = os.clock()
				profileEditSeq += 1
				patchLocalOverheadFromProfileField(field, value)
				if field == "relationshipMode" then
					optimisticRelationshipMode = value
					profilePendingByField[field] = value
					profileDebounceToken += 1
					local myToken = profileDebounceToken
					task.delay(PROFILE_RELATIONSHIP_DEBOUNCE_SEC, function()
						if myToken ~= profileDebounceToken then
							return
						end
						local pendingValue = profilePendingByField[field]
						profilePendingByField[field] = nil
						if pendingValue == nil then
							return
						end
						profileUpdateRemote:FireServer({
							field = field,
							value = pendingValue,
						})
					end)
					return
				end
				profileUpdateRemote:FireServer({
					field = field,
					value = value,
				})
			end)
		end
		ui:bindReset(function()
			bumpSettingsEditSeq()
			pendingSettingsForceRebuild = true
			markPendingSaveNotif("__reset__", nil)
			resetRemote:FireServer()
		end)
		ui:bindClose(function()
			ui:hide()
			if icon and type(icon.deselect) == "function" then
				icon:deselect()
			end
		end)
		if type(ui.bindVisibilityChanged) == "function" then
			ui:bindVisibilityChanged(function(visible: boolean)
				panelOpen = visible
				menuPreviewVisible = false
				setMenuBackdropEffectEnabled(false)
				applyCameraFocus()
				if visible then
					-- Settings rows build lazily on first Settings tab open.
				else
					flushSettingsSave()
					task.spawn(reconcileSettingsAfterClose)
				end
			end)
		end

		if icon then
			local iconWidget = resolveIconWidget(icon)
			if iconWidget then
				trackConnection(iconWidget.Activated:Connect(function()
					if panelOpen then
						ui:hide()
						if type(icon.deselect) == "function" then
							icon:deselect()
						end
					end
				end))
			end
			trackConnection(icon.selected:Connect(function()
				if panelOpen then
					return
				end
				ui:show()
			end))
			if icon.deselected and type(icon.deselected.Connect) == "function" then
				trackConnection(icon.deselected:Connect(function()
					if type(ui.isPointerInsidePanel) == "function" and ui:isPointerInsidePanel() then
						return
					end
					ui:hide()
				end))
			end
		end

		restoreCharacterHooks()
		trackConnection(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			applyCameraFocus()
		end))
		requestRemote:FireServer()
		profileRequestRemote:FireServer()
		applyHotbarZoom(35)
		if currentLocalOverheadPayload and type(ui.setLocalOverheadData) == "function" then
			ui:setLocalOverheadData(currentLocalOverheadPayload)
		end
		if type(ui.syncPayloadMirror) == "function" then
			ui:syncPayloadMirror(payloadForUi())
		end
		applyAllEffects()
		ui:hide()
		setMenuBackdropEffectEnabled(false)
		log:info("SettingsController initialized")
	end

	function controller:destroy()
		if humanoidConn then
			humanoidConn:Disconnect()
			humanoidConn = nil
		end
		if cameraTween then
			cameraTween:Cancel()
			cameraTween = nil
		end
		for player, conn in pairs(trackedEffectCharacterConns) do
			conn:Disconnect()
			trackedEffectCharacterConns[player] = nil
		end
		for player, conn in pairs(trackedEffectDescendantConns) do
			conn:Disconnect()
			trackedEffectDescendantConns[player] = nil
		end
		for _, conn in ipairs(controller._connections) do
			conn:Disconnect()
		end
		table.clear(controller._connections)
	end

	return controller
end

return createSettingsController
