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
	UI.divider(parent, 2)

	local card = UI.card(parent, 3)
	UI.sectionHeader(
		card,
		"RBXM Packager",
		"Legacy full-package export. For daily Luau updates, use Engine Update above.",
		0
	)

	UI.eyebrow(card, "Export Options", 1)
	local includeConfig = UI.checkboxRow(card, "Include Hazastudio_ClubKitConfig", true, 2)
	local includeSecrets = UI.checkboxRow(card, "Include Secrets template", true, 3)

	UI.divider(card, 4)

	UI.eyebrow(card, "Unpack Options", 5)
	local replaceExisting = UI.checkboxRow(card, "Replace existing instances", true, 6)
	local keepBuyerConfig = UI.checkboxRow(card, "Do not overwrite buyer ClubKitConfig", true, 7)
	local keepBuyerSecrets = UI.checkboxRow(card, "Do not overwrite buyer Secrets", true, 8)

	UI.bodyText(
		card,
		"Export: toolbar Export RBXM, then save the file.\nUnpack: toolbar Unpack RBXM, then pick a .rbxm file.",
		9
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
