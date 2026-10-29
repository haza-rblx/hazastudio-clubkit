--!strict
-- Client/Utils/TouchScrollAssist.luau
-- Scrolls a ScrollingFrame by hand for a touch the engine will not scroll it for. A finger that lands
-- on some content (the profile's 3D avatar, a settings slider) never moves the list, even though the
-- same drag a few pixels away does. This follows that one touch and moves CanvasPosition itself,
-- but only while the canvas holds still on its own, so a list the engine does scroll is never
-- moved twice.
--
--   TouchScrollAssist.attach(region, scrollingFrame) -> { RBXScriptConnection }
--       every touch that starts on `region` scrolls `scrollingFrame` vertically
--   TouchScrollAssist.follow(input, scrollingFrame, startPosition)
--       one touch already in progress (a slider that decided the finger is scrolling)
local UserInputService = game:GetService("UserInputService")

local TouchScrollAssist = {}

local function maxCanvasY(scrollingFrame: ScrollingFrame): number
	return math.max(0, scrollingFrame.AbsoluteCanvasSize.Y - scrollingFrame.AbsoluteWindowSize.Y)
end

function TouchScrollAssist.follow(input: InputObject, scrollingFrame: ScrollingFrame, startPosition: Vector3?)
	local lastY = if startPosition then startPosition.Y else input.Position.Y
	local lastCanvas = scrollingFrame.CanvasPosition
	local changedConn: RBXScriptConnection? = nil
	local endedConn: RBXScriptConnection? = nil
	local function stop()
		if changedConn then
			changedConn:Disconnect()
			changedConn = nil
		end
		if endedConn then
			endedConn:Disconnect()
			endedConn = nil
		end
	end
	changedConn = UserInputService.InputChanged:Connect(function(changed: InputObject)
		if changed ~= input then
			return
		end
		if not scrollingFrame.Parent or not scrollingFrame.ScrollingEnabled then
			stop()
			return
		end
		if (scrollingFrame.CanvasPosition - lastCanvas).Magnitude > 0.5 then
			-- The engine is scrolling this touch after all: leave it alone.
			stop()
			return
		end
		local y = changed.Position.Y
		local nextY = math.clamp(lastCanvas.Y - (y - lastY), 0, maxCanvasY(scrollingFrame))
		lastY = y
		if nextY ~= lastCanvas.Y then
			lastCanvas = Vector2.new(lastCanvas.X, nextY)
			scrollingFrame.CanvasPosition = lastCanvas
		end
	end)
	endedConn = UserInputService.InputEnded:Connect(function(ended: InputObject)
		if ended == input then
			stop()
		end
	end)
end

local function isShown(gui: GuiObject): boolean
	local node: Instance? = gui
	while node do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		if node:IsA("LayerCollector") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

-- Hit-tested by position from UserInputService: the region's own InputBegan never fired for these
-- touches in PARKLAB (input probe), so it cannot be what starts the assist.
function TouchScrollAssist.attach(region: GuiObject, scrollingFrame: ScrollingFrame): { RBXScriptConnection }
	return {
		UserInputService.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType ~= Enum.UserInputType.Touch or not region.Parent or not isShown(region) then
				return
			end
			local p = input.Position
			local topLeft = scrollingFrame.AbsolutePosition
			local bottomRight = topLeft + scrollingFrame.AbsoluteWindowSize
			local r0 = region.AbsolutePosition
			local r1 = r0 + region.AbsoluteSize
			-- Inside the region and inside the list's visible window (the region scrolls with it).
			if
				p.X >= math.max(r0.X, topLeft.X)
				and p.X <= math.min(r1.X, bottomRight.X)
				and p.Y >= math.max(r0.Y, topLeft.Y)
				and p.Y <= math.min(r1.Y, bottomRight.Y)
			then
				TouchScrollAssist.follow(input, scrollingFrame, p)
			end
		end),
	}
end

return TouchScrollAssist
