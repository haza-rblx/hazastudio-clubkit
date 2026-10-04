local TextEffects = require(script.Parent.Parent);
local SharedTickConnection = require(script.Parent.Parent.SharedTickConnection);

return function(uiInstance: GuiObject, speed: number, size: number, customColor: ColorSequence | Color3?, customTransparency: NumberSequence | number?, useScaledSize: boolean?)

    local colorToUse = customColor or TextEffects.Templates.Rainbow.Color
    
    local mainStroke = TextEffects.Stroke.new(uiInstance, size, nil, nil, useScaledSize);
    local strokeGradient = TextEffects.Gradient.new(mainStroke.Instance, colorToUse, 0);
    local Rotation = 5;

	local Connection
	Connection = SharedTickConnection({}, function(dt)
		if (not mainStroke.Instance or mainStroke.Instance.Parent == nil) then
			Connection:Disconnect();
			return;
		end;
		Rotation = Rotation + speed * dt;
		strokeGradient:SetRotation(Rotation, 1);
	end, uiInstance);

	return {
		Effects = { strokeGradient, mainStroke },
		Connections = { Connection }
	};
end
