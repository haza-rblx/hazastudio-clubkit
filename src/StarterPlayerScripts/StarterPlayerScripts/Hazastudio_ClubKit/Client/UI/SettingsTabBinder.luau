--!strict
-- Script-built settings tab (lazy rebuild, patch registry).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GraphicsQuality = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Utils.GraphicsQuality)
local Types = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.Types)
local ScrollIndicatorHelper = require(script.Parent.Parent.Utils.ScrollIndicatorHelper)
local MenuGuiRefs = require(script.Parent.MenuGuiRefs)
local MenuSettingsCore = require(script.Parent.MenuSettingsCore)

type SettingsPayload = Types.SettingsPayload
type FieldBinding = MenuSettingsCore.FieldBinding
type Refs = MenuGuiRefs.MenuGuiRefs

local SECTION_LIST_GAP = MenuSettingsCore.SECTION_LIST_GAP

local SettingsTabBinder = {}
SettingsTabBinder.__index = SettingsTabBinder

function SettingsTabBinder.new(refs: Refs)
	local self = setmetatable({}, SettingsTabBinder) :: any
	self._refs = refs
	self._scrollable = refs.settingsTab
	self._sectionTemplate = refs.settingsSectionTemplate
	self._resetButton = refs.settingsResetButton
	self._changeCallback = nil :: ((string, any) -> ())?
	self._resetCallback = nil :: (() -> ())?
	self._resetBound = false
	self._currentPayload = nil :: SettingsPayload?
	self._localOverheadPayload = nil
	self._settingsBuilt = false
	self._settingsFieldRegistry = {} :: { [string]: FieldBinding }
	self._sliderDragHandlers = {} :: { [string]: (boolean) -> () }
	self._sectionInstances = {} :: { GuiObject }
	return self
end

function SettingsTabBinder:bindChange(callback: (string, any) -> ())
	self._changeCallback = callback
end

function SettingsTabBinder:setSliderDragHandler(field: string, callback: (boolean) -> ())
	self._sliderDragHandlers[field] = callback
end

function SettingsTabBinder:bindReset(callback: () -> ())
	self._resetCallback = callback
	if self._resetButton and not self._resetBound then
		self._resetBound = true
		self._resetButton.Activated:Connect(function()
			if self._resetCallback then
				self._resetCallback()
			end
		end)
	end
end

function SettingsTabBinder:_configureScrollable()
	local scrollable = self._scrollable
	if not scrollable then
		return
	end
	scrollable.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollable.CanvasSize = UDim2.new(0, 0, 0, 0)
	if not scrollable:FindFirstChildWhichIsA("UIPadding") then
		local tabPadding = Instance.new("UIPadding")
		tabPadding.Name = "UIPadding"
		tabPadding.Parent = scrollable
	end
	local scrollLayout = MenuSettingsCore.configureVerticalLayout(scrollable)
	if scrollLayout then
		scrollLayout.Padding = UDim.new(0, SECTION_LIST_GAP)
	end
	ScrollIndicatorHelper.attach(scrollable)
end

function SettingsTabBinder:_applyTabIdentity()
	local scrollable = self._scrollable
	if not scrollable then
		return
	end
	if not scrollable:FindFirstChild("TabIdentity") then
		warn("[SettingsTabBinder] SettingsTab.TabIdentity not found — TabTitle/TabSubtitle tidak terisi")
		return
	end
	MenuSettingsCore.applySettingsTabPageIdentity(scrollable)
end

function SettingsTabBinder:applyTabIdentity()
	self:_applyTabIdentity()
end

function SettingsTabBinder:buildIfNeeded(payload: SettingsPayload?)
	if self._settingsBuilt then
		return
	end
	if not self._scrollable or not self._sectionTemplate or not self._resetButton then
		warn("[SettingsTabBinder] Missing settings tab refs; cannot build")
		return
	end

	self:_configureScrollable()
	self:_applyTabIdentity()
	if payload then
		self._currentPayload = payload
	end
	self:_rebuildSettingsSections(self._currentPayload or ({} :: any))
end

function SettingsTabBinder:isBuilt(): boolean
	return self._settingsBuilt == true
end

function SettingsTabBinder:_rebuildSettingsSections(payload: SettingsPayload)
	local scrollable = self._scrollable
	local sectionTemplate = self._sectionTemplate
	local resetButton = self._resetButton
	if not scrollable or not sectionTemplate or not resetButton then
		return
	end

	table.clear(self._settingsFieldRegistry)
	local previousCanvasPosition = scrollable.CanvasPosition
	local nextSectionInstances = {}
	local layoutOrder = 1

	for _, sectionDef in ipairs(MenuSettingsCore.getSettingsSectionDefs(self._localOverheadPayload)) do
		local ok, sectionOrError = pcall(function()
			return MenuSettingsCore.createSection(
				sectionTemplate,
				scrollable,
				sectionDef,
				payload,
				function(field, value)
					if self._changeCallback then
						self._changeCallback(field, value)
					end
				end,
				self._settingsFieldRegistry,
				self._sliderDragHandlers
			)
		end)
		if not ok then
			for _, section in ipairs(nextSectionInstances) do
				if section and section.Parent then
					section:Destroy()
				end
			end
			warn("[SettingsTabBinder] Failed to rebuild settings sections: " .. tostring(sectionOrError))
			return
		end
		local section = sectionOrError
		section.LayoutOrder = layoutOrder
		section.Visible = true
		layoutOrder += 1
		table.insert(nextSectionInstances, section)
	end

	for _, section in ipairs(self._sectionInstances) do
		if section and section.Parent then
			section:Destroy()
		end
	end
	self._sectionInstances = nextSectionInstances

	resetButton.LayoutOrder = 999
	resetButton.Parent = scrollable
	scrollable.CanvasPosition = previousCanvasPosition
	self._settingsBuilt = true
	self:refreshOverheadConditionalItems()
	task.defer(function()
		if scrollable.Parent then
			scrollable.CanvasPosition = previousCanvasPosition
		end
	end)

	if sectionTemplate.Parent then
		sectionTemplate.Visible = false
	end
end

function SettingsTabBinder:syncPayloadMirror(payload: SettingsPayload)
	self._currentPayload = payload
end

function SettingsTabBinder:getPayload(): SettingsPayload?
	return self._currentPayload
end

function SettingsTabBinder:updateConditionalRowVisibility()
	if not self._settingsBuilt then
		return
	end

	for _, binding in pairs(self._settingsFieldRegistry) do
		if binding.row then
			binding.row.Visible = MenuSettingsCore.shouldShowSettingsItem(binding.item, self._localOverheadPayload)
		end
	end

	for _, section in ipairs(self._sectionInstances) do
		if not section or not section.Parent then
			continue
		end
		local contentWrapper =
			MenuSettingsCore.findFirstDescendantByNames(section, { "SectionContentWrapper", "SectionContentWraooer" })
		local hasVisibleChild = false
		if contentWrapper then
			for _, child in ipairs(contentWrapper:GetChildren()) do
				if child:IsA("GuiObject") and child.Visible then
					hasVisibleChild = true
					break
				end
			end
		end
		section.Visible = hasVisibleChild
	end
end

function SettingsTabBinder:updateGraphicsOverrideLabels(payload: SettingsPayload)
	if not self._settingsBuilt then
		return
	end
	local overrides = payload.graphicsOverrides or {}
	for fieldName, binding in pairs(self._settingsFieldRegistry) do
		if binding.kind ~= "toggle" or not GraphicsQuality.isOverrideField(fieldName) then
			continue
		end
		local suffix = if overrides[fieldName] == true then " (override)" else ""
		MenuSettingsCore.setTextLabelText(binding.row, binding.item.label .. suffix)
	end
end

function SettingsTabBinder:patchFromPayload(payload: SettingsPayload)
	self._currentPayload = payload
	if not self._settingsBuilt then
		return
	end

	for _, binding in pairs(self._settingsFieldRegistry) do
		local resolved = MenuSettingsCore.resolveFieldValue(payload, binding.field)
		if binding.kind == "toggle" then
			binding.setValue(MenuSettingsCore.isMappedToggleEnabled(binding.item, resolved))
		elseif binding.kind == "segmented" then
			local defaultOption = binding.item.options[1]
			binding.setValue(tostring(resolved or MenuSettingsCore.getOptionValue(defaultOption)))
		elseif binding.kind == "slider" then
			binding.setValue(tonumber(resolved) or binding.item.min)
		end
	end

	self:updateConditionalRowVisibility()
	self:updateGraphicsOverrideLabels(payload)
end

function SettingsTabBinder:patchField(field: string, value: any)
	if self._currentPayload then
		MenuSettingsCore.assignFieldValue(self._currentPayload, field, value)
	end

	local binding = self._settingsFieldRegistry[field]
	if not binding then
		return
	end
	if binding.kind == "toggle" then
		if binding.item.valueMap then
			binding.setValue(value == binding.item.valueMap.on)
		else
			binding.setValue(value == true)
		end
	elseif binding.kind == "segmented" then
		binding.setValue(tostring(value))
	elseif binding.kind == "slider" then
		binding.setValue(tonumber(value) or binding.item.min)
	end

	if self._currentPayload then
		self:updateGraphicsOverrideLabels(self._currentPayload)
	end
end

function SettingsTabBinder:refreshOverheadConditionalItems()
	if not self._currentPayload then
		return
	end
	self:updateConditionalRowVisibility()
end

function SettingsTabBinder:setLocalOverheadData(payload: any)
	self._localOverheadPayload = payload
	self:refreshOverheadConditionalItems()
end

function SettingsTabBinder:setData(payload: SettingsPayload, options: { forceRebuild: boolean? }?)
	self._currentPayload = payload
	local forceRebuild = type(options) == "table" and options.forceRebuild == true
	if self._settingsBuilt and not forceRebuild then
		self:patchFromPayload(payload)
		return
	end
	if not self._settingsBuilt then
		self:buildIfNeeded(payload)
		return
	end
	self:_rebuildSettingsSections(payload)
end

return SettingsTabBinder
