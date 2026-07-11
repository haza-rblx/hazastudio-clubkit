--!nocheck
-- Engine update panel — check GitHub tags and apply Luau source sync.

local Theme = require(script.Parent.DovetailTheme)
local UI = require(script.Parent.DovetailUI)
local SourceSyncCore = require(script.Parent.SourceSyncCore)

local UpdaterPanel = {}

export type PanelApi = {
	checkForUpdates: () -> (),
	runUpdate: () -> (),
	setStatus: (text: string, tone: string?) -> (),
}

function UpdaterPanel.create(parent: Instance): PanelApi
	local card = UI.card(parent, 1)
	UI.sectionHeader(
		card,
		"Engine Update",
		"Sync Luau engine from GitHub tags. Config and secrets stay untouched.",
		0
	)

	local installedValue, latestValue = UI.versionPillRow(card, 1)

	UI.eyebrow(card, "Release Notes", 2)
	local changelogText = UI.changelogBox(card, 3)

	local buttonRow = Instance.new("Frame")
	buttonRow.BackgroundTransparency = 1
	buttonRow.Size = UDim2.new(1, 0, 0, Theme.sizes.buttonHeight)
	buttonRow.LayoutOrder = 4
	buttonRow.Parent = card

	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.Padding = UDim.new(0, Theme.sizes.gap)
	buttonLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buttonLayout.Parent = buttonRow

	local updateButton = UI.primaryButton(buttonRow, "Update Engine", 0)
	updateButton.Size = UDim2.new(0.55, -5, 1, 0)

	local checkButton = UI.ghostButton(buttonRow, "Check Updates", 1)
	checkButton.Size = UDim2.new(0.45, -5, 1, 0)

	local statusLine = UI.statusLine(card, 5)

	local busy = false
	local lastCheck: any = {
		localVersion = SourceSyncCore.getLocalVersion() or "unknown",
		updateAvailable = false,
	}
	installedValue.Text = "v" .. lastCheck.localVersion

	local function setStatus(text: string, tone: string?)
		statusLine.Text = text
		UI.setStatusTone(statusLine, tone)
	end

	local function applyCheckResult(result)
		installedValue.Text = "v" .. result.localVersion
		if result.latestVersion then
			latestValue.Text = "v" .. result.latestVersion
		else
			latestValue.Text = "-"
		end

		if result.changelog then
			changelogText.Text = UI.formatMarkdownPlain(result.changelog)
		end

		if result.error then
			setStatus(result.error, "error")
			warn("[ClubKitUpdater] " .. result.error)
			return
		end

		if result.updateAvailable then
			local msg = ("Update available: v%s -> v%s"):format(result.localVersion, result.latestVersion)
			setStatus(msg, "warning")
			print("[ClubKitUpdater] " .. msg)
		else
			local msg = ("Engine is up to date (v%s)."):format(result.localVersion)
			setStatus(msg, "success")
			print("[ClubKitUpdater] " .. msg)
		end
	end

	local function checkForUpdates()
		if busy then
			print("[ClubKitUpdater] Still busy, please wait...")
			return
		end
		busy = true
		setStatus("Checking GitHub tags...")
		print("[ClubKitUpdater] Checking GitHub tags...")
		task.spawn(function()
			local ok, result = pcall(SourceSyncCore.checkForUpdates)
			if not ok then
				local err = tostring(result)
				setStatus("Check failed: " .. err, "error")
				warn("[ClubKitUpdater] " .. err)
			else
				lastCheck = result
				applyCheckResult(result)
			end
			busy = false
		end)
	end

	local function runUpdate()
		if busy then
			return
		end
		if not lastCheck.latestTag then
			setStatus("Check for updates first.", "warning")
			return
		end

		if lastCheck.localVersion ~= "unknown" and lastCheck.latestVersion then
			local cmp = SourceSyncCore.compareVersions(lastCheck.localVersion, lastCheck.latestVersion)
			if cmp > 0 then
				setStatus("Downgrade detected. Confirm in Output before continuing.", "warning")
				warn("[ClubKitUpdater] Downgrade not blocked - proceed with caution.")
			elseif cmp == 0 then
				setStatus("Already on latest version.", "success")
				return
			end
		end

		busy = true
		setStatus("Fetching file tree...")
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
				setStatus("Update failed: " .. err, "error")
				warn("[ClubKitUpdater] " .. err)
				busy = false
				return
			end

			local report = reportOrErr
			local okCount = #report.ok
			local errCount = #report.errors
			if errCount == 0 then
				local doneMsg = ("Update complete: %d files applied from %s (v%s). Save place."):format(
					okCount,
					tag,
					report.version or "?"
				)
				setStatus(doneMsg, "success")
				print("[ClubKitUpdater] " .. doneMsg)
			else
				local doneMsg = ("Update finished with errors: %d ok, %d failed."):format(okCount, errCount)
				setStatus(doneMsg, "error")
				warn("[ClubKitUpdater] " .. doneMsg)
				for _, line in report.errors do
					warn("[ClubKitUpdater] FAIL " .. line)
				end
			end

			local recheckOk, recheckResult = pcall(SourceSyncCore.checkForUpdates)
			if recheckOk then
				lastCheck = recheckResult
				applyCheckResult(lastCheck)
			end
			busy = false
		end)
	end

	checkButton.MouseButton1Click:Connect(checkForUpdates)
	updateButton.MouseButton1Click:Connect(runUpdate)

	return {
		checkForUpdates = checkForUpdates,
		runUpdate = runUpdate,
		setStatus = setStatus,
	}
end

return UpdaterPanel
