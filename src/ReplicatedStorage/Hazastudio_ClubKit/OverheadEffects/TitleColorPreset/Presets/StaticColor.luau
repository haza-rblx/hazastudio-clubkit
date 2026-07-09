local TextEffects = require(script.Parent.Parent);

return function(uiInstance: GuiObject, speed: number, size: number, customColor: ColorSequence | Color3)
    local colorSequence: ColorSequence
    
    if typeof(customColor) == "ColorSequence" then
        colorSequence = customColor
    elseif typeof(customColor) == "Color3" then
        colorSequence = ColorSequence.new(customColor)
    else
        colorSequence = ColorSequence.new(Color3.fromRGB(255, 255, 255))
    end
    
    if uiInstance:IsA("TextLabel") or uiInstance:IsA("TextButton") or uiInstance:IsA("TextBox") then
        uiInstance.TextColor3 = colorSequence.Keypoints[1].Value
    end
    
    return {
        Effects = {}
    }
end