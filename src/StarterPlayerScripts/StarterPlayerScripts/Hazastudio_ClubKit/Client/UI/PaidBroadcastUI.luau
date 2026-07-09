--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local GeneralNotificationCenterService = require(script.Parent.Parent.Services.GeneralNotificationCenterService)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
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
}, PaidBroadcastUI))

function PaidBroadcastUI.new(refs: PaidBroadcastGuiRefs.Refs): UI
	local self = setmetatable({
		_refs = refs,
		_anim = AnimationHelper.new(),
		_onConfirm = nil :: ((message: string) -> ())?,
		_onClosed = nil :: (() -> ())?,
		_isVisible = false,
		_isClosing = false,
	}, PaidBroadcastUI)

	refs.root.Enabled = false
	refs.modal.Visible = false

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
		GeneralNotificationCenterService.show({
			title = "Broadcast",
			message = Config.PaidBroadcast.MSG_EMPTY,
			notifType = "WARNING",
			domain = "broadcast",
		})
		return
	end
	if #message > Config.PaidBroadcast.MAX_MESSAGE_LENGTH then
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
