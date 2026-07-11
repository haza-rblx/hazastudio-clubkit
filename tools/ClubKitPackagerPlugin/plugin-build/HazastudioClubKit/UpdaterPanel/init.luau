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
	UI.eyebrow(card, "Engine Update", 0)

	local _, installedValue = UI.statBlock(card, "Installed", 1)
	local _, latestValue = UI.statBlock(card, "Latest", 2)

	local changelogCard = UI.card(card, 3)
	UI.eyebrow(changelogCard, "Changelog", 0)
	local changelogText = UI.bodyText(changelogCard, "Check for updates to load changelog.", 1)

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
	updateButton.Size = UDim2.new(0.55, -4, 1, 0)

	local checkButton = UI.ghostButton(buttonRow, "Check for Updates", 1)
	checkButton.Size = UDim2.new(0.45, -4, 1, 0)

	UI.bodyText(
		card,
		"ClubKitConfig and Secrets are never modified. StarterGui, Workspace, and ServerStorage assets are untouched.",
		5
	)

	local statusLine = UI.statusLine(card, 6)

	local busy = false
	local lastCheck: any = {
		localVersion = SourceSyncCore.getLocalVersion() or "unknown",
		updateAvailable = false,
	}
	installedValue.Text = "v" .. lastCheck.localVersion

	local function setStatus(text: string, tone: string?)
		statusLine.Text = text
		if tone == "error" then
			statusLine.TextColor3 = Theme.colors.error
		elseif tone == "success" then
			statusLine.TextColor3 = Theme.colors.success
		elseif tone == "warning" then
			statusLine.TextColor3 = Theme.colors.warning
		else
			statusLine.TextColor3 = Theme.colors.ash
		end
	end

	local function applyCheckResult(result)
		installedValue.Text = "v" .. result.localVersion
		if result.latestVersion then
			latestValue.Text = "v" .. result.latestVersion
		else
			latestValue.Text = "—"
		end

		if result.changelog then
			changelogText.Text = result.changelog
		end

		if result.error then
			setStatus(result.error, "error")
			return
		end

		if result.updateAvailable then
			setStatus(
				("Update available: v%s → v%s"):format(result.localVersion, result.latestVersion),
				"warning"
			)
		else
			setStatus("Engine is up to date.", "success")
		end
	end

	local function checkForUpdates()
		if busy then
			return
		end
		busy = true
		setStatus("Checking GitHub tags…")
		task.spawn(function()
			local result = SourceSyncCore.checkForUpdates()
			lastCheck = result
			applyCheckResult(result)
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
				setStatus("Downgrade detected — use Check for Updates and confirm manually in Output.", "warning")
				warn("[ClubKitUpdater] Downgrade not blocked — proceed with caution.")
			elseif cmp == 0 then
				setStatus("Already on latest version.", "success")
				return
			end
		end

		busy = true
		setStatus("Fetching file tree…")
		task.spawn(function()
			local tag = lastCheck.latestTag :: string
			local report = SourceSyncCore.applyEngineUpdate(tag, function(msg, index, total)
				setStatus(("%s (%d/%d)"):format(msg, index, total))
			end)

			local okCount = #report.ok
			local errCount = #report.errors
			if errCount == 0 then
				setStatus(("Applied %d files from %s (v%s). Save place."):format(okCount, tag, report.version or "?"), "success")
			else
				setStatus(
					("Done with errors: %d ok, %d failed. See Output."):format(okCount, errCount),
					"error"
				)
				for _, line in report.errors do
					warn("[ClubKitUpdater] " .. line)
				end
			end

			for _, line in report.ok do
				print("[ClubKitUpdater] OK " .. line)
			end

			lastCheck = SourceSyncCore.checkForUpdates()
			applyCheckResult(lastCheck)
			busy = false
		end)
	end

	checkButton.MouseButton1Click:Connect(checkForUpdates)
	updateButton.MouseButton1Click:Connect(runUpdate)

	task.defer(checkForUpdates)

	return {
		checkForUpdates = checkForUpdates,
		runUpdate = runUpdate,
		setStatus = setStatus,
	}
end

return UpdaterPanel
