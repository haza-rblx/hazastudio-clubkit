local TextEffects = require(script.Parent.Parent);

return function(uiInstance: GuiObject, speed: number, size: number, customColor: ColorSequence | Color3)
    local colorSequence: ColorSequence
    
    if typeof(customColor) == "ColorSequence" then
        colorSequence = customColor
    elseif typeof(customColor) == "Color3" then
        colorSequence = ColorSequence.new({
            ColorSequenceKeypoint.new(0, customColor),
            ColorSequenceKeypoint.new(1, customColor)
        })
    else
        -- Default gradient
        colorSequence = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 200))
        })
    end
    
    local mainGradient = TextEffects.Gradient.new(uiInstance, colorSequence, 0)
    mainGradient:SetRotation(0, 1)
    
    return {
        Effects = { mainGradient }
    }
end