--!strict
-- Client/UI/ShopUI.lua
-- Display only. No remotes, no business logic.
-- Handles: show/hide modal, benefit carousel (fade), notification.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local ShopDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.ShopDomain)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
local UIMotion = require(script.Parent.Parent.Utils.UIMotion)
-- Mapping tier -> GUI element names
local TIER_CARD: { [string]: string } = {
}
local TIER_NOTIF: { [string]: string } = {
}
-- Button suffix per tier: Buy[Suffix]Button, Gift[Suffix]Button
local TIER_SUFFIX: { [string]: string } = {
}
for _, tier in ipairs(Config.Membership.SHOP_TIERS or {}) do
	local cfg = Config.Membership.Tiers[tier]
	if cfg then
		TIER_CARD[tier] = cfg.shopCard
		TIER_NOTIF[tier] = cfg.shopNotif
		TIER_SUFFIX[tier] = cfg.guiSuffix
	end
end
-- Tiers the buyer switched off (ClubKitConfig.Membership.TierN.Enabled = false).
-- ConfigBootstrap drops them from SHOP_TIERS, so nothing above wires them up — but
-- the card and notification instances still ship inside the buyer's ScreenGui and
-- would sit there as dead, unbuyable cards. The card row is a horizontal
-- UIListLayout with SortOrder.Name, so hiding a card reflows the rest by itself.
local DISABLED_TIER_CARDS: { string } = {}
local DISABLED_TIER_NOTIFS: { string } = {}
do
	local enabled: { [string]: true } = {}
	for _, tier in ipairs(Config.Membership.SHOP_TIERS or {}) do
		enabled[tier] = true
	end
	for tier, cfg in pairs(Config.Membership.Tiers or {}) do
		if not enabled[tier] and type(cfg) == "table" then
			if type(cfg.shopCard) == "string" and cfg.shopCard ~= "" then
				table.insert(DISABLED_TIER_CARDS, cfg.shopCard)
			end
			if type(cfg.shopNotif) == "string" and cfg.shopNotif ~= "" then
				table.insert(DISABLED_TIER_NOTIFS, cfg.shopNotif)
			end
		end
	end
end
local function normalizeTier(tier: string): string?
	return ShopDomain.parseShopTier(tier)
end
local function hideLegacyPriceDuplicates(scope: Instance, activeLabel: TextLabel)
	local function isAncestorOfActive(candidate: Instance): boolean
		local current = activeLabel.Parent
		while current do
			if current == candidate then
				return true
			end
			current = current.Parent
		end
		return false
	end
	for _, desc in ipairs(scope:GetDescendants()) do
		if desc:IsA("TextLabel") and desc ~= activeLabel and not isAncestorOfActive(desc) then
			desc.Visible = false
		end
	end
end
local function findTextLabelByNames(root: Instance, names: { string }): TextLabel?
	for _, name in ipairs(names) do
		local found = root:FindFirstChild(name, true)
		if found and found:IsA("TextLabel") then
			return found
		end
	end
	return nil
end
local function findVisiblePriceLabel(container: Instance): TextLabel?
	local innerPrice = container:FindFirstChild("3-Price")
	if innerPrice and innerPrice:IsA("Instance") then
		local nestedExplicitValue = innerPrice:FindFirstChild("3-Price-Value")
			or innerPrice:FindFirstChild("3-PriceValue")
		if nestedExplicitValue and nestedExplicitValue:IsA("TextLabel") then
			return nestedExplicitValue
		end
	end
	local explicitValue = container:FindFirstChild("3-Price-Value") or container:FindFirstChild("3-PriceValue")
	if explicitValue and explicitValue:IsA("TextLabel") then
		return explicitValue
	end
	local directNamed: { TextLabel } = {}
	local descendantNamed: { TextLabel } = {}
	local directAny: { TextLabel } = {}
	local descendantAny: { TextLabel } = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("TextLabel") then
			if child.Name == "3-Price" then
				table.insert(directNamed, child)
			else
				table.insert(directAny, child)
			end
		end
	end
	for _, desc in ipairs(container:GetDescendants()) do
		if desc ~= container and desc:IsA("TextLabel") then
			if desc.Name == "3-Price" then
				table.insert(descendantNamed, desc)
			else
				table.insert(descendantAny, desc)
			end
		end
	end
	local function pickBest(candidates: { TextLabel }): TextLabel?
		for _, label in ipairs(candidates) do
			if label.Visible then
				return label
			end
		end
		return candidates[1]
	end
	return pickBest(directNamed) or pickBest(descendantNamed) or pickBest(directAny) or pickBest(descendantAny)
end
local function clearIndicatorGuiObjects(wrapper: Instance)
	for _, child in ipairs(wrapper:GetChildren()) do
		if child:IsA("GuiObject") and not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end
local function fadeProperty(object: GuiObject): string?
	if object:IsA("ImageLabel") or object:IsA("ImageButton") then
		return "ImageTransparency"
	elseif object:IsA("TextLabel") or object:IsA("TextButton") then
		return "TextTransparency"
	end
	return nil
end
-- Dot appearance: colour eases, anything the indicator's UIListLayout measures is set outright
-- (ADR 0005 / ADR 0011 — never tween Size or Position of a laid-out child).
local function applyDotAppearance(dot: GuiObject, template: GuiObject)
	if dot.Size ~= template.Size then
		dot.Size = template.Size
	end
	UIMotion.tween(dot, 0.18, {
		BackgroundColor3 = template.BackgroundColor3,
		BackgroundTransparency = template.BackgroundTransparency,
	})
	if dot:IsA("ImageLabel") and template:IsA("ImageLabel") then
		if dot.Image ~= template.Image then
			dot.Image = template.Image
		end
		UIMotion.tween(dot, 0.18, {
			ImageColor3 = template.ImageColor3,
			ImageTransparency = template.ImageTransparency,
		})
	end
end
type BenefitEntry = { icon: string, title: string, description: string }
type TierRefs = {
	card: Frame,
	benefitIcon: ImageLabel,
	benefitTitle: TextLabel,
	benefitDesc: TextLabel,
	indicatorWrapper: Frame,
	indicatorActive: Frame, -- template (not parented to GUI)
	indicatorDisable: Frame, -- template (not parented to GUI)
}
type CarouselState = {
	index: number,
	benefits: { BenefitEntry },
	refs: TierRefs,
	animating: boolean,
}
-- ============================================================
local ShopUI = {} :: any
ShopUI.__index = ShopUI
local WAIT_TIMEOUT = 10 -- seconds max wait for GUI elements
function ShopUI.new(gui: ScreenGui)
	local self = setmetatable({}, ShopUI) :: any
	self._gui = gui
	self._mainWrapper = gui:WaitForChild("MainWrapper", WAIT_TIMEOUT) :: Frame
	self._notifWrapper = gui:WaitForChild("NotificationWrapper", WAIT_TIMEOUT) :: Frame
	if not self._mainWrapper then
		warn("[ShopUI] MainWrapper not found di " .. gui.Name)
		return self
	end
	if not self._notifWrapper then
		warn("[ShopUI] NotificationWrapper not found di " .. gui.Name)
		return self
	end
	self._contentWrapper = self._mainWrapper:WaitForChild("02-MainContentWrapper", WAIT_TIMEOUT) :: Frame
	self._closeBtn = self._mainWrapper:WaitForChild("3-CloseModalButton", WAIT_TIMEOUT) :: TextButton?
	self._tierRefs = {} :: { [string]: TierRefs }
	self._carousels = {} :: { [string]: CarouselState }
	self._anim = AnimationHelper.new()
	self._carouselEnabled = false
	self._destroyed = false
	self._connections = {} :: { RBXScriptConnection }
	self._priceLabels = {} :: { { label: TextLabel, price: number } }
	self._cardOrder = {} :: { GuiObject }
	self._cardBases = {} :: { [GuiObject]: number }
	self._notifFade = {} :: { [Instance]: { GuiObject } }
	self._notifBases = {} :: { [Instance]: { [GuiObject]: number } }
	self:_buildRefs()
	self:_initPrices()
	self:_captureMotionBases()
	self:_initCarousels()
	-- Hide all on init
	self._mainWrapper.Visible = false
	self._notifWrapper.Visible = false
	return self
end
-- Fetch and store references for all elements per tier
function ShopUI:_buildRefs()
	for _, cardName in ipairs(DISABLED_TIER_CARDS) do
		local card = self._contentWrapper:FindFirstChild(cardName)
		if card and card:IsA("GuiObject") then
			card.Visible = false
		end
	end
	for _, notifName in ipairs(DISABLED_TIER_NOTIFS) do
		local notif = self._notifWrapper and self._notifWrapper:FindFirstChild(notifName)
		if notif and notif:IsA("GuiObject") then
			notif.Visible = false
		end
	end
	for tier, cardName in pairs(TIER_CARD) do
		local card = self._contentWrapper:FindFirstChild(cardName) :: Frame?
		if not card then
			continue
		end
		local bw = card:FindFirstChild("BenefitWrapper") :: Frame?
		local dw = bw and bw:FindFirstChild("DescriptionWrapper") :: Frame?
		local indW = bw and bw:FindFirstChild("CarrouselIndicatorWrapper") :: Frame?
		if not (bw and dw and indW) then
			continue
		end
		-- Clone template indicator before cleanup
		local activeClone = indW:FindFirstChild("CarrouselIndicatorActive")
		local disableClone = indW:FindFirstChild("CarrouselIndicatorDisable")
		activeClone = activeClone and activeClone:Clone() :: Frame
		disableClone = disableClone and disableClone:Clone() :: Frame
		-- Remove template from GUI (recreated dynamically)
		clearIndicatorGuiObjects(indW)
		self._tierRefs[tier] = {
			card = card,
			benefitIcon = bw:FindFirstChildWhichIsA("ImageLabel") :: ImageLabel,
			benefitTitle = dw:FindFirstChild("BenefitTitle") :: TextLabel,
			benefitDesc = dw:FindFirstChild("BenefitDescription") :: TextLabel,
			indicatorWrapper = indW,
			indicatorActive = activeClone :: Frame,
			indicatorDisable = disableClone :: Frame,
		}
	end
end
-- Update harga display from Config
function ShopUI:_initPrices()
	for tier, cardName in pairs(TIER_CARD) do
		local entry = ShopDomain.getCatalogEntry(tier)
		if not entry then
			continue
		end
		local card = self._contentWrapper:FindFirstChild(cardName)
		if not card then
			continue
		end
		local jumbotron = card:FindFirstChild("JumbotronTextandImage") :: Frame?
		local piw = jumbotron
			and (jumbotron:FindFirstChild("ProductInfoWrapper") or jumbotron:FindFirstChild("Frame")) :: Frame?
		if not piw then
			continue
		end
		local titleLabel = findTextLabelByNames(piw, { "1-Title", "Title", "MembershipName", "TierName" })
		if titleLabel then
			titleLabel.Text = entry.name
		end
		local priceWrapper = piw:FindFirstChild("3-Price")
		local priceLabel: TextLabel? = nil
		if priceWrapper and priceWrapper:IsA("TextLabel") then
			priceLabel = priceWrapper
		elseif priceWrapper then
			priceLabel = findVisiblePriceLabel(priceWrapper)
		end
		if not priceLabel then
			priceLabel = findVisiblePriceLabel(piw)
		end
		if priceLabel then
			priceLabel.Text = tostring(entry.price)
			priceLabel.Visible = true
			hideLegacyPriceDuplicates(priceWrapper or piw, priceLabel)
			-- Only whole prices roll on open: countTo's default format must land on the exact
			-- same string the label already shows.
			local price = tonumber(entry.price)
			if price and price % 1 == 0 and tostring(entry.price) == tostring(math.floor(price)) then
				table.insert(self._priceLabels, { label = priceLabel, price = price })
			end
		else
			warn("[ShopUI] Price label not found for " .. tier .. " (" .. cardName .. ")")
		end
	end
end
-- Designed transparency of every card element, captured once before any fade touches them, so
-- the open stagger and the carousel swap can fade back to the buyer's own values.
function ShopUI:_captureMotionBases()
	for _, tier in ipairs(Config.Membership.SHOP_TIERS or {}) do
		local refs = self._tierRefs[tier]
		if not refs or not refs.card then
			continue
		end
		table.insert(self._cardOrder, refs.card)
		local elements: { GuiObject } = { refs.card }
		for _, desc in ipairs(refs.card:GetDescendants()) do
			if desc:IsA("GuiObject") then
				table.insert(elements, desc)
			end
		end
		UIMotion.captureBases(elements, self._cardBases)
	end
end
-- Rebuild indicator dots to match benefit count and active index. Same count = same dots, so the
-- active one eases into its colour instead of the whole row being destroyed and re-cloned.
function ShopUI:_buildIndicators(refs: TierRefs, count: number, activeIndex: number)
	local wrapper = refs.indicatorWrapper
	local dots: { GuiObject } = {}
	for _, child in ipairs(wrapper:GetChildren()) do
		if child:IsA("GuiObject") and string.sub(child.Name, 1, 4) == "Dot_" then
			table.insert(dots, child)
		end
	end
	if #dots == count then
		for i, dot in ipairs(dots) do
			local template = (i == activeIndex) and refs.indicatorActive or refs.indicatorDisable
			if template then
				applyDotAppearance(dot, template)
			end
		end
		wrapper.Visible = count > 1
		return
	end
	-- Remove previous dots
	clearIndicatorGuiObjects(wrapper)
	wrapper.Visible = count > 1
	if count <= 1 then
		return
	end
	for i = 1, count do
		local template = (i == activeIndex) and refs.indicatorActive or refs.indicatorDisable
		if not template then
			continue
		end
		local dot = template:Clone()
		dot.Name = "Dot_" .. i
		dot.Parent = wrapper
	end
end
-- Update one slide content (immediate, no animation)
function ShopUI:_applySlide(tier: string, index: number)
	local refs = self._tierRefs[tier]
	local cs = self._carousels[tier]
	if not refs or not cs then
		return
	end
	local benefit = cs.benefits[index]
	if not benefit then
		return
	end
	if refs.benefitIcon and refs.benefitIcon.Image ~= benefit.icon then
		refs.benefitIcon.Image = benefit.icon
	end
	if refs.benefitTitle and refs.benefitTitle.Text ~= benefit.title then
		refs.benefitTitle.Text = benefit.title
	end
	if refs.benefitDesc and refs.benefitDesc.Text ~= benefit.description then
		refs.benefitDesc.Text = benefit.description
	end
	self:_buildIndicators(refs, #cs.benefits, index)
	cs.index = index
end
-- Fade out -> swap content -> cascade back in. The icon/title/description live inside the card's
-- layouts, so only transparency moves (ADR 0011); the old Position tweens fought the layout.
function ShopUI:_fadeToSlide(tier: string, nextIndex: number)
	local refs = self._tierRefs[tier]
	local cs = self._carousels[tier]
	if not refs or not cs or cs.animating then
		return
	end
	cs.animating = true
	local fadeTime = Config.Shop.CAROUSEL_FADE_TIME
	local staggerTime = Config.Shop.CAROUSEL_STAGGER_TIME or 0.06
	-- Built one by one, not as an array literal: a missing icon would leave a nil hole that ipairs
	-- stops on, silently dropping the title and description fades.
	local targets: { GuiObject } = {}
	local function addTarget(obj: GuiObject?)
		if obj and self._cardBases[obj] ~= nil then
			table.insert(targets, obj)
		end
	end
	addTarget(refs.benefitIcon)
	addTarget(refs.benefitTitle)
	addTarget(refs.benefitDesc)
	for _, obj in ipairs(targets) do
		local property = fadeProperty(obj)
		if property then
			UIMotion.tween(obj, fadeTime, { [property] = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end
	task.wait(fadeTime)
	self:_applySlide(tier, nextIndex)
	-- Back to the designed value first: under reduced motion the fade-out above snapped to 1 and
	-- stagger() is a no-op, so this is what keeps the new benefit visible.
	for _, obj in ipairs(targets) do
		local property = fadeProperty(obj)
		if property then
			UIMotion.tween(obj, 0, { [property] = self._cardBases[obj] })
		end
	end
	UIMotion.stagger(targets, self._cardBases, staggerTime)
	UIMotion.pop(refs.benefitIcon, 1.12)
	task.wait(fadeTime + ((#targets - 1) * staggerTime))
	cs.animating = false
end
-- Setup and start all carousels
function ShopUI:_initCarousels()
	for tier, _ in pairs(TIER_CARD) do
		local refs = self._tierRefs[tier]
		local benefits = Config.Shop.BENEFITS[tier] or {}
		if not refs or #benefits == 0 then
			continue
		end
		local cs: CarouselState = { index = 1, benefits = benefits, refs = refs, animating = false }
		self._carousels[tier] = cs
		self:_applySlide(tier, 1)
		if #benefits > 1 then
			task.spawn(function()
				while not self._destroyed do
					task.wait(Config.Shop.CAROUSEL_INTERVAL)
					if self._destroyed then
						break
					end
					if not self._carouselEnabled then
						continue
					end
					local next = (cs.index % #benefits) + 1
					self:_fadeToSlide(tier, next)
				end
			end)
		end
	end
end
-- ============================================================
-- Public API
-- ============================================================
function ShopUI:show()
	self._carouselEnabled = true
	self._anim:presentCenterPanel(self._mainWrapper, nil, {
		enableBlur = true,
		blurName = "ShopUIBlur",
		enableZoom = true
	})
	-- Cards cascade in behind the panel's own open animation, then the prices roll up.
	UIMotion.stagger(self._cardOrder, self._cardBases, 0.05)
	for _, entry in ipairs(self._priceLabels) do
		UIMotion.countTo(entry.label, 0, entry.price, 0.45)
	end
end
function ShopUI:hide()
	self._carouselEnabled = false
	self._anim:dismissCenterPanel(self._mainWrapper, nil, {
		enableBlur = true,
		blurName = "ShopUIBlur",
		enableZoom = true
	})
end
function ShopUI:destroy()
	self._destroyed = true
	self._carouselEnabled = false
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
end
-- Press squash + hover lift + click, all owned by self._connections so destroy() releases them.
function ShopUI:_bindButton(button: GuiButton, callback: () -> ())
	for _, connection in ipairs(UIMotion.bindPress(button)) do
		table.insert(self._connections, connection)
	end
	for _, connection in ipairs(UIMotion.bindHover(button)) do
		table.insert(self._connections, connection)
	end
	table.insert(self._connections, button.MouseButton1Click:Connect(callback))
end
function ShopUI:showNotification(tier: string, playerDisplayName: string)
	local normalizedTier = normalizeTier(tier)
	if not normalizedTier then
		return
	end
	-- Hide all notifications
	for _, name in pairs(TIER_NOTIF) do
		local n = self._notifWrapper:FindFirstChild(name)
		if n then
			(n :: Frame).Visible = false
		end
	end
	local notifName = TIER_NOTIF[normalizedTier]
	local notif = notifName and self._notifWrapper:FindFirstChild(notifName) :: Frame?
	if not notif then
		return
	end
	-- Update teks judul with nama player
	local content = notif:FindFirstChild("1-RequestContent") :: Frame?
	local jumbotron = content and content:FindFirstChild("JumbotronTextandImage") :: Frame?
	local frame = jumbotron and jumbotron:FindFirstChild("Frame") :: Frame?
	local titleLabel = frame and frame:FindFirstChild("1-Title") :: TextLabel?
	if titleLabel then
		local entry = ShopDomain.getCatalogEntry(normalizedTier)
		local displayTier = entry and entry.name or normalizedTier
		titleLabel.Text = "Welcome to " .. displayTier .. ", " .. playerDisplayName .. "!"
	end
	notif.Visible = true
	self._notifWrapper.Visible = true
	-- swingIn - similar to CoupleSystem notification
	local content2 = notif:FindFirstChild("1-RequestContent") :: Frame?
	if content2 then
		self._anim:swingIn(content2, self._notifWrapper, nil)
		local elements = self._notifFade[content2]
		local bases = self._notifBases[content2]
		if not (elements and bases) then
			elements = {}
			for _, desc in ipairs(content2:GetDescendants()) do
				if desc:IsA("GuiObject") then
					table.insert(elements, desc)
				end
			end
			bases = UIMotion.captureBases(elements)
			self._notifFade[content2] = elements
			self._notifBases[content2] = bases
		end
		UIMotion.fadeIn(elements, bases, 0.08)
		local icon = jumbotron and jumbotron:FindFirstChildWhichIsA("ImageLabel")
		if icon then
			UIMotion.pop(icon, 1.25)
		end
	end
end
function ShopUI:hideNotification()
	local visible: Frame? = nil
	for _, name in pairs(TIER_NOTIF) do
		local n = self._notifWrapper:FindFirstChild(name) :: Frame?
		if n and n.Visible then
			visible = n
			break
		end
	end
	if visible then
		local content2 = visible:FindFirstChild("1-RequestContent") :: Frame?
		if content2 then
			self._anim:scaleOut(content2, function()
				self._notifWrapper.Visible = false
				-- Reset scale for berikutnya
				local s = content2:FindFirstChildWhichIsA("UIScale") :: UIScale?
				if s then
					s.Scale = 1
				end
			end)
			return
		end
	end
	self._notifWrapper.Visible = false
end
function ShopUI:bindBuyButton(tier: string, callback: () -> ())
	local normalizedTier = normalizeTier(tier)
	if not normalizedTier then
		return
	end
	local refs = self._tierRefs[normalizedTier]
	if not refs then
		return
	end
	local suffix = TIER_SUFFIX[normalizedTier]
	local inputArea = refs.card:FindFirstChild("InputArea") :: Frame?
	local btn = inputArea and inputArea:FindFirstChild("Buy" .. suffix .. "Button") :: TextButton?
	if btn then
		local button = btn :: TextButton
		self:_bindButton(button, function()
			UIMotion.pop(UIMotion.scaleTargetOf(button), 1.18)
			callback()
		end)
	end
end
function ShopUI:bindGiftButton(tier: string, callback: () -> ())
	local normalizedTier = normalizeTier(tier)
	if not normalizedTier then
		return
	end
	local refs = self._tierRefs[normalizedTier]
	if not refs then
		return
	end
	local suffix = TIER_SUFFIX[normalizedTier]
	local inputArea = refs.card:FindFirstChild("InputArea") :: Frame?
	local btn = inputArea and inputArea:FindFirstChild("Gift" .. suffix .. "Button") :: TextButton?
	if btn then
		local button = btn :: TextButton
		self:_bindButton(button, function()
			UIMotion.pop(UIMotion.scaleTargetOf(button), 1.18)
			callback()
		end)
	end
end
function ShopUI:bindClose(callback: () -> ())
	if self._closeBtn then
		self:_bindButton(self._closeBtn, callback)
	end
end
-- Bind "Wow, thanks!" button on specific notification tier
function ShopUI:bindNotifClose(tier: string, callback: () -> ())
	local normalizedTier = normalizeTier(tier)
	if not normalizedTier then
		return
	end
	local notifName = TIER_NOTIF[normalizedTier]
	local notif = self._notifWrapper:FindFirstChild(notifName) :: Frame?
	local content = notif and notif:FindFirstChild("1-RequestContent") :: Frame?
	local inputArea = content and content:FindFirstChild("InputArea") :: Frame?
	local btn = inputArea and inputArea:FindFirstChildWhichIsA("TextButton") :: TextButton?
	if btn then
		local button = btn :: TextButton
		self:_bindButton(button, function()
			UIMotion.pop(UIMotion.scaleTargetOf(button), 1.18)
			callback()
		end)
	end
end
return ShopUI
