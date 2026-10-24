--!strict
-- The Decks view: track headers, deck bodies around the centre column, the hardware strip (425),
-- the pad row (70) and the library (261), on the panel's 2 px gutters.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Vide = require(ReplicatedStorage.HazaDJ.Packages.Vide)
local Store = require(script.Parent.Parent.Store)
local Theme = require(script.Parent.Parent.Theme)
local Base = require(script.Parent.Parent.UI.Base)
local Covers = require(script.Parent.Parent.UI.Covers)
local Centre = require(script.Centre)
local Deck = require(script.Deck)
local DeckLibrary = require(script.DeckLibrary)
local DragLoad = require(script.DragLoad)
local Model = require(script.Model)
local PadRow = require(script.PadRow)
local Strip = require(script.Strip)

local Decks = {}

export type Props = {
	visible: () -> boolean, -- the Decks tab is showing
	compact: () -> boolean, -- Deck view mode: pads and library hidden
}

-- returns the three panel rows (deck, pads, library) for the root list
function Decks.new(p: Props): { Instance }
	local function color(id: string): Color3
		return Covers.trackColor(Store.library(), id)
	end
	local a, b = Model.new(1, color), Model.new(2, color)
	-- the frame clock runs only while the decks are on screen
	local ticking = false
	Vide.effect(function()
		local on = p.visible() and Store.open()
		if on ~= ticking then
			ticking = on
			Model.tick(on)
		end
	end)
	Vide.cleanup(function()
		if ticking then
			Model.tick(false)
		end
	end)

	local headA, headB =
		Deck.header(a, { Position = UDim2.fromOffset(0, 0) }), Deck.header(b, { Position = UDim2.fromOffset(626, 0) })
	local bodyA, bodyB =
		Deck.body(a, false, { Position = UDim2.fromOffset(0, 0) }),
		Deck.body(b, true, { Position = UDim2.fromOffset(814, 0) })
	DragLoad.target(1, headA, false)
	DragLoad.target(1, bodyA, true)
	DragLoad.target(2, headB, false)
	DragLoad.target(2, bodyB, true)
	local deckRow = Base.frame({
		Name = "Deck",
		Size = UDim2.new(1, 0, 0, Theme.DECK_H),
		LayoutOrder = 1,
		Visible = p.visible,
		Base.vlist(2),
		Base.frame({
			Name = "Tracks",
			Size = UDim2.new(1, 0, 0, Deck.HEAD_H),
			LayoutOrder = 1,
			headA,
			headB,
		}),
		Base.frame({
			Name = "Bodies",
			Size = UDim2.new(1, 0, 0, Deck.BODY_H),
			LayoutOrder = 2,
			bodyA,
			Centre.new({ Position = UDim2.fromOffset(438, 0) }),
			bodyB,
		}),
		Strip.new(a, b, { LayoutOrder = 3 }),
	})
	local pads = PadRow.new(Theme.PADS_H, {
		LayoutOrder = 2,
		Visible = function()
			return p.visible() and not p.compact()
		end,
	})
	local library = DeckLibrary.new(Theme.LIB_H, {
		LayoutOrder = 3,
		Visible = function()
			return p.visible() and not p.compact()
		end,
	})
	return { deckRow, pads, library }
end

return Decks
