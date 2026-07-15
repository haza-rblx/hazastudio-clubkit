--!strict
-- Late MusicPlayerUIBinder method definitions, applied by MusicPlayerUIBinder.luau.

type ManageFormCopy = {
	title: string,
	helper: string,
	button: string,
}
type PooledRow = {
	instance: GuiObject,
	connections: { RBXScriptConnection },
	boundItemId: string?,
}

return function(MusicPlayerUIBinder: any, H: any)
	local ContentProvider = H.ContentProvider
	local TweenService = H.TweenService
	local Players = H.Players
	local Workspace = H.Workspace
	local scheduleTrackTitleHeight = H.scheduleTrackTitleHeight
	local applyVirtualTrackTitle = H.applyVirtualTrackTitle
	local ScrollIndicatorHelper = H.ScrollIndicatorHelper
	local SliderSelectorUtil = H.SliderSelectorUtil
	local Config = H.Config
	local FADE_INFO_FAST = H.FADE_INFO_FAST
	local PLAYLIST_RELATED_CAMERA_FOV_DELTA = H.PLAYLIST_RELATED_CAMERA_FOV_DELTA
	local REQUEST_PLAYLIST_USER_LAYOUT_BASE = H.REQUEST_PLAYLIST_USER_LAYOUT_BASE
	local VIRTUAL_ROW_LAYOUT_BASE = H.VIRTUAL_ROW_LAYOUT_BASE
	local QUEUE_SCROLLBAR_IDLE_DELAY = H.QUEUE_SCROLLBAR_IDLE_DELAY
	local SEARCH_DEBOUNCE_SEC = H.SEARCH_DEBOUNCE_SEC or 0.18
	local getMonthDropsLabel = H.getMonthDropsLabel
	local getCoverGradientRotation = H.getCoverGradientRotation
	local buildCoverGradientColorSequence = H.buildCoverGradientColorSequence
	local getImageCoverKey = H.getImageCoverKey
	local getImageCoverUri = H.getImageCoverUri
	local normalizeListCoverUri = H.normalizeListCoverUri or getImageCoverUri
	local resolveCoverSourceForTrack = H.resolveCoverSourceForTrack
	local sampleImageCoverDarkestColor = H.sampleImageCoverDarkestColor
	local getPlaylistCoverAccentColor = H.getPlaylistCoverAccentColor
	local PLAYLIST_FORM_COPY = H.PLAYLIST_FORM_COPY
	local TRACK_FORM_COPY = H.TRACK_FORM_COPY
	local ensureUIScale = H.ensureUIScale
	local stashTemplateInstance = H.stashTemplateInstance
	local _clearListClones = H._clearListClones
	local disconnectPooledRowConnections = H.disconnectPooledRowConnections
	local disconnectConnectionList = H.disconnectConnectionList
	local ensurePooledRow = H.ensurePooledRow
	local hideUnusedPooledRows = H.hideUnusedPooledRows
	local destroyPooledRows = H.destroyPooledRows
	local startListRenderJob = H.startListRenderJob
	local cancelAllListRenderJobs = H.cancelAllListRenderJobs
	local disconnectVirtualList = H.disconnectVirtualList
	local disconnectAllVirtualLists = H.disconnectAllVirtualLists
	local renderVirtualList = H.renderVirtualList
	local hideIfGuiObject = H.hideIfGuiObject
	local trackConnection = H.trackConnection
	local trackUnsubscriber = H.trackUnsubscriber
	local bindClickable = H.bindClickable
	local bindTrackedClickable = H.bindTrackedClickable
	local isManageInteractionBlocked = H.isManageInteractionBlocked
	local findFirstByNames = H.findFirstByNames
	local forEachDirectChildByName = H.forEachDirectChildByName
	local findCoverTextLabel = H.findCoverTextLabel
	local getPlaylistTrackCount = H.getPlaylistTrackCount
	local formatTrackCount = H.formatTrackCount
	local setTextLabelByNames = H.setTextLabelByNames
	local applyNamedFont = H.applyNamedFont
	local setTextDisplay = H.setTextDisplay
	local setButtonDisplayText = H.setButtonDisplayText
	local setSwitchToggleVisual = H.setSwitchToggleVisual
	local bindSwitchToggleClick = H.bindSwitchToggleClick
	local formatDjSpeedText = H.formatDjSpeedText
	local formatDjEffectValueText = H.formatDjEffectValueText
	local djEffectSliderKey = H.djEffectSliderKey
	local bindDjSlider = H.bindDjSlider
	local getActionWrapper = H.getActionWrapper
	local hasMultipleDirectChildrenNamed = H.hasMultipleDirectChildrenNamed
	local setActionWrapperButtonsInteractable = H.setActionWrapperButtonsInteractable
	local getFormTitleDisplay = H.getFormTitleDisplay
	local getFormHelperDisplay = H.getFormHelperDisplay
	local getTextInput = H.getTextInput
	local setTextInput = H.setTextInput
	local resetRequestTrackFeedback = H.resetRequestTrackFeedback
	local buildOrderedPlaylistEntries = H.buildOrderedPlaylistEntries
	local buildOrderedTrackEntries = H.buildOrderedTrackEntries
	local formatClock = H.formatClock
	local getSpecialPlaylistIds = H.getSpecialPlaylistIds
	local applyPlaylistRowState = H.applyPlaylistRowState
	local capturePlaylistRowState = H.capturePlaylistRowState
	local restorePlaylistRowState = H.restorePlaylistRowState
	local setAllChildGradientsEnabled = H.setAllChildGradientsEnabled
	local findIndicatorFrame = H.findIndicatorFrame
	local copySelectionTemplateVisual = H.copySelectionTemplateVisual
	local getPanelBlurSize = H.getPanelBlurSize
	local getModalBackdropTransparency = H.getModalBackdropTransparency
	local playModalBlur = H.playModalBlur

	function MusicPlayerUIBinder:bindDjTab()
		local refs = self._refs
		local config = self._config or {}
		local djConfig = config.DJ or {}
		local soundBoardItems = djConfig.SOUND_BOARD_ITEMS or {}
		local speedPresets = djConfig.PLAYBACK_SPEED_PRESETS or {}
		local effects = djConfig.EFFECTS or {}
		local djTab = refs.djTab
		if not djTab then
			return
		end
	
		disconnectConnectionList(self._djSoundBoardConnections)
		disconnectConnectionList(self._djEffectConnections)
		self._djSpeedPresetButtons = {}
		self._djPlaybackSpeedSliderSetter = nil
		self._djPlaybackSpeedSliderRoot = nil
		self._djPlaybackSpeedHeaderValueLabel = nil
		self._djEffectSliderSetters = {}
		self._djEffectSliderRoots = {}
		self._djEffectToggleButtons = {}
		self._djModeToggle = nil
		self:_syncMainDragForActiveTab()
	
		local sliderDragDepth = 0
		local function setSliderDragActive(active: boolean)
			if active then
				sliderDragDepth += 1
			else
				sliderDragDepth = math.max(0, sliderDragDepth - 1)
			end
			if refs.mainDragDetector and self:_shouldMainDragBeEnabled() then
				refs.mainDragDetector.Enabled = sliderDragDepth <= 0
			elseif refs.mainDragDetector then
				refs.mainDragDetector.Enabled = false
			end
		end
	
		local playlistSection = findFirstByNames(djTab, { "1-PlaylistSection" })
		local djModeWrapper = findFirstByNames(playlistSection, { "DJModeWrapper" })
		local djModeContentWrapper = findFirstByNames(djModeWrapper, { "Wrapper" })
		local djModeToggle = findFirstByNames(djModeContentWrapper, { "ToggleEnableDJMode" })
			or findFirstByNames(djModeWrapper, { "ToggleEnableDJMode" })
		if djModeToggle and djModeToggle:IsA("GuiObject") then
			self._djModeToggle = djModeToggle :: GuiObject
			setSwitchToggleVisual(djModeToggle, self._store:get().isDjMode == true)
			task.defer(setSwitchToggleVisual, djModeToggle, self._store:get().isDjMode == true)
			bindSwitchToggleClick(self._djEffectConnections, djModeToggle, refs.mainDragDetector, function()
				setSwitchToggleVisual(djModeToggle, not (self._store:get().isDjMode == true))
				if self._onToggleDjMode then
					self._onToggleDjMode()
				end
			end, function()
				return self:_shouldMainDragBeEnabled()
			end)
		end
	
		local soundBoardWrapper = findFirstByNames(playlistSection, { "SoundBoardWrapper" })
		local soundBoardScroll = findFirstByNames(soundBoardWrapper, { "ScrollingFrame" })
		local soundBoardTemplate = findFirstByNames(soundBoardScroll, { "SoundBoardItemTemplate" })
		if soundBoardScroll and soundBoardTemplate and soundBoardTemplate:IsA("TextButton") then
			local template = soundBoardTemplate :: TextButton
			template.Visible = false
			_clearListClones(soundBoardScroll :: ScrollingFrame, "SoundBoardItemTemplate")
	
			for index, item in ipairs(soundBoardItems) do
				local clone = template:Clone()
				clone.Name = tostring(item.id or index)
				clone.LayoutOrder = index
				clone.Visible = true
				clone.Parent = soundBoardScroll
				setButtonDisplayText(clone, tostring(item.label or item.id or clone.Name))
	
				bindTrackedClickable(self._djSoundBoardConnections, clone, function()
					if self._onDjSoundboardTriggered then
						self._onDjSoundboardTriggered(tostring(item.id or clone.Name))
					end
				end)
			end
		end
	
		local soundEffectWrapper = findFirstByNames(djTab, { "SoundEffectWrapper" })
		local soundEffectScroll = findFirstByNames(soundEffectWrapper, { "ScrollableFrame" })
		local resetButton = findFirstByNames(soundEffectScroll, { "SoundEffectResetButton" })
		if resetButton then
			bindTrackedClickable(self._djEffectConnections, resetButton, function()
				if self._onDjResetRequested then
					self._onDjResetRequested()
				end
			end)
		end
	
		local playbackSpeedSection = findFirstByNames(soundEffectScroll, { "PlaybackSpeed" })
		local playbackSpeedWrapper = findFirstByNames(playbackSpeedSection, { "Wrapper" })
		local speedTop = findFirstByNames(playbackSpeedWrapper, { "Top" })
		local speedHeader = findFirstByNames(speedTop, { "Header" })
		if speedHeader then
			for _, child in ipairs(speedHeader:GetChildren()) do
				if child:IsA("TextLabel") and child.Text ~= "Playback Speed" then
					self._djPlaybackSpeedHeaderValueLabel = child :: TextLabel
					break
				end
			end
		end
		local speedTemplateWrapper = findFirstByNames(playbackSpeedWrapper, { "SpeedTemplateWrapper" })
		local speedSliderRoot = findFirstByNames(playbackSpeedWrapper, { "SliderWrapper" })
		if speedSliderRoot and speedSliderRoot:IsA("GuiObject") then
			self._djPlaybackSpeedSliderRoot = speedSliderRoot :: GuiObject
			self._djPlaybackSpeedSliderSetter = bindDjSlider(
				self._djEffectConnections,
				speedSliderRoot,
				0.25,
				2.0,
				0.05,
				self._djPlaybackSpeed,
				formatDjSpeedText,
				function(nextSpeed): boolean
					if self._onDjPlaybackSpeedChanged then
						return self._onDjPlaybackSpeedChanged(nextSpeed) == true
					end
					return true
				end,
				setSliderDragActive
			)
		end
	
		if speedTemplateWrapper then
			local presetNames = { "025", "050", "100", "150", "200" }
			for index, preset in ipairs(speedPresets) do
				local childName = presetNames[index] or tostring(index)
				local presetButton = findFirstByNames(speedTemplateWrapper, { childName })
				if presetButton then
					local speedValue = tonumber(preset.value) or self._djPlaybackSpeed
					self._djSpeedPresetButtons[speedValue] = presetButton :: GuiObject
					setButtonDisplayText(presetButton, tostring(preset.label or formatDjSpeedText(speedValue)))
					bindTrackedClickable(self._djEffectConnections, presetButton, function()
						if self._onDjPlaybackSpeedChanged then
							self._onDjPlaybackSpeedChanged(speedValue)
						end
					end)
				end
			end
		end
	
		local templateEffect = findFirstByNames(soundEffectScroll, { "TemplateEffect" })
		if soundEffectScroll and templateEffect and templateEffect:IsA("GuiObject") then
			local template = templateEffect :: GuiObject
			template.Visible = false
			for _, child in ipairs(soundEffectScroll:GetChildren()) do
				if child:IsA("GuiObject") and child:GetAttribute("DjEffectClone") == true then
					child:Destroy()
				end
			end
	
			for index, effect in ipairs(effects) do
				local effectId = tostring(effect.id or index)
				local effectClone = template:Clone()
				effectClone.Name = effectId
				effectClone.LayoutOrder = 100 + index
				effectClone:SetAttribute("DjEffectClone", true)
				effectClone.Visible = true
				effectClone.Parent = soundEffectScroll
	
				local sectionHeader = findFirstByNames(effectClone, { "SectionHeader" })
				local sectionName = findFirstByNames(sectionHeader, { "SectionName" })
				local toggle = findFirstByNames(sectionHeader, { "Toggle" })
				local effectEnabled = if self._djEffectEnabledById[effectId] ~= nil
					then self._djEffectEnabledById[effectId]
					else effect.defaultEnabled == true
				self._djEffectEnabledById[effectId] = effectEnabled
	
				if sectionName then
					setButtonDisplayText(sectionName, tostring(effect.sectionName or effect.label or effect.id or "Effect"))
				end
	
				if toggle then
					self._djEffectToggleButtons[effectId] = toggle :: GuiObject
					setSwitchToggleVisual(toggle, effectEnabled)
					task.defer(setSwitchToggleVisual, toggle, effectEnabled)
					bindSwitchToggleClick(self._djEffectConnections, toggle, refs.mainDragDetector, function()
						local nextEnabled = not (self._djEffectEnabledById[effectId] == true)
						local accepted = true
						if self._onDjEffectEnabledChanged then
							accepted = self._onDjEffectEnabledChanged(effectId, nextEnabled) == true
						end
						setSwitchToggleVisual(
							toggle,
							if accepted then nextEnabled else (self._djEffectEnabledById[effectId] == true)
						)
					end, function()
						return self:_shouldMainDragBeEnabled()
					end)
				end
	
				local wrapper = findFirstByNames(effectClone, { "Wrapper" })
				local effectItemTemplate = findFirstByNames(wrapper, { "EffectItemTemplate" })
				if effectItemTemplate and effectItemTemplate:IsA("GuiObject") then
					local itemTemplate = effectItemTemplate :: GuiObject
					itemTemplate.Visible = false
					local effectValues = self._djEffectValues[effectId]
					if not effectValues then
						effectValues = {}
						self._djEffectValues[effectId] = effectValues
					end
					local items = if type(effect.items) == "table" then effect.items else {}
					local itemCount = 0
					for itemIndex, item in ipairs(items) do
						local itemId = tostring(item.id or item.property or itemIndex)
						local itemClone = itemTemplate:Clone()
						itemClone.Name = itemId
						itemClone.LayoutOrder = itemIndex
						itemClone.Visible = true
						itemClone.Parent = wrapper
						itemCount += 1
	
						local itemLabel = findFirstByNames(itemClone, { "Item", "Label", "Name" })
						if itemLabel then
							setButtonDisplayText(itemLabel, tostring(item.label or item.id or item.property or "Value"))
						end
	
						local initialValue = if effectValues[itemId] ~= nil
							then effectValues[itemId]
							else tonumber(item.defaultValue) or 0
						effectValues[itemId] = initialValue
	
						local sliderRoot = findFirstByNames(itemClone, { "Slider" })
						if sliderRoot and sliderRoot:IsA("GuiObject") then
							local sliderKey = djEffectSliderKey(effectId, itemId)
							self._djEffectSliderRoots[sliderKey] = sliderRoot :: GuiObject
							self._djEffectSliderSetters[sliderKey] = bindDjSlider(
								self._djEffectConnections,
								itemClone,
								tonumber(item.min) or 0,
								tonumber(item.max) or 1,
								tonumber(item.step) or 0.05,
								initialValue,
								function(nextValue)
									return formatDjEffectValueText(nextValue, item.suffix)
								end,
								function(nextValue): boolean
									if self._onDjEffectValueChanged then
										return self._onDjEffectValueChanged(effectId, itemId, nextValue) == true
									end
									return true
								end,
								setSliderDragActive
							)
						end
					end
	
					if itemCount == 0 then
						itemTemplate.Visible = true
					end
				end
			end
		end
	
		self:setDjPlaybackSpeed(self._djPlaybackSpeed)
		for _, effect in ipairs(effects) do
			local effectId = tostring(effect.id or "")
			if effectId ~= "" then
				self:setDjEffectEnabled(effectId, self._djEffectEnabledById[effectId] == true)
				if type(effect.items) == "table" then
					for _, item in ipairs(effect.items) do
						local itemId = tostring(item.id or item.property or "")
						local value = self._djEffectValues[effectId] and self._djEffectValues[effectId][itemId]
						if itemId ~= "" and type(value) == "number" then
							self:setDjEffectValue(effectId, itemId, value)
						end
					end
				end
			end
		end
		self:_syncDjSwitchInputForActiveTab()
	end
	
	local function rememberRequesterThumbnail(self: any, requesterUserId: number, thumbnail: string)
		if self._userThumbnailCache[requesterUserId] == nil then
			table.insert(self._userThumbnailCacheOrder, requesterUserId)
		end
		self._userThumbnailCache[requesterUserId] = thumbnail
	
		local maxEntries = math.max(1, math.floor(tonumber(self._config and self._config.THUMBNAIL_CACHE_MAX) or 100))
		while #self._userThumbnailCacheOrder > maxEntries do
			local evictedUserId = table.remove(self._userThumbnailCacheOrder, 1)
			if evictedUserId then
				self._userThumbnailCache[evictedUserId] = nil
			end
		end
	end
	
	function MusicPlayerUIBinder:_setRequesterThumbnail(imageLabel: ImageLabel, requesterUserId: number?)
		imageLabel:SetAttribute("RequesterUserId", requesterUserId)
		imageLabel.Image = ""
	
		if type(requesterUserId) ~= "number" or requesterUserId <= 0 then
			return
		end
	
		local cached = self._userThumbnailCache[requesterUserId]
		if type(cached) == "string" and cached ~= "" then
			imageLabel.Image = cached
			return
		end
	
		task.spawn(function()
			local ok, thumbnail = pcall(
				Players.GetUserThumbnailAsync,
				Players,
				requesterUserId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size100x100
			)
	
			if not ok or type(thumbnail) ~= "string" or thumbnail == "" then
				return
			end
	
			rememberRequesterThumbnail(self, requesterUserId, thumbnail)
			if imageLabel.Parent and imageLabel:GetAttribute("RequesterUserId") == requesterUserId then
				imageLabel.Image = thumbnail
			end
		end)
	end
	
	function MusicPlayerUIBinder:_updateQueueHeaderVisibility()
		local refs = self._refs
		local header = refs.queueHeaderLabel
		local scroll = refs.scrollableQueue
		if not header or not scroll then
			return
		end
	
		local headerTop = header.AbsolutePosition.Y
		local headerBottom = headerTop + header.AbsoluteSize.Y
		local shouldShow = true
	
		for _, child in ipairs(scroll:GetChildren()) do
			if
				child:IsA("GuiObject")
				and child.Visible
				and child ~= refs.queueTemplate
				and child.Name ~= "QueueListTemplate"
				and child.Name ~= "UIListLayout"
				and child.Name ~= "UIPadding"
			then
				local top = child.AbsolutePosition.Y
				local bottom = top + child.AbsoluteSize.Y
				if bottom > headerTop and top < headerBottom then
					shouldShow = false
					break
				end
			end
		end
	
		if header.Visible ~= shouldShow then
			header.Visible = shouldShow
		end
	end
	
	-- ============================================================
	-- QUEUE RENDER
	-- ============================================================
	
	function MusicPlayerUIBinder:_requestImageCoverDarkestColor(playlist: any)
		if type(playlist) ~= "table" or (playlist.coverType or "gradient") ~= "image" then
			return
		end
	
		local coverKey = getImageCoverKey(playlist.coverValue)
		if not coverKey then
			return
		end
		if self._imageCoverDarkestColors[coverKey] or self._imageCoverDarkestColorRequests[coverKey] then
			return
		end
	
		self._imageCoverDarkestColorRequests[coverKey] = true
		task.spawn(function()
			local sampleOk, darkestColor = pcall(function()
				return sampleImageCoverDarkestColor(playlist.coverValue)
			end)
			self._imageCoverDarkestColorRequests[coverKey] = nil
			if self._isDestroyed or not sampleOk or not darkestColor then
				return
			end
	
			self._imageCoverDarkestColors[coverKey] = darkestColor
	
			local state = self._store:get()
			self:renderQueue(state.queue or {})
	
			local currentTrack = state.currentTrack
			if type(currentTrack) ~= "table" then
				return
			end
	
			local playlistsById = state.playlists or {}
			local parentPlaylist = currentTrack.playlist or playlistsById[currentTrack.playlistId]
			if type(parentPlaylist) == "table" and getImageCoverKey(parentPlaylist.coverValue) == coverKey then
				self:_updateAuraOverlay(parentPlaylist)
			end
		end)
	end
	
	function MusicPlayerUIBinder:_getQueueNumberColor(parentPlaylist: any?): Color3?
		if type(parentPlaylist) ~= "table" then
			return nil
		end
	
		if (parentPlaylist.coverType or "gradient") == "image" then
			self:_requestImageCoverDarkestColor(parentPlaylist)
		end
	
		return getPlaylistCoverAccentColor(parentPlaylist, self._config, self._imageCoverDarkestColors)
	end
	
	function MusicPlayerUIBinder:renderQueue(queue: { any })
		local refs = self._refs
		local scroll = refs.scrollableQueue
		local template = refs.queueTemplate
		local playlistsById = self._store:get().playlists or {}
	
		template.Visible = false
	
		for i, track in ipairs(queue) do
			local row = ensurePooledRow(self._queueRowPool, i, template, scroll)
			disconnectPooledRowConnections(row)
			local clone = row.instance
	
			-- QueueListTemplate structure (from live dump):
			-- RelatedPlaylistCover -> QueueNumberWrapper -> QueueNumber [TextLabel]
			-- RelatedPlaylistCover -> RelatedCoverTitle [TextLabel]
			-- TrackInformationSection -> TrackInfo -> TrackTitle [TextLabel]
			-- TrackInformationSection -> TrackInfo -> TrackCreator [TextLabel]
			local parentPlaylist = track.playlist or playlistsById[track.playlistId]
			local cover = clone:FindFirstChild("RelatedPlaylistCover")
			if cover then
				-- QueueNumber lives inside QueueNumberWrapper
				local queueWrapper = cover:FindFirstChild("QueueNumberWrapper")
				local queueNum = if queueWrapper then queueWrapper:FindFirstChild("QueueNumber") else nil
				if queueNum and queueNum:IsA("TextLabel") then
					(queueNum :: TextLabel).Text = string.format("%02d", i)
				end
				-- Color QueueNumber text from the playlist cover accent.
				if queueNum and queueNum:IsA("TextLabel") then
					local numberLabel = queueNum :: TextLabel
					if typeof(numberLabel:GetAttribute("QueueNumberBaseTextColor3")) ~= "Color3" then
						numberLabel:SetAttribute("QueueNumberBaseTextColor3", numberLabel.TextColor3)
					end
					local queueNumberColor = self:_getQueueNumberColor(parentPlaylist)
					numberLabel.TextColor3 = queueNumberColor
						or (numberLabel:GetAttribute("QueueNumberBaseTextColor3") :: Color3)
						or Color3.new(1, 1, 1)
				end
	
				local coverTitle = cover:FindFirstChild("RelatedCoverTitle")
				if coverTitle and coverTitle:IsA("TextLabel") then
					(coverTitle :: TextLabel).Text = if parentPlaylist then tostring(parentPlaylist.name or "") else ""
				end
	
				-- Apply cover style if track has playlist info
				if parentPlaylist then
					local coverSource = resolveCoverSourceForTrack(track, parentPlaylist)
					self:applyCoverStyle(cover, coverSource)
				end
			end
	
			local infoSection = clone:FindFirstChild("TrackInformationSection")
			if infoSection then
				local trackInfo = infoSection:FindFirstChild("TrackInfo")
				if trackInfo then
					local titleLabel = trackInfo:FindFirstChild("TrackTitle")
					if titleLabel and titleLabel:IsA("TextLabel") then
						local label = titleLabel :: TextLabel
						label.Text = track.name or ""
						scheduleTrackTitleHeight(label)
					end
					-- Actual field name is TrackCreator (not CreatorName)
					local creatorLabel = trackInfo:FindFirstChild("TrackCreator") or trackInfo:FindFirstChild("CreatorName")
					if creatorLabel and creatorLabel:IsA("TextLabel") then
						(creatorLabel :: TextLabel).Text = track.creator or ""
					end
	
					local trackLengthLabel = trackInfo:FindFirstChild("Track Length")
						or trackInfo:FindFirstChild("TrackLength")
					if trackLengthLabel and trackLengthLabel:IsA("TextLabel") then
						(trackLengthLabel :: TextLabel).Text = formatClock(tonumber(track.totalDuration) or 0)
					end
				end
	
				local requesterWrapper = infoSection:FindFirstChild("RequesterWrapper")
				if requesterWrapper then
					local requesterLabel = requesterWrapper:FindFirstChild("RequesterDisplayName")
					if requesterLabel and requesterLabel:IsA("TextLabel") then
						local requesterName = if track.isSystemAssigned == true
							then "Auto Playlist"
							else tostring(track.requesterDisplayName or "Unknown")
						local requesterTextLabel = requesterLabel :: TextLabel
						requesterTextLabel.Text = string.format("Requester : %s", requesterName)
					end
				end
	
				local requesterProfile = infoSection:FindFirstChild("RequesterProfilePicture")
				if requesterProfile and requesterProfile:IsA("ImageLabel") then
					if track.isSystemAssigned == true then
						requesterProfile.Visible = false
					else
						requesterProfile.Visible = true
						self:_setRequesterThumbnail(requesterProfile :: ImageLabel, tonumber(track.requesterUserId))
					end
				end
			end
	
			clone.Name = tostring(track.id or i)
			clone.LayoutOrder = i
			clone.Visible = true
		end
	
		hideUnusedPooledRows(self._queueRowPool, #queue + 1)
		self:_updateQueueHeaderVisibility()
	end
	
	-- ============================================================
	-- PLAYLIST ICON BOUNCE (idle loop, memory-safe)
	-- ============================================================
	
	function MusicPlayerUIBinder:_refreshPlaylistIconBounce(...)
		-- Cancel any existing bounces first
		local existing = self._playlistIconBounceCleanup
		if existing then
			for _, entry in ipairs(existing) do
				entry.kill()
				for _, t in ipairs(entry.tweens) do
					t:Cancel()
				end
				for _, c in ipairs(entry.conns) do
					c:Disconnect()
				end
			end
		end
		self._playlistIconBounceCleanup = {}
	
		local buttons = { ... }
		for delayIdx, btn in ipairs(buttons) do
			if not (btn and btn:IsA("GuiObject")) then
				continue
			end
			local cover = btn:FindFirstChild("PlaylistCover", true)
			local icon = if cover then cover:FindFirstChild("PlaylistIcon") else nil
			if not (icon and icon:IsA("GuiObject")) then
				continue
			end
	
			local iconObj = icon :: GuiObject
			local uiScale = ensureUIScale(iconObj)
	
			local PAUSE_BETWEEN = 4.0 -- idle pause between each attention cycle
			local DELAY_OFFSET = (delayIdx - 1) * 1.2 -- stagger between icons
	
			local alive = true
			local conns: { RBXScriptConnection } = {}
			local tweens: { Tween } = {}
	
			-- Attention-seeker sequence run as a task (coroutine-based)
			local function runCycle()
				if not alive then
					return
				end
	
				-- 1. Rise + tilt right
				uiScale.Scale = 1
				iconObj.Rotation = 0
				local tRise = TweenService:Create(
					uiScale,
					TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
					{ Scale = 1.18 }
				)
				local tTilt = TweenService:Create(
					iconObj,
					TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
					{ Rotation = 10 }
				)
				table.insert(tweens, tRise)
				table.insert(tweens, tTilt)
				tRise:Play()
				tTilt:Play()
				task.wait(0.20)
	
				-- 2. Shake: quick left-right-left-right rotation
				local shakeAngles = { -12, 10, -8, 6, -4, 0 }
				for _, angle in ipairs(shakeAngles) do
					if not alive then
						break
					end
					local tShake =
						TweenService:Create(iconObj, TweenInfo.new(0.07, Enum.EasingStyle.Linear), { Rotation = angle })
					table.insert(tweens, tShake)
					tShake:Play()
					task.wait(0.075)
				end
	
				-- 3. Settle: scale back to 1, rotation to 0
				if not alive then
					return
				end
				local tDown = TweenService:Create(
					uiScale,
					TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ Scale = 1.0 }
				)
				local tStraighten = TweenService:Create(
					iconObj,
					TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ Rotation = 0 }
				)
				table.insert(tweens, tDown)
				table.insert(tweens, tStraighten)
				tDown:Play()
				tStraighten:Play()
				task.wait(0.25)
			end
	
			-- Loop thread
			local thread = task.spawn(function()
				task.wait(DELAY_OFFSET)
				while alive do
					runCycle()
					task.wait(PAUSE_BETWEEN)
				end
			end)
	
			table.insert(self._playlistIconBounceCleanup, {
				tweens = tweens,
				conns = conns,
				kill = function()
					alive = false
					task.cancel(thread)
					iconObj.Rotation = 0
					uiScale.Scale = 1
				end,
			})
		end
	end
	
	-- ============================================================
	-- PLAYLIST LIST RENDER (Request Tab)
	-- ============================================================
	
	function MusicPlayerUIBinder:renderPlaylists(playlists: { any }, searchQuery: string)
		local refs = self._refs
		local scroll = refs.scrollablePlaylist
		local normalTemplate = refs.playlistTemplateNormal
		local selectedTemplate = refs.playlistTemplateSelected
		local state = self._store:get()
		local selectedPlaylistId = state.selectedPlaylistId
		local favoritesPlaylistId, newDropsPlaylistId = getSpecialPlaylistIds(self._config)
	
		if not self._specialPlaylistDefaults then
			self._specialPlaylistDefaults = {
				favorites = capturePlaylistRowState(refs.favoritesPlaylistButton),
				newDrops = capturePlaylistRowState(refs.newDropsPlaylistButton),
			}
		end
		local specialDefaults = self._specialPlaylistDefaults
	
		normalTemplate.Visible = false
		selectedTemplate.Visible = false
		normalTemplate.LayoutOrder = 10000
		selectedTemplate.LayoutOrder = 10001
	
		refs.favoritesPlaylistButton.Visible = true
		refs.newDropsPlaylistButton.Visible = true
		refs.favoritesPlaylistButton.LayoutOrder = 1
		refs.newDropsPlaylistButton.LayoutOrder = 2
	
		if selectedPlaylistId == favoritesPlaylistId then
			applyPlaylistRowState(refs.favoritesPlaylistButton, selectedTemplate)
		else
			restorePlaylistRowState(refs.favoritesPlaylistButton, specialDefaults.favorites)
		end
	
		if selectedPlaylistId == newDropsPlaylistId then
			applyPlaylistRowState(refs.newDropsPlaylistButton, selectedTemplate)
		else
			restorePlaylistRowState(refs.newDropsPlaylistButton, specialDefaults.newDrops)
		end
	
		-- Dynamic NewDrops month label
		do
			local ndCover = refs.newDropsPlaylistButton:FindFirstChild("PlaylistCover", true)
			local ndNameLabel = if ndCover then ndCover:FindFirstChild("PlaylistName") else nil
			if ndNameLabel and ndNameLabel:IsA("TextLabel") then
				(ndNameLabel :: TextLabel).Text = getMonthDropsLabel()
			end
		end
	
		-- Idle bounce animation on special playlist icons (once per panel session).
		if not self._specialPlaylistBounceActive then
			self:_refreshPlaylistIconBounce(refs.favoritesPlaylistButton, refs.newDropsPlaylistButton)
			self._specialPlaylistBounceActive = true
		end

		local orderedPlaylists = buildOrderedPlaylistEntries(playlists, searchQuery)
		hideUnusedPooledRows(self._requestPlaylistRowPool, 1)

		startListRenderJob(self, "requestPlaylists", #orderedPlaylists, function(index: number)
			local entry = orderedPlaylists[index]
			local id = entry.id
			local playlist = entry.playlist
			local row = ensurePooledRow(self._requestPlaylistRowPool, index, normalTemplate, scroll)
			disconnectPooledRowConnections(row)
			local clone = row.instance

			local info = clone:FindFirstChild("PlaylistInformation")
			if info then
				local nameLabel = info:FindFirstChild("PlaylistName")
				if nameLabel and nameLabel:IsA("TextLabel") then
					(nameLabel :: TextLabel).Text = playlist.name or ""
				end

				local totalTrackLabel = info:FindFirstChild("TotalTrack")
				if totalTrackLabel and totalTrackLabel:IsA("TextLabel") then
					local trackCount = type(playlist.trackIds) == "table" and #playlist.trackIds or 0
					local suffix = if trackCount == 1 then "Track" else "Tracks"
					(totalTrackLabel :: TextLabel).Text = string.format("%d %s", trackCount, suffix)
				end
			end

			local coverElement = clone:FindFirstChild("PlaylistCover") or clone:FindFirstChild("ImageLabel")
			if coverElement then
				self:applyCoverStyle(coverElement, playlist, { listThumb = true })
			end

			if clone:IsA("GuiObject") then
				applyPlaylistRowState(clone, if selectedPlaylistId == id then selectedTemplate else normalTemplate)
			end

			clone.Name = id
			clone.LayoutOrder = REQUEST_PLAYLIST_USER_LAYOUT_BASE + index
			clone.Visible = true

			if clone:IsA("TextButton") then
				bindTrackedClickable(row.connections, clone, function()
					if self._onPlaylistSelected then
						self._onPlaylistSelected(id)
					end
				end)
			end
		end)
	end
	
	-- ============================================================
	-- Track list render (Request tab, 2 kolom)
	-- ============================================================
	
	function MusicPlayerUIBinder:renderTracks(tracks: { any }, searchQuery: string)
		local refs = self._refs
		local state = self._store:get()
		local playlistsById = state.playlists or {}
		local _, newDropsPlaylistId = getSpecialPlaylistIds(self._config)
		refs.trackTemplateLeft.Visible = false
		refs.trackTemplateRight.Visible = false
	
		local filtered = buildOrderedTrackEntries(tracks, searchQuery, state.selectedPlaylistId, newDropsPlaylistId)
		local leftTracks = {} :: { any }
		local rightTracks = {} :: { any }
		for index, track in ipairs(filtered) do
			if index % 2 == 1 then
				table.insert(leftTracks, track)
			else
				table.insert(rightTracks, track)
			end
		end
	
		local function renderRequestTrackRow(row: PooledRow, track: any, index: number)
			local parentPlaylist = playlistsById[track.playlistId] or track.playlist
			local coverSource = resolveCoverSourceForTrack(track, parentPlaylist)
	
			local clone = row.instance
			local feedbackLocked = false
			local function requestTrack()
				if feedbackLocked then
					return
				end
				if self._isAddToQueueModalOpen then
					return
				end
				if track.id then
					self:openAddToQueueConfirmation(track, parentPlaylist)
				end
			end
	
			if clone:IsA("TextButton") then
				(clone :: TextButton).AutoButtonColor = false
				(clone :: TextButton).Active = true
				(clone :: TextButton).Interactable = true
			end
	
			-- TrackWrapperTemplate structure (dari GUI dump):
			-- TrackInformationWrapper -> TrackInformation -> TrackDetails -> TrackTitle [TextLabel]
			-- TrackInformation -> AddToQueueWrapper -> AddToQueueButton [TextButton]
			local infoWrap = clone:FindFirstChild("TrackInformationWrapper")
			if infoWrap then
				local info = infoWrap:FindFirstChild("TrackInformation")
				if info then
					local details = info:FindFirstChild("TrackDetails")
					if details then
						local titleLabel = details:FindFirstChild("TrackTitle")
						if titleLabel and titleLabel:IsA("TextLabel") then
							local label = titleLabel :: TextLabel
							applyVirtualTrackTitle(label, track.name or "")
						end
	
						local creatorLabel = details:FindFirstChild("TrackCreator")
						if creatorLabel and creatorLabel:IsA("TextLabel") then
							(creatorLabel :: TextLabel).Text = track.creator or ""
						end
					end
					local addWrap = info:FindFirstChild("AddToQueueWrapper")
					if addWrap then
						local trackLengthLabel = addWrap:FindFirstChild("TrackLength")
						if trackLengthLabel and trackLengthLabel:IsA("TextLabel") then
							local totalSeconds = math.max(0, math.floor(tonumber(track.totalDuration) or 0))
							local minutes = math.floor(totalSeconds / 60)
							local seconds = totalSeconds % 60
							(trackLengthLabel :: TextLabel).Text = string.format("%02d:%02d", minutes, seconds)
						end
	
						local addBtn = addWrap:FindFirstChild("AddToQueueButton")
						local addIcon = if addBtn then addBtn:FindFirstChild("AddToQueueIconBefore") else nil
						resetRequestTrackFeedback(addBtn, addIcon)
	
						if addBtn and addBtn:IsA("GuiButton") then
							local addQueueButton = addBtn :: GuiButton
							addQueueButton.Active = true
							addQueueButton.Interactable = true
						end
	
						if addIcon and addIcon:IsA("GuiButton") then
							local addQueueIcon = addIcon :: GuiButton
							addQueueIcon.Active = true
							addQueueIcon.Interactable = true
						end
	
						if addWrap:IsA("GuiObject") then
							local addWrapGui = addWrap :: GuiObject
							addWrapGui.Active = true
							table.insert(
								row.connections,
								addWrapGui.InputBegan:Connect(function(input)
									if
										input.UserInputType == Enum.UserInputType.MouseButton1
										or input.UserInputType == Enum.UserInputType.Touch
									then
										requestTrack()
									end
								end)
							)
						end
	
						if addBtn then
							bindTrackedClickable(row.connections, addBtn, requestTrack)
							if addIcon then
								bindTrackedClickable(row.connections, addIcon, requestTrack)
							end
						end
					end
				end
			end
	
			-- Apply cover style to track's playlist cover if available
			if coverSource then
				local coverElement = clone:FindFirstChild("PlaylistCover")
					or clone:FindFirstChild("TrackCover")
					or clone:FindFirstChild("RelatedPlaylistCover")
				if coverElement then
					self:applyCoverStyle(coverElement, coverSource, { listThumb = true })
				end
			end
	
			if clone:IsA("GuiButton") then
				bindTrackedClickable(row.connections, clone, requestTrack)
			end
	
			clone.Name = track.id or tostring(index)
			clone.LayoutOrder = VIRTUAL_ROW_LAYOUT_BASE + index
			clone.Visible = true
		end
	
		renderVirtualList(self, {
			key = "requestTracksLeft",
			scroll = refs.scrollableTrackLeft,
			pool = self._requestTrackLeftRowPool,
			template = refs.trackTemplateLeft,
			items = leftTracks,
			renderRow = renderRequestTrackRow,
		})
		renderVirtualList(self, {
			key = "requestTracksRight",
			scroll = refs.scrollableTrackRight,
			pool = self._requestTrackRightRowPool,
			template = refs.trackTemplateRight,
			items = rightTracks,
			renderRow = renderRequestTrackRow,
		})
	end
	
	function MusicPlayerUIBinder:setManageSubView(subView: string, options: { preserveEditing: boolean? }?)
		local refs = self._refs
		local blur = refs.utilitiesBackdropBlur
		local playlistModal = refs.formPlaylist
		local trackModal = refs.formTrack
		local preserveEditing = options ~= nil and options.preserveEditing == true
	
		local function resetModal(modal: GuiObject?)
			if not modal then
				return
			end
	
			modal.Visible = false
			local modalScale = modal:FindFirstChildWhichIsA("UIScale")
			if modalScale then
				modalScale.Scale = 1
			end
		end
	
		local function openModal(modal: GuiObject?)
			if not modal then
				return
			end
	
			modal.Visible = true
			local modalScale = modal:FindFirstChildWhichIsA("UIScale")
			if modalScale then
				modalScale.Scale = 1
			end
			if self._anim then
				self._anim:presentDialog(modal)
			end
		end
	
		local function hideMainWrapperForManageForm()
			if refs.mainWrapper and refs.mainWrapper.Visible then
				self._manageFormHiddenMainWrapper = true
				refs.mainWrapper.Visible = false
			end
		end
	
		local function restoreMainWrapperAfterManageForm()
			if self._manageFormHiddenMainWrapper and refs.mainWrapper then
				refs.mainWrapper.Visible = true
			end
			self._manageFormHiddenMainWrapper = false
		end
	
		local normalizedSubView = if subView == "create_playlist_focus"
			then "edit_playlist"
			elseif subView == "create_track_focus" then "edit_track"
			else subView
	
		if normalizedSubView == "edit_playlist" then
			-- Close all other modal layers before opening
			self:closeVoteModal(true)
			self:closeAddToQueueConfirmation(true)
			self:closePlaylistRelatedModal(true)
			self:closeTrackRelatedModal(true)
			resetModal(trackModal)
			blur.Visible = true
			blur.Active = true
			blur.ZIndex = math.max(playlistModal.ZIndex - 1, 0)
			blur.BackgroundTransparency = getModalBackdropTransparency()
			hideMainWrapperForManageForm()
			openModal(playlistModal)
			self._activeManageModal = playlistModal
		elseif normalizedSubView == "edit_track" then
			-- Close all other modal layers before opening
			self:closeVoteModal(true)
			self:closeAddToQueueConfirmation(true)
			self:closePlaylistRelatedModal(true)
			self:closeTrackRelatedModal(true)
			resetModal(playlistModal)
			blur.Visible = true
			blur.Active = true
			blur.ZIndex = math.max(trackModal.ZIndex - 1, 0)
			blur.BackgroundTransparency = getModalBackdropTransparency()
			hideMainWrapperForManageForm()
			openModal(trackModal)
			self._activeManageModal = trackModal
		else
			resetModal(playlistModal)
			resetModal(trackModal)
			restoreMainWrapperAfterManageForm()
			blur.Active = false
			blur.Visible = false
			blur.BackgroundTransparency = 1
			self._activeManageModal = nil
		end
	
		local storePatch: { [string]: any } = { manageSubView = subView }
		if normalizedSubView ~= "edit_track" and normalizedSubView ~= "edit_playlist" then
			if not preserveEditing then
				storePatch.editingTrack = nil
				storePatch.editingPlaylist = nil
				self._trackFormCreateMode = true
				self._playlistFormCreateMode = true
			end
		end
		self._store:set(storePatch)
	end
	
	function MusicPlayerUIBinder:_closeManageFormForConfirmation()
		local refs = self._refs
		if self._activeManageModal then
			self._activeManageModal.Visible = false
			self._activeManageModal = nil
		end
		if refs.formPlaylist then
			refs.formPlaylist.Visible = false
		end
		if refs.formTrack then
			refs.formTrack.Visible = false
		end
		if refs.utilitiesBackdropBlur then
			refs.utilitiesBackdropBlur.Active = false
			refs.utilitiesBackdropBlur.Visible = false
			refs.utilitiesBackdropBlur.BackgroundTransparency = 1
		end
	end
	
	-- Manage form copy
	
	function MusicPlayerUIBinder:_syncManageFormCopy(kind: "playlist" | "track", isEditing: boolean)
		local form: GuiObject
		local titleNames: { string }
		local primaryButtonNames: { string }
		local copy: ManageFormCopy
	
		if kind == "playlist" then
			form = self._refs.formPlaylist
			titleNames = {
				"CreateorCustomPlaylistTitle",
				"CreateorEditPlaylistTitle",
				"PlaylistFormTitle",
				"PlaylistTitle",
			}
			primaryButtonNames = { "CreateorSavePlaylistButton" }
			copy = if isEditing then PLAYLIST_FORM_COPY.update else PLAYLIST_FORM_COPY.create
		else
			form = self._refs.formTrack
			titleNames = {
				"AddorEditTrackTitle",
				"UploadorCustomTrackTitle",
				"CreateorCustomTrackTitle",
				"UploadorEditTrackTitle",
				"TrackFormTitle",
				"TrackTitle",
			}
			primaryButtonNames = { "UploadorSaveTrackButton" }
			copy = if isEditing then TRACK_FORM_COPY.update else TRACK_FORM_COPY.create
		end
	
		local actionWrapper = getActionWrapper(form)
		local primaryButton = findFirstByNames(actionWrapper, primaryButtonNames)
		local cancelButton = if actionWrapper then actionWrapper:FindFirstChild("CancelButton", true) else nil
		local titleDisplay = getFormTitleDisplay(form, titleNames)
		local helperDisplay = nil :: Instance?
		if actionWrapper and primaryButton and not hasMultipleDirectChildrenNamed(actionWrapper, primaryButton.Name) then
			helperDisplay = getFormHelperDisplay(actionWrapper, primaryButton, cancelButton)
		end
	
		setTextDisplay(titleDisplay, copy.title)
		setTextDisplay(helperDisplay, copy.helper)
		if actionWrapper then
			for _, name in ipairs(primaryButtonNames) do
				forEachDirectChildByName(actionWrapper, name, function(child)
					setButtonDisplayText(child, copy.button)
				end)
			end
		else
			setButtonDisplayText(primaryButton, copy.button)
		end
	end
	
	-- Form validation
	
	function MusicPlayerUIBinder:validatePlaylistForm(data: { [string]: any }): (boolean, string)
		if not data.name or data.name == "" then
			return false, "Playlist name is required"
		end
		if #data.name > 50 then
			return false, "Playlist name too long (max 50 characters)"
		end
		-- Validate cover selection
		if not data.coverType or (data.coverType ~= "gradient" and data.coverType ~= "image") then
			return false, "Please select a cover style"
		end
		if data.coverType == "gradient" and (not data.coverValue or data.coverValue < 1) then
			return false, "Please select a color gradient"
		end
		if data.coverType == "image" and (not data.coverValue or data.coverValue == "") then
			return false, "Please enter an image asset ID"
		end
		-- Font is optional, will use default if not set
		return true, ""
	end
	
	function MusicPlayerUIBinder:validateTrackForm(data: { [string]: any }): (boolean, string)
		if not data.name or data.name == "" then
			return false, "Track name is required"
		end
		if not data.creator or data.creator == "" then
			return false, "Creator name is required"
		end
		if not data.playlistId or data.playlistId == "" then
			return false, "Please select a playlist"
		end
		if not data.parts or #data.parts == 0 then
			return false, "At least one audio ID is required"
		end
		-- Validate audio IDs are numbers
		for i, part in ipairs(data.parts) do
			if tonumber(part) == nil then
				return false, "Audio ID " .. tostring(i) .. " must be a number"
			end
		end
		return true, ""
	end
	
	-- Form helpers
	
	local function getPlaylistFormScrollable(formPlaylist: Instance?): Instance?
		return formPlaylist and formPlaylist:FindFirstChild("ScrollablePlayerList")
	end
	
	local function getCustomizeCoverParts(formPlaylist: Instance?): (
		Instance?,
		Instance?,
		Instance?,
		Instance?,
		Instance?,
		Instance?,
		Instance?,
		Instance?
	)
		local scrollable = getPlaylistFormScrollable(formPlaylist)
		local customizeCover = scrollable and scrollable:FindFirstChild("2-CustomizeCover")
		local selectorStyle = customizeCover and customizeCover:FindFirstChild("SelectorStyle")
		local colorTabBtn = selectorStyle and selectorStyle:FindFirstChild("ColorTabButton")
		local imageTabBtn = selectorStyle and selectorStyle:FindFirstChild("ImageTabButton")
		local canvasGroup = customizeCover and customizeCover:FindFirstChild("CanvasGroup")
		local colorTemplateList = canvasGroup and canvasGroup:FindFirstChild("ColorTemplateList")
		local inputImageID = canvasGroup and canvasGroup:FindFirstChild("InputImageID")
		local selectFontFace = scrollable and scrollable:FindFirstChild("3-SelectFontFace")
		return customizeCover,
			colorTabBtn,
			imageTabBtn,
			canvasGroup,
			colorTemplateList,
			inputImageID,
			selectFontFace,
			selectorStyle
	end
	
	local function getPlaylistVisibilityParts(formPlaylist: Instance?): (Instance?, TextButton?, TextButton?)
		local scrollable = getPlaylistFormScrollable(formPlaylist)
		local visibilityField = scrollable and scrollable:FindFirstChild("4-PlaylistVisibility")
		local list = visibilityField and visibilityField:FindFirstChild("SelectFontFaceList")
		local scroll = list and list:FindFirstChild("ScrollableFontFace")
		local privateBtn = scroll and scroll:FindFirstChild("Normal")
		local publicBtn = scroll and scroll:FindFirstChild("Selected")
		return visibilityField,
			if privateBtn and privateBtn:IsA("TextButton") then privateBtn :: TextButton else nil,
			if publicBtn and publicBtn:IsA("TextButton") then publicBtn :: TextButton else nil
	end
	
	function MusicPlayerUIBinder:populateTrackForm(track: any?)
		local refs = self._refs
		local store = self._store
		local currentState = store:get()
		local isCreateMode = track == nil
		self._trackFormCreateMode = isCreateMode
		self:_syncManageFormCopy("track", not isCreateMode)
		if track then
			setTextInput(refs.formTrackNameField, track.name or "")
			setTextInput(refs.formTrackCreatorField, track.creator or "")
			for i, partFrame in ipairs(refs.formTrackIdParts) do
				setTextInput(partFrame, (track.parts and track.parts[i]) or "")
			end
			-- Per-track playback speed: kalau track punya nilai sendiri,
			-- tampilkan di TextBox; kalau nil, biarin kosong (= pakai global).
			if refs.formTrackPlaybackSpeedField then
				local speed = (track :: any).playbackSpeed
				if typeof(speed) == "number" and speed > 0 then
					setTextInput(refs.formTrackPlaybackSpeedField, tostring(speed))
				else
					setTextInput(refs.formTrackPlaybackSpeedField, "")
				end
			end
			store:set({
				selectedTrackPlaylistId = track.playlistId or nil,
			})
		else
			local preservedPlaylistId = currentState.selectedTrackPlaylistId
			if preservedPlaylistId and not (currentState.playlists or {})[preservedPlaylistId] then
				preservedPlaylistId = nil
			end
			-- Clear for create mode
			setTextInput(refs.formTrackNameField, "")
			setTextInput(refs.formTrackCreatorField, "")
			for _, partFrame in ipairs(refs.formTrackIdParts) do
				setTextInput(partFrame, "")
			end
			if refs.formTrackPlaybackSpeedField then
				setTextInput(refs.formTrackPlaybackSpeedField, "")
			end
			store:set({
				editingTrack = nil,
				selectedTrackPlaylistId = preservedPlaylistId,
			})
		end
	
		self:renderTrackPlaylistOptions(store:get().playlists or {})
	end
	
	function MusicPlayerUIBinder:populatePlaylistForm(playlist: any?)
		local refs = self._refs
		local store = self._store
		local isCreateMode = playlist == nil
		self._playlistFormCreateMode = isCreateMode
		self:_syncManageFormCopy("playlist", not isCreateMode)
	
		if playlist then
			setTextInput(refs.formPlaylistNameField, playlist.name or "")
	
			-- Set preview name for gradient cards
			store:set({ playlistNamePreview = playlist.name or "" })
	
			-- Populate cover selection
			if playlist.coverType == "image" then
				store:set({
					selectedCoverType = "image",
					selectedCoverValue = playlist.coverValue or "",
				})
				self:_setCoverTab("image")
				local _, _, _, _, _, inputImageID = getCustomizeCoverParts(refs.formPlaylist)
				if inputImageID and inputImageID:IsA("TextBox") then
					(inputImageID :: TextBox).Text = playlist.coverValue or ""
				end
			else
				-- Gradient mode
				local gradientIndex = playlist.coverValue or 1
				store:set({
					selectedCoverType = "gradient",
					selectedCoverValue = gradientIndex,
				})
				self:_setCoverTab("color")
				self:_selectGradient(gradientIndex)
			end
	
			-- Populate font selection
			if playlist.fontFace then
				local config = self._config
				if config and config.FONT_PRESETS then
					-- Find font index
					local fontIndex = 1
					for i, fontName in ipairs(config.FONT_PRESETS) do
						if fontName == playlist.fontFace then
							fontIndex = i
							break
						end
					end
					self:_selectFont(fontIndex, playlist.fontFace)
				end
			end
	
			local visibility = type(playlist.visibility) == "string" and playlist.visibility or "public"
			store:set({ selectedPlaylistVisibility = visibility })
			self:_selectPlaylistVisibility(visibility)
		else
			-- Clear for create mode
			setTextInput(refs.formPlaylistNameField, "")
	
			-- Reset preview name
			store:set({ playlistNamePreview = "" })
	
			-- Reset to defaults
			store:set({
				editingPlaylist = nil,
				selectedCoverType = "gradient",
				selectedCoverValue = 1,
				selectedFontFace = "Original",
				selectedPlaylistVisibility = "public",
			})
	
			self:_setCoverTab("color")
			local _, _, _, _, _, inputImageID = getCustomizeCoverParts(refs.formPlaylist)
			if inputImageID and inputImageID:IsA("TextBox") then
				(inputImageID :: TextBox).Text = ""
			end
	
			-- Select first gradient and font
			self:_selectGradient(1)
			self:_selectFont(1, "Original")
			self:_selectPlaylistVisibility("public")
		end
	end
	
	function MusicPlayerUIBinder:readTrackForm(): { [string]: any }
		local refs = self._refs
		local state = self._store:get()
		local parts: { string } = {}
		for _, partFrame in ipairs(refs.formTrackIdParts) do
			local v = getTextInput(partFrame)
			if v ~= "" then
				table.insert(parts, v)
			end
		end
		-- Per-track playback speed (optional). Tolerant ke input user:
		--   "2.3", "2.3x", " 0.85 " semua valid. Empty/invalid = nil
		--   (server fallback ke Config.Music.PLAYBACK_SPEED).
		local playbackSpeed: number? = nil
		if refs.formTrackPlaybackSpeedField then
			local raw = getTextInput(refs.formTrackPlaybackSpeedField)
			if raw ~= "" then
				local cleaned = (raw:gsub("[xX%s]", ""))
				local n = tonumber(cleaned)
				if n and n > 0 then
					playbackSpeed = n
				end
			end
		end
		return {
			name = getTextInput(refs.formTrackNameField),
			playlistId = state.selectedTrackPlaylistId or getTextInput(refs.formTrackPlaylistField),
			creator = getTextInput(refs.formTrackCreatorField),
			parts = parts,
			playbackSpeed = playbackSpeed,
		}
	end
	
	function MusicPlayerUIBinder:readPlaylistForm(): { [string]: any }
		local refs = self._refs
		local store = self._store
		local state = store:get()
	
		return {
			name = getTextInput(refs.formPlaylistNameField),
			coverType = state.selectedCoverType or "gradient", -- "gradient" or "image"
			coverValue = state.selectedCoverValue or 1, -- gradient index or image assetId
			fontFace = if state.selectedCoverType == "image" then "Original" else (state.selectedFontFace or "Original"),
			visibility = state.selectedPlaylistVisibility or "public",
		}
	end
	
	function MusicPlayerUIBinder:_selectPlaylistVisibility(visibility: string)
		local refs = self._refs
		local store = self._store
		local _, privateBtn, publicBtn = getPlaylistVisibilityParts(refs.formPlaylist)
		if not privateBtn or not publicBtn then
			return
		end
	
		local selectedVisibility = if visibility == "private" then "private" else "public"
		copySelectionTemplateVisual(privateBtn, if selectedVisibility == "private" then publicBtn else privateBtn)
		copySelectionTemplateVisual(publicBtn, if selectedVisibility == "public" then publicBtn else privateBtn)
		store:set({ selectedPlaylistVisibility = selectedVisibility })
	end
	
	function MusicPlayerUIBinder:bindPlaylistVisibility()
		local refs = self._refs
		local _, privateBtn, publicBtn = getPlaylistVisibilityParts(refs.formPlaylist)
		if not privateBtn or not publicBtn then
			return
		end
	
		trackConnection(
			self,
			privateBtn.Activated:Connect(function()
				self:_selectPlaylistVisibility("private")
			end)
		)
		trackConnection(
			self,
			publicBtn.Activated:Connect(function()
				self:_selectPlaylistVisibility("public")
			end)
		)
	
		self:_selectPlaylistVisibility(self._store:get().selectedPlaylistVisibility or "public")
	end
	
	function MusicPlayerUIBinder:bindRequestFromId()
		local refs = self._refs
		if not refs.requestFromIdButton then
			return
		end
	
		local function submitRequestFromId()
			if not refs.requestFromIdInput or not self._onResolveRequestAsset then
				return
			end
			local raw = refs.requestFromIdInput.Text
			if type(raw) ~= "string" or raw:match("^%s*$") then
				if self._onFormNotify then
					self._onFormNotify("warning", "Asset ID required", "Enter a Roblox audio asset ID first.")
				end
				return
			end
			self._onResolveRequestAsset(raw)
		end
	
		trackConnection(self, refs.requestFromIdButton.Activated:Connect(submitRequestFromId))
		if refs.requestFromIdInput then
			trackConnection(
				self,
				refs.requestFromIdInput.FocusLost:Connect(function(enterPressed: boolean)
					if enterPressed then
						submitRequestFromId()
					end
				end)
			)
		end
	end
	
	-- ============================================================
	-- COVER & FONT CUSTOMIZATION
	-- ============================================================
	
	local function setCoverTabButtonVisual(button: Instance?, selected: boolean)
		if not button or not button:IsA("GuiObject") then
			return
		end
		local gui = button :: GuiObject
		gui.BackgroundColor3 = if selected then Color3.fromRGB(8, 8, 8) else Color3.fromRGB(48, 48, 48)
		gui.BackgroundTransparency = 0
		setAllChildGradientsEnabled(gui, false)
	
		if button:IsA("TextButton") then
			local textButton = button :: TextButton
			textButton.TextTransparency = if selected then 0 else 0.05
		else
			local textLabel = button:FindFirstChildWhichIsA("TextLabel", true)
			if textLabel then
				textLabel.TextTransparency = if selected then 0 else 0.05
			end
		end
	end
	
	function MusicPlayerUIBinder:_setCoverTab(tabType: string)
		local _, colorTabBtn, imageTabBtn, _, colorTemplateList, inputImageID, selectFontFace =
			getCustomizeCoverParts(self._refs.formPlaylist)
		if not colorTemplateList or not inputImageID then
			return
		end
	
		local isImage = tabType == "image"
		if colorTemplateList:IsA("GuiObject") then
			(colorTemplateList :: GuiObject).Visible = not isImage
		end
		if inputImageID:IsA("GuiObject") then
			(inputImageID :: GuiObject).Visible = isImage
		end
		if selectFontFace and selectFontFace:IsA("GuiObject") then
			(selectFontFace :: GuiObject).Visible = not isImage
		end
	
		setCoverTabButtonVisual(colorTabBtn, not isImage)
		setCoverTabButtonVisual(imageTabBtn, isImage)
		self._store:set({ selectedCoverType = if isImage then "image" else "gradient" })
	end
	
	function MusicPlayerUIBinder:applyCoverStyle(
		coverElement: Instance,
		playlist: any,
		opts: { listThumb: boolean? }?
	)
		-- Apply cover style (gradient or image) to a playlist cover element
		-- coverElement can be an ImageLabel (playlist cover) or a Frame container
		-- that owns a background gradient (now playing wrapper).

		local imageLabel = if coverElement:IsA("ImageLabel") then coverElement else nil
		local useListThumb = opts ~= nil and opts.listThumb == true

		local config = self._config
		if not config then
			return
		end

		-- Default to gradient if no coverType specified
		local coverType = playlist.coverType or "gradient"
		local textLabel = if imageLabel then findCoverTextLabel(imageLabel) else nil
		local backgroundGradient = coverElement:FindFirstChild("BackgroundNowPlaying(DependsonPlaylist)", true)
		local targetGradient = if imageLabel
			then (imageLabel :: ImageLabel):FindFirstChildOfClass("UIGradient")
			else if backgroundGradient and backgroundGradient:IsA("UIGradient") then backgroundGradient else nil
		local strokeTransparencyAttribute = "MusicCoverBaseStrokeTransparency"
		local backgroundTransparencyAttribute = "MusicCoverBaseBackgroundTransparency"

		local function applyCoverText()
			if not textLabel then
				return
			end
			textLabel.Visible = coverType ~= "image"
			textLabel.Text = playlist.name or ""

			local success = applyNamedFont(textLabel, tostring(playlist.fontFace or "Original"))
			if not success then
				textLabel.FontFace = Font.fromEnum(Enum.Font.SourceSans)
			end
		end

		-- Disable ALL UIGradient descendants when in image mode (CoverImageType rule)
		local function setAllGradientsEnabled(enabled: boolean)
			for _, descendant in ipairs(coverElement:GetDescendants()) do
				if descendant:IsA("UIGradient") then
					descendant.Enabled = enabled
				end
			end
			if targetGradient and targetGradient:IsA("UIGradient") then
				targetGradient.Enabled = enabled
			end
		end

		local function setImageCoverChromeVisible(root: Instance, visible: boolean)
			for _, descendant in ipairs(root:GetDescendants()) do
				if descendant:IsA("UIStroke") then
					local stroke = descendant :: UIStroke
					local baseTransparency = stroke:GetAttribute(strokeTransparencyAttribute)
					if type(baseTransparency) ~= "number" then
						baseTransparency = stroke.Transparency
						stroke:SetAttribute(strokeTransparencyAttribute, baseTransparency)
					end
					stroke.Transparency = if visible then baseTransparency else 1
				end
			end
		end

		local function setImageCoverBackgroundVisible(label: ImageLabel, visible: boolean)
			local baseTransparency = label:GetAttribute(backgroundTransparencyAttribute)
			if type(baseTransparency) ~= "number" then
				baseTransparency = label.BackgroundTransparency
				label:SetAttribute(backgroundTransparencyAttribute, baseTransparency)
			end
			label.BackgroundTransparency = if visible then baseTransparency else 1
		end

		local function setCoverImage(label: ImageLabel, uri: string)
			if label.Image ~= uri then
				label.Image = uri
			end
		end

		if coverType == "image" then
			setAllGradientsEnabled(false)
			if imageLabel then
				local typedImageLabel = imageLabel :: ImageLabel
				setImageCoverChromeVisible(typedImageLabel, false)
				setImageCoverBackgroundVisible(typedImageLabel, false)
				local uri = if useListThumb
					then (normalizeListCoverUri(playlist.coverValue) or "")
					else (getImageCoverUri(playlist.coverValue) or "")
				setCoverImage(typedImageLabel, uri)
				applyCoverText()
			elseif targetGradient and targetGradient:IsA("UIGradient") then
				targetGradient.Color = ColorSequence.new(Color3.fromRGB(22, 22, 22), Color3.fromRGB(0, 0, 0))
				targetGradient.Rotation = 90
			end
		else
			-- Gradient mode: enable UIGradient, set colors
			local gradientIndex = playlist.coverValue or 1
			local gradients = config.COVER_GRADIENTS

			if gradients and gradientIndex >= 1 and gradientIndex <= #gradients then
				local gradient = gradients[gradientIndex]

				local uiGradient = targetGradient
				if imageLabel and not uiGradient then
					local created = Instance.new("UIGradient")
					created.Parent = imageLabel
					uiGradient = created
				end

				if uiGradient and uiGradient:IsA("UIGradient") then
					uiGradient.Enabled = true
					uiGradient.Color = buildCoverGradientColorSequence(gradient)
					uiGradient.Rotation = getCoverGradientRotation(gradient)
				end

				if imageLabel then
					-- Reset image to empty (show gradient only)
					local typedImageLabel = imageLabel :: ImageLabel
					setImageCoverChromeVisible(typedImageLabel, true)
					setImageCoverBackgroundVisible(typedImageLabel, true)
					setCoverImage(typedImageLabel, "")
				end
				applyCoverText()
			end
		end
	end
	
	function MusicPlayerUIBinder:_populatePlaylistPreviewCard(template: Instance, playlist: any)
		local name = if type(playlist) == "table" then tostring(playlist.name or "") else ""
		local trackCount = getPlaylistTrackCount(playlist)
	
		local info = template:FindFirstChild("PlaylistInformation")
		if info then
			local nameLabel = info:FindFirstChild("PlaylistName")
			if nameLabel and nameLabel:IsA("TextLabel") then
				(nameLabel :: TextLabel).Text = name
			end
	
			local totalTrackLabel = info:FindFirstChild("TotalTrack")
			if totalTrackLabel and totalTrackLabel:IsA("TextLabel") then
				(totalTrackLabel :: TextLabel).Text = formatTrackCount(trackCount)
			end
		end
	
		local coverElement = template:FindFirstChild("PlaylistCover")
		if coverElement and type(playlist) == "table" then
			self:applyCoverStyle(coverElement, playlist)
			local coverName = coverElement:FindFirstChild("PlaylistName")
			if coverName and coverName:IsA("TextLabel") then
				(coverName :: TextLabel).Text = name
			end
		end
	end
	
	function MusicPlayerUIBinder:_buildUpdatedPlaylistPreview(
		beforePlaylist: any?,
		formData: { [string]: any }
	): { [string]: any }
		local preview: { [string]: any } = {}
		if type(beforePlaylist) == "table" then
			for key, value in pairs(beforePlaylist) do
				preview[key] = value
			end
		end
		preview.name = formData.name
		preview.coverType = formData.coverType
		preview.coverValue = formData.coverValue
		preview.fontFace = formData.fontFace
		preview.visibility = formData.visibility or preview.visibility or "public"
		preview.trackIds = if type(preview.trackIds) == "table" then preview.trackIds else {}
		return preview
	end
	
	function MusicPlayerUIBinder:_buildUpdatedTrackPreview(
		beforeTrack: any?,
		formData: { [string]: any }
	): { [string]: any }
		local preview: { [string]: any } = {}
		if type(beforeTrack) == "table" then
			for key, value in pairs(beforeTrack) do
				preview[key] = value
			end
		end
	
		preview.name = formData.name
		preview.creator = formData.creator
		preview.parts = formData.parts
		preview.playlistId = formData.playlistId
		if formData.id ~= nil then
			preview.id = formData.id
		end
	
		local playlistsById = self._store:get().playlists or {}
		local playlistId = tostring(formData.playlistId or "")
		if playlistId ~= "" then
			preview.playlist = playlistsById[playlistId] or preview.playlist
		end
	
		preview.totalDuration = tonumber(formData.totalDuration) or tonumber(preview.totalDuration) or 0
		return preview
	end
	
	function MusicPlayerUIBinder:_populateTrackPreviewCard(template: Instance, track: any, playlist: any?)
		local previewTrack = if type(track) == "table" then track else {}
		local resolvedPlaylist = playlist or previewTrack.playlist
	
		template.Visible = true
	
		local coverElement = template:FindFirstChild("RelatedPlaylistCover")
		if coverElement then
			if resolvedPlaylist then
				self:applyCoverStyle(coverElement, resolvedPlaylist)
			end
	
			local playlistNameLabel = findCoverTextLabel(coverElement)
			if playlistNameLabel then
				playlistNameLabel.Text = (resolvedPlaylist and resolvedPlaylist.name) or ""
			end
		end
	
		local infoWrap = template:FindFirstChild("TrackInformationWrapper")
		local info = infoWrap and infoWrap:FindFirstChild("TrackInformation")
		local nestedDetails = info and info:FindFirstChild("TrackDetails")
		local details = nestedDetails or info
		if details then
			local titleLabel = details:FindFirstChild("TrackTitle")
			if titleLabel and titleLabel:IsA("TextLabel") then
				(titleLabel :: TextLabel).Text = tostring(previewTrack.name or "")
			end
	
			local creatorLabel = details:FindFirstChild("TrackCreator") or details:FindFirstChild("TrackLength")
			if creatorLabel and creatorLabel:IsA("TextLabel") then
				(creatorLabel :: TextLabel).Text = tostring(previewTrack.creator or "")
			end
		end
	
		local addWrap = if info then (info:FindFirstChild("AddToQueueWrapper") or info) else nil
		if addWrap then
			local trackLengthLabel = addWrap:FindFirstChild("TrackLength")
			if trackLengthLabel and trackLengthLabel:IsA("TextLabel") then
				(trackLengthLabel :: TextLabel).Text = formatClock(tonumber(previewTrack.totalDuration) or 0)
			end
	
			local addBtn = addWrap:FindFirstChild("AddToQueueButton")
			if addBtn and addBtn:IsA("GuiObject") then
				addBtn.Visible = false
			end
		end
	end
	
	function MusicPlayerUIBinder:_hidePlaylistRelatedModalFrames()
		local refs = self._refs
		refs.addToPlaylistConfirmation.Visible = false
		refs.deletePlaylistConfirmation.Visible = false
		refs.editPlaylistConfirmation.Visible = false
	end
	
	function MusicPlayerUIBinder:_openPlaylistRelatedModal(modal: Frame)
		local refs = self._refs
		local blur = self:_getPlaylistRelatedBlur()
		local camera = Workspace.CurrentCamera
		self:_hidePlaylistRelatedModalFrames()
		self._activePlaylistRelatedModal = modal
	
		refs.playlistRelatedBackdropBlur.Active = true
		refs.playlistRelatedBackdropBlur.ZIndex = modal.ZIndex - 1
		refs.playlistRelatedBackdropBlur.BackgroundTransparency = 1
		refs.playlistRelatedBackdropBlur.Visible = true
		TweenService:Create(refs.playlistRelatedBackdropBlur, FADE_INFO_FAST, {
			BackgroundTransparency = getModalBackdropTransparency(),
		}):Play()
		playModalBlur(blur, getPanelBlurSize())
		if camera then
			self._playlistRelatedBaseFov = camera.FieldOfView
			self:_tweenPlaylistRelatedCamera(math.max(1, camera.FieldOfView - PLAYLIST_RELATED_CAMERA_FOV_DELTA))
		end
		self:_suppressPlaylistRelatedWorldChrome()
		self:_hideMainWrapperForPlaylistRelated()
		self._isPlaylistRelatedModalOpen = true
	
		self._anim:presentDialog(modal)
	end
	
	function MusicPlayerUIBinder:closePlaylistRelatedModal(immediate: boolean?, restoreMainWrapper: boolean?)
		local refs = self._refs
		local activeModal = self._activePlaylistRelatedModal
		local blur = self:_getPlaylistRelatedBlur()
		local restoreFov = self._playlistRelatedBaseFov
		local shouldRestoreMainWrapper = restoreMainWrapper ~= false
	
		self._pendingPlaylistModalAction = nil
		self._activePlaylistRelatedModal = nil
		self._isPlaylistRelatedModalOpen = false
		self._playlistRelatedBaseFov = nil
	
		if immediate then
			blur.Size = 0
			blur.Enabled = false
			if restoreFov then
				self:_tweenPlaylistRelatedCamera(restoreFov, true)
			end
			refs.playlistRelatedBackdropBlur.Visible = false
			refs.playlistRelatedBackdropBlur.Active = false
			refs.playlistRelatedBackdropBlur.BackgroundTransparency = getModalBackdropTransparency()
			self:_restorePlaylistRelatedWorldChrome()
			if shouldRestoreMainWrapper then
				self:_restoreMainWrapperAfterPlaylistRelated()
			else
				self:_clearPlaylistRelatedMainWrapperRestore()
			end
			if activeModal then
				local modalScale = activeModal:FindFirstChildWhichIsA("UIScale")
				if modalScale then
					modalScale.Scale = 1
				end
			end
			self:_hidePlaylistRelatedModalFrames()
			return
		end
	
		TweenService:Create(blur, FADE_INFO_FAST, {
			Size = 0,
		}):Play()
		if restoreFov then
			self:_tweenPlaylistRelatedCamera(restoreFov)
		end
		refs.playlistRelatedBackdropBlur.Active = false
		TweenService:Create(refs.playlistRelatedBackdropBlur, FADE_INFO_FAST, {
			BackgroundTransparency = 1,
		}):Play()
		task.delay(FADE_INFO_FAST.Time, function()
			if not self._isPlaylistRelatedModalOpen then
				blur.Enabled = false
				refs.playlistRelatedBackdropBlur.Visible = false
				refs.playlistRelatedBackdropBlur.Active = false
				refs.playlistRelatedBackdropBlur.BackgroundTransparency = getModalBackdropTransparency()
				self:_restorePlaylistRelatedWorldChrome()
			end
		end)
	
		if activeModal then
			self._anim:dismissDialog(activeModal, function()
				if self._isPlaylistRelatedModalOpen then
					return
				end
				self:_hidePlaylistRelatedModalFrames()
				if shouldRestoreMainWrapper then
					self:_restoreMainWrapperAfterPlaylistRelated()
				else
					self:_clearPlaylistRelatedMainWrapperRestore()
				end
			end)
		else
			self:_hidePlaylistRelatedModalFrames()
			if shouldRestoreMainWrapper then
				self:_restoreMainWrapperAfterPlaylistRelated()
			else
				self:_clearPlaylistRelatedMainWrapperRestore()
			end
		end
	end
	
	function MusicPlayerUIBinder:_openCreatePlaylistConfirmation(formData: { [string]: any })
		local refs = self._refs
		local preview = self:_buildUpdatedPlaylistPreview(nil, formData)
		self._pendingPlaylistModalAction = {
			action = "create",
			data = formData,
		}
		self:_closeManageFormForConfirmation()
		self:_populatePlaylistPreviewCard(refs.addToPlaylistTemplate, preview)
		self:_openPlaylistRelatedModal(refs.addToPlaylistConfirmation)
	end
	
	function MusicPlayerUIBinder:_openDeletePlaylistConfirmation(playlist: any, data: { [string]: any })
		local refs = self._refs
		self._pendingPlaylistModalAction = {
			action = "delete",
			data = data,
		}
		self:_populatePlaylistPreviewCard(refs.deletePlaylistTemplate, playlist)
		self:_openPlaylistRelatedModal(refs.deletePlaylistConfirmation)
	end
	
	function MusicPlayerUIBinder:_openUpdatePlaylistConfirmation(beforePlaylist: any, formData: { [string]: any })
		local refs = self._refs
		local afterPlaylist = self:_buildUpdatedPlaylistPreview(beforePlaylist, formData)
		self._pendingPlaylistModalAction = {
			action = "update",
			data = formData,
		}
		self:_closeManageFormForConfirmation()
		self:_populatePlaylistPreviewCard(refs.editPlaylistBeforeTemplate, beforePlaylist)
		self:_populatePlaylistPreviewCard(refs.editPlaylistAfterTemplate, afterPlaylist)
		self:_openPlaylistRelatedModal(refs.editPlaylistConfirmation)
	end
	
	function MusicPlayerUIBinder:_confirmPlaylistRelatedModal()
		local pending = self._pendingPlaylistModalAction
		if not pending then
			self:closePlaylistRelatedModal()
			return
		end
	
		local action = pending.action
		local data = pending.data
		self:closePlaylistRelatedModal()
		if action == "create" then
			self:_enterManageIdle(false)
		elseif action == "update" then
			self:setManageSubView("idle", { preserveEditing = true })
		else
			self:_enterManageIdle(false)
		end
		if self._onManagePlaylist then
			self._onManagePlaylist(action, data)
		end
	end
	
	function MusicPlayerUIBinder:bindCoverTabs()
		local refs = self._refs
		local store = self._store
	
		local _, colorTabBtn, imageTabBtn, _, colorTemplateList, inputImageID = getCustomizeCoverParts(refs.formPlaylist)
	
		if not colorTabBtn or not imageTabBtn or not colorTemplateList or not inputImageID then
			return
		end
	
		-- Bind tab buttons
		if colorTabBtn:IsA("TextButton") then
			trackConnection(
				self,
				(colorTabBtn :: TextButton).Activated:Connect(function()
					self:_setCoverTab("color")
				end)
			)
		end
	
		if imageTabBtn:IsA("TextButton") then
			trackConnection(
				self,
				(imageTabBtn :: TextButton).Activated:Connect(function()
					self:_setCoverTab("image")
				end)
			)
		end
	
		-- Bind image input TextBox
		if inputImageID:IsA("TextBox") then
			trackConnection(
				self,
				(inputImageID :: TextBox):GetPropertyChangedSignal("Text"):Connect(function()
					if not (inputImageID :: TextBox).Visible then
						return
					end
					local assetId = (inputImageID :: TextBox).Text
					store:set({
						selectedCoverType = "image",
						selectedCoverValue = assetId,
					})
				end)
			)
		end
	
		-- Default to color tab
		self:_setCoverTab("color")
	end
	
	function MusicPlayerUIBinder:bindColorSelection()
		local refs = self._refs
		local store = self._store
		local config = self._config
	
		if not config or not config.COVER_GRADIENTS then
			return
		end
	
		local customizeCover = select(1, getCustomizeCoverParts(refs.formPlaylist))
		if not customizeCover then
			return
		end
	
		local colorTemplateList = select(5, getCustomizeCoverParts(refs.formPlaylist))
		if not colorTemplateList then
			return
		end
	
		-- Find template cards (NormalState and SelectedState)
		local normalTemplate = colorTemplateList:FindFirstChild("NormalState")
		local selectedTemplate = colorTemplateList:FindFirstChild("SelectedState")
	
		if not normalTemplate or not selectedTemplate then
			return
		end
	
		-- Hide templates
		normalTemplate.Visible = false
		selectedTemplate.Visible = false
	
		-- Clear existing clones
		for _, child in ipairs(colorTemplateList:GetChildren()) do
			if child:IsA("TextButton") and child.Name:match("^GradientCard_") then
				child:Destroy()
			end
		end
	
		-- Create gradient cards from config
		local gradients = config.COVER_GRADIENTS
		for i, gradient in ipairs(gradients) do
			local card = normalTemplate:Clone()
			card.Name = "GradientCard_" .. tostring(i)
			card.Visible = true
			card.LayoutOrder = i
	
			-- Apply gradient to card's ImageLabel
			local imageLabel = card:FindFirstChild("ImageLabel")
			if imageLabel then
				local uiGradient = imageLabel:FindFirstChildOfClass("UIGradient")
				if not uiGradient then
					uiGradient = Instance.new("UIGradient")
					uiGradient.Parent = imageLabel
				end
	
				-- Set gradient colors and rotation
				uiGradient.Color = buildCoverGradientColorSequence(gradient)
				uiGradient.Rotation = getCoverGradientRotation(gradient)
	
				-- Find and setup the playlist name label
				local playlistNameLabel = imageLabel:FindFirstChild("PlaylistNameDynamic")
				if playlistNameLabel and playlistNameLabel:IsA("TextLabel") then
					-- Will be updated when playlist name changes
					(playlistNameLabel :: TextLabel).Text = ""
	
					-- Apply default font
					local defaultFont = store:get().selectedFontFace or "Original"
					local success = applyNamedFont(playlistNameLabel :: TextLabel, defaultFont)
					if not success then
						(playlistNameLabel :: TextLabel).FontFace = Font.fromEnum(Enum.Font.SourceSans)
					end
				end
	
				-- Find indicator frame
				local indicator = imageLabel:FindFirstChild("NormalorSelectedIndicatorsNormal")
				if indicator then
					local frame = indicator:FindFirstChild("Frame")
					if frame then
						frame.Visible = false -- Hidden by default
					end
				end
			end
	
			-- Bind click event
			if card:IsA("TextButton") then
				trackConnection(
					self,
					(card :: TextButton).Activated:Connect(function()
						self:_selectGradient(i)
					end)
				)
			end
	
			card.Parent = colorTemplateList
		end
	
		-- Select first gradient by default
		self:_selectGradient(1)
	
		-- Subscribe to playlist name changes to update preview
		trackUnsubscriber(
			self,
			store:subscribe("playlistNamePreview", function(name)
				self:_updateGradientPreviews(name)
			end)
		)
	end
	
	function MusicPlayerUIBinder:_selectGradient(index: number)
		local refs = self._refs
		local store = self._store
		self:_setCoverTab("color")
	
		local customizeCover = select(1, getCustomizeCoverParts(refs.formPlaylist))
		if not customizeCover then
			return
		end
	
		local colorTemplateList = select(5, getCustomizeCoverParts(refs.formPlaylist))
		if not colorTemplateList then
			return
		end
		local normalTemplate = colorTemplateList:FindFirstChild("NormalState")
		local selectedTemplate = colorTemplateList:FindFirstChild("SelectedState")
	
		-- Hide all indicators first
		for _, child in ipairs(colorTemplateList:GetChildren()) do
			if child:IsA("TextButton") and child.Name:match("^GradientCard_") then
				local isSelected = child.Name == "GradientCard_" .. tostring(index)
				copySelectionTemplateVisual(child, if isSelected then selectedTemplate else normalTemplate)
	
				local imageLabel = child:FindFirstChild("ImageLabel")
				if imageLabel then
					local indicator = imageLabel:FindFirstChild("NormalorSelectedIndicatorsNormal")
					if indicator then
						local frame = indicator:FindFirstChild("Frame")
						if frame then
							frame.Visible = false
						end
					end
				end
			end
		end
	
		-- Show indicator for selected card
		local selectedCard = colorTemplateList:FindFirstChild("GradientCard_" .. tostring(index))
		if selectedCard then
			local imageLabel = selectedCard:FindFirstChild("ImageLabel")
			if imageLabel then
				local indicator = imageLabel:FindFirstChild("NormalorSelectedIndicatorsNormal")
				if indicator then
					local frame = indicator:FindFirstChild("Frame")
					if frame then
						frame.Visible = true
					end
				end
			end
		end
	
		-- Update store
		store:set({
			selectedCoverType = "gradient",
			selectedCoverValue = index,
		})
	end
	
	function MusicPlayerUIBinder:_updateGradientPreviews(playlistName: string)
		-- Update playlist name text in all gradient preview cards
		local refs = self._refs
		local store = self._store
		local state = store:get()
	
		local customizeCover = select(1, getCustomizeCoverParts(refs.formPlaylist))
		if not customizeCover then
			return
		end
	
		local colorTemplateList = select(5, getCustomizeCoverParts(refs.formPlaylist))
		if not colorTemplateList then
			return
		end
	
		-- Update all gradient cards
		for _, child in ipairs(colorTemplateList:GetChildren()) do
			if child:IsA("TextButton") and child.Name:match("^GradientCard_") then
				local imageLabel = child:FindFirstChild("ImageLabel")
				if imageLabel then
					-- Find TextLabel (not PlaylistNameDynamic)
					local textLabel = imageLabel:FindFirstChild("PlaylistNameDynamic")
						or imageLabel:FindFirstChild("TextLabel")
					if textLabel and textLabel:IsA("TextLabel") then
						(textLabel :: TextLabel).Text = playlistName or ""
	
						-- Apply current selected font
						local fontFace = state.selectedFontFace or "Original"
						local success = applyNamedFont(textLabel :: TextLabel, fontFace)
						if not success then
							-- Fallback to default
							(textLabel :: TextLabel).FontFace = Font.fromEnum(Enum.Font.SourceSans)
						end
					end
				end
			end
		end
	end
	
	function MusicPlayerUIBinder:renderTrackPlaylistOptions(playlists: { [string]: any })
		local refs = self._refs
		local store = self._store
	
		local selectorField = refs.formTrackPlaylistField
		if not selectorField then
			return
		end
	
		local selectWrapper = selectorField:FindFirstChild("SelectWrapper")
		if not selectWrapper then
			return
		end
	
		local scrollablePlaylist = selectWrapper:FindFirstChild("ScrollablePlaylist")
		if not scrollablePlaylist or not scrollablePlaylist:IsA("ScrollingFrame") then
			return
		end
	
		local normalTemplate = scrollablePlaylist:FindFirstChild("Normal")
			or scrollablePlaylist:FindFirstChild("NormalState")
		local selectedTemplate = scrollablePlaylist:FindFirstChild("Selected")
			or scrollablePlaylist:FindFirstChild("SelectedState")
	
		if not normalTemplate or not selectedTemplate then
			return
		end
	
		if normalTemplate:IsA("GuiObject") then
			normalTemplate.Visible = false
		end
		if selectedTemplate:IsA("GuiObject") then
			selectedTemplate.Visible = false
		end
	
		for _, child in ipairs(scrollablePlaylist:GetChildren()) do
			if child:IsA("TextButton") and child.Name:match("^PlaylistOption_") then
				child:Destroy()
			end
		end
	
		local orderedPlaylists = {}
		for id, playlist in pairs(playlists) do
			table.insert(orderedPlaylists, {
				id = id,
				playlist = playlist,
			})
		end
	
		table.sort(orderedPlaylists, function(a, b)
			local aName = tostring(a.playlist.name or ""):lower()
			local bName = tostring(b.playlist.name or ""):lower()
			return aName < bName
		end)
	
		for index, entry in ipairs(orderedPlaylists) do
			local card = (normalTemplate :: Instance):Clone()
			if not card:IsA("TextButton") then
				card:Destroy()
				continue
			end
	
			card.Name = "PlaylistOption_" .. tostring(entry.id)
			card.Visible = true
			card.LayoutOrder = index
	
			local imageLabel = card:FindFirstChild("ImageLabel")
				or card:FindFirstChild("PlaylistCover")
				or card:FindFirstChild("Cover")
			if imageLabel then
				self:applyCoverStyle(imageLabel, entry.playlist)
				local indicatorFrame = findIndicatorFrame(imageLabel)
				if indicatorFrame then
					indicatorFrame.Visible = false
				end
			end
	
			bindClickable(card, function()
				self:_selectTrackPlaylist(tostring(entry.id))
			end)
	
			card.Parent = scrollablePlaylist
		end
	
		local selectedPlaylistId = store:get().selectedTrackPlaylistId
		if selectedPlaylistId and playlists[selectedPlaylistId] then
			self:_selectTrackPlaylist(selectedPlaylistId)
		else
			store:set({ selectedTrackPlaylistId = nil })
		end
	end
	
	function MusicPlayerUIBinder:_selectTrackPlaylist(playlistId: string)
		local refs = self._refs
		local store = self._store
	
		local selectorField = refs.formTrackPlaylistField
		if not selectorField then
			return
		end
	
		local selectWrapper = selectorField:FindFirstChild("SelectWrapper")
		if not selectWrapper then
			return
		end
	
		local scrollablePlaylist = selectWrapper:FindFirstChild("ScrollablePlaylist")
		if not scrollablePlaylist or not scrollablePlaylist:IsA("ScrollingFrame") then
			return
		end
	
		for _, child in ipairs(scrollablePlaylist:GetChildren()) do
			if child:IsA("TextButton") and child.Name:match("^PlaylistOption_") then
				local imageLabel = child:FindFirstChild("ImageLabel")
					or child:FindFirstChild("PlaylistCover")
					or child:FindFirstChild("Cover")
				local indicatorFrame = findIndicatorFrame(imageLabel)
				if indicatorFrame then
					indicatorFrame.Visible = false
				end
			end
		end
	
		local selectedCard = scrollablePlaylist:FindFirstChild("PlaylistOption_" .. playlistId)
		if selectedCard and selectedCard:IsA("TextButton") then
			local imageLabel = selectedCard:FindFirstChild("ImageLabel")
				or selectedCard:FindFirstChild("PlaylistCover")
				or selectedCard:FindFirstChild("Cover")
			local indicatorFrame = findIndicatorFrame(imageLabel)
			if indicatorFrame then
				indicatorFrame.Visible = true
			end
		end
	
		store:set({ selectedTrackPlaylistId = playlistId })
	end
	
	function MusicPlayerUIBinder:bindFontSelection()
		local refs = self._refs
		local config = self._config
	
		if not config or not config.FONT_PRESETS then
			return
		end
	
		local selectFontFace = select(7, getCustomizeCoverParts(refs.formPlaylist))
		if not selectFontFace then
			return
		end
	
		local selectFontFaceList = selectFontFace:FindFirstChild("SelectFontFaceList")
		if not selectFontFaceList then
			return
		end
	
		local scrollableFontFace = selectFontFaceList:FindFirstChild("ScrollableFontFace")
		if not scrollableFontFace then
			return
		end
	
		-- Find template cards
		local normalTemplate = scrollableFontFace:FindFirstChild("Normal")
		local selectedTemplate = scrollableFontFace:FindFirstChild("Selected")
	
		if not normalTemplate or not selectedTemplate then
			return
		end
	
		-- Hide templates
		normalTemplate.Visible = false
		selectedTemplate.Visible = false
	
		-- Clear existing clones
		for _, child in ipairs(scrollableFontFace:GetChildren()) do
			if child:IsA("TextButton") and child.Name:match("^FontCard_") then
				child:Destroy()
			end
		end
	
		-- Create font cards from config
		local fonts = config.FONT_PRESETS
		for i, fontName in ipairs(fonts) do
			local card = normalTemplate:Clone()
			card.Name = "FontCard_" .. tostring(i)
			card.Visible = true
			card.LayoutOrder = i
	
			-- Set font name in card
			local imageLabel = card:FindFirstChild("ImageLabel")
			if imageLabel then
				local fontLabel = imageLabel:FindFirstChild("FontFace") or imageLabel:FindFirstChild("FontFaceName")
				if fontLabel and fontLabel:IsA("TextLabel") then
					(fontLabel :: TextLabel).Text = fontName
					local success = applyNamedFont(fontLabel :: TextLabel, fontName)
					if not success then
						-- Fallback to default if font not found
						(fontLabel :: TextLabel).FontFace = Font.fromEnum(Enum.Font.SourceSans)
					end
				end
	
				-- Find indicator frame
				local indicator = imageLabel:FindFirstChild("NormalStateIndicator")
					or imageLabel:FindFirstChild("SelectedIndicator")
				if indicator then
					local frame = indicator:FindFirstChild("Frame")
					if frame then
						frame.Visible = false -- Hidden by default
					end
				end
			end
	
			-- Bind click event
			if card:IsA("TextButton") then
				trackConnection(
					self,
					(card :: TextButton).Activated:Connect(function()
						self:_selectFont(i, fontName)
					end)
				)
			end
	
			card.Parent = scrollableFontFace
		end
	
		-- Select first font by default
		self:_selectFont(1, fonts[1])
	end
	
	function MusicPlayerUIBinder:_selectFont(index: number, fontName: string)
		local refs = self._refs
		local store = self._store
	
		local selectFontFace = select(7, getCustomizeCoverParts(refs.formPlaylist))
		if not selectFontFace then
			return
		end
	
		local selectFontFaceList = selectFontFace:FindFirstChild("SelectFontFaceList")
		if not selectFontFaceList then
			return
		end
	
		local scrollableFontFace = selectFontFaceList:FindFirstChild("ScrollableFontFace")
		if not scrollableFontFace then
			return
		end
		local normalTemplate = scrollableFontFace:FindFirstChild("Normal")
		local selectedTemplate = scrollableFontFace:FindFirstChild("Selected")
	
		-- Hide all indicators first
		for _, child in ipairs(scrollableFontFace:GetChildren()) do
			if child:IsA("TextButton") and child.Name:match("^FontCard_") then
				local isSelected = child.Name == "FontCard_" .. tostring(index)
				copySelectionTemplateVisual(child, if isSelected then selectedTemplate else normalTemplate)
	
				local imageLabel = child:FindFirstChild("ImageLabel")
				if imageLabel then
					local indicator = imageLabel:FindFirstChild("NormalStateIndicator")
						or imageLabel:FindFirstChild("SelectedIndicator")
					if indicator then
						local frame = indicator:FindFirstChild("Frame")
						if frame then
							frame.Visible = false
						end
					end
				end
			end
		end
	
		-- Show indicator for selected card
		local selectedCard = scrollableFontFace:FindFirstChild("FontCard_" .. tostring(index))
		if selectedCard then
			local imageLabel = selectedCard:FindFirstChild("ImageLabel")
			if imageLabel then
				local indicator = imageLabel:FindFirstChild("NormalStateIndicator")
					or imageLabel:FindFirstChild("SelectedIndicator")
				if indicator then
					local frame = indicator:FindFirstChild("Frame")
					if frame then
						frame.Visible = true
					end
				end
			end
		end
	
		-- Update store
		store:set({ selectedFontFace = fontName })
	
		-- Update gradient preview cards with new font
		local state = store:get()
		self:_updateGradientPreviews(state.playlistNamePreview or "")
	end
	
	-- ============================================================
	-- MANAGE LIST RENDER
	-- ============================================================
	
	function MusicPlayerUIBinder:renderManagePlaylists(playlists: { any }, searchQuery: string?)
		local refs = self._refs
		local store = self._store
		local scroll = refs.scrollableManagePlaylist
		local template = refs.managePlaylistTemplate
	
		self:renderTrackPlaylistOptions(playlists)
	
		template.Visible = false
	
		local orderedPlaylists = buildOrderedPlaylistEntries(playlists, searchQuery)
		hideUnusedPooledRows(self._managePlaylistRowPool, 1)
	
		startListRenderJob(self, "managePlaylists", #orderedPlaylists, function(index: number)
			local entry = orderedPlaylists[index]
			local id = entry.id
			local playlist = entry.playlist
			local row = ensurePooledRow(self._managePlaylistRowPool, index, template, scroll)
			disconnectPooledRowConnections(row)
			local clone = row.instance
	
			-- PlaylistTemplate (manage): PlaylistInfo -> PlaylistDetail -> PlaylistName [TextLabel]
			local info = clone:FindFirstChild("PlaylistInfo")
			if info then
				local detail = info:FindFirstChild("PlaylistDetail")
				if detail then
					local nameLabel = detail:FindFirstChild("PlaylistName")
					if nameLabel and nameLabel:IsA("TextLabel") then
						local displayName = playlist.name or ""
						if playlist.visibility == "private" then
							displayName = displayName .. " (Private)"
						end
						(nameLabel :: TextLabel).Text = displayName
					end
					setTextLabelByNames(
						detail,
						{ "TotalTracks", "TotalTrack" },
						formatTrackCount(getPlaylistTrackCount(playlist))
					)
				end
				-- EditButton & DeleteButton di dalam PlaylistInfo -> InputArea
				local inputArea = info:FindFirstChild("InputArea")
				if inputArea then
					local editBtn = findFirstByNames(inputArea, {
						"EditButton",
						"EditPlaylistButton",
						"EditTrackButton",
					})
					bindTrackedClickable(row.connections, editBtn, function()
						if isManageInteractionBlocked(store) then
							return
						end
						if self._onManageSubView then
							self._onManageSubView("edit_playlist", playlist)
						end
					end)
	
					-- Delete button binding
					local deleteBtn = findFirstByNames(inputArea, {
						"DeleteButton",
						"DeletePlaylistButton",
						"DeleteTrackButton",
					})
					bindTrackedClickable(row.connections, deleteBtn, function()
						if isManageInteractionBlocked(store) then
							return
						end
						self:_openDeletePlaylistConfirmation(playlist, { id = id })
					end)
				end
			end
	
			-- Apply cover style to playlist cover element
			-- Try multiple possible locations for cover element
			local playlistInfo = clone:FindFirstChild("PlaylistInfo")
			local coverElement = clone:FindFirstChild("PlaylistCover")
				or clone:FindFirstChild("ImageLabel")
				or clone:FindFirstChild("Cover")
				or (playlistInfo and playlistInfo:FindFirstChild("ImageLabel"))
	
			if coverElement then
				self:applyCoverStyle(coverElement, playlist, { listThumb = true })
			end

			clone.Name = id
			clone.LayoutOrder = index
			clone.Visible = true
		end)
	end

	function MusicPlayerUIBinder:_populateManageTrackRow(
		row: any,
		track: any,
		trackData: any,
		index: number,
		id: string,
		store: any
	)
		local clone = row.instance
		local parentPlaylist = trackData.playlist

		local trackInfo = clone:FindFirstChild("TrackInfo")
		if trackInfo then
			local detailed = trackInfo:FindFirstChild("TrackDetailed")
			if detailed then
				local trackFrame = detailed:FindFirstChild("Track")
				if trackFrame then
					local titleLabel = trackFrame:FindFirstChild("TrackTitle")
					if titleLabel and titleLabel:IsA("TextLabel") then
						applyVirtualTrackTitle(titleLabel :: TextLabel, track.name or "")
					end
					setTextLabelByNames(
						trackFrame,
						{ "TrackLength", "TrackDuration", "Duration" },
						formatClock(
							tonumber(track.totalDuration or track.duration or track.durationSeconds or track.length or 0)
								or 0
						)
					)
					local creatorLabel = trackFrame:FindFirstChild("TrackCreator")
					if creatorLabel and creatorLabel:IsA("TextLabel") then
						(creatorLabel :: TextLabel).Text = track.creator or ""
					end
				end
				local inputArea = detailed:FindFirstChild("InputArea")
				if inputArea then
					local editBtn = findFirstByNames(inputArea, { "EditButton", "EditTrackButton" })
					bindTrackedClickable(row.connections, editBtn, function()
						if isManageInteractionBlocked(store) then
							return
						end
						if self._onManageSubView then
							self._onManageSubView("edit_track", trackData)
						end
					end)
					local deleteBtn = findFirstByNames(inputArea, { "DeleteButton", "DeleteTrackButton" })
					bindTrackedClickable(row.connections, deleteBtn, function()
						if isManageInteractionBlocked(store) then
							return
						end
						if not self._onManageTrack then
							return
						end
						self:_openDeleteTrackConfirmation(trackData, { id = id })
					end)
				end
			end
		end

		if parentPlaylist then
			local coverElement = clone:FindFirstChild("RelatedPlaylistCover")
				or clone:FindFirstChild("PlaylistCover")
				or clone:FindFirstChild("TrackCover")
			if coverElement then
				self:applyCoverStyle(coverElement, parentPlaylist, { listThumb = true })
			end
		end

		clone.Name = id
		clone.LayoutOrder = VIRTUAL_ROW_LAYOUT_BASE + index
		clone.Visible = true
	end
	
	function MusicPlayerUIBinder:renderManageTracks(tracks: { any }, searchQuery: string?)
		local refs = self._refs
		local store = self._store
		local playlistsById = store:get().playlists or {}
		local scroll = refs.scrollableManageTrack
		local templateLeft = refs.manageTrackTemplate
		local templateRight = refs.manageTrackTemplateRight
		local containerLeft = refs.manageTrackScrollLeft or scroll
		local containerRight = refs.manageTrackScrollRight
	
		templateLeft.Visible = false
		if templateRight then
			templateRight.Visible = false
		end
	
		local orderedTracks = buildOrderedTrackEntries(tracks, searchQuery, nil, "")
	
		if not containerRight then
			renderVirtualList(self, {
				key = "manageTracksLeft",
				scroll = scroll,
				parent = containerLeft :: Instance,
				pool = self._manageTrackRowPool,
				template = templateLeft,
				items = orderedTracks,
				renderRow = function(row: PooledRow, track: any, index: number)
					local id = tostring(track.id or "")
					local parentPlaylist = playlistsById[track.playlistId] or track.playlist
					local trackData = table.clone(track)
					trackData.id = trackData.id or id
					trackData.playlist = parentPlaylist
					self:_populateManageTrackRow(row, track, trackData, index, id, store)
				end,
			})
			disconnectVirtualList(self, "manageTracksRight")
			hideUnusedPooledRows(self._manageTrackRightRowPool, 1)
			return
		end
	
		local leftTracks = {} :: { any }
		local rightTracks = {} :: { any }
		for index, track in ipairs(orderedTracks) do
			if index % 2 == 1 then
				table.insert(leftTracks, track)
			else
				table.insert(rightTracks, track)
			end
		end
	
		local function renderManageTrackRow(row: PooledRow, track: any, index: number)
			local id = tostring(track.id or "")
			local parentPlaylist = playlistsById[track.playlistId] or track.playlist
			local trackData = table.clone(track)
			trackData.id = trackData.id or id
			trackData.playlist = parentPlaylist
	
			self:_populateManageTrackRow(row, track, trackData, index, id, store)
		end
	
		renderVirtualList(self, {
			key = "manageTracksLeft",
			scroll = scroll,
			parent = containerLeft :: Instance,
			pool = self._manageTrackRowPool,
			template = templateLeft,
			items = leftTracks,
			renderRow = renderManageTrackRow,
		})
		renderVirtualList(self, {
			key = "manageTracksRight",
			scroll = scroll,
			parent = containerRight :: Instance,
			pool = self._manageTrackRightRowPool,
			template = templateRight :: TextButton,
			items = rightTracks,
			renderRow = renderManageTrackRow,
		})
	end
	
	-- ============================================================
	-- BIND ALL UI EVENTS (dipanggil oleh Controller saat init)
	-- ============================================================
	
	function MusicPlayerUIBinder:bindAll()
		local refs = self._refs
		local store = self._store
	
		-- Jangan pernah tampilkan template mentah di runtime.
		hideIfGuiObject(refs.playlistTemplateNormal)
		hideIfGuiObject(refs.playlistTemplateSelected)
		hideIfGuiObject(refs.queueTemplate)
		hideIfGuiObject(refs.trackTemplateLeft)
		hideIfGuiObject(refs.trackTemplateRight)
		hideIfGuiObject(refs.djTab)
		hideIfGuiObject(refs.managePlaylistTemplate)
		hideIfGuiObject(refs.manageTrackTemplate)
		hideIfGuiObject(refs.addToQueueConfirmation)
		hideIfGuiObject(refs.utilitiesBackdropBlur)
		hideIfGuiObject(refs.voteModal)
		hideIfGuiObject(refs.voteTrackTemplate)
		hideIfGuiObject(refs.playlistRelatedBackdropBlur)
		hideIfGuiObject(refs.addToPlaylistConfirmation)
		hideIfGuiObject(refs.deletePlaylistConfirmation)
		hideIfGuiObject(refs.editPlaylistConfirmation)
		hideIfGuiObject(refs.trackRelatedBackdropBlur)
		hideIfGuiObject(refs.addToTrackConfirmation)
		hideIfGuiObject(refs.deleteTrackConfirmation)
		hideIfGuiObject(refs.editTrackConfirmation)
		hideIfGuiObject(refs.formPlaylist)
		hideIfGuiObject(refs.formTrack)
		if refs.controlledByDjInfo then
			refs.controlledByDjInfo.Visible = false
		end
		if refs.tipsDynamic then
			refs.tipsDynamic.Visible = true
		end
		refs.voteSkipButtonText.Text = "Vote Skip"
	
		stashTemplateInstance(refs.playlistTemplateNormal, "RuntimeTemplates")
		stashTemplateInstance(refs.playlistTemplateSelected, "RuntimeTemplates")
		stashTemplateInstance(refs.queueTemplate, "RuntimeTemplates")
		stashTemplateInstance(refs.trackTemplateLeft, "RuntimeTemplates")
		stashTemplateInstance(refs.trackTemplateRight, "RuntimeTemplates")
		stashTemplateInstance(refs.managePlaylistTemplate, "RuntimeTemplates")
		stashTemplateInstance(refs.manageTrackTemplate, "RuntimeTemplates")
	
		-- Close button
		trackConnection(
			self,
			refs.closeButton.Activated:Connect(function()
				if self._onCloseRequested then
					self._onCloseRequested()
				end
			end)
		)
	
		trackConnection(
			self,
			refs.addToQueueConfirmButton.Activated:Connect(function()
				if self._pendingRequestTrackId and self._onRequestTrack then
					self._onRequestTrack(self._pendingRequestTrackId)
				end
				self:closeAddToQueueConfirmation()
			end)
		)
	
		trackConnection(
			self,
			refs.addToQueueFavoriteButton.Activated:Connect(function()
				if self._pendingRequestTrackId and self._onAddFavoriteTrack then
					self._onAddFavoriteTrack(self._pendingRequestTrackId, self._pendingFavoriteShouldRemove == true)
				end
				self:closeAddToQueueConfirmation()
			end)
		)
	
		trackConnection(
			self,
			refs.addToQueueCancelButton.Activated:Connect(function()
				self:closeAddToQueueConfirmation()
			end)
		)
	
		if refs.addToFavoritesButton then
			local favBtn = refs.addToFavoritesButton
			local favScale = ensureUIScale(favBtn)
			trackConnection(
				self,
				favBtn.Activated:Connect(function()
					local state = store:get()
					local currentTrack = state.currentTrack
					if type(currentTrack) ~= "table" or type(currentTrack.id) ~= "string" then
						return
					end
					-- ScalePop: quick up then smooth spring back
					local popUp = TweenService:Create(
						favScale,
						TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ Scale = 1.25 }
					)
					local popDown = TweenService:Create(
						favScale,
						TweenInfo.new(0.30, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
						{ Scale = 1.0 }
					)
					popUp.Completed:Connect(function(s)
						if s == Enum.TweenStatus.Completed then
							popDown:Play()
						end
					end)
					popUp:Play()
					if self._onAddFavoriteTrack then
						local favoriteTrackIds = state.favoriteTrackIds or {}
						self._onAddFavoriteTrack(currentTrack.id, favoriteTrackIds[currentTrack.id] == true)
					end
				end)
			)
		end
	
		trackConnection(
			self,
			refs.voteRejectButton.Activated:Connect(function()
				if self._onVoteSkip then
					self._onVoteSkip("reject")
				end
			end)
		)
	
		trackConnection(
			self,
			refs.voteSkipButtonModal.Activated:Connect(function()
				if self._onVoteSkip then
					self._onVoteSkip("skip")
				end
			end)
		)
	
		trackConnection(
			self,
			refs.utilitiesBackdropBlur.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					self:closeAddToQueueConfirmation()
				end
			end)
		)
	
		trackConnection(
			self,
			refs.playlistRelatedBackdropBlur.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					self:_cancelPlaylistRelatedConfirmation()
				end
			end)
		)
	
		trackConnection(
			self,
			refs.addToPlaylistCreateButton.Activated:Connect(function()
				self:_confirmPlaylistRelatedModal()
			end)
		)
	
		trackConnection(
			self,
			refs.addToPlaylistCancelButton.Activated:Connect(function()
				self:_cancelPlaylistRelatedConfirmation()
			end)
		)
	
		trackConnection(
			self,
			refs.deletePlaylistConfirmButton.Activated:Connect(function()
				self:_confirmPlaylistRelatedModal()
			end)
		)
	
		trackConnection(
			self,
			refs.deletePlaylistCancelButton.Activated:Connect(function()
				self:closePlaylistRelatedModal()
			end)
		)
	
		trackConnection(
			self,
			refs.editPlaylistSaveButton.Activated:Connect(function()
				self:_confirmPlaylistRelatedModal()
			end)
		)
	
		trackConnection(
			self,
			refs.editPlaylistCancelButton.Activated:Connect(function()
				self:_cancelPlaylistRelatedConfirmation()
			end)
		)
	
		trackConnection(
			self,
			refs.trackRelatedBackdropBlur.InputBegan:Connect(function(input)
				if
					input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch
				then
					self:_cancelTrackRelatedConfirmation()
				end
			end)
		)
	
		trackConnection(
			self,
			refs.addToTrackSaveButton.Activated:Connect(function()
				self:_confirmTrackRelatedModal()
			end)
		)
	
		trackConnection(
			self,
			refs.addToTrackCancelButton.Activated:Connect(function()
				self:_cancelTrackRelatedConfirmation()
			end)
		)
	
		trackConnection(
			self,
			refs.deleteTrackConfirmButton.Activated:Connect(function()
				self:_confirmTrackRelatedModal()
			end)
		)
	
		trackConnection(
			self,
			refs.deleteTrackCancelButton.Activated:Connect(function()
				self:closeTrackRelatedModal()
			end)
		)
	
		trackConnection(
			self,
			refs.editTrackSaveButton.Activated:Connect(function()
				self:_confirmTrackRelatedModal()
			end)
		)
	
		trackConnection(
			self,
			refs.editTrackCancelButton.Activated:Connect(function()
				self:_cancelTrackRelatedConfirmation()
			end)
		)
	
		-- Tab buttons
		trackConnection(
			self,
			refs.tabs.nowPlaying.Activated:Connect(function()
				self:switchTab("nowplaying")
				if self._onTabSelected then
					self._onTabSelected("nowplaying")
				end
			end)
		)
		trackConnection(
			self,
			refs.tabs.reqSong.Activated:Connect(function()
				self:switchTab("request")
				if self._onTabSelected then
					self._onTabSelected("request")
				end
			end)
		)
		trackConnection(
			self,
			refs.tabs.manage.Activated:Connect(function()
				if not store:get().isManageAllowed then
					return
				end
				self:switchTab("manage")
				if self._onTabSelected then
					self._onTabSelected("manage")
				end
			end)
		)
		trackConnection(
			self,
			refs.tabs.dj.Activated:Connect(function()
				if not store:get().isManageAllowed then
					return
				end
				self:switchTab("dj")
				if self._onTabSelected then
					self._onTabSelected("dj")
				end
			end)
		)
	
		-- Vote skip
		trackConnection(
			self,
			refs.voteSkipButton.Activated:Connect(function()
				if self._onVoteSkip then
					self._onVoteSkip("skip")
				end
			end)
		)
	
		trackConnection(
			self,
			refs.scrollableQueue:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
				self:_updateQueueHeaderVisibility()
			end)
		)
		trackUnsubscriber(
			self,
			ScrollIndicatorHelper.attach(refs.scrollableQueue, {
				fadeoutDelay = QUEUE_SCROLLBAR_IDLE_DELAY,
			}).destroy
		)
	
		-- Scrollbar idle-color: dim bar when not scrolling
		do
			local PLAYLIST_IDLE = Color3.fromHex("181818")
			local PLAYLIST_ACTIVE = Color3.fromHex("555555")
			local TRACK_IDLE = Color3.fromHex("111111")
			local TRACK_ACTIVE = Color3.fromHex("444444")
			local IDLE_DELAY = 1 -- seconds of no scroll before dimming
	
			local function bindScrollIdle(scroll: ScrollingFrame, idleColor: Color3, activeColor: Color3)
				scroll.ScrollBarImageColor3 = idleColor
				local debounce: thread? = nil
				trackConnection(
					self,
					scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
						scroll.ScrollBarImageColor3 = activeColor
						if debounce then
							task.cancel(debounce)
						end
						debounce = task.delay(IDLE_DELAY, function()
							debounce = nil
							scroll.ScrollBarImageColor3 = idleColor
						end)
					end)
				)
			end
	
			bindScrollIdle(refs.scrollablePlaylist, PLAYLIST_IDLE, PLAYLIST_ACTIVE)
			bindScrollIdle(refs.scrollableTrackLeft, TRACK_IDLE, TRACK_ACTIVE)
			bindScrollIdle(refs.scrollableTrackRight, TRACK_IDLE, TRACK_ACTIVE)
		end
	
		-- Search box (debounced — avoid remount storm per keystroke)
		trackConnection(
			self,
			refs.searchBox:GetPropertyChangedSignal("Text"):Connect(function()
				local q = refs.searchBox.Text
				store:set({ searchQuery = q })
				self._searchDebounceToken = (self._searchDebounceToken or 0) + 1
				local token = self._searchDebounceToken
				task.delay(SEARCH_DEBOUNCE_SEC, function()
					if token ~= self._searchDebounceToken then
						return
					end
					if self._onSearchChanged then
						self._onSearchChanged(q)
					end
				end)
			end)
		)

		do
			local managePlaylistSearch = refs.scrollableManagePlaylist:FindFirstChild("SearchPlaylist", true)
			if managePlaylistSearch and managePlaylistSearch:IsA("TextBox") then
				trackConnection(
					self,
					(managePlaylistSearch :: TextBox):GetPropertyChangedSignal("Text"):Connect(function()
						local q = (managePlaylistSearch :: TextBox).Text
						store:set({ managePlaylistSearchQuery = q })
						self._managePlaylistSearchToken = (self._managePlaylistSearchToken or 0) + 1
						local token = self._managePlaylistSearchToken
						task.delay(SEARCH_DEBOUNCE_SEC, function()
							if token ~= self._managePlaylistSearchToken then
								return
							end
							self:renderManagePlaylists(store:get().playlists or {}, q)
						end)
					end)
				)
			end

			local manageTrackSearch = refs.scrollableManageTrack:FindFirstChild("SearTrack", true)
				or refs.scrollableManageTrack:FindFirstChild("SearchTrack", true)
				or refs.scrollableManageTrack:FindFirstChild("SearchTracks", true)
			if manageTrackSearch and manageTrackSearch:IsA("TextBox") then
				trackConnection(
					self,
					(manageTrackSearch :: TextBox):GetPropertyChangedSignal("Text"):Connect(function()
						local q = (manageTrackSearch :: TextBox).Text
						store:set({ manageTrackSearchQuery = q })
						self._manageTrackSearchToken = (self._manageTrackSearchToken or 0) + 1
						local token = self._manageTrackSearchToken
						task.delay(SEARCH_DEBOUNCE_SEC, function()
							if token ~= self._manageTrackSearchToken then
								return
							end
							self:renderManageTracks(store:get().manageTracks or store:get().tracks or {}, q)
						end)
					end)
				)
			end
		end
	
		trackConnection(
			self,
			refs.favoritesPlaylistButton.Activated:Connect(function()
				local favoritesPlaylistId = select(1, getSpecialPlaylistIds(self._config))
				if self._onPlaylistSelected then
					self._onPlaylistSelected(favoritesPlaylistId)
				end
			end)
		)
	
		trackConnection(
			self,
			refs.newDropsPlaylistButton.Activated:Connect(function()
				local _, newDropsPlaylistId = getSpecialPlaylistIds(self._config)
				if self._onPlaylistSelected then
					self._onPlaylistSelected(newDropsPlaylistId)
				end
			end)
		)
	
		-- Manage frame buttons
		trackConnection(
			self,
			refs.createPlaylistButton.Activated:Connect(function()
				local state = store:get()
				if state.isLoading then
					return
				end
				local isCreatePlaylistOpen = state.manageSubView == "edit_playlist"
					and self._playlistFormCreateMode
					and state.editingPlaylist == nil
	
				if isCreatePlaylistOpen then
					self:_enterManageIdle(false)
					return
				end
	
				if self._onManageSubView then
					self._onManageSubView("edit_playlist", nil)
				else
					self:populatePlaylistForm(nil)
					self:setManageSubView("edit_playlist")
				end
			end)
		)
	
		trackConnection(
			self,
			refs.uploadTrackButton.Activated:Connect(function()
				local state = store:get()
				if state.isLoading then
					return
				end
				local isCreateTrackOpen = state.manageSubView == "edit_track"
					and self._trackFormCreateMode
					and state.editingTrack == nil
	
				if isCreateTrackOpen then
					self:_enterManageIdle(false)
					return
				end
	
				if self._onManageSubView then
					self._onManageSubView("edit_track", nil)
				else
					self:populateTrackForm(nil)
					self:setManageSubView("edit_track")
				end
			end)
		)
	
		-- Bind cover and font customization
		self:bindCoverTabs()
		self:bindColorSelection()
		self:bindFontSelection()
		self:bindPlaylistVisibility()
		self:bindRequestFromId()
	
		-- Bind playlist name input for preview
		local playlistNameField = refs.formPlaylistNameField
		local playlistNameBox = playlistNameField:FindFirstChildWhichIsA("TextBox")
		if playlistNameBox then
			trackConnection(
				self,
				(playlistNameBox :: TextBox):GetPropertyChangedSignal("Text"):Connect(function()
					local name = (playlistNameBox :: TextBox).Text
					store:set({ playlistNamePreview = name })
				end)
			)
		end
	
		-- Save playlist button
		local savePlaylistBtn = refs.formPlaylist:FindFirstChild("ActionableWrapper")
		if savePlaylistBtn then
			local btn = savePlaylistBtn:FindFirstChild("CreateorSavePlaylistButton")
			if btn and btn:IsA("TextButton") then
				trackConnection(
					self,
					(btn :: TextButton).Activated:Connect(function()
						if store:get().isLoading then
							return
						end
						if self._onManagePlaylist then
							local formData = self:readPlaylistForm()
							local valid, err = self:validatePlaylistForm(formData)
							if not valid then
								warn("[MusicPlayer] Validation failed: " .. err)
								return
							end
							local state = store:get()
							local editingPlaylist = if self._playlistFormCreateMode then nil else state.editingPlaylist
							local action = editingPlaylist and "update" or "create"
							if action == "update" then
								formData.id = editingPlaylist.id
								self:_openUpdatePlaylistConfirmation(editingPlaylist, formData)
							else
								self:_openCreatePlaylistConfirmation(formData)
							end
						end
					end)
				)
			end
		end
	
		-- Save track button
		local saveTrackBtn = refs.formTrack:FindFirstChild("ActionableWrapper")
		if saveTrackBtn then
			local btn = saveTrackBtn:FindFirstChild("UploadorSaveTrackButton")
			if btn and btn:IsA("TextButton") then
				trackConnection(
					self,
					(btn :: TextButton).Activated:Connect(function()
						if store:get().isLoading then
							return
						end
						if not self._onManageTrack then
							return
						end
	
						local formData = self:readTrackForm()
						local valid, err = self:validateTrackForm(formData)
						if not valid then
							warn("[MusicPlayer] Validation failed: " .. err)
							if self._onFormNotify then
								self._onFormNotify("warning", "Validation failed", err)
							end
							return
						end
	
						local state = store:get()
						local editingTrack = if self._trackFormCreateMode then nil else state.editingTrack
						local action = editingTrack and "update" or "upload"
	
						-- Async audio asset validation before proceeding
						store:set({ isLoading = true })
						task.spawn(function()
							local allReady = true
							local failedPartIndex: number? = nil
							local failedStatus: string? = nil
	
							for i, partId in ipairs(formData.parts) do
								local contentId = "rbxassetid://" .. tostring(partId)
								local sound = Instance.new("Sound")
								sound.SoundId = contentId
								pcall(function()
									ContentProvider:PreloadAsync({ sound })
								end)
								local status = ContentProvider:GetAssetFetchStatus(contentId)
								sound:Destroy()
								if status ~= Enum.AssetFetchStatus.Success then
									allReady = false
									failedPartIndex = i
									failedStatus = tostring(status and status.Name or "Unknown")
									break
								end
							end
	
							store:set({ isLoading = false })
	
							if not allReady then
								local title = if failedStatus == "TimedOut"
									then "Audio check timed out"
									else "Audio not ready"
								local desc = if failedStatus == "TimedOut"
									then "Roblox took too long to respond. This may be a temporary CDN issue. Please try again."
									else ("Roblox can't serve audio part %d yet. It may still be under review or the ID is invalid. Please try again in a few minutes."):format(failedPartIndex or 1)
								if self._onFormNotify then
									self._onFormNotify("warning", title, desc)
								end
								return
							end
	
							-- All parts valid, proceed
							if action == "update" then
								formData.id = editingTrack.id
								self:_openUpdateTrackConfirmation(editingTrack, formData)
							else
								self:_openCreateTrackConfirmation(formData)
							end
						end)
					end)
				)
			end
		end
	
		-- Cancel playlist form (CloseModalButton in header, or CancelButton in ActionableWrapper)
		do
			local btn = refs.formPlaylist:FindFirstChild("CloseModalButton", true)
				or (
					refs.formPlaylist:FindFirstChild("ActionableWrapper")
					and refs.formPlaylist:FindFirstChild("ActionableWrapper"):FindFirstChild("CancelButton")
				)
			if btn and btn:IsA("TextButton") or (btn and btn:IsA("ImageButton")) then
				trackConnection(
					self,
					(btn :: GuiButton).Activated:Connect(function()
						if store:get().isLoading then
							return
						end
						self:_enterManageIdle(false)
					end)
				)
			end
		end
	
		-- Cancel track form (CloseModalButton in header, or CancelButton in ActionableWrapper)
		do
			local btn = refs.formTrack:FindFirstChild("CloseModalButton", true)
				or (
					refs.formTrack:FindFirstChild("ActionableWrapper")
					and refs.formTrack:FindFirstChild("ActionableWrapper"):FindFirstChild("CancelButton")
				)
			if btn and (btn:IsA("TextButton") or btn:IsA("ImageButton")) then
				trackConnection(
					self,
					(btn :: GuiButton).Activated:Connect(function()
						if store:get().isLoading then
							return
						end
						self:_enterManageIdle(false)
					end)
				)
			end
		end
	
		-- Loading state subscription
		trackUnsubscriber(
			self,
			store:subscribe("isLoading", function(isLoading)
				-- Disable buttons saat loading
				refs.createPlaylistButton.Interactable = not isLoading
				refs.uploadTrackButton.Interactable = not isLoading
				setActionWrapperButtonsInteractable(refs.formPlaylist, "CreateorSavePlaylistButton", not isLoading)
				setActionWrapperButtonsInteractable(refs.formTrack, "UploadorSaveTrackButton", not isLoading)
			end)
		)
		trackUnsubscriber(
			self,
			store:subscribe("currentTrack", function(track)
				self:updateTrackDisplay(if type(track) == "table" then track else nil)
				self:_updateNowPlayingFavoriteState(track)
			end)
		)
		trackUnsubscriber(
			self,
			store:subscribe("favoriteTrackIds", function()
				self:_updateNowPlayingFavoriteState(store:get().currentTrack)
			end)
		)
	
		-- DJ mode gating: saat DJ mode ON, privileged users (Admin/DJ/Owner) tetap bisa akses.
		-- Regular player di-block.
		local function updateDjModeGating()
			local storeState = store:get()
			local localUserId = Players.LocalPlayer and Players.LocalPlayer.UserId
			local isDjOwner = storeState.isDjMode == true
				and type(localUserId) == "number"
				and storeState.djOwnerUserId == localUserId
			local canControl = isDjOwner or storeState.isManageAllowed == true
			local shouldHide = storeState.isDjMode == true and not canControl
			refs.voteSkipButton.Visible = not shouldHide
			refs.tabs.reqSong.Visible = not shouldHide
			SliderSelectorUtil.setTabButtonDimmed(refs.tabs.reqSong, shouldHide)
			if shouldHide and storeState.activeTab == "request" then
				self:switchTab("nowplaying")
			else
				self:_updateTabButtonVisuals(store:get().activeTab or "nowplaying")
			end
		end
		trackUnsubscriber(
			self,
			store:subscribe("isDjMode", function()
				updateDjModeGating()
			end)
		)
		trackUnsubscriber(
			self,
			store:subscribe("djOwnerUserId", function()
				updateDjModeGating()
			end)
		)
		trackUnsubscriber(
			self,
			store:subscribe("isManageAllowed", function()
				updateDjModeGating()
			end)
		)
	
		-- DraggableIcon: no custom logic, UIDragDetector already handles MainWrapper
	
		-- ManageAllowed: disable tab secara visual (data di-push dari controller via store subscribe)
		-- Manage tab: saat DJ mode ON, privileged users (DJ owner / Admin / Owner) tetap bisa akses.
		local function updateManageTab(allowed: boolean)
			local storeState = store:get()
			local localUserId = Players.LocalPlayer and Players.LocalPlayer.UserId
			local isDjOwner = storeState.isDjMode == true
				and type(localUserId) == "number"
				and storeState.djOwnerUserId == localUserId
			local canControl = isDjOwner or allowed
			local visible = if storeState.isDjMode then canControl else allowed
			refs.tabs.manage.Visible = visible
			SliderSelectorUtil.setTabButtonDimmed(refs.tabs.manage, not visible)
			if not visible and store:get().activeTab == "manage" then
				self:switchTab("nowplaying")
			else
				self:_updateTabButtonVisuals(store:get().activeTab or "nowplaying")
			end
		end
		local function updateDjTabAccess(allowed: boolean)
			local storeState = store:get()
			local localUserId = Players.LocalPlayer and Players.LocalPlayer.UserId
			local isDjOwner = storeState.isDjMode == true
				and type(localUserId) == "number"
				and storeState.djOwnerUserId == localUserId
			local canControl = isDjOwner or allowed
			local visible = if storeState.isDjMode then canControl else allowed
			refs.tabs.dj.Visible = visible
			SliderSelectorUtil.setTabButtonDimmed(refs.tabs.dj, not visible)
			if not visible and store:get().activeTab == "dj" then
				self:switchTab("nowplaying")
			else
				self:_updateTabButtonVisuals(store:get().activeTab or "nowplaying")
			end
		end
		local function updateDjTabState(enabled: boolean)
			setButtonDisplayText(refs.tabs.dj, "DJ")
			setSwitchToggleVisual(self._djModeToggle, enabled == true)
			task.defer(function()
				setSwitchToggleVisual(self._djModeToggle, enabled == true)
				self:_syncDjSwitchInputForActiveTab()
			end)
			self:_syncDjSwitchInputForActiveTab()
		end
		self._onUpdateManageTab = updateManageTab
		self._onUpdateDjTabAccess = updateDjTabAccess
		self._onUpdateDjTabState = updateDjTabState
		updateManageTab(false) -- default disabled sampai controller push data
		updateDjTabAccess(false)
		updateDjTabState(self._store:get().isDjMode == true)
		updateDjModeGating()
		self:bindDjTab()
		self:_updateQueueHeaderVisibility()
		self:_updateTabButtonVisuals(self._store:get().activeTab or "nowplaying")
	
		-- Initial state: ensure manage sections visible
		self:setManageSubView("idle")
	end
	
	-- Callback setters
	
	function MusicPlayerUIBinder:setOnCloseRequested(fn: () -> ())
		self._onCloseRequested = fn
	end
	
	function MusicPlayerUIBinder:setOnTabSelected(fn: (string) -> ())
		self._onTabSelected = fn
	end
	
	function MusicPlayerUIBinder:setOnToggleDjMode(fn: () -> ())
		self._onToggleDjMode = fn
	end
	
	function MusicPlayerUIBinder:setOnVoteSkip(fn: (string?) -> ())
		self._onVoteSkip = fn
	end
	
	function MusicPlayerUIBinder:setOnRequestTrack(fn: (string) -> ())
		self._onRequestTrack = fn
	end
	
	function MusicPlayerUIBinder:setOnAddFavoriteTrack(fn: (string, boolean) -> ())
		self._onAddFavoriteTrack = fn
	end
	
	function MusicPlayerUIBinder:setOnPlaylistSelected(fn: (string) -> ())
		self._onPlaylistSelected = fn
	end
	
	function MusicPlayerUIBinder:setOnSearchChanged(fn: (string) -> ())
		self._onSearchChanged = fn
	end
	
	function MusicPlayerUIBinder:setOnVolumeChanged(fn: (number) -> ())
		self._onVolumeChanged = fn
	end
	
	function MusicPlayerUIBinder:setOnManageSubView(fn: (string, any?) -> ())
		self._onManageSubView = fn
	end
	
	function MusicPlayerUIBinder:setOnManagePlaylist(fn: (string, { [string]: any }) -> ())
		self._onManagePlaylist = fn
	end
	
	function MusicPlayerUIBinder:setOnResolveRequestAsset(fn: (string) -> ())
		self._onResolveRequestAsset = fn
	end
	
	function MusicPlayerUIBinder:setOnManageTrack(fn: (string, { [string]: any }) -> ())
		self._onManageTrack = fn
	end
	
	function MusicPlayerUIBinder:setOnFormNotify(fn: (string, string, string?) -> ())
		self._onFormNotify = fn
	end
	
	function MusicPlayerUIBinder:setOnDjSoundboardTriggered(fn: (string) -> boolean)
		self._onDjSoundboardTriggered = fn
	end
	
	function MusicPlayerUIBinder:setOnDjPlaybackSpeedChanged(fn: (number) -> boolean)
		self._onDjPlaybackSpeedChanged = fn
	end
	
	function MusicPlayerUIBinder:setOnDjEffectEnabledChanged(fn: (string, boolean) -> boolean)
		self._onDjEffectEnabledChanged = fn
	end
	
	function MusicPlayerUIBinder:setOnDjEffectValueChanged(fn: (string, string, number) -> boolean)
		self._onDjEffectValueChanged = fn
	end
	
	function MusicPlayerUIBinder:setOnDjBassEnabledChanged(fn: (boolean) -> ())
		self._onDjBassEnabledChanged = fn
		self._onDjEffectEnabledChanged = function(effectId, enabled)
			if effectId == "equalizer" then
				return fn(enabled) == true
			end
			return true
		end
	end
	
	function MusicPlayerUIBinder:setOnDjBassValueChanged(fn: (number) -> ())
		self._onDjBassValueChanged = fn
		self._onDjEffectValueChanged = function(effectId, itemId, value)
			if effectId == "equalizer" and itemId == "low" then
				fn(value)
				return true
			end
			return true
		end
	end
	
	function MusicPlayerUIBinder:setOnDjResetRequested(fn: () -> boolean)
		self._onDjResetRequested = fn
	end
	
	function MusicPlayerUIBinder:setManageAllowed(allowed: boolean)
		if self._onUpdateManageTab then
			self._onUpdateManageTab(allowed)
		end
		if self._onUpdateDjTabAccess then
			self._onUpdateDjTabAccess(allowed)
		end
	end
	
	function MusicPlayerUIBinder:setDjModeEnabled(enabled: boolean)
		if self._onUpdateDjTabState then
			self._onUpdateDjTabState(enabled)
		end
		-- Re-evaluate manage/DJ tab access when DJ mode toggles.
		-- setManageAllowed provides the base permission; the internal
		-- updateManageTab/updateDjTabAccess now overlay DJ-owner check.
		local storeState = self._store:get()
		self:setManageAllowed(storeState.isManageAllowed == true)
	end
	
	function MusicPlayerUIBinder:setTotalDuration(duration: number)
		self._totalDuration = duration
	end
	
	function MusicPlayerUIBinder:destroy()
		self._isDestroyed = true
		cancelAllListRenderJobs(self)
		disconnectAllVirtualLists(self)
		self:_stopTipsLoop()
		if self._auraHeartbeatConn then
			self._auraHeartbeatConn:Disconnect()
			self._auraHeartbeatConn = nil
		end
		if self._auraGradientTween then
			self._auraGradientTween:Cancel()
			self._auraGradientTween = nil
		end
		if self._auraGradientConn then
			self._auraGradientConn:Disconnect()
			self._auraGradientConn = nil
		end
		for index = 1, #self._auraSoundCache do
			self._auraSoundCache[index] = nil
		end
		self._auraSoundScanClock = 0
		if self._playlistIconBounceCleanup then
			for _, entry in ipairs(self._playlistIconBounceCleanup) do
				entry.kill()
				for _, t in ipairs(entry.tweens) do
					t:Cancel()
				end
				for _, c in ipairs(entry.conns) do
					c:Disconnect()
				end
			end
			self._playlistIconBounceCleanup = nil
		end
		self:closeAddToQueueConfirmation(true)
		self:closeVoteModal(true)
		self:closePlaylistRelatedModal(true)
		self:closeTrackRelatedModal(true)
		self:stopProgressTracking()
		if self._refs.mainDragDetector and self._mainWrapperDragDetectorEnabled ~= nil then
			self._refs.mainDragDetector.Enabled = self._mainWrapperDragDetectorEnabled
		end
		if self._volumeDragConn then
			self._volumeDragConn:Disconnect()
			self._volumeDragConn = nil
		end
		disconnectConnectionList(self._djSoundBoardConnections)
		disconnectConnectionList(self._djEffectConnections)
		for _, conn in ipairs(self._connections) do
			conn:Disconnect()
		end
		self._connections = {}
		for _, unsubscribe in ipairs(self._unsubscribers) do
			unsubscribe()
		end
		self._unsubscribers = {}
		destroyPooledRows(self._queueRowPool)
		destroyPooledRows(self._requestPlaylistRowPool)
		destroyPooledRows(self._requestTrackLeftRowPool)
		destroyPooledRows(self._requestTrackRightRowPool)
		destroyPooledRows(self._managePlaylistRowPool)
		destroyPooledRows(self._manageTrackRowPool)
		destroyPooledRows(self._manageTrackRightRowPool)
	end
end
