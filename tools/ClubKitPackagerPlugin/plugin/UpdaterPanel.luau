--!nocheck
-- Engine update panel — clones UpdatePluginGUI into DockWidget (compact dock scale).

local SourceSyncCore = require(script.Parent.SourceSyncCore)
local DovetailUI = require(script.Parent.DovetailUI)

local UpdaterPanel = {}

export type PanelApi = {
	checkForUpdates: () -> (),
	runUpdate: () -> (),
	setStatus: (text: string, tone: string?) -> (),
}

export type CreateOpts = {
	onDismiss: (() -> ())?,
}

local COLOR_PRIMARY = Color3.fromRGB(0, 132, 255)
local COLOR_DISABLED = Color3.fromRGB(80, 80, 80)
local COLOR_STATUS = Color3.fromRGB(180, 180, 185)
local BODY_FALLBACK =
	"Keeps the Club Kit engine current. ClubKitConfig and Secrets are never overwritten; missing config keys may be filled in."

local SKIP_TITLE = {
	Added = true,
	Changed = true,
	Fixed = true,
	Removed = true,
	Deprecated = true,
	Security = true,
}

local function truncateNotes(text: string, maxChars: number): string
	local plain = string.gsub(text, "\r\n", "\n")
	if #plain <= maxChars then
		return plain
	end
	return string.sub(plain, 1, maxChars - 1) .. "…"
end

local function cleanupChangelog(raw: string): string
	local plain = DovetailUI.formatMarkdownPlain(raw)
	plain = string.gsub(plain, "^%s*%-?%s*%d%d%d%d%-%d%d%-%d%d%s*\n+", "")
	plain = string.gsub(plain, "^%s*%d%d%d%d%-%d%d%-%d%d%s*\n+", "")
	return plain
end

local function firstFeatureTitle(notes: string): string
	for line in string.gmatch(notes, "[^\r\n]+") do
		local trimmed = string.match(line, "^%s*(.-)%s*$") or line
		trimmed = string.gsub(trimmed, "^[-*]%s*", "")
		if trimmed == "" or SKIP_TITLE[trimmed] then
			-- skip
		elseif string.match(trimmed, "^%d%d%d%d%-%d%d%-%d%d$") then
			-- skip date-only lines
		elseif string.match(trimmed, "^%[%s*") then
			-- skip
		else
			local cut = string.match(trimmed, "^(.-)%s+[—–-]%s+") or trimmed
			if #cut > 56 then
				cut = string.sub(cut, 1, 55) .. "…"
			end
			return cut
		end
	end
	return "Club Kit Engine"
end

local function findTemplate(): Instance?
	local here = script.Parent
	if here then
		local gui = here:FindFirstChild("UpdatePluginGUI")
		if gui then
			return gui
		end
	end
	return script:FindFirstChild("UpdatePluginGUI")
end

local function mustFind(root: Instance, name: string): Instance
	local found = root:FindFirstChild(name, true)
	if not found then
		error("[ClubKitUpdater] Missing UI node: " .. name)
	end
	return found
end

-- Design was sized for a large ScreenGui mock; dock is ~360px — scale type down.
local function applyDockScale(page: GuiObject)
	page.Size = UDim2.fromScale(1, 1)
	page.Position = UDim2.fromScale(0, 0)
	page.AnchorPoint = Vector2.new(0, 0)

	local scroll = page:FindFirstChild("ScrollingFrame")
	if scroll and scroll:IsA("ScrollingFrame") then
		-- Leave room for ButtonsGroup (~100px)
		scroll.Size = UDim2.new(1, 0, 1, -108)
		scroll.Position = UDim2.new(0.5, 0, 0, 0)
		scroll.AnchorPoint = Vector2.new(0.5, 0)
	end

	local buttons = page:FindFirstChild("ButtonsGroup")
	if buttons and buttons:IsA("GuiObject") then
		buttons.Size = UDim2.new(1, 0, 0, 100)
		buttons.Position = UDim2.new(0.5, 0, 1, 0)
		buttons.AnchorPoint = Vector2.new(0.5, 1)
	end

	local sizes = {
		Title = 22,
		NewVersionInfo = 13,
		ExistingVersionInfo = 13,
		UpdateInfoTitle = 15,
		UpdateTitle = 14,
		UpdateInfoDetailed = 12,
		UpdateEngineButton = 15,
		StayonThisVersionButton = 14,
	}
	for name, textSize in sizes do
		local node = page:FindFirstChild(name, true)
		if node and (node:IsA("TextLabel") or node:IsA("TextButton")) then
			node.TextSize = textSize
		end
	end

	local icon = page:FindFirstChild("ImageLabel", true)
	if icon and icon:IsA("ImageLabel") then
		icon.Size = UDim2.fromOffset(52, 52)
	end

	local updateBtn = page:FindFirstChild("UpdateEngineButton", true)
	if updateBtn and updateBtn:IsA("GuiObject") then
		updateBtn.Size = UDim2.new(1, 0, 0, 40)
	end
	local stayBtn = page:FindFirstChild("StayonThisVersionButton", true)
	if stayBtn and stayBtn:IsA("GuiObject") then
		stayBtn.Size = UDim2.new(1, 0, 0, 36)
	end
end

function UpdaterPanel.create(parent: Instance, opts: CreateOpts?): PanelApi
	opts = opts or {}

	local template = findTemplate()
	if not template then
		error(
			"[ClubKitUpdater] UpdatePluginGUI template missing. Rebuild plugin with UpdatePluginGUI.rbxmx embedded."
		)
	end

	local pageTemplate = template:FindFirstChild("UpdatePage")
	if not pageTemplate or not pageTemplate:IsA("GuiObject") then
		error("[ClubKitUpdater] UpdatePluginGUI.UpdatePage missing.")
	end

	local page = pageTemplate:Clone()
	page.Name = "UpdatePage"
	page.LayoutOrder = 1
	page.Parent = parent
	applyDockScale(page)

	local header = mustFind(page, "Header")
	local newVersionInfo = mustFind(header, "NewVersionInfo") :: TextLabel
	local existingVersionInfo = mustFind(header, "ExistingVersionInfo") :: TextLabel
	local heroTitle = mustFind(header, "Title") :: TextLabel

	local updateTitle = mustFind(page, "UpdateTitle") :: TextLabel
	local updateInfoDetailed = mustFind(page, "UpdateInfoDetailed") :: TextLabel
	local updateInfoTitle = mustFind(page, "UpdateInfoTitle") :: TextLabel

	local updateButton = mustFind(page, "UpdateEngineButton") :: TextButton
	local stayButton = mustFind(page, "StayonThisVersionButton") :: TextButton

	-- Compact status under hero (does not steal "What's on this update?" heading)
	local statusLine = Instance.new("TextLabel")
	statusLine.Name = "StatusLine"
	statusLine.BackgroundTransparency = 1
	statusLine.Size = UDim2.new(1, 0, 0, 0)
	statusLine.AutomaticSize = Enum.AutomaticSize.Y
	statusLine.FontFace = existingVersionInfo.FontFace
	statusLine.TextSize = 11
	statusLine.TextWrapped = true
	statusLine.TextXAlignment = Enum.TextXAlignment.Center
	statusLine.TextColor3 = COLOR_STATUS
	statusLine.Text = ""
	statusLine.LayoutOrder = 99
	statusLine.Parent = header

	local busy = false
	local lastCheck: any = {
		localVersion = SourceSyncCore.getLocalVersion() or "unknown",
		updateAvailable = false,
	}

	local function setStatus(text: string, _tone: string?)
		statusLine.Text = text or ""
	end

	-- Primary CTA: "Update engine" only when a newer tag exists; otherwise "Check update".
	local function setPrimaryIdle(canInstall: boolean)
		updateButton.Active = true
		updateButton.AutoButtonColor = true
		if canInstall then
			updateButton.Text = "Update engine"
			updateButton.BackgroundColor3 = COLOR_PRIMARY
		else
			updateButton.Text = "Check update"
			updateButton.BackgroundColor3 = COLOR_DISABLED
		end
	end

	local function setPrimaryBusy(label: string)
		updateButton.Active = false
		updateButton.AutoButtonColor = false
		updateButton.Text = label
		updateButton.BackgroundColor3 = COLOR_DISABLED
	end

	local function refreshMeta()
		local localV = lastCheck.localVersion or "unknown"
		local latestV = lastCheck.latestVersion
		existingVersionInfo.Text = ("Current Version : %s"):format(localV)

		if lastCheck.error then
			newVersionInfo.Text = "New Version : —"
			heroTitle.Text = "Could not check for updates."
			updateTitle.Text = "Check failed"
			updateInfoDetailed.Text = tostring(lastCheck.error)
			updateInfoTitle.Text = "What's on this update?"
			setPrimaryIdle(false)
			return
		end

		if latestV and lastCheck.updateAvailable then
			newVersionInfo.Text = ("New Version : %s"):format(latestV)
			heroTitle.Text = "The Club Kit Engine update is here."
			setPrimaryIdle(true)
		elseif latestV then
			newVersionInfo.Text = ("New Version : %s"):format(latestV)
			heroTitle.Text = "You're on the latest Club Kit Engine."
			setPrimaryIdle(false)
		else
			newVersionInfo.Text = "New Version : —"
			heroTitle.Text = "Check for the Club Kit Engine update."
			setPrimaryIdle(false)
		end
	end

	local function applyCheckResult(result)
		lastCheck = result
		refreshMeta()

		updateInfoTitle.Text = "What's on this update?"

		if result.changelog and result.changelog ~= "" then
			local plain = cleanupChangelog(result.changelog)
			updateTitle.Text = firstFeatureTitle(plain)
			updateInfoDetailed.Text = truncateNotes(plain, 480)
		else
			updateTitle.Text = if result.updateAvailable then "Engine update available" else "Club Kit Engine"
			updateInfoDetailed.Text = BODY_FALLBACK
		end

		if result.error then
			setStatus(result.error)
			warn("[ClubKitUpdater] " .. result.error)
			return
		end

		if result.updateAvailable then
			local msg = ("Update available: v%s → v%s"):format(result.localVersion, result.latestVersion)
			setStatus(msg)
			print("[ClubKitUpdater] " .. msg)
		else
			setStatus(("Up to date · v%s"):format(result.localVersion))
			print(("[ClubKitUpdater] Engine is up to date (v%s)."):format(result.localVersion))
		end
	end

	local function checkForUpdates()
		if busy then
			print("[ClubKitUpdater] Still busy, please wait...")
			return
		end
		busy = true
		heroTitle.Text = "Checking for updates…"
		setPrimaryBusy("Checking…")
		setStatus("Checking GitHub tags…")
		print("[ClubKitUpdater] Checking GitHub tags...")
		task.spawn(function()
			local ok, result = pcall(SourceSyncCore.checkForUpdates)
			if not ok then
				local err = tostring(result)
				lastCheck.error = err
				refreshMeta()
				setStatus("Check failed: " .. err)
				warn("[ClubKitUpdater] " .. err)
			else
				applyCheckResult(result)
			end
			busy = false
		end)
	end

	local function runUpdate()
		if busy then
			return
		end
		if not lastCheck.updateAvailable or not lastCheck.latestTag then
			checkForUpdates()
			return
		end

		if lastCheck.localVersion ~= "unknown" and lastCheck.latestVersion then
			local cmp = SourceSyncCore.compareVersions(lastCheck.localVersion, lastCheck.latestVersion)
			if cmp > 0 then
				setStatus("Downgrade detected — see Output.")
				warn("[ClubKitUpdater] Downgrade not blocked - proceed with caution.")
			elseif cmp == 0 then
				setStatus("Already on latest version.")
				refreshMeta()
				return
			end
		end

		busy = true
		setPrimaryBusy("Updating…")
		setStatus("Fetching file tree…")
		print("[ClubKitUpdater] Applying update from " .. tostring(lastCheck.latestTag) .. "...")
		task.spawn(function()
			local tag = lastCheck.latestTag :: string
			local ok, reportOrErr = pcall(function()
				return SourceSyncCore.applyEngineUpdate(tag, function(msg, index, total)
					local line = ("%s (%d/%d)"):format(msg, index, total)
					setStatus(line)
					print("[ClubKitUpdater] " .. line)
				end)
			end)

			if not ok then
				local err = tostring(reportOrErr)
				setStatus("Update failed: " .. err)
				warn("[ClubKitUpdater] " .. err)
				busy = false
				refreshMeta()
				return
			end

			local report = reportOrErr
			local okCount = #report.ok
			local errCount = #report.errors
			if report.configPatch then
				print("[ClubKitUpdater] " .. tostring(report.configPatch))
			end
			if errCount == 0 then
				local doneMsg = ("Done · %d files · v%s · save place"):format(okCount, report.version or "?")
				if report.configPatch then
					doneMsg = doneMsg .. " · " .. tostring(report.configPatch)
				end
				setStatus(doneMsg)
				print("[ClubKitUpdater] " .. doneMsg)
			else
				local doneMsg = ("Finished with errors: %d ok, %d failed."):format(okCount, errCount)
				setStatus(doneMsg)
				warn("[ClubKitUpdater] " .. doneMsg)
				for _, line in report.errors do
					warn("[ClubKitUpdater] FAIL " .. line)
				end
			end

			local recheckOk, recheckResult = pcall(SourceSyncCore.checkForUpdates)
			if recheckOk then
				applyCheckResult(recheckResult)
			else
				refreshMeta()
			end
			busy = false
		end)
	end

	local function primaryClick()
		if lastCheck.updateAvailable and lastCheck.latestTag then
			runUpdate()
		else
			checkForUpdates()
		end
	end

	local function stayOnVersion()
		if busy then
			return
		end
		print("[ClubKitUpdater] Stay on this version")
		if opts.onDismiss then
			opts.onDismiss()
		end
	end

	refreshMeta()
	updateInfoTitle.Text = "What's on this update?"
	updateTitle.Text = "Club Kit Engine"
	updateInfoDetailed.Text = BODY_FALLBACK
	setStatus("Opening · checking for updates…")
	setPrimaryIdle(false)

	updateButton.MouseButton1Click:Connect(primaryClick)
	stayButton.MouseButton1Click:Connect(stayOnVersion)

	return {
		checkForUpdates = checkForUpdates,
		runUpdate = runUpdate,
		setStatus = setStatus,
	}
end

return UpdaterPanel
