-- When designing your game for many devices and screen sizes, icons may occasionally
-- particularly for smaller devices like phones, overlap with other icons or the bounds
-- of the screen. The overflow handler solves this challenge by moving the out-of-bounds
-- icon into an overflow menu (with a limited scrolling canvas) preventing overlaps occuring



-- LOCAL
local Overflow = {}
local holders = {}
local orderedAvailableIcons = {}
local iconsDict
local currentCamera = workspace.CurrentCamera
local overflowIcons = {}
local overflowIconUIDs = {}
local Utility = require(script.Parent.Parent.Utility)
local beginCheckingCenterIcons = false
local beganSecondaryCenterCheck = false
local Icon



-- FUNCTIONS
-- This is called upon the Icon initializing
function Overflow.start(incomingIcon)
	Icon = incomingIcon
	iconsDict = Icon.iconsDictionary
	local primaryScreenGui
	for _, screenGui in pairs(Icon.container) do
		if primaryScreenGui == nil and screenGui.ScreenInsets == Enum.ScreenInsets.TopbarSafeInsets then
			primaryScreenGui = screenGui
		end
		for _, holder in pairs(screenGui.Holders:GetChildren()) do
			if holder:GetAttribute("IsAHolder") then
				holders[holder.Name] = holder
			end
		end
	end

	-- We listen for changes in icons (such as them being added, removed,
	-- the setting of a different alignment, the widget size changing, etc)
	local beginOverflow = false
	local updateBoundaries = Utility.createStagger(0.1, function(ignoreAvailable)
		if not beginOverflow then
			return
		end
		if not ignoreAvailable then
			Overflow.updateAvailableIcons("Center")
		end
		Overflow.updateBoundary("Left")
		Overflow.updateBoundary("Right")
	end)
	task.delay(0.5, function()
		beginOverflow = true
		updateBoundaries()
	end)
	task.delay(2, function()
		-- This is essential to prevent central icons begin added
		-- left or right due to incomplete UIListLayout calculations
		-- within the first few frames
		beginCheckingCenterIcons = true
		updateBoundaries()
	end)
	Icon.iconAdded:Connect(updateBoundaries)
	Icon.iconRemoved:Connect(updateBoundaries)
	Icon.iconChanged:Connect(updateBoundaries)
	currentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		updateBoundaries(true)
	end)
	primaryScreenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		updateBoundaries(true)
	end)
end

function Overflow.getWidth(icon, getMaxWidth)
	-- Rows in the overflow dropdown are stretched to a fixed width, so while an icon is
	-- inside one we use the width it had on the topbar (recorded when it joined)
	local restWidth = icon.parentIconUID and icon.overflowRestWidth
	if restWidth then
		return restWidth
	end
	local widget = icon.widget
	return widget:GetAttribute("TargetWidth") or widget.AbsoluteSize.X
end

function Overflow.getAvailableIcons(alignment)
	local ourOrderedIcons = orderedAvailableIcons[alignment]
	if not ourOrderedIcons then
		ourOrderedIcons = Overflow.updateAvailableIcons(alignment)
	end
	return ourOrderedIcons
end

function Overflow.updateAvailableIcons(alignment)

	-- We only track items that are directly on the topbar (i.e. not within a parent icon)
	local ourTotal = 0
	local ourOrderedIcons = {}
	for _, icon in pairs(iconsDict) do
		local parentUID = icon.parentIconUID
		local isDirectlyOnTopbar = not parentUID or overflowIconUIDs[parentUID]
		local isOverflow = overflowIconUIDs[icon.UID]
		if isDirectlyOnTopbar and icon.alignment == alignment and not isOverflow and icon.isEnabled then
			table.insert(ourOrderedIcons, icon)
			ourTotal += 1
		end
	end

	-- Ignore if no icons are available
	if ourTotal <= 0 then
		return {}
	end

	-- This sorts these icons by smallest order, or if equal, left-most position
	-- (even for the right alignment because all icons are sorted left-to-right)
	table.sort(ourOrderedIcons, function(iconA, iconB)
		local orderA = iconA.widget.LayoutOrder
		local orderB = iconB.widget.LayoutOrder
		local hasParentA = iconA.parentIconUID
		local hasParentB = iconB.parentIconUID
		if hasParentA == hasParentB then
			if orderA < orderB then
				return true
			end
			if orderA > orderB then
				return false
			end
			return iconA.widget.AbsolutePosition.X < iconB.widget.AbsolutePosition.X
		elseif hasParentB then
			return false
		elseif hasParentA then
			return true
		end
		return nil
	end)

	-- Finish up
	orderedAvailableIcons[alignment] = ourOrderedIcons
	return ourOrderedIcons

end

function Overflow.getRealXPositions(alignment, orderedIcons)
	-- We calculate the the absolute position of icons instead of reading
	-- directly to determine where they would be if not within an overflow
	local isLeft = alignment == "Left"
	local holder = holders[alignment]
	local holderXPos = holder.AbsolutePosition.X
	local holderXSize = holder.AbsoluteSize.X
	local holderUIList = holder.UIListLayout
	local topbarInset = holderUIList.Padding.Offset
	local absoluteX = (isLeft and holderXPos) or holderXPos + holderXSize
	local realXPositions = {}
	if isLeft then
		Utility.reverseTable(orderedIcons)
	end
	for i = #orderedIcons, 1, -1 do
		local icon = orderedIcons[i]
		local sizeX = Overflow.getWidth(icon)
		if not isLeft then
			absoluteX -= sizeX
		end
		realXPositions[icon.UID] = absoluteX
		if isLeft then
			absoluteX += sizeX
		end
		absoluteX += (isLeft and topbarInset) or -topbarInset
	end
	return realXPositions
end

-- Dropdown rows look like Roblox's own menu: 44 px tall, icon + label left-aligned in one column.
-- Applied as a removable modification, so an icon that leaves the overflow gets its topbar look back.
-- Icon-only buttons need a label here: icon.overflowLabel, or Icon.overflowLabels[<image asset>].
local ROW_WIDTH, ROW_HEIGHT, ROW_ICON, ROW_GAP, ROW_PAD = 200, 44, 24, 12, 16
function Overflow.styleRow(icon, overflowIcon, topbarX)
	local image = icon:getInstance("IconImage")
	local hasImage = image.Image ~= ""
	-- The row order overwrites the topbar LayoutOrder, and removeModification does not put the old
	-- value back: an icon leaving the dropdown kept order*1000 and jumped right of Menu (PARKLAB).
	-- Keep the real order once, use it for the row and restore it on leave.
	if icon.overflowTopbarOrder == nil then
		icon.overflowTopbarOrder = icon.widget.LayoutOrder
	end
	local topbarOrder = icon.overflowTopbarOrder
	local mods = {
		{"Widget", "MinimumWidth", ROW_WIDTH},
		{"Widget", "MinimumHeight", ROW_HEIGHT},
		{"IconLabel", "TextSize", 16},
		{"IconLabel", "TextXAlignment", Enum.TextXAlignment.Left},
		{"PaddingLeft", "Size", UDim2.fromOffset(hasImage and ROW_PAD or ROW_PAD + ROW_ICON + ROW_GAP, 0)},
		{"PaddingCenter", "Size", UDim2.fromOffset(hasImage and ROW_GAP or 0, 0)},
		{"IconImage", "Size", UDim2.fromOffset(ROW_ICON, ROW_ICON)},
		{"ContentsList", "Padding", UDim.new(0, 0)},
		-- Same order as on the topbar: the icon's order first, its screen position breaks ties
		{"Widget", "LayoutOrder", topbarOrder * 1000 + math.clamp(math.floor(topbarX), 0, 999)},
	}
	if icon:getInstance("IconLabel").Text == "" then
		local text = icon.overflowLabel or (Icon.overflowLabels and Icon.overflowLabels[image.Image])
		if text then
			table.insert(mods, {"IconLabel", "Text", text})
		end
	end
	icon:modifyTheme(mods, "OverflowRow")
	icon.joinJanitor:add(function()
		icon:removeModification("OverflowRow")
		if icon.overflowTopbarOrder ~= nil then
			icon:setOrder(icon.overflowTopbarOrder / 100)
			icon.overflowTopbarOrder = nil
		end
	end)
	if not overflowIcon.overflowDropdownStyled then
		overflowIcon.overflowDropdownStyled = true
		local dropdown = overflowIcon:getInstance("Dropdown")
		dropdown.DropdownCorner.CornerRadius = UDim.new(0, 12)
		local padding = dropdown.DropdownScroller:FindFirstChild("DropdownPadding")
		if padding then
			padding.PaddingTop = UDim.new(0, 8)
			padding.PaddingBottom = UDim.new(0, 8)
		end
	end
end

function Overflow.updateBoundary(alignment)

	-- We only track items that are directly on the topbar (i.e. not within a parent icon) or within an overflow
	local holder = holders[alignment]
	local holderUIList = holder.UIListLayout
	local holderXPos = holder.AbsolutePosition.X
	local holderXSize = holder.AbsoluteSize.X
	local topbarInset = holderUIList.Padding.Offset
	local topbarPadding = holderUIList.Padding.Offset
	local BOUNDARY_GAP = topbarInset
	local ourOrderedIcons = Overflow.updateAvailableIcons(alignment)
	local boundWidth = 0
	local ourTotal = 0
	for _, icon in pairs(ourOrderedIcons) do
		boundWidth += Overflow.getWidth(icon) + topbarPadding
		ourTotal += 1
	end
	if ourTotal <= 0 then
		return
	end
	
	-- These are the icons with menus which icons will be moved into
	-- when overflowing
	local isCentral = alignment == "Center"
	local isLeft = alignment == "Left"
	local isRight = not isLeft
	local overflowIcon = overflowIcons[alignment]
	if not overflowIcon and not isCentral and #ourOrderedIcons > 0 then
		local order = (isLeft and -9999999) or 9999999
		overflowIcon = Icon.new()--:setLabel(`{alignment}`)
		overflowIcon:setImage(6069276526, "Deselected")
		overflowIcon:setImage("rbxasset://textures/ui/InspectMenu/x.png", "Selected") -- close button while open
		overflowIcon:modifyTheme({"IconImage", "Size", UDim2.fromScale(0.375, 0.375), "Selected"}) -- 3/4 of the dots size
		overflowIcon:setName("Overflow"..alignment)
		overflowIcon:setOrder(order)
		overflowIcon:setAlignment(alignment)
		overflowIcon:autoDeselect(false)
		overflowIcon.isAnOverflow = true
		-- Starts closed: the three dots open a dropdown below the topbar
		overflowIcon:setEnabled(false)
		overflowIcons[alignment] = overflowIcon
		overflowIconUIDs[overflowIcon.UID] = true
	end

	-- The default boundary is the point where both the left-most-right-icon
	-- and left-most-right-icon meet OR the opposite side of the screen
	local oppositeAlignment = (alignment == "Left" and "Right") or "Left"
	local oppositeOrderedIcons = Overflow.updateAvailableIcons(oppositeAlignment)
	local nearestOppositeIcon = (isLeft and oppositeOrderedIcons[1]) or (isRight and oppositeOrderedIcons[#oppositeOrderedIcons])
	local oppositeOverflowIcon = overflowIcons[oppositeAlignment]
	local boundary = (isLeft and holderXPos + holderXSize) or holderXPos
	if nearestOppositeIcon then
		local oppositeRealXPositions = Overflow.getRealXPositions(oppositeAlignment, oppositeOrderedIcons)
		local oppositeX = oppositeRealXPositions[nearestOppositeIcon.UID]
		local oppositeXSize = Overflow.getWidth(nearestOppositeIcon)
		boundary = (isLeft and oppositeX - BOUNDARY_GAP) or oppositeX + oppositeXSize + BOUNDARY_GAP
	end
	
	-- We get the left-most icon (if left alignment) or right-most-icon (if
	-- right alignment) of the central icons group to see if we need to change
	-- the boundary (if the central icon boundary is smaller than the alignment
	-- boundary then we use the central)
	local totalChecks = 0
	local usingNearestCenter = false
	local function checkToShiftCentralIcon()
		local centerOrderedIcons = Overflow.getAvailableIcons("Center")
		local centerPos = (isLeft and 1) or #centerOrderedIcons
		local nearestCenterIcon = centerOrderedIcons[centerPos]
		local function secondaryCheck()
			if not beganSecondaryCenterCheck then
				beganSecondaryCenterCheck = true
				task.delay(3, Overflow.updateBoundary, alignment)
			end
		end
		if nearestCenterIcon and not nearestCenterIcon.hasRelocatedInOverflow then
			local ourNearestIcon = (isLeft and ourOrderedIcons[#ourOrderedIcons]) or (isRight and ourOrderedIcons[1])
			local centralNearestXPos = nearestCenterIcon.widget.AbsolutePosition.X
			local ourNearestXPos = ourNearestIcon.widget.AbsolutePosition.X
			local ourNearestXSize = Overflow.getWidth(ourNearestIcon)
			local centerBoundary = (isLeft and centralNearestXPos-BOUNDARY_GAP) or centralNearestXPos + Overflow.getWidth(nearestCenterIcon) + BOUNDARY_GAP
			local removeBoundary = (isLeft and ourNearestXPos + ourNearestXSize) or ourNearestXPos
			local hasShifted = false
			if isLeft then
				if centerBoundary < removeBoundary then
					if not beginCheckingCenterIcons then
						secondaryCheck()
						return
					end
					nearestCenterIcon:align("Left")
					nearestCenterIcon.hasRelocatedInOverflow = true
					hasShifted = true
				end
			elseif isRight then
				if centerBoundary > removeBoundary then
					if not beginCheckingCenterIcons or removeBoundary < 0 then
						secondaryCheck()
						return
					end
					nearestCenterIcon:align("Right")
					nearestCenterIcon.hasRelocatedInOverflow = true
					hasShifted = true
				end
			end
			if hasShifted then
				totalChecks += 1
				if totalChecks <= 4 then
					Overflow.updateAvailableIcons("Center")
					checkToShiftCentralIcon()
				end
			end
		end
	end
	checkToShiftCentralIcon()
	
	--[[
	This updates the maximum size of the overflow menus
	The menu determines its bounds from the smallest of either:
	 	1. The closest center-aligned icon (i.e. the boundary)
	 	2. The edge of the opposite overflow menu UNLESS...
	 	3. ... the edge exceeds more than half the screenGui
	--]]
	if overflowIcon then
		local menuBoundary = boundary
		local menu = overflowIcon:getInstance("Menu")
		local holderXEndPos = holderXPos + holderXSize
		local menuWidth = holderXSize
		if menu and oppositeOverflowIcon then
			local oppositeWidget = oppositeOverflowIcon.widget
			local oppositeXPos = oppositeWidget.AbsolutePosition.X
			local oppositeXSize = Overflow.getWidth(oppositeOverflowIcon)
			local oppositeBoundary = (isLeft and oppositeXPos - BOUNDARY_GAP) or oppositeXPos + oppositeXSize + BOUNDARY_GAP
			local oppositeMenu = oppositeOverflowIcon:getInstance("Menu")
			local isDominant = menu.AbsoluteCanvasSize.X >= oppositeMenu.AbsoluteCanvasSize.X
			if not usingNearestCenter then
				local halfwayXPos = holderXPos + holderXSize/2
				local halfwayBoundary = (isLeft and halfwayXPos - BOUNDARY_GAP/2) or halfwayXPos + BOUNDARY_GAP/2
				menuBoundary = halfwayBoundary
				if isDominant then
					menuBoundary = oppositeBoundary
				end
			end
			menuWidth = (isLeft and menuBoundary - holderXPos) or (holderXEndPos - menuBoundary)
		end
		local currentMaxWidth = menu and menu:GetAttribute("MaxWidth")
		menuWidth = Utility.round(menuWidth)
		if menu and currentMaxWidth ~= menuWidth then
			menu:SetAttribute("MaxWidth", menuWidth)
		end
	end

	-- Parent ALL icons of that alignment into the overflow if at least on
	-- sibling exceeds the bounds.
	-- We calculate the the absolute position of icons instead of reading
	-- directly to determine where they would be if not within an overflow
	local joinOverflow = false
	-- Icons flagged alwaysOverflow (phone: freecam, music refresh) always sit in the dropdown, so
	-- they do not take part in the "does it fit on the topbar" measurement.
	local measuredIcons = {}
	for _, icon in ipairs(ourOrderedIcons) do
		if not icon.alwaysOverflow then
			table.insert(measuredIcons, icon)
		end
	end
	local realXPositions = Overflow.getRealXPositions(alignment, measuredIcons)
	for i = #measuredIcons, 1, -1 do
		local icon = measuredIcons[i]
		local widgetX = Overflow.getWidth(icon)
		local xPos = realXPositions[icon.UID]
		if (isLeft and xPos + widgetX >= boundary) or (isRight and xPos <= boundary) then
			joinOverflow = true
		end
	end
	-- Icons flagged keepOutsideOverflow (e.g. the Menu button) always stay on the topbar.
	-- They still count for the boundaries above, they are just never moved.
	local joinableCount = 0
	for i = #ourOrderedIcons, 1, -1 do
		local icon = ourOrderedIcons[i]
		if not overflowIconUIDs[icon.UID] and not icon.keepOutsideOverflow then
			joinableCount += 1
		end
	end
	if joinableCount == 0 then
		joinOverflow = false
	end
	local widthOverflow = joinOverflow
	for _, icon in ipairs(ourOrderedIcons) do
		if icon.alwaysOverflow and not icon.keepOutsideOverflow and not overflowIconUIDs[icon.UID] then
			joinOverflow = true
			break
		end
	end
	-- On the right the three dots sit just left of the pinned icons, so Menu stays the right-most button
	if isRight then
		local pinnedOrder
		for _, icon in ipairs(ourOrderedIcons) do
			if icon.keepOutsideOverflow and not overflowIconUIDs[icon.UID] then
				local order = icon.widget.LayoutOrder
				if not pinnedOrder or order < pinnedOrder then
					pinnedOrder = order
				end
			end
		end
		if pinnedOrder and overflowIcon.overflowLayoutOrder ~= pinnedOrder - 1 then
			overflowIcon.overflowLayoutOrder = pinnedOrder - 1
			overflowIcon:modifyTheme({"IconSpot", "LayoutOrder", pinnedOrder - 1})
			overflowIcon:modifyTheme({"Widget", "LayoutOrder", pinnedOrder - 1})
		end
	end
	for i = #ourOrderedIcons, 1, -1 do
		local icon = ourOrderedIcons[i]
		local isOverflow = overflowIconUIDs[icon.UID]
		if not isOverflow then
			if icon.keepOutsideOverflow then
				if icon.parentIconUID then
					icon.overflowRestWidth = nil
					icon:leave()
				end
			elseif (widthOverflow or icon.alwaysOverflow) and not icon.parentIconUID then
				-- joinDropdown (vertical list under the three dots) instead of joinMenu
				-- (horizontal strip), so phones keep the topbar single-row.
				icon.overflowRestWidth = Overflow.getWidth(icon)
				local topbarX = icon.widget.AbsolutePosition.X
				icon:joinDropdown(overflowIcon)
				Overflow.styleRow(icon, overflowIcon, topbarX)
				-- Picking a row closes the dropdown (user taps only, not code-driven selects).
				-- An icon with overflowAction runs that instead of toggling itself (e.g. the music
				-- icon's row is just "Reload Music" here).
				icon.joinJanitor:add(icon.selected:Connect(function(fromSource)
					if fromSource ~= "User" then
						return
					end
					if icon.overflowAction then
						icon:deselect("OverflowAction", icon)
						task.spawn(icon.overflowAction)
					end
					if overflowIcon.isSelected then
						overflowIcon:deselect("OverflowPick", overflowIcon)
					end
				end))
			elseif not (widthOverflow or icon.alwaysOverflow) and icon.parentIconUID then
				icon.overflowRestWidth = nil
				icon:leave()
			end
		end
	end

	-- Hide the overflows when not in use
	if overflowIcon.isEnabled ~= joinOverflow then
		overflowIcon:setEnabled(joinOverflow)
	end
	if not joinOverflow and overflowIcon.isSelected then
		overflowIcon:deselect("OverflowEmpty", overflowIcon)
	end

end



return Overflow