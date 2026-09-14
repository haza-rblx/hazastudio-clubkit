--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local GeneralNotificationCenterService = require(script.Parent.Parent.Services.GeneralNotificationCenterService)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
local UIMotion = require(script.Parent.Parent.Utils.UIMotion)
local PaidBroadcastTitleCopy = require(script.Parent.PaidBroadcastTitleCopy)
local PaidBroadcastGuiRefs = require(script.Parent.PaidBroadcastGuiRefs)

export type ShowOptions = {
	bypassPayment: boolean,
	priceRobux: number?,
	player: Player,
}

local PaidBroadcastUI = {}
PaidBroadcastUI.__index = PaidBroadcastUI

local MODAL_BLUR_OPTIONS = {
	enableBlur = true,
	blurName = "PaidBroadcastUIBlur",
	enableZoom = true,
}

export type UI = typeof(setmetatable({} :: {
	_refs: PaidBroadcastGuiRefs.Refs,
	_anim: AnimationHelper.AnimationHelper,
	_onConfirm: ((message: string) -> ())?,
	_onClosed: (() -> ())?,
	_isVisible: boolean,
	_isClosing: boolean,
	_motion: { RBXScriptConnection },
	_fadeRows: { GuiObject },
	_fadeBases: { [GuiObject]: number },
}, PaidBroadcastUI))

function PaidBroadcastUI.new(refs: PaidBroadcastGuiRefs.Refs): UI
	local fadeRows: { GuiObject } = { refs.staticTitle }
	if refs.continueText then
		table.insert(fadeRows, refs.continueText)
	end

	local self = setmetatable({
		_refs = refs,
		_anim = AnimationHelper.new(),
		_onConfirm = nil :: ((message: string) -> ())?,
		_onClosed = nil :: (() -> ())?,
		_isVisible = false,
		_isClosing = false,
		_motion = {} :: { RBXScriptConnection },
		_fadeRows = fadeRows,
		-- Designed transparencies, read once: the composer GUI is bound once per session.
		_fadeBases = UIMotion.captureBases(fadeRows),
	}, PaidBroadcastUI)

	refs.root.Enabled = false
	refs.modal.Visible = false

	-- Press squash + pointer hover, bound once per UI instance and owned by it, exactly as
	-- long-lived as the click handlers below (the composer GUI lives for the session).
	for _, button in ipairs({ refs.continueButton, refs.cancelButton }) do
		for _, connection in ipairs(UIMotion.bindPress(button)) do
			table.insert(self._motion, connection)
		end
		for _, connection in ipairs(UIMotion.bindHover(button)) do
			table.insert(self._motion, connection)
		end
	end

	refs.cancelButton.MouseButton1Click:Connect(function()
		self:hide()
		if self._onClosed then
			self._onClosed()
		end
	end)

	refs.continueButton.MouseButton1Click:Connect(function()
		self:_confirm()
	end)

	return self
end

function PaidBroadcastUI.setOnConfirm(self: UI, callback: (message: string) -> ())
	self._onConfirm = callback
end

function PaidBroadcastUI.setOnClosed(self: UI, callback: () -> ())
	self._onClosed = callback
end

function PaidBroadcastUI.isVisible(self: UI): boolean
	return self._isVisible
end

function PaidBroadcastUI._updateContinueLabel(self: UI, bypassPayment: boolean, priceRobux: number?)
	local label = self._refs.continueText
	if not label then
		return
	end
	if bypassPayment then
		label.Text = Config.PaidBroadcast.CONTINUE_TEXT_FREE
		return
	end
	local price = if type(priceRobux) == "number" and priceRobux > 0 then priceRobux else 0
	label.Text = string.format(Config.PaidBroadcast.CONTINUE_TEXT_TEMPLATE, price)
end

function PaidBroadcastUI.show(self: UI, options: ShowOptions)
	self._refs.staticTitle.Text = PaidBroadcastTitleCopy.pickModalTitle(options.player)
	self._updateContinueLabel(self, options.bypassPayment, options.priceRobux)
	self._refs.messageBox.Text = ""
	self._isVisible = true
	self._isClosing = false
	self._refs.root.Enabled = true
	self._anim:presentCenterPanel(self._refs.modal, function()
		self._refs.messageBox:CaptureFocus()
	end, MODAL_BLUR_OPTIONS)
	-- Title and the (just-rewritten) price label arrive behind the panel's own open animation.
	UIMotion.fadeIn(self._fadeRows, self._fadeBases, 0.06)
end

function PaidBroadcastUI.hide(self: UI)
	if not self._isVisible and not self._refs.modal.Visible then
		return
	end
	if self._isClosing then
		return
	end

	self._isVisible = false
	self._isClosing = true
	self._refs.messageBox:ReleaseFocus()

	if not self._refs.modal.Visible then
		self._isClosing = false
		self._refs.root.Enabled = false
		self._refs.messageBox.Text = ""
		return
	end

	self._anim:dismissCenterPanel(self._refs.modal, function()
		self._isClosing = false
		if not self._isVisible then
			self._refs.root.Enabled = false
			self._refs.messageBox.Text = ""
		end
	end, MODAL_BLUR_OPTIONS)
end

function PaidBroadcastUI._confirm(self: UI)
	local message = self._refs.messageBox.Text:match("^%s*(.-)%s*$") or ""
	if message == "" then
		-- Rotation never touches layout, so the empty box can shake wherever it is laid out.
		UIMotion.wiggle(self._refs.messageBox, 6)
		GeneralNotificationCenterService.show({
			title = "Broadcast",
			message = Config.PaidBroadcast.MSG_EMPTY,
			notifType = "WARNING",
			domain = "broadcast",
		})
		return
	end
	if #message > Config.PaidBroadcast.MAX_MESSAGE_LENGTH then
		UIMotion.wiggle(self._refs.messageBox, 6)
		GeneralNotificationCenterService.show({
			title = "Broadcast",
			message = Config.PaidBroadcast.MSG_TOO_LONG,
			notifType = "WARNING",
			domain = "broadcast",
		})
		return
	end
	if self._onConfirm then
		self._onConfirm(message)
	end
end

return PaidBroadcastUI
