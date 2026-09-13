--!strict
-- Fades a whole GUI subtree from each element's own designed transparency. For cards built
-- from a plain Frame (no GroupTransparency), e.g. notification center V2 with UIShadow.
-- capture() once the card is filled, then set()/tween() an alpha: 0 = as designed, 1 = gone.

local TweenService = game:GetService("TweenService")

type Entry = {
	instance: Instance,
	property: string,
	base: number,
}

export type Snapshot = {
	entries: { Entry },
	driver: NumberValue,
}

local GuiFade = {}

local function add(entries: { Entry }, instance: Instance, property: string, base: number)
	table.insert(entries, { instance = instance, property = property, base = base })
end

local function collect(entries: { Entry }, instance: Instance)
	if instance:IsA("GuiObject") then
		add(entries, instance, "BackgroundTransparency", instance.BackgroundTransparency)
	end
	if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		local text = instance :: any
		add(entries, instance, "TextTransparency", text.TextTransparency)
		add(entries, instance, "TextStrokeTransparency", text.TextStrokeTransparency)
	elseif instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
		add(entries, instance, "ImageTransparency", (instance :: any).ImageTransparency)
	elseif instance:IsA("UIStroke") then
		add(entries, instance, "Transparency", instance.Transparency)
	elseif instance:IsA("UIShadow") then
		add(entries, instance, "Transparency", (instance :: any).Transparency)
	end
end

function GuiFade.capture(root: Instance): Snapshot
	local entries: { Entry } = {}
	collect(entries, root)
	for _, descendant in ipairs(root:GetDescendants()) do
		collect(entries, descendant)
	end
	local driver = Instance.new("NumberValue")
	local snapshot: Snapshot = { entries = entries, driver = driver }
	driver.Changed:Connect(function(alpha: number)
		GuiFade.apply(snapshot, alpha)
	end)
	return snapshot
end

function GuiFade.apply(snapshot: Snapshot, alpha: number)
	local a = math.clamp(alpha, 0, 1)
	for _, entry in ipairs(snapshot.entries) do
		if entry.instance.Parent then
			(entry.instance :: any)[entry.property] = entry.base + (1 - entry.base) * a
		end
	end
end

function GuiFade.set(snapshot: Snapshot, alpha: number)
	snapshot.driver.Value = alpha
	GuiFade.apply(snapshot, alpha)
end

function GuiFade.tween(snapshot: Snapshot, info: TweenInfo, alpha: number): Tween
	local created = TweenService:Create(snapshot.driver, info, { Value = alpha })
	created:Play()
	return created
end

function GuiFade.destroy(snapshot: Snapshot)
	snapshot.driver:Destroy()
end

return GuiFade
