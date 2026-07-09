local TextEffects = require(script.Parent.Parent);

return function(uiInstance: GuiObject, speed: number, size: number?, customColor: ColorSequence | Color3?, customTransparency: NumberSequence | number?, useScaledSize: boolean?)

    local colorToUse = customColor or TextEffects.Templates.Silver.Color
    
    local mainGradient = TextEffects.Gradient.new(uiInstance, colorToUse, 0);
    mainGradient:SetRotation(-75, 1);
    mainGradient:SetOffsetSpeed(speed, 1);
    return {
        Effects = { mainGradient }
    };
end