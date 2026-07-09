--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)

local CarryDomain = {}

export type CarryStyleEntry = {
	name: string,
	displayName: string,
}

local carryConfig = Config.Carry

function CarryDomain.isValidStyle(styleName: string): boolean
	return carryConfig.STYLES[styleName] ~= nil
end

function CarryDomain.getStyleDisplayName(styleName: string): string
	local style = carryConfig.STYLES[styleName]
	if style == nil then
		return styleName
	end
	return style.displayName
end

function CarryDomain.getStyles(): { CarryStyleEntry }
	local styles = {}
	for _, styleName in ipairs(carryConfig.STYLE_ORDER) do
		local style = carryConfig.STYLES[styleName]
		if style ~= nil then
			table.insert(styles, {
				name = styleName,
				displayName = style.displayName,
			})
		end
	end
	return styles
end

function CarryDomain.getAnimationId(styleName: string, role: "carrier" | "carried", _rigType: string): number
	local style = carryConfig.STYLES[styleName]
	if style == nil or type(style.animations) ~= "table" then
		return 0
	end
	local id = if role == "carrier" then style.animations.carrier else style.animations.carried
	if type(id) == "number" and id > 0 then
		return id
	end
	return 0
end

function CarryDomain.isInRange(posA: Vector3, posB: Vector3, maxDistance: number): boolean
	return (posA - posB).Magnitude <= maxDistance
end

function CarryDomain.getAttachPartName(): string
	local physics = carryConfig.PHYSICS
	if physics ~= nil and type(physics.ATTACH_PART) == "string" then
		return physics.ATTACH_PART
	end
	return "UpperTorso"
end

function CarryDomain.shouldSetNetworkOwner(): boolean
	local physics = carryConfig.PHYSICS
	return physics == nil or physics.SET_NETWORK_OWNER ~= false
end

function CarryDomain.findCharacterAttachPart(character: Model, partName: string): BasePart?
	local part = character:FindFirstChild(partName)
	if part ~= nil and part:IsA("BasePart") then
		return part
	end
	if partName ~= "HumanoidRootPart" then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root ~= nil and root:IsA("BasePart") then
			return root
		end
	end
	return nil
end

function CarryDomain.getCarryOffsetParts(styleName: string): ({ number }, { number }, boolean)
	local style = carryConfig.STYLES[styleName]
	if style == nil then
		return { 0, 0, 0 }, { 0, 0, 0 }, false
	end

	return table.clone(style.offset), table.clone(style.rotation), style.inverse == true
end

function CarryDomain.composeCarryOffset(offset: { number }, rotation: { number }, inverse: boolean?): CFrame
	local cframe = CFrame.new(offset[1], offset[2], offset[3])
		* CFrame.fromEulerAnglesXYZ(math.rad(rotation[1]), math.rad(rotation[2]), math.rad(rotation[3]))
	if inverse == true then
		return cframe:Inverse()
	end
	return cframe
end

function CarryDomain.buildFiremanC0(): CFrame
	local offset = Vector3.new(0.5, 1, -1)
	local rotation = CFrame.Angles(math.rad(-90), 0, math.rad(180))
	local baseCFrame = CFrame.new(0.9, 0.6, 1.04)
	return baseCFrame * CFrame.new(offset) * rotation
end

function CarryDomain.getCarryWeldC0(styleName: string, offset: { number }, rotation: { number }, inverse: boolean): CFrame
	local style = carryConfig.STYLES[styleName]
	if style ~= nil and style.c0Kind == "fireman" then
		return CarryDomain.buildFiremanC0()
	end
	return CarryDomain.composeCarryOffset(offset, rotation, inverse)
end

function CarryDomain.getCarryOffset(styleName: string): CFrame
	local offset, rotation, inverse = CarryDomain.getCarryOffsetParts(styleName)
	return CarryDomain.getCarryWeldC0(styleName, offset, rotation, inverse)
end

function CarryDomain.formatCarryConfigSnippet(
	styleName: string,
	offset: { number },
	rotation: { number },
	inverse: boolean?
): string
	return string.format(
		"%s = {\n\toffset = { %.3f, %.3f, %.3f },\n\trotation = { %.3f, %.3f, %.3f },\n\tinverse = %s,\n}",
		styleName,
		offset[1],
		offset[2],
		offset[3],
		rotation[1],
		rotation[2],
		rotation[3],
		tostring(inverse == true)
	)
end

return CarryDomain
