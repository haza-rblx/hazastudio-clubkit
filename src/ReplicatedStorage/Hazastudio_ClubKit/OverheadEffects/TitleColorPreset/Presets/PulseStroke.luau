local TextEffects = require(script.Parent.Parent);
local RunService = game:GetService("RunService")

return function(uiInstance: GuiObject, speed: number, size: number, customColor: ColorSequence | Color3)
    local color1: Color3
    local color2: Color3
    
    if typeof(customColor) == "ColorSequence" then
        local keypoints = customColor.Keypoints
        color1 = keypoints[1].Value
        color2 = keypoints[#keypoints].Value
    elseif typeof(customColor) == "Color3" then
        color1 = customColor
        color2 = customColor
    else
        color1 = Color3.fromRGB(255, 255, 255)
        color2 = Color3.fromRGB(58, 58, 58)
    end
    
    local colorSequence = ColorSequence.new({
        ColorSequenceKeypoint.new(0, color1),
        ColorSequenceKeypoint.new(0.5, color2),
        ColorSequenceKeypoint.new(1, color1)
    })
    
    local mainGradient = TextEffects.Gradient.new(uiInstance, colorSequence, 0)

    mainGradient:SetOffsetSpeed(speed or 1.0, 1)
    mainGradient:SetRotation(30, 1)
    
    return {
        Effects = { mainGradient },
        Color1 = color1,
        Color2 = color2,
        Mode = "PulseStroke"
    }
end