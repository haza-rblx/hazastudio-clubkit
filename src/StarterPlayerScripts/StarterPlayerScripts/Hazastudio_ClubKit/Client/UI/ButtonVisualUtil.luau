--!strict
-- Capture/apply TextButton visuals from Studio Idle/Selected template pairs.

export type ButtonStyleSnapshot = {
	backgroundColor3: Color3,
	backgroundTransparency: number,
	borderSizePixel: number,
	textColor3: Color3?,
	textTransparency: number?,
	items: { { path: string, className: string, props: { [string]: any } } },
}

local function nameLooksActive(name: string): boolean
	local lower = string.lower(name)
	return string.find(lower, "active", 1, true) ~= nil or string.find(lower, "selected", 1, true) ~= nil
end

local function nameLooksIdle(name: string): boolean
	local lower = string.lower(name)
	return string.find(lower, "idle", 1, true) ~= nil or string.find(lower, "normal", 1, true) ~= nil
end

local function relativePath(root: Instance, descendant: Instance): string
	local parts: { string } = {}
	local current: Instance? = descendant
	while current and current ~= root do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	return table.concat(parts, "/")
end

local function findByRelativePath(root: Instance, path: string): Instance?
	if path == "" then
		return root
	end
	local current: Instance = root
	for token in string.gmatch(path, "[^/]+") do
		local nextInst = current:FindFirstChild(token)
		if not nextInst then
			return nil
		end
		current = nextInst
	end
	return current
end

local ButtonVisualUtil = {}

function ButtonVisualUtil.capture(button: TextButton): ButtonStyleSnapshot
	local items: { { path: string, className: string, props: { [string]: any } } } = {}
	for _, descendant in ipairs(button:GetDescendants()) do
		local path = relativePath(button, descendant)
		if descendant:IsA("UIGradient") then
			table.insert(items, {
				path = path,
				className = "UIGradient",
				props = {
					Enabled = descendant.Enabled,
					Color = descendant.Color,
					Transparency = descendant.Transparency,
					Rotation = descendant.Rotation,
				},
			})
		elseif descendant:IsA("UIStroke") then
			table.insert(items, {
				path = path,
				className = "UIStroke",
				props = {
					Color = descendant.Color,
					Transparency = descendant.Transparency,
					Thickness = descendant.Thickness,
					Enabled = descendant.Enabled,
				},
			})
		elseif descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			table.insert(items, {
				path = path,
				className = descendant.ClassName,
				props = {
					TextColor3 = descendant.TextColor3,
					TextTransparency = descendant.TextTransparency,
					Visible = descendant.Visible,
				},
			})
		elseif descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
			table.insert(items, {
				path = path,
				className = descendant.ClassName,
				props = {
					ImageColor3 = descendant.ImageColor3,
					ImageTransparency = descendant.ImageTransparency,
					BackgroundColor3 = (descendant :: GuiObject).BackgroundColor3,
					BackgroundTransparency = (descendant :: GuiObject).BackgroundTransparency,
					Visible = descendant.Visible,
				},
			})
		elseif descendant:IsA("Frame") or descendant:IsA("CanvasGroup") then
			local gui = descendant :: GuiObject
			table.insert(items, {
				path = path,
				className = descendant.ClassName,
				props = {
					BackgroundColor3 = gui.BackgroundColor3,
					BackgroundTransparency = gui.BackgroundTransparency,
					Visible = gui.Visible,
				},
			})
		elseif descendant:IsA("GuiObject") and (nameLooksActive(descendant.Name) or nameLooksIdle(descendant.Name)) then
			table.insert(items, {
				path = path,
				className = descendant.ClassName,
				props = { Visible = (descendant :: GuiObject).Visible },
			})
		end
	end

	return {
		backgroundColor3 = button.BackgroundColor3,
		backgroundTransparency = button.BackgroundTransparency,
		borderSizePixel = button.BorderSizePixel,
		textColor3 = button.TextColor3,
		textTransparency = button.TextTransparency,
		items = items,
	}
end

function ButtonVisualUtil.apply(button: TextButton, snapshot: ButtonStyleSnapshot)
	button.BackgroundColor3 = snapshot.backgroundColor3
	button.BackgroundTransparency = snapshot.backgroundTransparency
	button.BorderSizePixel = snapshot.borderSizePixel
	if snapshot.textColor3 then
		button.TextColor3 = snapshot.textColor3
	end
	if snapshot.textTransparency ~= nil then
		button.TextTransparency = snapshot.textTransparency
	end

	for _, item in ipairs(snapshot.items) do
		local target = findByRelativePath(button, item.path)
		if target and target.ClassName == item.className then
			for prop, value in pairs(item.props) do
				(target :: any)[prop] = value
			end
		end
	end
end

function ButtonVisualUtil.setInternalIdleSelected(button: TextButton, selected: boolean)
	button.Visible = true
	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant:IsA("UIGradient") then
			local gradientName = descendant.Name
			if nameLooksActive(gradientName) or nameLooksIdle(gradientName) then
				descendant.Enabled = if selected then nameLooksActive(gradientName) else nameLooksIdle(gradientName)
			end
		elseif descendant:IsA("GuiObject") then
			if descendant:IsA("TextButton") or descendant:IsA("ImageButton") then
				continue
			end
			local childName = descendant.Name
			if nameLooksActive(childName) then
				descendant.Visible = selected
			elseif nameLooksIdle(childName) then
				descendant.Visible = not selected
			end
		end
	end
end

return ButtonVisualUtil
