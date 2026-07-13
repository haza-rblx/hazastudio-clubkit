--!strict
-- PATH: StarterPlayerScripts/Client/UI/MusicTopbarIcon.luau
-- Owns the TopbarPlus icon visibility for the Music feature.
--
-- Strategy: ONE persistent icon instance. Show/hide via widget reparenting.
-- Why NOT destroy/recreate:
--   TopbarPlus v3 internal state (alignment groups, icon registry) does not
--   fully reset on destroy(), causing new icons to fail occupying the same slot.
-- Why NOT just setEnabled(false):
--   setEnabled(false) does not reliably hide the visual on every TopbarPlus build.
-- Solution: cache the widget GuiObject + a non-nil restore parent, reparent to
--   nil on hide, and on show always re-apply styling (align) so TopbarPlus
--   reparents even if our cached parent was lost.
--
-- Horizontal setMenu children (Music Player / Load Track) are created once and
-- kept for the icon lifetime. applyStyling re-runs on show but must not rebuild
-- the menu (would orphan listeners / thrash TopbarPlus).

local MusicTopbarIcon = {}
MusicTopbarIcon.__index = MusicTopbarIcon

export type SelectionCallback = () -> ()

export type MenuItemConfig = {
	label: string,
	onSelected: SelectionCallback?,
}

export type Deps = {
	iconFactory: () -> any, -- () -> TopbarPlus icon
	applyStyling: (icon: any) -> (), -- caller-controlled styling/layout (parent)
	applyMenuChildStyling: ((icon: any) -> ())?, -- styling for setMenu children
	openPlayerLabel: string?,
	loadTrackLabel: string?,
	logger: any?, -- optional ILogger
}

export type MusicTopbarIcon = typeof(setmetatable(
	{} :: {
		_iconFactory: () -> any,
		_applyStyling: (icon: any) -> (),
		_applyMenuChildStyling: ((icon: any) -> ())?,
		_log: any?,
		_instance: any?,
		_openPlayerIcon: any?,
		_loadTrackIcon: any?,
		_widget: GuiObject?,
		_widgetParent: Instance?,
		_shown: boolean,
		_selectedCallbacks: { SelectionCallback },
		_deselectedCallbacks: { SelectionCallback },
		_openPlayerCallbacks: { SelectionCallback },
		_loadTrackCallbacks: { SelectionCallback },
		_destroyed: boolean,
	},
	MusicTopbarIcon
))

local function safePcall(fn: () -> ()): ()
	local ok, err = pcall(fn)
	if not ok then
		warn("[MusicTopbarIcon] " .. tostring(err))
	end
end

local function tryGuiObject(candidate: any): GuiObject?
	if typeof(candidate) == "Instance" and (candidate :: Instance):IsA("GuiObject") then
		return candidate :: GuiObject
	end
	return nil
end

-- Attempt to resolve the widget GuiObject from a TopbarPlus icon.
local function resolveWidget(icon: any): GuiObject?
	local directNames = { "widget", "_widget", "widgetInstance", "_widgetInstance", "buttonInstance", "_buttonInstance" }
	for _, name in ipairs(directNames) do
		local ok, val = pcall(function()
			return (icon :: any)[name]
		end)
		if ok then
			local w = tryGuiObject(val)
			if w then
				return w
			end
		end
	end

	local methodNames = { "getInstance", "getWidget", "getButton", "getIconInstance" }
	for _, methodName in ipairs(methodNames) do
		local method = (icon :: any)[methodName]
		if type(method) == "function" then
			local ok, result = pcall(function()
				return method(icon, "Widget")
			end)
			if ok then
				local w = tryGuiObject(result)
				if w then
					return w
				end
			end
			ok, result = pcall(function()
				return method(icon)
			end)
			if ok then
				local w = tryGuiObject(result)
				if w then
					return w
				end
			end
		end
	end

	return nil
end

-- Prefer TopbarPlus alignmentHolder; never treat nil as a valid restore parent.
local function resolveRestoreParent(icon: any, widget: GuiObject?): Instance?
	local okHolder, holder = pcall(function()
		return (icon :: any).alignmentHolder
	end)
	if okHolder and typeof(holder) == "Instance" then
		return holder
	end
	if widget and widget.Parent then
		return widget.Parent
	end
	return nil
end

local function rememberParent(self: MusicTopbarIcon, parent: Instance?)
	if parent ~= nil then
		self._widgetParent = parent
	end
end

local function fireCallbacks(list: { SelectionCallback })
	local callbacks = table.clone(list)
	for _, cb in ipairs(callbacks) do
		task.spawn(cb)
	end
end

local function bindChildSelected(child: any, fire: () -> ())
	if child == nil then
		return
	end
	if child.selected and type(child.selected.Connect) == "function" then
		child.selected:Connect(function()
			fire()
		end)
		return
	end
	if type(child.bindEvent) == "function" then
		safePcall(function()
			child:bindEvent("selected", function()
				fire()
			end)
		end)
	end
end

local function createMenuChild(
	self: MusicTopbarIcon,
	label: string,
	callbacks: { SelectionCallback }
): any?
	local ok, child = pcall(self._iconFactory)
	if not ok or child == nil then
		if self._log then
			self._log:warn("MusicTopbarIcon: menu child iconFactory failed", { error = tostring(child), label = label })
		else
			warn("[MusicTopbarIcon] menu child iconFactory failed: " .. tostring(child))
		end
		return nil
	end

	safePcall(function()
		if type(child.setLabel) == "function" then
			child:setLabel(label)
		end
		if type(child.oneClick) == "function" then
			child:oneClick(true)
		end
		if type(child.modifyTheme) == "function" then
			child:modifyTheme({
				{ "IconImage", "Visible", false },
				{ "PaddingLeft", "Size", UDim2.fromScale(0, 1) },
			})
		end
		if self._applyMenuChildStyling then
			self._applyMenuChildStyling(child)
		end
	end)

	bindChildSelected(child, function()
		if not self._shown then
			return
		end
		fireCallbacks(callbacks)
	end)

	return child
end

local function setupMenu(self: MusicTopbarIcon, openPlayerLabel: string, loadTrackLabel: string)
	local parent = self._instance
	if parent == nil or type(parent.setMenu) ~= "function" then
		return
	end

	local openPlayer = createMenuChild(self, openPlayerLabel, self._openPlayerCallbacks)
	local loadTrack = createMenuChild(self, loadTrackLabel, self._loadTrackCallbacks)
	self._openPlayerIcon = openPlayer
	self._loadTrackIcon = loadTrack

	local items = {}
	if openPlayer then
		table.insert(items, openPlayer)
	end
	if loadTrack then
		table.insert(items, loadTrack)
	end
	if #items == 0 then
		return
	end

	safePcall(function()
		parent:setMenu(items)
	end)
end

function MusicTopbarIcon.new(deps: Deps): MusicTopbarIcon
	assert(type(deps.iconFactory) == "function", "MusicTopbarIcon.new: iconFactory must be a function")
	assert(type(deps.applyStyling) == "function", "MusicTopbarIcon.new: applyStyling must be a function")

	local self = setmetatable({
		_iconFactory = deps.iconFactory,
		_applyStyling = deps.applyStyling,
		_applyMenuChildStyling = deps.applyMenuChildStyling,
		_log = deps.logger,
		_instance = nil,
		_openPlayerIcon = nil,
		_loadTrackIcon = nil,
		_widget = nil :: GuiObject?,
		_widgetParent = nil :: Instance?,
		_shown = false,
		_selectedCallbacks = {} :: { SelectionCallback },
		_deselectedCallbacks = {} :: { SelectionCallback },
		_openPlayerCallbacks = {} :: { SelectionCallback },
		_loadTrackCallbacks = {} :: { SelectionCallback },
		_destroyed = false,
	}, MusicTopbarIcon)

	local ok, instance = pcall(deps.iconFactory)
	if not ok or instance == nil then
		if deps.logger then
			deps.logger:warn("MusicTopbarIcon: iconFactory failed", { error = tostring(instance) })
		else
			warn("[MusicTopbarIcon] iconFactory failed: " .. tostring(instance))
		end
		return (self :: any) :: MusicTopbarIcon
	end

	self._instance = instance

	safePcall(function()
		deps.applyStyling(instance)
	end)

	setupMenu(
		self,
		tostring(deps.openPlayerLabel or "Music Player"),
		tostring(deps.loadTrackLabel or "Load Track")
	)

	if instance.selected and type(instance.selected.Connect) == "function" then
		instance.selected:Connect(function()
			if not self._shown then
				safePcall(function()
					instance:deselect()
				end)
				return
			end
			-- Parent select only toggles the horizontal menu — do not treat as open panel.
			fireCallbacks(self._selectedCallbacks)
		end)
	end

	if instance.deselected and type(instance.deselected.Connect) == "function" then
		instance.deselected:Connect(function()
			if not self._shown then
				return
			end
			fireCallbacks(self._deselectedCallbacks)
		end)
	end

	local function cacheWidget()
		local w = self._widget or resolveWidget(instance)
		if not w then
			return
		end
		self._widget = w
		rememberParent(self, resolveRestoreParent(instance, w))

		if not self._shown then
			w.Visible = false
			w.Active = false
			w.Parent = nil
		end
	end

	cacheWidget()
	task.defer(cacheWidget)
	task.delay(0.1, cacheWidget)
	task.delay(0.5, cacheWidget)
	task.delay(1, cacheWidget)

	-- Start hidden; MusicPlayerController shows it after engine/panel boot
	-- (global mode) or on zone enter (zone mode).
	self:hide()

	return (self :: any) :: MusicTopbarIcon
end

function MusicTopbarIcon:isShown(): boolean
	return self._shown
end

function MusicTopbarIcon:getInstance(): any
	return self._instance
end

local function assertVisible(self: MusicTopbarIcon)
	local instance = self._instance
	if instance == nil then
		return
	end

	safePcall(function()
		(instance :: any):setEnabled(true)
	end)

	-- Re-align via caller styling so TopbarPlus reparents to alignmentHolder
	-- even when our cached parent was lost (Parent was already nil when cached).
	safePcall(function()
		self._applyStyling(instance)
	end)

	-- Re-assert setMenu so hide/show reparent races do not drop children.
	if type(instance.setMenu) == "function" then
		local items = {}
		if self._openPlayerIcon then
			table.insert(items, self._openPlayerIcon)
		end
		if self._loadTrackIcon then
			table.insert(items, self._loadTrackIcon)
		end
		if #items > 0 then
			safePcall(function()
				instance:setMenu(items)
			end)
		end
	end

	local widget = self._widget or resolveWidget(instance)
	if widget then
		self._widget = widget
		rememberParent(self, resolveRestoreParent(instance, widget))
		local parent = self._widgetParent
		if parent then
			widget.Parent = parent
		end
		widget.Visible = true
		widget.Active = true
	end
end

-- Make the icon visible. Idempotent: re-asserts parenting even if already shown.
function MusicTopbarIcon:show()
	if self._destroyed or self._instance == nil then
		return
	end

	self._shown = true
	assertVisible(self)

	-- TopbarPlus may re-layout after setEnabled; win the race + fix first-show
	-- icon/label alignment by re-asserting after a defer and short delay.
	task.defer(function()
		if self._shown and not self._destroyed then
			assertVisible(self)
		end
	end)
	task.delay(0.15, function()
		if self._shown and not self._destroyed then
			assertVisible(self)
		end
	end)
end

local function fireDeselectedCallbacks(self: MusicTopbarIcon)
	fireCallbacks(self._deselectedCallbacks)
end

function MusicTopbarIcon:hide()
	if self._instance == nil then
		return
	end

	local instance = self._instance
	local wasShown = self._shown

	if wasShown then
		fireDeselectedCallbacks(self)
	end

	self._shown = false

	safePcall(function()
		(instance :: any):deselect()
	end)

	safePcall(function()
		(instance :: any):setEnabled(false)
	end)

	local widget = self._widget or resolveWidget(instance)
	if widget then
		self._widget = widget
		-- Capture restore parent BEFORE unparenting; never overwrite with nil.
		rememberParent(self, resolveRestoreParent(instance, widget))
		widget.Visible = false
		widget.Active = false
		widget.Parent = nil
	end
end

function MusicTopbarIcon:deselect()
	if not self._shown or self._instance == nil then
		return
	end
	safePcall(function()
		(self._instance :: any):deselect()
	end)
end

local function appendCallback(list: { SelectionCallback }, cb: SelectionCallback): () -> ()
	table.insert(list, cb)
	return function()
		for index, existing in ipairs(list) do
			if existing == cb then
				table.remove(list, index)
				break
			end
		end
	end
end

function MusicTopbarIcon:onSelected(callback: SelectionCallback): () -> ()
	return appendCallback(self._selectedCallbacks, callback)
end

function MusicTopbarIcon:onDeselected(callback: SelectionCallback): () -> ()
	return appendCallback(self._deselectedCallbacks, callback)
end

function MusicTopbarIcon:onOpenPlayer(callback: SelectionCallback): () -> ()
	return appendCallback(self._openPlayerCallbacks, callback)
end

function MusicTopbarIcon:onLoadTrack(callback: SelectionCallback): () -> ()
	return appendCallback(self._loadTrackCallbacks, callback)
end

function MusicTopbarIcon:destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self:hide()
	table.clear(self._selectedCallbacks)
	table.clear(self._deselectedCallbacks)
	table.clear(self._openPlayerCallbacks)
	table.clear(self._loadTrackCallbacks)

	for _, child in ipairs({ self._openPlayerIcon, self._loadTrackIcon }) do
		if child then
			for _, methodName in ipairs({ "destroy", "Destroy" }) do
				local method = (child :: any)[methodName]
				if type(method) == "function" then
					pcall(function()
						method(child)
					end)
					break
				end
			end
		end
	end
	self._openPlayerIcon = nil
	self._loadTrackIcon = nil

	if self._instance then
		local instance = self._instance
		self._instance = nil
		for _, methodName in ipairs({ "destroy", "Destroy" }) do
			local method = (instance :: any)[methodName]
			if type(method) == "function" then
				pcall(function()
					method(instance)
				end)
				break
			end
		end
	end
end

return MusicTopbarIcon
