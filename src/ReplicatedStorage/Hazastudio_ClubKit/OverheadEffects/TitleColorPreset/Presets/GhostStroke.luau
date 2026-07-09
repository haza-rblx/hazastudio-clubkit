local TextEffects = require(script.Parent.Parent);

return function(uiInstance: GuiObject, speed: number, size: number, customColor: ColorSequence | Color3?, customTransparency: NumberSequence | number?, useScaledSize: boolean?)

    local colorToUse = customColor or TextEffects.Templates.Ghost.Color
    local transparencyToUse = customTransparency or TextEffects.Templates.Ghost.Transparency
    
    local mainGradient = TextEffects.Gradient.new(uiInstance, colorToUse, transparencyToUse);
    mainGradient:SetOffsetSpeed(speed, 1);
    mainGradient:SetTransparencyOffsetSpeed(speed * 0.9, 1);

    local mainStroke = TextEffects.Stroke.new(uiInstance, size, nil, nil, useScaledSize);
    local strokeGradient = TextEffects.Gradient.new(mainStroke.Instance, colorToUse, transparencyToUse);
    strokeGradient:SetOffsetSpeed(-speed * 0.9, 1);
    strokeGradient:SetTransparencyOffsetSpeed(-speed * 0.9, 1);
    return {
        Effects = { mainGradient, strokeGradient, mainStroke }
    };
end