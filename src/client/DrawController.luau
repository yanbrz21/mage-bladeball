--!strict

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Network = Shared:WaitForChild("Network")

local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local InventoryConfig = require(Config:WaitForChild("InventoryConfig"))
local Remotes = require(Network:WaitForChild("Remotes"))

local HUD_SCREENGUI: ScreenGui?

local requestSkinDrawRemote = Remotes.GetClientToServer(
	Network,
	Remotes.ClientToServer.RequestSkinDraw
)

local skinDrawResultRemote = Remotes.GetServerToClient(
	Network,
	Remotes.ServerToClient.SkinDrawResult
)

local economyBalanceChangedRemote = Remotes.GetServerToClient(
	Network,
	Remotes.ServerToClient.EconomyBalanceChanged
)

local inventoryUpdatedRemote = Remotes.GetServerToClient(
	Network,
	Remotes.ServerToClient.InventoryUpdated
)

local DrawController = {
	Name = "DrawController",
}

local DRAW_ID_ATTRIBUTE = "ID"
local SELECTED_ATTRIBUTE = "SELECTED"

local GACHA_PART_TAG = "GACHA_PART"
local GACHA_PART_MARGIN = 2.5
local GACHA_PART_CHECK_INTERVAL = 0.1

local ROLL_CLONE_ATTRIBUTE = "IS_ROLL_CLONE"
local ROLL_TEMPLATE_ATTRIBUTE = "IS_ROLL_TEMPLATE"

local ROLL_LEAD_CARD_COUNT = 24
local ROLL_TRAIL_CARD_COUNT = 5
local ROLL_DURATION_SECONDS = 2.15
local ROLL_RESULT_WAIT_SECONDS = 1

local SELECTED_STROKE_COLOR = Color3.fromRGB(193, 134, 251)
local UNSELECTED_STROKE_COLOR = Color3.fromRGB(38, 38, 38)

local rarityRank = {
	Common = 1,
	Rare = 2,
	Epic = 3,
	Legendary = 4,
	Mythic = 5,
}

local rarityColors = {
	Common = Color3.fromRGB(178, 183, 205),
	Rare = Color3.fromRGB(89, 171, 255),
	Epic = Color3.fromRGB(184, 110, 255),
	Legendary = Color3.fromRGB(255, 150, 25),
	Mythic = Color3.fromRGB(255, 70, 97),
}

type SkinDrawRewardPayload = {
	category: string,
	itemId: string,
	displayName: string,
	rarity: string,
	isNew: boolean,
	duplicateConversionType: string?,
	duplicateConversionAmount: number?,
}

type SkinDrawResultPayload = {
	success: boolean,
	code: string,
	drawId: string,
	count: number,
	totalCost: number?,
	skinTokensAwarded: number?,
	abilityFragmentsAwarded: number?,
	balanceBefore: number?,
	balanceAfter: number?,
	skinTokensBefore: number?,
	skinTokensAfter: number?,
	rewards: { SkinDrawRewardPayload },
}

type RollVisualItem = {
	category: string,
	itemId: string,
	displayName: string,
	rarity: string,
}

local screen: Instance?

local coinsText: TextLabel?

local spinItems: Frame?

local spin1xButton: TextButton?
local spin5xButton: TextButton?

local drawButton: GuiButton?
local drawClose: GuiObject?

local gemsDrawPrice: TextLabel?
local coinsDrawPrice: TextLabel?

local spinPrices: Frame?
local price1x: TextLabel?
local price5x: TextLabel?

local rngFrame: Frame?
local chooseDrawFrame: Frame?
local oddsFrame: Frame?

local rollExplanationText: TextLabel?
local skipDrawButton: TextButton?
local rollScrollingFrame: ScrollingFrame?

local spinTypesButtons: { Instance } = {}

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local currentDrawId = "NormalAbilityDraw"
local currentCount = 1
local currentBalance = 0

local lastGachaPartCheck = 0
local isWatchingGachaPart = false
local wasInsideGachaPart = false

local isDrawing = false
local isRolling = false
local isWaitingForDrawResult = false
local isRollFinished = false
local rollToken = 0
local rollTween: Tween?
local latestDrawResult: SkinDrawResultPayload?

local connections: { RBXScriptConnection } = {}
local didBuildUI = false

function DrawController:Init(context)
	if self._didInit then
		return
	end

	self._didInit = true
	self._context = context
	self._localPlayer = localPlayer
	self._connections = connections
	self._screen = screen
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

local function getOptionalReferenceByTag(tag: string): Instance?
	local items = CollectionService:GetTagged(tag)

	for _, item in items do
		if item:IsDescendantOf(playerGui) then
			return item
		end
	end

	return nil
end

local function setScreenEnabled(enabled: boolean)
	if screen == nil then
		return
	end

	if screen:IsA("ScreenGui") then
		screen.Enabled = enabled
	elseif screen:IsA("GuiObject") then
		screen.Visible = enabled
	end
end

local function setGuiVisible(instance: Instance?, visible: boolean)
	if instance == nil then
		return
	end

	if instance:IsA("ScreenGui") then
		instance.Enabled = visible
	elseif instance:IsA("GuiObject") then
		instance.Visible = visible
	elseif instance:IsA("Frame") then
		instance.Visible = visible
	end
end

local function setHudVisible(visible: boolean)
	setGuiVisible(HUD_SCREENGUI, visible)
end

local function getGachaBasePart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("Model") then
		local primaryPart = instance.PrimaryPart
		if primaryPart ~= nil then
			return primaryPart
		end

		local foundPart = instance:FindFirstChildWhichIsA("BasePart", true)
		if foundPart ~= nil then
			return foundPart
		end
	end

	return nil
end

local function isPositionInsidePart(part: BasePart, worldPosition: Vector3): boolean
	local localPosition = part.CFrame:PointToObjectSpace(worldPosition)
	local halfSize = part.Size * 0.5

	return math.abs(localPosition.X) <= halfSize.X + GACHA_PART_MARGIN
		and math.abs(localPosition.Y) <= halfSize.Y + GACHA_PART_MARGIN
		and math.abs(localPosition.Z) <= halfSize.Z + GACHA_PART_MARGIN
end

local function isInsideAnyGachaPart(): boolean
	local character = localPlayer.Character
	if character == nil then
		return false
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return false
	end

	for _, taggedInstance in CollectionService:GetTagged(GACHA_PART_TAG) do
		local gachaPart = getGachaBasePart(taggedInstance)

		if gachaPart ~= nil and gachaPart:IsDescendantOf(workspace) then
			if isPositionInsidePart(gachaPart, rootPart.Position) then
				return true
			end
		end
	end

	return false
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

local function getRarityColor(rarity: string): Color3
	return rarityColors[rarity] or Color3.fromRGB(167, 157, 194)
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

local function formatPercent(value: number): string
	if value <= 0 then
		return "0%"
	end

	if value >= 10 then
		return string.format("%.1f%%", value)
	end

	return string.format("%.2f%%", value)
end

local function getDrawRarityOdds(drawConfig): { [string]: number }
	local rarityWeights = {}
	local totalWeight = 0

	for _, entry in drawConfig.Entries do
		local rarity = entry.Rarity
		local weight = entry.Weight

		if type(rarity) ~= "string" or typeof(weight) ~= "number" then
			continue
		end

		totalWeight += weight
		rarityWeights[rarity] = (rarityWeights[rarity] or 0) + weight
	end

	local rarityOdds = {}

	if totalWeight <= 0 then
		return rarityOdds
	end

	for rarity, weight in rarityWeights do
		rarityOdds[rarity] = (weight / totalWeight) * 100
	end

	return rarityOdds
end

local function updateOddsFrame()
	if oddsFrame == nil then
		return
	end

	local drawConfig = getDrawConfig(currentDrawId)
	if drawConfig == nil then
		return
	end

	local rarityOdds = getDrawRarityOdds(drawConfig)

	for _, rarityFrame in oddsFrame:GetChildren() do
		if not rarityFrame:IsA("GuiObject") then
			continue
		end

		local rarityName = rarityFrame.Name
		local percentLabel = rarityFrame:FindFirstChild("Percentage")

		if percentLabel == nil or not percentLabel:IsA("TextLabel") then
			warn(`[DrawController] missing Percentage TextLabel inside odds rarity frame: {rarityFrame:GetFullName()}`)
			continue
		end

		local rarityLabel = rarityFrame:FindFirstChild("Rarity")

		if rarityLabel ~= nil and rarityLabel:IsA("TextLabel") then
			rarityLabel.Text = rarityName
			rarityLabel.TextColor3 = getRarityColor(rarityName)
		end

		local percent = rarityOdds[rarityName] or 0
		percentLabel.Text = formatPercent(percent)
	end
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
			rarityLabel.TextColor3 = getRarityColor(entry.Rarity)
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

local function readBalanceAttribute()
	local coins = localPlayer:GetAttribute("Coins")
	currentBalance = if typeof(coins) == "number" then coins else 0
end

local function updateCurrencyLabels()
	readBalanceAttribute()

	local skinTokens = localPlayer:GetAttribute("SkinTokens") or 0

	if coinsText ~= nil then
		coinsText.Text = tostring(currentBalance)
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

	local deco = button:FindFirstChild("Deco")
	if deco ~= nil then
		local glow = deco:FindFirstChild("Glow", true)

		if glow ~= nil and glow:IsA("GuiObject") then
			glow.Visible = selected
		end
	end

	local inner = button:FindFirstChild("Inner", true)
	if inner ~= nil and inner:IsA("UIStroke") then
		inner.Color = if selected then SELECTED_STROKE_COLOR else UNSELECTED_STROKE_COLOR
	end
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
	updateOddsFrame()
	updateSpinTypeButtonsVisual()
end

local function setCurrentCount(count: number)
	currentCount = count
	print(`[DrawController] selected count: {count}`)
	updateDrawPrices()
end

local function setSkipButtonTitle(text: string)
	if skipDrawButton == nil then
		return
	end

	local title = skipDrawButton:FindFirstChild("Title", true)

	if title ~= nil and title:IsA("TextLabel") then
		title.Text = text
		return
	end

	skipDrawButton.Text = text
end

local function setRollExplanation(text: string)
	if rollExplanationText ~= nil then
		rollExplanationText.Text = text
	end
end

local function clearRollClones()
	if rollScrollingFrame == nil then
		return
	end

	for _, child in rollScrollingFrame:GetChildren() do
		if child:GetAttribute(ROLL_CLONE_ATTRIBUTE) == true then
			child:Destroy()
		end
	end

	rollScrollingFrame.CanvasPosition = Vector2.new(0, rollScrollingFrame.CanvasPosition.Y)
end

local function ensureRollListLayout(): UIListLayout?
	if rollScrollingFrame == nil then
		return nil
	end

	local existingLayout = rollScrollingFrame:FindFirstChildWhichIsA("UIListLayout")

	if existingLayout ~= nil then
		existingLayout.FillDirection = Enum.FillDirection.Horizontal
		existingLayout.SortOrder = Enum.SortOrder.LayoutOrder
		return existingLayout
	end

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 12)
	layout.Parent = rollScrollingFrame

	return layout
end

local function findRollTemplateByRarity(rarity: string): GuiObject?
	if rollScrollingFrame == nil then
		return nil
	end

	local upperRarity = string.upper(rarity)

	local namesToTry = {
		rarity,
		upperRarity,
		`{rarity}Template`,
		`{upperRarity}_TEMPLATE`,
		`{upperRarity}TEMPLATE`,
	}

	for _, name in namesToTry do
		local found = rollScrollingFrame:FindFirstChild(name, true)

		if found ~= nil and found:IsA("GuiObject") and found:GetAttribute(ROLL_CLONE_ATTRIBUTE) ~= true then
			found:SetAttribute(ROLL_TEMPLATE_ATTRIBUTE, true)
			return found
		end
	end

	warn(`[DrawController] missing roll template for rarity: {rarity}`)
	return nil
end

local function findFirstTextLabel(parent: Instance, names: { string }): TextLabel?
	for _, name in names do
		local found = parent:FindFirstChild(name, true)

		if found ~= nil and found:IsA("TextLabel") then
			return found
		end
	end

	return nil
end

local function setRollCloneInfo(clone: GuiObject, item: RollVisualItem)
	local titleLabel = findFirstTextLabel(clone, { "Title", "Name", "ItemName" })
	local rarityLabel = findFirstTextLabel(clone, { "Rarity" })

	if titleLabel ~= nil then
		titleLabel.Text = item.displayName
	end

	if rarityLabel ~= nil then
		rarityLabel.Text = item.rarity
		rarityLabel.TextColor3 = getRarityColor(item.rarity)
	end
end

local function createRollClone(item: RollVisualItem, layoutOrder: number): GuiObject?
	if rollScrollingFrame == nil then
		return nil
	end

	local template = findRollTemplateByRarity(item.rarity)
	if template == nil then
		return nil
	end

	local clone = template:Clone()
	clone.Name = `ROLL_{layoutOrder}_{item.itemId}`
	clone.Visible = true
	clone.LayoutOrder = layoutOrder
	clone:SetAttribute(ROLL_CLONE_ATTRIBUTE, true)
	clone:SetAttribute("ITEM_ID", item.itemId)
	clone:SetAttribute("RARITY", item.rarity)
	clone:SetAttribute("CATEGORY", item.category)
	clone.Parent = rollScrollingFrame

	setRollCloneInfo(clone, item)

	return clone
end

local function getRollVisualItemFromEntry(entry): RollVisualItem
	return {
		category = entry.Category,
		itemId = entry.ItemId,
		displayName = getInventoryDisplayName(entry.Category, entry.ItemId),
		rarity = entry.Rarity,
	}
end

local function getRollVisualItemFromReward(reward: SkinDrawRewardPayload): RollVisualItem
	return {
		category = reward.category,
		itemId = reward.itemId,
		displayName = reward.displayName,
		rarity = reward.rarity,
	}
end

local function getSortedRollEntries(drawConfig): { any }
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

		return getInventoryDisplayName(a.Category, a.ItemId) < getInventoryDisplayName(b.Category, b.ItemId)
	end)

	return entries
end

local function buildRollVisualItems(drawConfig, reward: SkinDrawRewardPayload): ({ RollVisualItem }, number)
	local entries = getSortedRollEntries(drawConfig)
	local targetItem = getRollVisualItemFromReward(reward)

	if #entries <= 0 then
		return { targetItem }, 1
	end

	local items = {} :: { RollVisualItem }

	for index = 1, ROLL_LEAD_CARD_COUNT do
		local entry = entries[((index - 1) % #entries) + 1]
		table.insert(items, getRollVisualItemFromEntry(entry))
	end

	local targetIndex = #items + 1
	table.insert(items, targetItem)

	for index = 1, ROLL_TRAIL_CARD_COUNT do
		local entry = entries[((index - 1) % #entries) + 1]
		table.insert(items, getRollVisualItemFromEntry(entry))
	end

	return items, targetIndex
end

local function updateRollCanvasSize()
	if rollScrollingFrame == nil then
		return
	end

	local layout = rollScrollingFrame:FindFirstChildWhichIsA("UIListLayout")

	if layout ~= nil then
		rollScrollingFrame.CanvasSize = UDim2.fromOffset(layout.AbsoluteContentSize.X, 0)
	end
end

local function getTargetCanvasPosition(targetClone: GuiObject): Vector2
	if rollScrollingFrame == nil then
		return Vector2.zero
	end

	local targetCenterX = targetClone.AbsolutePosition.X
		- rollScrollingFrame.AbsolutePosition.X
		+ rollScrollingFrame.CanvasPosition.X
		+ (targetClone.AbsoluteSize.X * 0.5)

	local viewportCenterX = rollScrollingFrame.AbsoluteSize.X * 0.5
	local wantedX = math.max(0, targetCenterX - viewportCenterX)

	return Vector2.new(wantedX, rollScrollingFrame.CanvasPosition.Y)
end

local function stopRollTween()
	if rollTween ~= nil then
		rollTween:Cancel()
		rollTween = nil
	end
end

local function finishRollUi()
	isRolling = false
	isDrawing = false
	isWaitingForDrawResult = false
	isRollFinished = true

	stopRollTween()
	setSkipButtonTitle("CLAIM")
end

local function claimRollUi()
	isRolling = false
	isDrawing = false
	isWaitingForDrawResult = false
	isRollFinished = false
	latestDrawResult = nil
	rollToken += 1

	stopRollTween()
	clearRollClones()

	setGuiVisible(rngFrame, false)
	setGuiVisible(chooseDrawFrame, true)
	setSkipButtonTitle("SKIP")
	setRollExplanation("")

	updateCurrencyLabels()
	updateDrawPrices()
	updateSpinItems()
	updateOddsFrame()
	updateSpinTypeButtonsVisual()
end

local function skipRoll()
	local result = latestDrawResult

	if result == nil then
		claimRollUi()
		return
	end

	rollToken += 1
	stopRollTween()
	clearRollClones()

	local lastReward = result.rewards[#result.rewards]
	if lastReward ~= nil then
		local visualItem = getRollVisualItemFromReward(lastReward)
		createRollClone(visualItem, 1)
		setRollExplanation(lastReward.displayName)
	end

	finishRollUi()
end

local function playSingleRoll(
	token: number,
	drawConfig,
	reward: SkinDrawRewardPayload,
	index: number,
	total: number
): boolean
	if rollScrollingFrame == nil then
		return false
	end

	clearRollClones()
	ensureRollListLayout()

	rollScrollingFrame.CanvasPosition = Vector2.new(0, rollScrollingFrame.CanvasPosition.Y)

	local visualItems, targetIndex = buildRollVisualItems(drawConfig, reward)
	local targetClone: GuiObject?

	for itemIndex, item in visualItems do
		local clone = createRollClone(item, itemIndex)

		if itemIndex == targetIndex then
			targetClone = clone
		end
	end

	task.wait()
	updateRollCanvasSize()
	task.wait()

	if token ~= rollToken then
		return false
	end

	if targetClone == nil then
		return false
	end

	setRollExplanation("Rolling...")

	local targetCanvasPosition = getTargetCanvasPosition(targetClone)

	local tween = TweenService:Create(
		rollScrollingFrame,
		TweenInfo.new(ROLL_DURATION_SECONDS, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{
			CanvasPosition = targetCanvasPosition,
		}
	)

	rollTween = tween

	local completed = false
	local completedConnection = tween.Completed:Connect(function()
		completed = true
	end)

	tween:Play()

	while not completed and token == rollToken do
		task.wait(0.03)
	end

	completedConnection:Disconnect()

	if rollTween == tween then
		rollTween = nil
	end

	if token ~= rollToken then
		return false
	end

	rollScrollingFrame.CanvasPosition = targetCanvasPosition
	setRollExplanation(reward.displayName)

	task.wait(ROLL_RESULT_WAIT_SECONDS)

	return token == rollToken
end

local function startRollSequence(result: SkinDrawResultPayload)
	local drawConfig = getDrawConfig(result.drawId)
	if drawConfig == nil then
		isDrawing = false
		isWaitingForDrawResult = false
		return
	end

	latestDrawResult = result
	isRolling = true
	isDrawing = true
	isWaitingForDrawResult = false
	isRollFinished = false
	rollToken += 1

	local token = rollToken

	setGuiVisible(chooseDrawFrame, false)
	setGuiVisible(rngFrame, true)
	setSkipButtonTitle("SKIP")
	setRollExplanation("Rolling...")

	task.spawn(function()
		for index, reward in result.rewards do
			if token ~= rollToken then
				return
			end

			local completed = playSingleRoll(token, drawConfig, reward, index, #result.rewards)
			if not completed then
				return
			end
		end

		if token == rollToken then
			finishRollUi()
		end
	end)
end

local function getDrawResultMessage(result: SkinDrawResultPayload): string
	if result.success then
		return "draw complete"
	end

	if result.code == "InsufficientCoins" then
		return "not enough coins"
	elseif result.code == "ProfileNotLoaded" then
		return "profile still loading"
	elseif result.code == "InvalidDraw" then
		return "draw unavailable"
	elseif result.code == "DirtyMarkFailed" then
		return "could not save draw"
	end

	return result.code
end

local function handleSkinDrawResult(payload: SkinDrawResultPayload)
	if payload.balanceAfter ~= nil then
		currentBalance = payload.balanceAfter
	end

	updateCurrencyLabels()
	updateDrawPrices()

	if not payload.success then
		isDrawing = false
		isRolling = false
		isWaitingForDrawResult = false

		setGuiVisible(chooseDrawFrame, true)
		setGuiVisible(rngFrame, false)

		warn(`[DrawController] draw failed: {getDrawResultMessage(payload)}`)
		return
	end

	if #payload.rewards <= 0 then
		isDrawing = false
		isRolling = false
		isWaitingForDrawResult = false

		warn("[DrawController] draw succeeded but returned no rewards")
		return
	end

	startRollSequence(payload)
end

local function requestDraw(count: number)
	if isDrawing or isRolling or isWaitingForDrawResult then
		return
	end

	local drawConfig = getDrawConfig(currentDrawId)
	if drawConfig == nil then
		return
	end

	readBalanceAttribute()

	local cost = drawConfig.Cost * count
	if currentBalance < cost then
		warn(`[DrawController] not enough coins. need {math.max(0, cost - currentBalance)} more coins`)
		return
	end

	setCurrentCount(count)

	isDrawing = true
	isWaitingForDrawResult = true
	isRollFinished = false

	setGuiVisible(chooseDrawFrame, false)
	setGuiVisible(rngFrame, true)
	setSkipButtonTitle("SKIP")
	setRollExplanation("Rolling...")
	clearRollClones()

	requestSkinDrawRemote:FireServer({
		drawId = currentDrawId,
		count = count,
	})
end

local function onDrawButtonClicked(count: number)
	requestDraw(count)
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

local function closeDrawUi()
	setScreenEnabled(false)
	setHudVisible(true)
end

local function connectDrawClose()
	if drawClose == nil then
		warn("[DrawController] draw close not found")
		return
	end

	if drawClose:IsA("GuiButton") then
		table.insert(
			connections,
			drawClose.Activated:Connect(function()
				closeDrawUi()
			end)
		)

		return
	end

	drawClose.Active = true

	table.insert(
		connections,
		drawClose.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				closeDrawUi()
			end
		end)
	)
end

local function startGachaPartWatcher()
	if isWatchingGachaPart then
		return
	end

	isWatchingGachaPart = true
	wasInsideGachaPart = false

	table.insert(
		connections,
		RunService.Heartbeat:Connect(function()
			local now = os.clock()

			if now - lastGachaPartCheck < GACHA_PART_CHECK_INTERVAL then
				return
			end

			lastGachaPartCheck = now

			local isInside = isInsideAnyGachaPart()

			if isInside and not wasInsideGachaPart then
				DrawController:Open()
			end

			wasInsideGachaPart = isInside
		end)
	)

	table.insert(
		connections,
		localPlayer.CharacterAdded:Connect(function()
			wasInsideGachaPart = false
			setScreenEnabled(false)
			setHudVisible(true)
		end)
	)
end

function DrawController:GetReferences()
	coinsText = getReferenceByTag("SPIN_COINS") :: TextLabel?

	spin1xButton = getReferenceByTag("SPIN_1X_BUTTON") :: TextButton?
	spin5xButton = getReferenceByTag("SPIN_5X_BUTTON") :: TextButton?

	drawButton = getOptionalReferenceByTag("DRAW_BUTTON") :: GuiButton?

	gemsDrawPrice = getReferenceByTag("GEMS_DRAW_PRICE") :: TextLabel?
	coinsDrawPrice = getReferenceByTag("COINS_DRAW_PRICE") :: TextLabel?

	spinPrices = getReferenceByTag("SPIN_PRICES") :: Frame?
	spinItems = getReferenceByTag("SPIN_ITEMS") :: Frame?

	screen = getReferenceByTag("SPIN_SCREEN") :: ScreenGui?

	chooseDrawFrame = getReferenceByTag("CHOOSE_DRAW_FRAME") :: Frame?
	rngFrame = getReferenceByTag("RNG_FRAME") :: Frame?
	oddsFrame = getReferenceByTag("ODDS_FRAME") :: Frame?

	rollScrollingFrame = getReferenceByTag("ROLL_SCROLLING_FRAME") :: ScrollingFrame?
	skipDrawButton = getReferenceByTag("ROLL_SKIP_BUTTON") :: TextButton?
	rollExplanationText = getReferenceByTag("ROLL_EXPLANATION_TEXT") :: TextLabel?

	HUD_SCREENGUI = getReferenceByTag("SIDEMENU") :: ScreenGui?

	local foundDrawClose = getOptionalReferenceByTag("DRAW_CLOSE")
		or getOptionalReferenceByTag("DRAWCLOSE")
		or getOptionalReferenceByTag("DRAW_CLOSE_BUTTON")

	if foundDrawClose ~= nil and foundDrawClose:IsA("GuiObject") then
		drawClose = foundDrawClose
	end

	if spinPrices ~= nil then
		local foundPrice1x = spinPrices:FindFirstChild("x1", true)
		local foundPrice5x = spinPrices:FindFirstChild("x5", true)

		if foundPrice1x ~= nil and foundPrice1x:IsA("TextLabel") then
			price1x = foundPrice1x
		end

		if foundPrice5x ~= nil and foundPrice5x:IsA("TextLabel") then
			price5x = foundPrice5x
		end
	end
end

function DrawController:BuildUI()
	if didBuildUI then
		updateCurrencyLabels()
		updateDrawPrices()
		updateSpinItems()
		updateOddsFrame()
		updateSpinTypeButtonsVisual()
		return
	end

	didBuildUI = true

	self:GetReferences()

	setScreenEnabled(false)
	setHudVisible(true)
	startGachaPartWatcher()

	setGuiVisible(chooseDrawFrame, true)
	setGuiVisible(rngFrame, false)
	setSkipButtonTitle("SKIP")

	updateCurrencyLabels()
	updateDrawPrices()
	updateSpinItems()
	updateOddsFrame()

	if drawButton ~= nil then
		print("[DrawController] draw button connected")

		table.insert(
			connections,
			drawButton.Activated:Connect(function()
				print("[DrawController] draw button clicked")
				DrawController:Open()
			end)
		)
	else
		warn("[DrawController] draw button not found")
	end

	connectDrawClose()

	if spin1xButton ~= nil then
		table.insert(
			connections,
			spin1xButton.Activated:Connect(function()
				onDrawButtonClicked(1)
			end)
		)
	end

	if spin5xButton ~= nil then
		table.insert(
			connections,
			spin5xButton.Activated:Connect(function()
				onDrawButtonClicked(5)
			end)
		)
	end

	if skipDrawButton ~= nil then
		table.insert(
			connections,
			skipDrawButton.Activated:Connect(function()
				if isRolling or isWaitingForDrawResult then
					skipRoll()
					return
				end

				if isRollFinished then
					claimRollUi()
					return
				end
			end)
		)
	end

	connectSpinTypeButtons()

	table.insert(connections, localPlayer:GetAttributeChangedSignal("Coins"):Connect(function()
		updateCurrencyLabels()
		updateDrawPrices()
	end))

	table.insert(connections, localPlayer:GetAttributeChangedSignal("SkinTokens"):Connect(updateCurrencyLabels))

	table.insert(connections, economyBalanceChangedRemote.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end

		local balance = payload.balance
		if typeof(balance) == "number" then
			currentBalance = balance
		end

		updateCurrencyLabels()
		updateDrawPrices()
	end))

	table.insert(connections, inventoryUpdatedRemote.OnClientEvent:Connect(function()
		updateSpinItems()
	end))

	table.insert(connections, skinDrawResultRemote.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end

		handleSkinDrawResult(payload :: SkinDrawResultPayload)
	end))
end

function DrawController:Open()
	setScreenEnabled(true)
	setHudVisible(false)

	if not isDrawing and not isRolling and not isWaitingForDrawResult and not isRollFinished then
		setGuiVisible(chooseDrawFrame, true)
		setGuiVisible(rngFrame, false)
		setSkipButtonTitle("SKIP")
		setRollExplanation("")
	end

	updateCurrencyLabels()
	updateDrawPrices()
	updateSpinItems()
	updateOddsFrame()
	updateSpinTypeButtonsVisual()
end

function DrawController:Close()
	closeDrawUi()
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