local RunService = game:GetService("RunService")


local AnimationModes = {}
AnimationModes.__index = AnimationModes
local activeAnimations = {}

function AnimationModes.parseHexColor(hex: string): Color3
    if typeof(hex) ~= "string" then 
        return Color3.new(1, 1, 1) 
    end
    hex = hex:gsub("#", "")
    if #hex == 6 then
        local r = tonumber("0x" .. hex:sub(1, 2)) / 255
        local g = tonumber("0x" .. hex:sub(3, 4)) / 255
        local b = tonumber("0x" .. hex:sub(5, 6)) / 255
        return Color3.new(r, g, b)
    end
    return Color3.new(1, 1, 1)
end

function AnimationModes.color3ToHex(color: Color3): string
    if typeof(color) ~= "Color3" then
        return "FFFFFF"
    end
    local r = math.floor(color.R * 255)
    local g = math.floor(color.G * 255)
    local b = math.floor(color.B * 255)
    return string.format("%02X%02X%02X", r, g, b)
end

local ANIMATION_CONFIGS = {
    ["gradient_anim"] = {
        speed = 1.5,
        rotation = 0,
        description = "Simple offset oscillation"
    },
    ["gradient_anim2"] = {
        speed = 0.5,
        rotation = 30,
        description = "Color phase swap with offset"
    },
    ["gradient_anim3"] = {
        speed = 1,
        rotation = 30,
        description = "Color phase swap with stroke gradient"
    }
}

local PRESET_MODES = {
    "StaticColor", "Gradient", "Pulse",
    "Bubblegum", "ChromeStroke", "Ghost", "GhostStroke", "Gold", "GoldStroke",
    "Lava", "LavaStroke", "OceanicStroke", "Rainbow", "RainbowStroke",
    "Silver", "SilverStroke", "Zebra", "RainbowOutline", "DeathStroke",
    "IceStroke", "FireStroke", "Matrix", "GreenOutline", "Shine",
    "WaveStroke", "ShineOutline", "ElectricStroke", "NeonStroke",
    "SunsetStroke", "GalaxyStroke", "PulseGradient", "PulseStroke", "PulseStrokeInvert"
}

function AnimationModes.GetConfig(mode: string): table
    return ANIMATION_CONFIGS[mode]
end

function AnimationModes.IsPreset(mode: string): boolean
    for _, preset in ipairs(PRESET_MODES) do
        if preset == mode then
            return true
        end
    end
    return false
end

function AnimationModes.GetPresetModes(): {string}
    return PRESET_MODES
end

function AnimationModes.new(uiInstance: GuiObject, mode: string, color1: Color3 | string, color2: Color3 | string, useRenderStepped: boolean?): table
    local self = setmetatable({}, AnimationModes)
    
    self.UIInstance = uiInstance
    self.Mode = mode
    self.IsPaused = false
    self.Connection = nil
    self.UseRenderStepped = useRenderStepped ~= false 
    
    -- Parse colors
    if typeof(color1) == "string" then
        self.Color1 = AnimationModes.parseHexColor(color1)
    else
        self.Color1 = color1 or Color3.fromRGB(255, 0, 0)
    end
    
    if typeof(color2) == "string" then
        self.Color2 = AnimationModes.parseHexColor(color2)
    else
        self.Color2 = color2 or Color3.fromRGB(0, 0, 255)
    end
    
    self.Offset = 0
    self.Phase = 0
    self.Timer = 0
    
    local textLabel = uiInstance:FindFirstChildWhichIsA("TextLabel")
    local targetInstance = uiInstance
    
    if textLabel then
        targetInstance = textLabel
    end
    
    self.Gradient = targetInstance:FindFirstChild("AnimationGradient")
    if not self.Gradient then
        self.Gradient = targetInstance:FindFirstChildWhichIsA("UIGradient")
    end
    if not self.Gradient then
        self.Gradient = Instance.new("UIGradient")
        self.Gradient.Name = "AnimationGradient"
        self.Gradient.Parent = targetInstance
    else
        self.Gradient.Name = "AnimationGradient"
    end
    self.TargetInstance = targetInstance
    
    local textLabel = uiInstance:FindFirstChildWhichIsA("TextLabel")
    if textLabel then
        self.Stroke = textLabel:FindFirstChildWhichIsA("UIStroke")
    end
    if not self.Stroke then
        self.Stroke = uiInstance:FindFirstChildWhichIsA("UIStroke")
    end
    self.StrokeGradient = nil
    
    if mode == "gradient_anim2" or mode == "gradient_anim3" then
        if not self.Stroke then
            self.Stroke = Instance.new("UIStroke")
            self.Stroke.Thickness = 1.5
            self.Stroke.Parent = uiInstance
        else
            self.Stroke.Enabled = true
            self.Stroke.Thickness = 1.5
        end
        
        self.StrokeGradient = self.Stroke:FindFirstChild("StrokeGradient")
        if not self.StrokeGradient then
            self.StrokeGradient = Instance.new("UIGradient")
            self.StrokeGradient.Name = "StrokeGradient"
            self.StrokeGradient.Parent = self.Stroke
        end
    end
    
    self:InitializeGradient()
    self:Start()
    
    table.insert(activeAnimations, self)
    
    return self
end

function AnimationModes:InitializeGradient()
    local config = ANIMATION_CONFIGS[self.Mode]
    if not config then return end
    
    self.Gradient.Rotation = config.rotation
    
    if self.Mode == "gradient_anim" then
        self.Gradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, self.Color1),
            ColorSequenceKeypoint.new(1, self.Color2)
        })
        
    elseif self.Mode == "gradient_anim2" or self.Mode == "gradient_anim3" then
        self.Gradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, self.Color1),
            ColorSequenceKeypoint.new(0.5, self.Color2),
            ColorSequenceKeypoint.new(1, self.Color1)
        })
        
        if self.StrokeGradient then
            self.StrokeGradient.Rotation = config.rotation
            local existingColor = self.StrokeGradient.Color
            local keypoints = existingColor and existingColor.Keypoints or {}
            if #keypoints < 3 then
                self.StrokeGradient.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, self.Color2),
                    ColorSequenceKeypoint.new(0.5, self.Color1),
                    ColorSequenceKeypoint.new(1, self.Color2)
                })
            end
        end
    end
end

function AnimationModes:Start()
    if self.Connection then
        self.Connection:Disconnect()
    end
    
    local config = ANIMATION_CONFIGS[self.Mode]
    if not config then return end
    
    local event = self.UseRenderStepped and RunService.RenderStepped or RunService.Heartbeat
    
    self.Connection = event:Connect(function(dt)
        if self.IsPaused then return end
        
        if not self.UIInstance or self.UIInstance.Parent == nil then
            self:Destroy()
            return
        end
        
        self.Timer = self.Timer + (config.speed * dt)
        
        if self.Mode == "gradient_anim" then
            local oscillation = math.sin(self.Timer) * 0.5
            self.Gradient.Offset = Vector2.new(oscillation, 0)
            
        elseif self.Mode == "gradient_anim2" then
            local offsetMove = math.sin(self.Timer * math.pi) * 0.3
            self.Gradient.Offset = Vector2.new(offsetMove, 0)
            
            if self.StrokeGradient then
                self.StrokeGradient.Offset = Vector2.new(offsetMove, 0)
            end
            
            if self.Timer >= 2 then
                self.Timer = 0
                self.Phase = 1 - self.Phase
                
                if self.Phase == 0 then
                    self.Gradient.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, self.Color1),
                        ColorSequenceKeypoint.new(0.5, self.Color2),
                        ColorSequenceKeypoint.new(1, self.Color1)
                    })
                    if self.StrokeGradient then
                        self.StrokeGradient.Color = ColorSequence.new({
                            ColorSequenceKeypoint.new(0, self.Color2),
                            ColorSequenceKeypoint.new(0.5, self.Color1),
                            ColorSequenceKeypoint.new(1, self.Color2)
                        })
                    end
                else
                    self.Gradient.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, self.Color2),
                        ColorSequenceKeypoint.new(0.5, self.Color1),
                        ColorSequenceKeypoint.new(1, self.Color2)
                    })
                    if self.StrokeGradient then
                        self.StrokeGradient.Color = ColorSequence.new({
                            ColorSequenceKeypoint.new(0, self.Color1),
                            ColorSequenceKeypoint.new(0.5, self.Color2),
                            ColorSequenceKeypoint.new(1, self.Color1)
                        })
                    end
                end
            end
            
        elseif self.Mode == "gradient_anim3" then
            local offsetMove = math.sin(self.Timer * math.pi) * 0.3
            self.Gradient.Offset = Vector2.new(offsetMove, 0)
            
            if self.StrokeGradient then
                self.StrokeGradient.Offset = Vector2.new(offsetMove, 0)
            end
            
            if self.Timer >= 2 then
                self.Timer = 0
                self.Phase = 1 - self.Phase
                
                if self.Phase == 0 then
                    self.Gradient.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, self.Color1),
                        ColorSequenceKeypoint.new(0.5, self.Color2),
                        ColorSequenceKeypoint.new(1, self.Color1)
                    })
                    if self.StrokeGradient then
                        self.StrokeGradient.Color = ColorSequence.new({
                            ColorSequenceKeypoint.new(0, self.Color2),
                            ColorSequenceKeypoint.new(0.5, self.Color1),
                            ColorSequenceKeypoint.new(1, self.Color2)
                        })
                    end
                else
                    self.Gradient.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, self.Color2),
                        ColorSequenceKeypoint.new(0.5, self.Color1),
                        ColorSequenceKeypoint.new(1, self.Color2)
                    })
                    if self.StrokeGradient then
                        self.StrokeGradient.Color = ColorSequence.new({
                            ColorSequenceKeypoint.new(0, self.Color1),
                            ColorSequenceKeypoint.new(0.5, self.Color2),
                            ColorSequenceKeypoint.new(1, self.Color1)
                        })
                    end
                end
            end
        end
    end)
end

function AnimationModes:Pause()
    self.IsPaused = true
end

function AnimationModes:Resume()
    self.IsPaused = false
end

function AnimationModes:SetColors(color1: Color3 | string, color2: Color3 | string)
    if typeof(color1) == "string" then
        self.Color1 = AnimationModes.parseHexColor(color1)
    else
        self.Color1 = color1
    end
    
    if typeof(color2) == "string" then
        self.Color2 = AnimationModes.parseHexColor(color2)
    else
        self.Color2 = color2
    end
    
    self:InitializeGradient()
end

function AnimationModes:Destroy()
    if self.Connection then
        self.Connection:Disconnect()
        self.Connection = nil
    end
    
    for i, anim in ipairs(activeAnimations) do
        if anim == self then
            table.remove(activeAnimations, i)
            break
        end
    end
end

function AnimationModes.GetAvailableModes(): {string}
    return {"gradient_anim", "gradient_anim2", "gradient_anim3"}
end

function AnimationModes.GetModeDescription(mode: string): string
    local config = ANIMATION_CONFIGS[mode]
    return config and config.description or "Unknown mode"
end

function AnimationModes.GetModeDisplayName(mode: string): string
    local displayNames = {
        ["static"] = "STATIC",
        ["gradient"] = "GRADIENT",
        ["Pulse"] = "PULSE",
        ["PulseStroke"] = "PULSE STROKE",
        ["PulseStrokeInvert"] = "PULSE INVERT",
        ["gradient_anim"] = "PULSE",
        ["gradient_anim2"] = "PULSE STROKE",
        ["gradient_anim3"] = "PULSE INVERT",
        ["StaticColor"] = "STATIC",
        ["Gradient"] = "GRADIENT",
        ["PulseGradient"] = "PULSE GRADIENT"
    }
    if displayNames[mode] then
        return displayNames[mode]
    end
    return mode:upper()
end

function AnimationModes.GetModesInOrder(): {string}
    return {"static", "gradient", "gradient_anim", "gradient_anim2", "gradient_anim3"}
end

function AnimationModes.GetAllModesInOrder(): {string}
    local modes = {"static", "gradient", "gradient_anim", "gradient_anim2", "gradient_anim3"}
    for _, preset in ipairs(PRESET_MODES) do
        table.insert(modes, preset)
    end
    return modes
end

return AnimationModes