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
-- Solution: cache the widget GuiObject immediately after creation, then
--   reparent it to nil on hide (guaranteed invisible) and restore on show.

local MusicTopbarIcon = {}
MusicTopbarIcon.__index = MusicTopbarIcon

export type SelectionCallback = () -> ()

export type Deps = {
	iconFactory: () -> any, -- () -> TopbarPlus icon
	applyStyling: (icon: any) -> (), -- caller-controlled styling/layout
	logger: any?, -- optional ILogger
}

export type MusicTopbarIcon = typeof(setmetatable(
	{} :: {
		_iconFactory: () -> any,
		_applyStyling: (icon: any) -> (),
		_log: any?,
		_instance: any?,
		_widget: GuiObject?,
		_widgetParent: Instance?,
		_shown: boolean,
		_selectedCallbacks: { SelectionCallback },
		_deselectedCallbacks: { SelectionCallback },
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

-- Attempt to resolve the widget GuiObject from a TopbarPlus icon.
-- Tries multiple known property/method names across versions.
local function resolveWidget(icon: any): GuiObject?
	local function tryResolve(candidate: any): GuiObject?
		if typeof(candidate) == "Instance" and (candidate :: Instance):IsA("GuiObject") then
			return candidate :: GuiObject
		end
		return nil
	end

	-- Direct property access
	local directNames = { "widget", "_widget", "widgetInstance", "_widgetInstance", "buttonInstance", "_buttonInstance" }
	for _, name in ipairs(directNames) do
		local ok, val = pcall(function()
			return (icon :: any)[name]
		end)
		if ok then
			local w = tryResolve(val)
			if w then
				return w
			end
		end
	end

	-- Method access
	local methodNames = { "getInstance", "getWidget", "getButton", "getIconInstance" }
	for _, methodName in ipairs(methodNames) do
		local method = (icon :: any)[methodName]
		if type(method) == "function" then
			local ok, result = pcall(function()
				return method(icon, "Widget")
			end)
			if ok then
				local w = tryResolve(result)
				if w then
					return w
				end
			end
			ok, result = pcall(function()
				return method(icon)
			end)
			if ok then
				local w = tryResolve(result)
				if w then
					return w
				end
			end
		end
	end

	return nil
end

function MusicTopbarIcon.new(deps: Deps): MusicTopbarIcon
	assert(type(deps.iconFactory) == "function", "MusicTopbarIcon.new: iconFactory must be a function")
	assert(type(deps.applyStyling) == "function", "MusicTopbarIcon.new: applyStyling must be a function")

	local self = setmetatable({
		_iconFactory = deps.iconFactory,
		_applyStyling = deps.applyStyling,
		_log = deps.logger,
		_instance = nil,
		_widget = nil :: GuiObject?,
		_widgetParent = nil :: Instance?,
		_shown = false,
		_selectedCallbacks = {} :: { SelectionCallback },
		_deselectedCallbacks = {} :: { SelectionCallback },
		_destroyed = false,
	}, MusicTopbarIcon)

	-- Create the icon instance once, apply styling, then immediately hide.
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

	-- Apply styling (image, label, alignment, theme).
	safePcall(function()
		deps.applyStyling(instance)
	end)

	-- Wire selection events. These connections live for the lifetime of the icon.
	-- Callbacks check _shown to prevent firing when hidden.
	if instance.selected and type(instance.selected.Connect) == "function" then
		instance.selected:Connect(function()
			if not self._shown then
				-- Icon is hidden but somehow got selected (shouldn't happen with
				-- reparent, but defensive). Force deselect.
				safePcall(function()
					instance:deselect()
				end)
				return
			end
			local callbacks = table.clone(self._selectedCallbacks)
			for _, cb in ipairs(callbacks) do
				task.spawn(cb)
			end
		end)
	end

	if instance.deselected and type(instance.deselected.Connect) == "function" then
		instance.deselected:Connect(function()
			if not self._shown then
				return
			end
			local callbacks = table.clone(self._deselectedCallbacks)
			for _, cb in ipairs(callbacks) do
				task.spawn(cb)
			end
		end)
	end

	-- Resolve and cache widget. Retry with defer/delay for timing.
	local function cacheWidget()
		if self._widget then
			return
		end
		local w = resolveWidget(instance)
		if w then
			self._widget = w
			self._widgetParent = w.Parent

			-- If icon is currently hidden, ensure the newly-cached widget is also
			-- hidden immediately. This handles the case where hide() was called
			-- before the widget was resolved.
			if not self._shown then
				w.Visible = false
				w.Active = false
				w.Parent = nil
			end
		end
	end

	cacheWidget()
	task.defer(cacheWidget)
	task.delay(0.1, cacheWidget)
	task.delay(0.5, cacheWidget)
	task.delay(1, cacheWidget)

	-- Start hidden (icon should only appear when player enters a zone).
	self:hide()

	return (self :: any) :: MusicTopbarIcon
end

-- Returns true if the icon is currently visible.
function MusicTopbarIcon:isShown(): boolean
	return self._shown
end

-- Internal accessor for raw TopbarPlus icon.
function MusicTopbarIcon:getInstance(): any
	return self._instance
end

-- Make the icon visible in the topbar.
function MusicTopbarIcon:show()
	if self._destroyed or self._instance == nil then
		return
	end
	if self._shown then
		return
	end
	self._shown = true

	local instance = self._instance

	-- Call setEnabled(true) FIRST so TopbarPlus internal state knows the icon
	-- should be active. This may trigger internal layout that expects the widget.
	safePcall(function()
		(instance :: any):setEnabled(true)
	end)

	-- If widget wasn't cached yet, try resolving now.
	if not self._widget then
		local w = resolveWidget(instance)
		if w then
			self._widget = w
			if not self._widgetParent then
				-- Widget might have been reparented by TopbarPlus during setEnabled.
				-- Use current parent as the canonical parent.
				self._widgetParent = w.Parent
			end
		end
	end

	-- Restore widget to topbar AFTER setEnabled so TopbarPlus doesn't fight us.
	if self._widget and self._widgetParent then
		self._widget.Parent = self._widgetParent
		self._widget.Visible = true
		self._widget.Active = true
	end

	-- TopbarPlus may re-layout after setEnabled and override our widget state.
	-- Re-apply visibility after a short defer to win the race.
	-- Also re-apply styling to force TopbarPlus to recalculate internal layout
	-- (without this, icon+label alignment is broken until first interaction).
	if self._widget then
		local widget = self._widget
		local widgetParent = self._widgetParent
		task.defer(function()
			if self._shown and widget and widgetParent then
				widget.Parent = widgetParent
				widget.Visible = true
				widget.Active = true
			end
			-- Re-apply styling forces TopbarPlus to recalculate layout (fixes
			-- icon+label misalignment on first show before any interaction).
			if self._shown and self._instance then
				safePcall(function()
					self._applyStyling(self._instance)
				end)
			end
		end)
	end


end

local function fireDeselectedCallbacks(self: MusicTopbarIcon)
	local callbacks = table.clone(self._deselectedCallbacks)
	for _, cb in ipairs(callbacks) do
		task.spawn(cb)
	end
end

-- Hide the icon from the topbar. Does NOT destroy — just reparents widget away.
function MusicTopbarIcon:hide()
	if self._instance == nil then
		return
	end
	if not self._shown and self._widget ~= nil then
		-- Already hidden but ensure widget is gone
		self._widget.Parent = nil
		return
	end

	local instance = self._instance
	local wasShown = self._shown

	-- Notify listeners (e.g. MobilePanelManager.close) while still marked shown.
	-- TopbarPlus deselect alone is not enough: our deselected handler ignores
	-- events once _shown is false, which left mobile GUI focus stuck open.
	if wasShown then
		fireDeselectedCallbacks(self)
	end

	self._shown = false

	-- Deselect after callbacks so TopbarPlus internal state also closes.
	safePcall(function()
		(instance :: any):deselect()
	end)

	-- setEnabled(false) as first layer
	safePcall(function()
		(instance :: any):setEnabled(false)
	end)

	-- If widget wasn't cached yet, try resolving now before hiding.
	if not self._widget then
		local w = resolveWidget(instance)
		if w then
			self._widget = w
			if not self._widgetParent then
				self._widgetParent = w.Parent
			end
		end
	end

	-- Reparent widget to nil — guaranteed invisible regardless of TopbarPlus internals
	if self._widget then
		if not self._widgetParent then
			self._widgetParent = self._widget.Parent
		end
		self._widget.Visible = false
		self._widget.Active = false
		self._widget.Parent = nil
	end


end

-- Force the icon into the deselected (closed) state. No-op if not shown.
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

-- Register a callback fired when the icon is selected (clicked open).
-- Returns an unsubscribe function — caller MUST store it for cleanup.
function MusicTopbarIcon:onSelected(callback: SelectionCallback): () -> ()
	return appendCallback(self._selectedCallbacks, callback)
end

-- Register a callback fired when the icon is deselected (closed).
-- Returns an unsubscribe function — caller MUST store it for cleanup.
function MusicTopbarIcon:onDeselected(callback: SelectionCallback): () -> ()
	return appendCallback(self._deselectedCallbacks, callback)
end

-- Full teardown.
function MusicTopbarIcon:destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self:hide()
	table.clear(self._selectedCallbacks)
	table.clear(self._deselectedCallbacks)

	-- Best-effort destroy of the TopbarPlus icon
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
