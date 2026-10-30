--!strict
-- Covers: the playlist cover (the owner's template, rebuilt in code), the cover row used in both
-- library columns, the initials track cover, and the DJ avatar.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vide = require(ReplicatedStorage.CosmicDJ.Packages.Vide)
local Shared = ReplicatedStorage.CosmicDJ.Shared
local Format = require(Shared.Format)
local Types = require(Shared.Types)
local Base = require(script.Parent.Base)
local Hover = require(script.Parent.Hover)
local Theme = require(script.Parent.Parent.Theme)

local create, source, read = Vide.create, Vide.source, Vide.read
local C, W, B, SB, R = Theme.C, Theme.W, Theme.B, Theme.SB, Theme.R
local with, frame, label, corner = Base.with, Base.frame, Base.label, Base.corner

local Covers = {}

Covers.COVER_R = 4 -- a touch sharper than the template (owner, 2026-10-22)

-- a playlist's colour, a track's colour (its first playlist's; none = dark). No colour set = the
-- accent: call these inside a prop function so default covers follow an accent change.
function Covers.playlistColor(pl: Types.Playlist?): Color3
	if pl and pl.color then
		local ok, c = pcall(Color3.fromHex, pl.color)
		if ok then
			return c
		end
	end
	return Theme.accent()
end

function Covers.trackColor(lib: Types.Library, trackId: string): Color3
	for _, pl in lib.playlists do
		if table.find(pl.tracks, trackId) then
			return Covers.playlistColor(pl)
		end
	end
	return C.coverEmpty
end

export type CoverOpts = {
	text: any, -- printed bottom-left
	image: any?, -- asset id or nil
	color: any?, -- Color3 for a playlist; nil = the dark library cover
	textSize: number?,
	inset: number?, -- padding, 7 by default
}

-- the cover square; size it from outside (Size / aspect)
function Covers.cover(o: CoverOpts, props: Base.Props?): ImageLabel
	local isPl = o.color ~= nil
	local e = o.inset or 7
	return create("ImageLabel")(with({
		Name = "PlaylistCover",
		BackgroundColor3 = if isPl then W else C.libCover,
		BorderSizePixel = 0,
		ScaleType = Enum.ScaleType.Crop,
		Image = function()
			local img = read(o.image)
			return if img then "rbxassetid://" .. string.format("%d", img) else ""
		end,
		corner(Covers.COVER_R),
		create("UIPadding")({
			PaddingLeft = UDim.new(0, e),
			PaddingRight = UDim.new(0, e),
			PaddingTop = UDim.new(0, e),
			PaddingBottom = UDim.new(0, e),
		}),
		if isPl
			then create("UIGradient")({
				Rotation = 90,
				-- the colour gradient would tint a cover image
				Enabled = function()
					return read(o.image) == nil
				end,
				Color = function()
					return ColorSequence.new(read(o.color) :: Color3)
				end,
			})
			else nil,
		create("TextLabel")({
			Name = "PlaylistName",
			Text = o.text,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			RichText = true,
			FontFace = SB,
			TextSize = o.textSize or 12,
			TextColor3 = W,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		create("ImageLabel")({
			Name = "PlaylistIcon",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.new(0.3, 0, 0.3, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = Theme.MUSIC_ICON,
		}),
	}, props))
end

export type RowOpts = {
	on: any, -- selected
	title: any,
	coverText: any,
	count: any, -- "14 Tracks"
	countColor: any?,
	image: any?,
	color: any?, -- playlist colour; nil = library row
	h: number?, -- row height, 76
	onClick: () -> (),
	order: number?,
}

-- a cover row (76 px): cover, then the name over the count
function Covers.row(o: RowOpts): TextButton
	local h = o.h or 76
	local hover = source(false)
	local coverTextSize = if h < 76 then math.max(9, math.floor(h / 7)) else 12
	local inset = if h < 76 then math.max(4, h // 12) else 7
	return create("TextButton")({
		Name = "Row",
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, h),
		LayoutOrder = o.order or 0,
		BackgroundColor3 = function()
			return if read(o.on) then C.select else C.hover
		end,
		BackgroundTransparency = function()
			return if read(o.on) or hover() then 0 else 1
		end,
		Hover.track(hover),
		Activated = o.onClick,
		Base.hlist(0, nil, { VerticalAlignment = Enum.VerticalAlignment.Top }),
		Base.pad(8, 8, 4, 4),
		Covers.cover(
			{ text = o.coverText, image = o.image, color = o.color, textSize = coverTextSize, inset = inset },
			{
				Size = UDim2.new(0.5, 0, 1, 0),
				LayoutOrder = 1,
				create("UIAspectRatioConstraint")({ AspectRatio = 1 }),
			}
		),
		frame({
			Name = "PlaylistInformation",
			LayoutOrder = 2,
			Size = UDim2.new(1, -(h - 8), 1, 0),
			Base.vlist(2, {
				VerticalAlignment = Enum.VerticalAlignment.Center,
				HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween,
			}),
			Base.pad(12, 0, 0, 0),
			label(o.title, {
				Name = "PlaylistName",
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextSize = 14,
				TextYAlignment = Enum.TextYAlignment.Center,
				LayoutOrder = 1,
			}),
			label(o.count, {
				Name = "TotalTrack",
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				FontFace = R,
				TextSize = 13,
				TextColor3 = o.countColor or C.countText,
				TextYAlignment = Enum.TextYAlignment.Center,
				LayoutOrder = 2,
			}),
		}),
	})
end

-- the initials cover for a track, in its playlist colour
function Covers.track(title: any, color: any, size: number, props: Base.Props?): Frame
	return Base.new(
		"Frame",
		with({
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = color,
			corner(if size > 40 then 4 else 2),
			label(function()
				return Format.initials(read(title))
			end, {
				AutomaticSize = Enum.AutomaticSize.None,
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				FontFace = B,
				TextSize = if size > 40 then 20 else 12,
				TextTransparency = 0.15,
			}),
		}, props)
	)
end

export type AvatarPerson = { userId: number, name: string, handle: string }

-- the Roblox headshot when there is a real user id, else initials on a grey; live = red ring,
-- online = a small green dot
function Covers.avatar(p: AvatarPerson, size: number, live: boolean, online: boolean, props: Base.Props?): Frame
	local real = p.userId > 0
	local ring = nil
	if live then
		ring = create("UIStroke")({
			Color = Theme.accent,
			Thickness = if size > 60 then 3 else 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		})
	elseif online then
		local d = math.max(8, size // 4)
		ring = Base.new("Frame", {
			Size = UDim2.fromOffset(d, d),
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.fromScale(1, 1),
			BackgroundColor3 = C.ok,
			ZIndex = 2,
			corner(d // 2),
			create("UIStroke")({ Color = C.tile, Thickness = 2 }),
		})
	end
	return Base.new(
		"Frame",
		with({
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = if real then C.card2 else Format.shade(p.handle),
			corner(size // 2),
			if real
				then create("ImageLabel")({
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", p.userId),
					corner(size // 2),
				})
				else nil,
			if real
				then nil
				else create("UIGradient")({
					Rotation = 45,
					Color = ColorSequence.new(W, Color3.fromRGB(150, 150, 150)),
				}),
			if real
				then nil
				else label(Format.initials(p.name), {
					AutomaticSize = Enum.AutomaticSize.None,
					Size = UDim2.fromScale(1, 1),
					TextXAlignment = Enum.TextXAlignment.Center,
					FontFace = B,
					TextSize = math.floor(size * 0.36),
				}),
			ring,
		}, props)
	)
end

return Covers
