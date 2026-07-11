--!nocheck
-- RBXM export / unpack options panel (Dovetail styling).

local UI = require(script.Parent.DovetailUI)

local PackagerPanel = {}

export type ExportOptions = {
	includeConfig: boolean,
	includeSecrets: boolean,
}

export type UnpackOptions = {
	replaceExisting: boolean,
	keepBuyerConfig: boolean,
	keepBuyerSecrets: boolean,
}

export type PanelApi = {
	getExportOptions: () -> ExportOptions,
	getUnpackOptions: () -> UnpackOptions,
}

function PackagerPanel.create(parent: Instance): PanelApi
	local card = UI.card(parent, 2)
	UI.eyebrow(card, "RBXM Packager", 0)

	local includeConfig = UI.checkboxRow(card, "Include Hazastudio_ClubKitConfig", true, 1)
	local includeSecrets = UI.checkboxRow(card, "Include Secrets template", true, 2)
	local replaceExisting = UI.checkboxRow(card, "Replace existing instances", true, 3)
	local keepBuyerConfig = UI.checkboxRow(card, "Do not overwrite buyer ClubKitConfig", true, 4)
	local keepBuyerSecrets = UI.checkboxRow(card, "Do not overwrite buyer Secrets", true, 5)

	UI.bodyText(
		card,
		"Export: toolbar Export RBXM → save file.\nUnpack: toolbar Unpack RBXM → pick .rbxm file.\nFor daily Luau updates, use Engine Update above instead.",
		6
	)

	return {
		getExportOptions = function()
			return {
				includeConfig = includeConfig.Value,
				includeSecrets = includeSecrets.Value,
			}
		end,
		getUnpackOptions = function()
			return {
				replaceExisting = replaceExisting.Value,
				keepBuyerConfig = keepBuyerConfig.Value,
				keepBuyerSecrets = keepBuyerSecrets.Value,
			}
		end,
	}
end

return PackagerPanel
