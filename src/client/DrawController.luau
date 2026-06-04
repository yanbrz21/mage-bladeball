--!strict

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local InventoryConfig = require(Config:WaitForChild("InventoryConfig"))

local DrawController = {
	Name = "DrawController",
}

local DRAW_ID_ATTRIBUTE = "ID"
local SELECTED_ATTRIBUTE = "SELECTED"

local foundPrice1x:TextLabel?
local foundPrice5x:TextLabel?

local screen

local selectButtonColors = {
	Selected = Color3.fromRGB(148, 41, 224),
	Unselected = Color3.fromRGB(0, 0, 0),
}

local rarityRank = {
	Common = 1,
	Rare = 2,
	Epic = 3,
	Legendary = 4,
	Mythic = 5,
}

local coinsText: TextLabel?
local gemsText: TextLabel?

local spinItems: Frame?

local spin1xButton: TextButton?
local spin5xButton: TextButton?

local gemsDrawPrice: TextLabel?
local coinsDrawPrice: TextLabel?

local spinPrices: Frame?
local price1x: TextLabel?
local price5x: TextLabel?

local spinTypesButtons: { Instance } = {}

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local currentDrawId = "NormalAbilityDraw"
local currentCount = 1

local connections: { RBXScriptConnection } = {}
local didBuildUI = false

function DrawController:Init(context)
	if self._didInit then
		return
	end
	
	self._screen = screen
	self._didInit = true
	self._context = context
	self._localPlayer = localPlayer
	self._connections = connections
end

local function getReferenceByTag(tag: string, timeout: number?): Instance?
	local startedAt = os.clock()
	local maxWait = timeout or 10

	while os.clock() - startedAt < maxWait do
		local items = CollectionService:GetTagged(tag)

		for _, item in items do
			if item:IsDescendantOf(playerGui) then
				return item
			end
		end

		task.wait(0.1)
	end

	warn(`[DrawController] no tagged player gui item found: {tag}`)
	return nil
end

local function getTextLabelByTag(tag: string): TextLabel?
	local instance = getReferenceByTag(tag)

	if instance == nil then
		return nil
	end

	if not instance:IsA("TextLabel") then
		warn(`[DrawController] {tag} is not a TextLabel, got {instance.ClassName}`)
		return nil
	end

	return instance
end

local function getTextButtonByTag(tag: string): TextButton?
	local instance = getReferenceByTag(tag)

	if instance == nil then
		return nil
	end

	if not instance:IsA("TextButton") then
		warn(`[DrawController] {tag} is not a TextButton, got {instance.ClassName}`)
		return nil
	end

	return instance
end

local function getFrameByTag(tag: string): Frame?
	local instance = getReferenceByTag(tag)

	if instance == nil then
		return nil
	end

	if not instance:IsA("Frame") then
		warn(`[DrawController] {tag} is not a Frame, got {instance.ClassName}`)
		return nil
	end

	return instance
end

local function getDrawConfig(drawId: string)
	local drawCatalog = EconomyConfig.DrawCatalog :: any
	local drawConfig = drawCatalog[drawId]

	if drawConfig == nil then
		warn(`[DrawController] invalid draw id: {drawId}`)
		return nil
	end

	return drawConfig
end

local function getInventoryDisplayName(category: string, itemId: string): string
	local categories = InventoryConfig.Categories :: any
	local categoryConfig = categories[category]

	if type(categoryConfig) ~= "table" then
		return itemId
	end

	local items = categoryConfig.Items
	if type(items) ~= "table" then
		return itemId
	end

	local itemConfig = items[itemId]
	if type(itemConfig) ~= "table" then
		return itemId
	end

	local displayName = itemConfig.DisplayName
	if type(displayName) ~= "string" then
		return itemId
	end

	return displayName
end

local function getSortedSpinItemFrames(): { Frame }
	local frames = {} :: { Frame }

	if spinItems == nil then
		return frames
	end

	for _, child in spinItems:GetChildren() do
		if child:IsA("Frame") then
			table.insert(frames, child)
		end
	end

	table.sort(frames, function(a, b)
		return a.Name < b.Name
	end)

	return frames
end

local function getBestDrawEntries(drawConfig): { any }
	local entries = {}

	for _, entry in drawConfig.Entries do
		table.insert(entries, entry)
	end

	table.sort(entries, function(a, b)
		local leftRank = rarityRank[a.Rarity] or 0
		local rightRank = rarityRank[b.Rarity] or 0

		if leftRank ~= rightRank then
			return leftRank > rightRank
		end

		if a.Weight ~= b.Weight then
			return a.Weight > b.Weight
		end

		return tostring(a.ItemId) < tostring(b.ItemId)
	end)

	return entries
end

local function updateSpinItems()
	local drawConfig = getDrawConfig(currentDrawId)
	if drawConfig == nil then
		return
	end

	local frames = getSortedSpinItemFrames()
	local bestEntries = getBestDrawEntries(drawConfig)

	for index, frame in frames do
		local entry = bestEntries[index]
		if entry == nil then
			continue
		end

		local info = frame:FindFirstChild("Info")
		if info == nil or not info:IsA("Frame") then
			warn(`[DrawController] missing Info frame inside {frame:GetFullName()}`)
			continue
		end

		local rarityLabel = info:FindFirstChild("Rarity")
		local titleLabel = info:FindFirstChild("Title")

		if rarityLabel ~= nil and rarityLabel:IsA("TextLabel") then
			rarityLabel.Text = tostring(entry.Rarity)
		else
			warn(`[DrawController] missing Info.Rarity TextLabel inside {frame:GetFullName()}`)
		end

		if titleLabel ~= nil and titleLabel:IsA("TextLabel") then
			titleLabel.Text = getInventoryDisplayName(entry.Category, entry.ItemId)
		else
			warn(`[DrawController] missing Info.Title TextLabel inside {frame:GetFullName()}`)
		end
	end
end

local function updateCurrencyLabels()
	local coins = localPlayer:GetAttribute("Coins") or 0
	local skinTokens = localPlayer:GetAttribute("SkinTokens") or 0

	if coinsText ~= nil then
		coinsText.Text = tostring(coins)
	end

	if gemsText ~= nil then
		gemsText.Text = tostring(skinTokens)
	end
end

local function updateDrawPrices()
	local drawConfig = getDrawConfig(currentDrawId)
	if drawConfig == nil then
		return
	end

	local cost = drawConfig.Cost
	local totalCost = cost * currentCount

	if price1x ~= nil then
		price1x.Text = tostring(cost)
	end

	if price5x ~= nil then
		price5x.Text = tostring(cost * 5)
	end

	if coinsDrawPrice ~= nil then
		coinsDrawPrice.Text = tostring(totalCost)
	end

	if gemsDrawPrice ~= nil then
		gemsDrawPrice.Text = tostring(totalCost)
	end
end

local function setSpinTypeButtonVisual(button: TextButton, selected: boolean)
	button:SetAttribute(SELECTED_ATTRIBUTE, selected)
	button.BackgroundColor3 = if selected then selectButtonColors.Selected else selectButtonColors.Unselected
end

local function updateSpinTypeButtonsVisual()
	for _, instance in spinTypesButtons do
		if not instance:IsDescendantOf(playerGui) then
			continue
		end

		if not instance:IsA("TextButton") then
			continue
		end

		local button = instance :: TextButton
		local drawId = button:GetAttribute(DRAW_ID_ATTRIBUTE)
		local isSelected = drawId == currentDrawId

		setSpinTypeButtonVisual(button, isSelected)
	end
end

local function setCurrentDraw(drawId: string)
	local drawConfig = getDrawConfig(drawId)
	if drawConfig == nil then
		return
	end

	currentDrawId = drawId

	print(`[DrawController] selected draw: {drawId}`)
	print(`[DrawController] display name: {drawConfig.DisplayName}`)
	print(`[DrawController] cost: {drawConfig.Cost}`)

	updateDrawPrices()
	updateSpinItems()
	updateSpinTypeButtonsVisual()
end

local function setCurrentCount(count: number)
	currentCount = count

	print(`[DrawController] selected count: {count}`)
	updateDrawPrices()
end

local function connectSpinTypeButtons()
	print("[DrawController] connect spin type buttons")

	spinTypesButtons = CollectionService:GetTagged("SPIN_TYPE_BUTTON")

	for _, instance in spinTypesButtons do
		if not instance:IsDescendantOf(playerGui) then
			continue
		end

		if not instance:IsA("TextButton") then
			warn(`[DrawController] SPIN_TYPE_BUTTON is not TextButton: {instance:GetFullName()}`)
			continue
		end

		local button = instance :: TextButton
		local drawId = button:GetAttribute(DRAW_ID_ATTRIBUTE)

		if type(drawId) ~= "string" then
			warn(`[DrawController] missing/invalid {DRAW_ID_ATTRIBUTE} attribute on {button:GetFullName()}`)
			continue
		end

		table.insert(
			connections,
			button.Activated:Connect(function()
				setCurrentDraw(drawId)
			end)
		)
	end

	updateSpinTypeButtonsVisual()
end

function DrawController:GetReferences()
	coinsText = getTextLabelByTag("SPIN_COINS")
	gemsText = getTextLabelByTag("SPIN_GEMS")

	spin1xButton = getTextButtonByTag("SPIN_1X_BUTTON")
	spin5xButton = getTextButtonByTag("SPIN_5X_BUTTON")

	gemsDrawPrice = getTextLabelByTag("GEMS_DRAW_PRICE")
	coinsDrawPrice = getTextLabelByTag("COINS_DRAW_PRICE")

	spinPrices = getFrameByTag("SPIN_PRICES")
	spinItems = getFrameByTag("SPIN_ITEMS")

	screen = getReferenceByTag('SPIN_SCREEN')

	foundPrice1x = spinPrices:FindFirstChild("x1", true)
	foundPrice5x = spinPrices:FindFirstChild("x5", true)
end

function DrawController:BuildUI()
	if didBuildUI then
		updateCurrencyLabels()
		updateDrawPrices()
		updateSpinItems()
		updateSpinTypeButtonsVisual()
		return
	end

	didBuildUI = true

	self:GetReferences()

	updateCurrencyLabels()
	updateDrawPrices()
	updateSpinItems()

	if spin1xButton ~= nil then
		table.insert(
			connections,
			spin1xButton.Activated:Connect(function()
				setCurrentCount(1)
				print(`[DrawController] spin 1x | drawId: {currentDrawId}`)
			end)
		)
	end

	if spin5xButton ~= nil then
		table.insert(
			connections,
			spin5xButton.Activated:Connect(function()
				setCurrentCount(5)
				print(`[DrawController] spin 5x | drawId: {currentDrawId}`)
			end)
		)
	end

	connectSpinTypeButtons()

	table.insert(connections, localPlayer:GetAttributeChangedSignal("Coins"):Connect(updateCurrencyLabels))
	table.insert(connections, localPlayer:GetAttributeChangedSignal("SkinTokens"):Connect(updateCurrencyLabels))
end

function DrawController:Open()
	updateCurrencyLabels()
	updateDrawPrices()
	updateSpinItems()
	updateSpinTypeButtonsVisual()
end

function DrawController:Start()
	print("[DrawController] started")

	if self._didStart then
		return
	end

	self._didStart = true
	self:BuildUI()
end

return DrawController