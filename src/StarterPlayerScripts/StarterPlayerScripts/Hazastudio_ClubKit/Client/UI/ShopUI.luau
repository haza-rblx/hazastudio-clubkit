--!strict
-- Client/UI/ShopUI.lua
-- Display only. No remotes, no business logic.
-- Handles: show/hide modal, benefit carousel (fade), notification.
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Constants.Config)
local ShopDomain = require(ReplicatedStorage.Hazastudio_ClubKit.Shared.Domain.ShopDomain)
local AnimationHelper = require(script.Parent.Parent.Utils.AnimationHelper)
-- Mapping tier -> nama elemen di GUI
local TIER_CARD: { [string]: string } = {
}
local TIER_NOTIF: { [string]: string } = {
}
-- Suffix tombol per tier: Buy[Suffix]Button, Gift[Suffix]Button
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
type BenefitEntry = { icon: string, title: string, description: string }
type TierRefs = {
	card: Frame,
	benefitIcon: ImageLabel,
	benefitTitle: TextLabel,
	benefitDesc: TextLabel,
	indicatorWrapper: Frame,
	indicatorActive: Frame, -- template (tidak di-parent ke GUI)
	indicatorDisable: Frame, -- template (tidak di-parent ke GUI)
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
local WAIT_TIMEOUT = 10 -- detik maksimal menunggu elemen GUI
function ShopUI.new(gui: ScreenGui)
	local self = setmetatable({}, ShopUI) :: any
	self._gui = gui
	self._mainWrapper = gui:WaitForChild("MainWrapper", WAIT_TIMEOUT) :: Frame
	self._notifWrapper = gui:WaitForChild("NotificationWrapper", WAIT_TIMEOUT) :: Frame
	if not self._mainWrapper then
		warn("[ShopUI] MainWrapper tidak ditemukan di " .. gui.Name)
		return self
	end
	if not self._notifWrapper then
		warn("[ShopUI] NotificationWrapper tidak ditemukan di " .. gui.Name)
		return self
	end
	self._contentWrapper = self._mainWrapper:WaitForChild("02-MainContentWrapper", WAIT_TIMEOUT) :: Frame
	self._closeBtn = self._mainWrapper:WaitForChild("3-CloseModalButton", WAIT_TIMEOUT) :: TextButton?
	self._tierRefs = {} :: { [string]: TierRefs }
	self._carousels = {} :: { [string]: CarouselState }
	self._anim = AnimationHelper.new()
	self._carouselEnabled = false
	self._destroyed = false
	self:_buildRefs()
	self:_initPrices()
	self:_initCarousels()
	-- Sembunyikan semua saat init
	self._mainWrapper.Visible = false
	self._notifWrapper.Visible = false
	return self
end
-- Ambil dan store referensi semua elemen per tier
function ShopUI:_buildRefs()
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
		-- Clone template indicator sebelum dibersihkan
		local activeClone = indW:FindFirstChild("CarrouselIndicatorActive")
		local disableClone = indW:FindFirstChild("CarrouselIndicatorDisable")
		activeClone = activeClone and activeClone:Clone() :: Frame
		disableClone = disableClone and disableClone:Clone() :: Frame
		-- Bersihkan template dari GUI (akan dibuat ulang secara dinamis)
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
-- Update harga display dari Config
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
		else
			warn("[ShopUI] Price label not found for " .. tier .. " (" .. cardName .. ")")
		end
	end
end
-- Bangun ulang indicator dots sesuai jumlah benefit dan index aktif
function ShopUI:_buildIndicators(refs: TierRefs, count: number, activeIndex: number)
	local wrapper = refs.indicatorWrapper
	-- Hapus dots sebelumnya
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
-- Update konten satu slide (langsung, tanpa animasi)
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
	if refs.benefitIcon then
		refs.benefitIcon.Image = benefit.icon
	end
	if refs.benefitTitle then
		refs.benefitTitle.Text = benefit.title
	end
	if refs.benefitDesc then
		refs.benefitDesc.Text = benefit.description
	end
	self:_buildIndicators(refs, #cs.benefits, index)
	cs.index = index
end
-- Fade out -> ganti konten -> fade in
local function buildExitProps(obj: Instance, basePosition: UDim2, offsetScale: number): { [string]: any }?
	local props: { [string]: any } = {
		Position = basePosition + UDim2.fromScale(offsetScale, 0),
	}
	if obj:IsA("ImageLabel") then
		props.ImageTransparency = 1
	elseif obj:IsA("TextLabel") then
		props.TextTransparency = 1
		props.TextStrokeTransparency = 1
	else
		return nil
	end
	return props
end
local function buildEnterProps(obj: Instance, basePosition: UDim2, offsetScale: number): { [string]: any }?
	local props: { [string]: any } = {
		Position = basePosition + UDim2.fromScale(offsetScale, 0),
	}
	if obj:IsA("ImageLabel") then
		props.ImageTransparency = 1
	elseif obj:IsA("TextLabel") then
		props.TextTransparency = 1
		props.TextStrokeTransparency = 1
	else
		return nil
	end
	return props
end
local function buildRestProps(obj: Instance, basePosition: UDim2): { [string]: any }?
	local props: { [string]: any } = {
		Position = basePosition,
	}
	if obj:IsA("ImageLabel") then
		props.ImageTransparency = 0
	elseif obj:IsA("TextLabel") then
		props.TextTransparency = 0
		props.TextStrokeTransparency = 0
	else
		return nil
	end
	return props
end
function ShopUI:_fadeToSlide(tier: string, nextIndex: number)
	local refs = self._tierRefs[tier]
	local cs = self._carousels[tier]
	if not refs or not cs or cs.animating then
		return
	end
	cs.animating = true
	local fadeTime = Config.Shop.CAROUSEL_FADE_TIME
	local staggerTime = Config.Shop.CAROUSEL_STAGGER_TIME or 0.06
	local slideOffset = Config.Shop.CAROUSEL_SLIDE_OFFSET or 0.03
	local targets = {
		refs.benefitIcon :: Instance?,
		refs.benefitTitle :: Instance?,
		refs.benefitDesc :: Instance?,
	}
	local basePositions: { [Instance]: UDim2 } = {}
	for index, obj in ipairs(targets) do
		if not obj then
			continue
		end
		local guiObj = obj :: GuiObject
		local basePosition = guiObj.Position
		basePositions[obj] = basePosition
		local directionOffset = slideOffset + ((index - 1) * 0.015)
		local exitProps = buildExitProps(obj, basePosition, directionOffset)
		if exitProps then
			task.delay((index - 1) * staggerTime, function()
				TweenService
					:Create(obj, TweenInfo.new(fadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), exitProps)
					:Play()
			end)
		end
	end
	task.wait(fadeTime + ((#targets - 1) * staggerTime))
	self:_applySlide(tier, nextIndex)
	for _, obj in ipairs(targets) do
		if not obj then
			continue
		end
		local basePosition = basePositions[obj]
		if not basePosition then
			continue
		end
		local objIndex = table.find(targets, obj) or 1
		local directionOffset = slideOffset + ((objIndex - 1) * 0.015)
		local enterProps = buildEnterProps(obj, basePosition, -directionOffset)
		if enterProps then
			for prop, value in pairs(enterProps) do
				(obj :: any)[prop] = value
			end
		end
	end
	for index, obj in ipairs(targets) do
		if not obj then
			continue
		end
		local basePosition = basePositions[obj]
		if not basePosition then
			continue
		end
		local restProps = buildRestProps(obj, basePosition)
		if restProps then
			task.delay((index - 1) * staggerTime, function()
				TweenService
					:Create(obj, TweenInfo.new(fadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), restProps)
					:Play()
			end)
		end
	end
	task.wait(fadeTime + ((#targets - 1) * staggerTime))
	cs.animating = false
end
-- Setup dan mulai semua carousel
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
end
function ShopUI:showNotification(tier: string, playerDisplayName: string)
	local normalizedTier = normalizeTier(tier)
	if not normalizedTier then
		return
	end
	-- Sembunyikan semua notification
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
	-- Update teks judul dengan nama player
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
	-- swingIn - senada dengan notif di CoupleSystem
	local content2 = notif:FindFirstChild("1-RequestContent") :: Frame?
	if content2 then
		self._anim:swingIn(content2, self._notifWrapper, nil)
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
				-- Reset scale untuk berikutnya
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
		btn.MouseButton1Click:Connect(callback)
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
		btn.MouseButton1Click:Connect(callback)
	end
end
function ShopUI:bindClose(callback: () -> ())
	if self._closeBtn then
		self._closeBtn.MouseButton1Click:Connect(callback)
	end
end
-- Bind tombol "Wow, thanks!" pada notification tier tertentu
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
		btn.MouseButton1Click:Connect(callback)
	end
end
return ShopUI
