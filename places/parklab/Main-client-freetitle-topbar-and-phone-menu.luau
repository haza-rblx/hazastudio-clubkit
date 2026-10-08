-- PLACE-LOCAL OVERRIDE (PARKLAB) — snapshot of place-only code, read 2026-10-06.
-- NOT in the repo (`git log -S freeTitleEventIcon` is empty). The next engine sync
-- to PARKLAB replaces StarterPlayerScripts.Hazastudio_ClubKit.Main and drops all of it.
-- The Free Title topbar icon now exists in the repo as FreeTitleEvent.Trigger = "Topbar"
-- (2026-10-06); the PHONE OVERFLOW MENU (part 2) does not — keep this file to port it.
-- Line numbers are PARKLAB's Main as of 2026-10-06 (2415 lines).

-- ============================================================================
-- Part 1 — Main 1184-1209: Free Title topbar icon (superseded by repo Trigger)
-- ============================================================================
-- Free Title Event topbar icon (replaces the floating card).
local freeTitleEventIcon = Icon.new()
freeTitleEventIcon:setImage(Config.FreeTitleEvent.TOPBAR_ICON)
freeTitleEventIcon:setLabel("")
freeTitleEventIcon:setOrder(Config.FreeTitleEvent.TOPBAR_ORDER)
freeTitleEventIcon:setEnabled(Config.FeatureFlags.FreeTitleEventEnabled == true)
setCompactTopbarWidth(freeTitleEventIcon, 36)
removeTopbarInnerPadding(freeTitleEventIcon)
styleTopbarPill(freeTitleEventIcon)
enlargeTopbarIcon(freeTitleEventIcon, 36, 12)
-- The topbar image label defaults to ScaleType.Stretch, which distorts
-- non-square assets. Fit keeps the asset's own aspect inside the slot.
task.spawn(function()
	local widget
	for _ = 1, 40 do
		widget = resolveTopbarWidget(freeTitleEventIcon)
		if widget and widget.AbsoluteSize.X > 0 then
			break
		end
		task.wait(0.1)
	end
	local image = widget and widget:FindFirstChildWhichIsA("ImageLabel", true)
	if image then
		image.ScaleType = Enum.ScaleType.Fit
	end
end)

-- ============================================================================
-- Part 2 — Main 1227-1305: phone-only overflow "..." dropdown (NOT in repo)
-- Sits right after the TopMenuController.hideTopbarTriggerIcons pcall block.
-- ============================================================================
-- === Phone-only overflow dropdown ===
-- Registry for icons created later in boot (freecam, auto-dance); dropdown items resolve at click time.
local phoneDropdownRegistry: { [string]: any } = {}
if PhoneLayout.isPhoneLayout() then
	local function hideFromStrip(icon: any)
		pcall(function()
			if type(icon.leave) == "function" then
				icon:leave()
			end
			if type(icon.setEnabled) == "function" then
				icon:setEnabled(false)
			end
		end)
	end
	-- Keep the icons alive (select() still fires bindings) but off the strip.
	hideFromStrip(adminIcon)
	hideFromStrip(commandLibraryIcon)
	hideFromStrip(freeTitleEventIcon)

	local moreIcon = Icon.new()
	-- Same three-dot asset TopbarPlus itself uses for its overflow icon (6069276526).
	moreIcon:setImage(6069276526)
	moreIcon:setLabel("")
	moreIcon:setOrder(Config.TopbarMenu.ORDER + 3)
	setCompactTopbarWidth(moreIcon, 36)
	removeTopbarInnerPadding(moreIcon)
	styleTopbarPill(moreIcon)
	enlargeTopbarIcon(moreIcon, 36, 12)

	local function makeItem(label, onSelect)
		local item = Icon.new()
		item:setLabel(label)
		pcall(function()
			item:oneClick(true)
			item:modifyTheme({
				{ "IconImage", "Visible", false },
				{ "PaddingLeft", "Size", UDim2.fromScale(0, 1) },
			})
		end)
		item.selected:Connect(function()
			onSelect()
		end)
		return item
	end

	local items = {
		makeItem("Admin Panel", function()
			adminIcon:select()
		end),
		makeItem("Command Center", function()
			commandLibraryIcon:select()
		end),
		-- Freecam & Auto Dance icons are created later in boot; resolve at click time.
		makeItem("Freecam", function()
			local icon = phoneDropdownRegistry.freecam
			if icon and icon.isSelected then
				icon:deselect()
			elseif icon then
				icon:select()
			end
		end),
		makeItem("Auto Dance", function()
			local icon = phoneDropdownRegistry.autoDance
			if icon and icon.isSelected then
				icon:deselect()
			elseif icon then
				icon:select()
			end
		end),
	}
	if Config.FeatureFlags.FreeTitleEventEnabled == true then
		table.insert(items, makeItem("Free Title", function()
			freeTitleEventIcon:select()
		end))
	end
	pcall(function()
		moreIcon:setDropdown(items)
	end)
end
-- NOTE: phoneDropdownRegistry.freecam / .autoDance are assigned further down in
-- PARKLAB's Main where those icons are created — not captured in this snapshot.

-- ============================================================================
-- Part 3 — Main 1627-1644, inside trackBootTask("SettingsController.init"),
-- right after ClientMods.TopMenuController.setSettingsUI(settingsUI)
-- (superseded by MenuShellUI:openCustomTitlePanelWhenReady in the repo)
-- ============================================================================
	-- Free Title Event topbar icon opens the custom title panel.
	-- The profile payload arrives async (ProfileMenuSync, DataStore-backed), so a
	-- click during boot has nothing to open yet - wait for it instead of no-op.
	freeTitleEventIcon.selected:Connect(function()
		freeTitleEventIcon:deselect()
		if settingsUI:openCustomTitlePanel() then
			return
		end
		task.spawn(function()
			for _ = 1, 40 do
				task.wait(0.25)
				if settingsUI:openCustomTitlePanel() then
					return
				end
			end
			ClientMods.NotifService.warn("Profile data belum siap, coba lagi sebentar.", { dedupeKey = "freetitle-notready" })
		end)
	end)
