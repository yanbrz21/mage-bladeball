--!strict

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Network = Shared:WaitForChild("Network")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local DrawConfig = require(Config:WaitForChild("DrawConfig"))
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local EventBus = require(Packages.CommonKit.EventBus)
local InventoryConfig = require(Config:WaitForChild("InventoryConfig"))
local MatchConfig = require(Config:WaitForChild("MatchConfig"))
local Remotes = require(Network:WaitForChild("Remotes"))

local HUD_SCREENGUI: ScreenGui?

local requestSkinDrawRemote = Remotes.GetClientToServer(Network, Remotes.ClientToServer.RequestSkinDraw)

local skinDrawResultRemote = Remotes.GetServerToClient(Network, Remotes.ServerToClient.SkinDrawResult)

local economyBalanceChangedRemote = Remotes.GetServerToClient(Network, Remotes.ServerToClient.EconomyBalanceChanged)

local inventoryUpdatedRemote = Remotes.GetServerToClient(Network, Remotes.ServerToClient.InventoryUpdated)

local DrawController = {
	Name = "DrawController",
}

local DRAW_ID_ATTRIBUTE = "ID"
local SELECTED_ATTRIBUTE = "SELECTED"
local AUDIO_CLICK_EVENT_ATTRIBUTE = "AudioClickEvent"
local TAB_SWITCH_AUDIO_EVENT = "TabSwitch"
local SPIN_TYPE_CONNECTED_ATTRIBUTE = "ParabellumSpinTypeConnected"
local DRAW_KIND_COIN = "Coin"
local DRAW_KIND_ROBUX = "Robux"
local COIN_PRICE_ICON = "rbxassetid://87190121549893"
local ROBUX_PRICE_ICON = "rbxassetid://138110852462666"

local GACHA_PART_TAG = "GACHA_PART"
local GACHA_PART_MARGIN = 2.5
local GACHA_PART_CHECK_INTERVAL = 0.1

local ROLL_CLONE_ATTRIBUTE = "IS_ROLL_CLONE"
local ROLL_TEMPLATE_ATTRIBUTE = "IS_ROLL_TEMPLATE"

local ROLL_LEAD_CARD_COUNT = 48
local ROLL_TRAIL_CARD_COUNT = 7
local ROLL_DURATION_SECONDS = 3.25
local ROLL_RESULT_WAIT_SECONDS = 1.15
local ROLL_TICK_MIN_DISTANCE_PIXELS = 24
local ROLL_TICK_MIN_INTERVAL_SECONDS = 0.035
local LOCAL_DRAW_ROLL_TICK_EVENT = "Client.LocalDrawRollTick"
local LOCAL_DRAW_ROLL_STOPPED_EVENT = "Client.LocalDrawRollStopped"
local LOCAL_DRAW_RESULT_REVEALED_EVENT = "Client.LocalDrawResultRevealed"
local DRAW_ENTRY_CONNECTED_ATTRIBUTE = "ParabellumDrawEntryConnected"
local HIGHLIGHT_TEMPLATE_FOLDER_NAME = "Template"
local HIGHLIGHT_ITEM_TEMPLATE_NAME = "HighlightItem"
local HIGHLIGHT_GRADIENTS_FOLDER_NAME = "Gradients"
local HIGHLIGHT_ITEM_CLONE_ATTRIBUTE = "ParabellumHighlightItemClone"

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

local rarityHighlightStyles = {
	Common = {
		gradientName = "Blue",
	},
	Rare = {
		gradientName = "Blue",
	},
	Epic = {
		gradientName = "Purple",
	},
	Legendary = {
		gradientName = "Yellow",
	},
	Mythic = {
		gradientName = "Yellow",
	},
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

type ResolvedDraw = {
	drawId: string,
	kind: string,
	config: any,
}

type RobuxDrawProduct = {
	productKey: string,
	productId: number,
	robuxPrice: number,
	displayName: string,
	count: number,
}

type HighlightVisualEntry = {
	Category: string,
	ItemId: string,
	Weight: number?,
	exclusive: boolean,
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
local price1xIcon: ImageLabel?
local price5xIcon: ImageLabel?

local rngFrame: Frame?
local chooseDrawFrame: Frame?
local oddsFrame: Frame?

local rollExplanationText: TextLabel?
local skipDrawButton: TextButton?
local rollScrollingFrame: ScrollingFrame?

local spinTypesButtons: { Instance } = {}

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local currentDrawId = ""
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
	end
end

local function isGuiActionEnabled(instance: GuiObject): boolean
	if not instance.Visible then
		return false
	end

	if instance:IsA("GuiButton") then
		return instance.Active and instance.Interactable
	end

	return true
end

local function connectGuiAction(instance: GuiObject, callback: () -> ())
	local lastActionAt = 0

	local function fireAction()
		if not isGuiActionEnabled(instance) then
			return
		end

		local now = os.clock()
		if now - lastActionAt < 0.12 then
			return
		end

		lastActionAt = now
		callback()
	end

	if instance:IsA("GuiButton") then
		table.insert(connections, instance.Activated:Connect(fireAction))
	else
		instance.Active = true
	end

	table.insert(
		connections,
		instance.InputBegan:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				fireAction()
			end
		end)
	)
end

local function preventGuiResetOnSpawn(instance: Instance?)
	local current = instance
	while current ~= nil do
		if current:IsA("ScreenGui") then
			current.ResetOnSpawn = false
			return
		end

		current = current.Parent
	end
end

local function preventTaggedGuiResetOnSpawn(tag: string)
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsDescendantOf(playerGui) or instance:IsDescendantOf(StarterGui) then
			preventGuiResetOnSpawn(instance)
		end
	end
end

local function preventDrawGuiResetOnSpawn()
	preventTaggedGuiResetOnSpawn("DRAW_BUTTON")
	preventTaggedGuiResetOnSpawn("SIDEMENU")
	preventTaggedGuiResetOnSpawn("SPIN_SCREEN")
end

local function setHudVisible(visible: boolean)
	setGuiVisible(HUD_SCREENGUI, visible)
end

local function isLocalPlayerLockedForRound(): boolean
	local playerState = localPlayer:GetAttribute("PlayerState")
	return playerState == MatchConfig.PlayerStates.AliveInRound or playerState == MatchConfig.PlayerStates.DeadInRound
end

local function updateDrawEntryVisibility()
	local shouldShow = not isLocalPlayerLockedForRound()
	for _, instance in CollectionService:GetTagged("DRAW_BUTTON") do
		if instance:IsDescendantOf(playerGui) and instance:IsA("GuiObject") then
			instance.Visible = shouldShow
		end
	end
end

local function connectDrawEntryButton(instance: Instance)
	if not instance:IsDescendantOf(playerGui) or not instance:IsA("GuiButton") then
		return
	end

	preventGuiResetOnSpawn(instance)
	drawButton = instance
	instance.Visible = not isLocalPlayerLockedForRound()

	if instance:GetAttribute(DRAW_ENTRY_CONNECTED_ATTRIBUTE) == true then
		return
	end

	instance:SetAttribute(DRAW_ENTRY_CONNECTED_ATTRIBUTE, true)
	connectGuiAction(instance, function()
		print("[DrawController] draw button clicked")
		DrawController:Open()
	end)
end

local function syncDrawEntryButtons()
	preventDrawGuiResetOnSpawn()
	for _, instance in CollectionService:GetTagged("DRAW_BUTTON") do
		connectDrawEntryButton(instance)
	end
	updateDrawEntryVisibility()
end

local function handleDrawScreenAdded(instance: Instance)
	if not instance:IsDescendantOf(playerGui) then
		return
	end

	screen = instance
	preventGuiResetOnSpawn(instance)
	setScreenEnabled(false)
end

local function handleSideMenuAdded(instance: Instance)
	if not instance:IsDescendantOf(playerGui) then
		return
	end

	HUD_SCREENGUI = instance :: any
	preventGuiResetOnSpawn(instance)
	setHudVisible(true)
	syncDrawEntryButtons()
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

local function resolveDraw(drawId: string): ResolvedDraw?
	local drawCatalog = DrawConfig.DrawCatalog :: any
	local coinDrawConfig = drawCatalog[drawId]

	if type(coinDrawConfig) == "table" then
		return {
			drawId = drawId,
			kind = DRAW_KIND_COIN,
			config = coinDrawConfig,
		}
	end

	local robuxDrawCatalog = DrawConfig.RobuxDrawCatalog :: any
	local robuxDrawConfig = robuxDrawCatalog[drawId]

	if type(robuxDrawConfig) == "table" then
		return {
			drawId = drawId,
			kind = DRAW_KIND_ROBUX,
			config = robuxDrawConfig,
		}
	end

	warn(`[DrawController] invalid draw id: {drawId}`)
	return nil
end

local function getDrawConfig(drawId: string)
	local resolvedDraw = resolveDraw(drawId)
	return if resolvedDraw ~= nil then resolvedDraw.config else nil
end

local function getDefaultDrawId(): string
	for _, drawId in DrawConfig.DrawOrder do
		if type(drawId) == "string" and resolveDraw(drawId) ~= nil then
			return drawId
		end
	end

	return ""
end

local function findRobuxDrawProduct(drawId: string, count: number): RobuxDrawProduct?
	local robuxCatalog = EconomyConfig.RobuxShopCatalog :: any

	for productKey, productConfig in robuxCatalog do
		if type(productKey) ~= "string" or type(productConfig) ~= "table" then
			continue
		end

		local reward = productConfig.Reward
		if type(reward) ~= "table" then
			continue
		end

		if reward.Type ~= "RobuxDraw" or reward.DrawId ~= drawId or reward.Count ~= count then
			continue
		end

		local productId = productConfig.ProductId
		local robuxPrice = productConfig.RobuxPrice
		local displayName = productConfig.DisplayName
		if type(productId) ~= "number" or type(robuxPrice) ~= "number" or type(displayName) ~= "string" then
			continue
		end

		return {
			productKey = productKey,
			productId = productId,
			robuxPrice = robuxPrice,
			displayName = displayName,
			count = count,
		}
	end

	return nil
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

local function getInventoryRarity(category: string, itemId: string): string
	local categories = InventoryConfig.Categories :: any
	local categoryConfig = categories[category]

	if type(categoryConfig) ~= "table" then
		return "Common"
	end

	local items = categoryConfig.Items
	if type(items) ~= "table" then
		return "Common"
	end

	local itemConfig = items[itemId]
	if type(itemConfig) ~= "table" then
		return "Common"
	end

	local rarity = itemConfig.Rarity
	if type(rarity) ~= "string" or rarity == "" then
		return "Common"
	end

	return rarity
end

local function getRarityColor(rarity: string): Color3
	return rarityColors[rarity] or Color3.fromRGB(167, 157, 194)
end

local function getBestDrawEntries(drawConfig): { any }
	local entries = {}

	for _, entry in drawConfig.Entries do
		table.insert(entries, entry)
	end

	table.sort(entries, function(a, b)
		local leftRarity = getInventoryRarity(a.Category, a.ItemId)
		local rightRarity = getInventoryRarity(b.Category, b.ItemId)
		local leftRank = rarityRank[leftRarity] or 0
		local rightRank = rarityRank[rightRarity] or 0

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

local function getAutoHighlightEntries(drawConfig): { HighlightVisualEntry }
	local entries = {}

	for _, entry in getBestDrawEntries(drawConfig) do
		table.insert(entries, {
			Category = entry.Category,
			ItemId = entry.ItemId,
			Weight = entry.Weight,
			exclusive = false,
		})
	end

	return entries
end

local function getHighlightTemplateFolder(): Folder?
	if spinItems == nil then
		return nil
	end

	local templateFolder = spinItems:FindFirstChild(HIGHLIGHT_TEMPLATE_FOLDER_NAME)
	if templateFolder == nil or not templateFolder:IsA("Folder") then
		return nil
	end

	return templateFolder
end

local function getHighlightItemTemplate(): Frame?
	local templateFolder = getHighlightTemplateFolder()
	if templateFolder ~= nil then
		local template = templateFolder:FindFirstChild(HIGHLIGHT_ITEM_TEMPLATE_NAME)
		if template ~= nil and template:IsA("Frame") then
			template.Visible = false
			return template
		end

		warn("[DrawController] missing Template.HighlightItem under SPIN_ITEMS")
	end

	if spinItems == nil then
		return nil
	end

	for _, child in spinItems:GetChildren() do
		if child:IsA("Frame") and child:GetAttribute(HIGHLIGHT_ITEM_CLONE_ATTRIBUTE) ~= true then
			child.Visible = false
			return child
		end
	end

	warn("[DrawController] no highlight item template found")
	return nil
end

local function clearHighlightItemClones()
	if spinItems == nil then
		return
	end

	for _, child in spinItems:GetChildren() do
		if child:GetAttribute(HIGHLIGHT_ITEM_CLONE_ATTRIBUTE) == true then
			child:Destroy()
		elseif child:IsA("Frame") then
			child.Visible = false
		end
	end
end

local function getHighlightGradientSource(rarity: string): UIGradient?
	local style = rarityHighlightStyles[rarity]
	if style == nil then
		warn(`[DrawController] unsupported highlight rarity style: {rarity}`)
		style = rarityHighlightStyles.Rare
	end

	local templateFolder = getHighlightTemplateFolder()
	if templateFolder == nil then
		return nil
	end

	local gradientsFolder = templateFolder:FindFirstChild(HIGHLIGHT_GRADIENTS_FOLDER_NAME)
	if gradientsFolder == nil or not gradientsFolder:IsA("Folder") then
		warn("[DrawController] missing Template.Gradients under SPIN_ITEMS")
		return nil
	end

	local gradientName = style.gradientName
	local gradient = gradientsFolder:FindFirstChild(gradientName)
	if gradient ~= nil and gradient:IsA("UIGradient") then
		return gradient
	end

	warn(`[DrawController] missing highlight gradient source: {gradientName}`)
	return nil
end

local function applyGradientProperties(target: UIGradient, source: UIGradient)
	target.Color = source.Color
	target.Transparency = source.Transparency
	target.Rotation = source.Rotation
	target.Offset = source.Offset
	target.Enabled = source.Enabled
end

local function applyHighlightRarityStyle(frame: Frame, rarity: string)
	local deco = frame:FindFirstChild("Deco")
	if deco == nil then
		warn(`[DrawController] missing Deco folder inside {frame:GetFullName()}`)
		return
	end

	local bg = deco:FindFirstChild("Bg")
	if bg == nil or not bg:IsA("GuiObject") then
		warn(`[DrawController] missing Deco.Bg inside {frame:GetFullName()}`)
		return
	end

	local gradientSource = getHighlightGradientSource(rarity)
	if gradientSource == nil then
		return
	end

	local targetGradient = bg:FindFirstChildWhichIsA("UIGradient")
	if targetGradient == nil then
		local clonedGradient = gradientSource:Clone()
		clonedGradient.Name = "Gradient"
		clonedGradient.Parent = bg
	else
		applyGradientProperties(targetGradient, gradientSource)
	end
end

local function findDrawEntry(drawConfig, category: string, itemId: string): any?
	for _, entry in drawConfig.Entries do
		if entry.Category == category and entry.ItemId == itemId then
			return entry
		end
	end

	return nil
end

local function getHighlightDrawEntries(drawConfig): { HighlightVisualEntry }
	local highlights = drawConfig.Highlights
	if type(highlights) ~= "table" or #highlights <= 0 then
		return getAutoHighlightEntries(drawConfig)
	end

	local entries = {} :: { HighlightVisualEntry }

	for _, highlight in highlights do
		if type(highlight) ~= "table" then
			warn("[DrawController] draw highlight entries must be tables")
			continue
		end

		local highlightConfig = highlight :: any
		local category = highlightConfig.Category
		local itemId = highlightConfig.ItemId
		if type(category) ~= "string" or type(itemId) ~= "string" then
			warn("[DrawController] draw highlight entries need Category and ItemId")
			continue
		end

		local entry = findDrawEntry(drawConfig, category, itemId)
		if entry == nil then
			warn(`[DrawController] draw highlight item is not in entries: {category}:{itemId}`)
			continue
		end

		table.insert(entries, {
			Category = entry.Category,
			ItemId = entry.ItemId,
			Weight = entry.Weight,
			exclusive = highlightConfig.Exclusive == true,
		})
	end

	if #entries <= 0 then
		return getAutoHighlightEntries(drawConfig)
	end

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

	if type(drawConfig.RarityWeights) == "table" then
		for rarity, weight in drawConfig.RarityWeights do
			if type(rarity) ~= "string" or typeof(weight) ~= "number" then
				continue
			end

			totalWeight += weight
			rarityWeights[rarity] = (rarityWeights[rarity] or 0) + weight
		end
	else
		for _, entry in drawConfig.Entries do
			local rarity = getInventoryRarity(entry.Category, entry.ItemId)
			local weight = entry.Weight

			if type(rarity) ~= "string" or typeof(weight) ~= "number" then
				continue
			end

			totalWeight += weight
			rarityWeights[rarity] = (rarityWeights[rarity] or 0) + weight
		end
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
		local percent = rarityOdds[rarityName] or 0
		rarityFrame.Visible = percent > 0

		if percent <= 0 then
			continue
		end

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

		percentLabel.Text = formatPercent(percent)
	end
end

local function findHighlightTextLabel(root: Instance, name: string): TextLabel?
	local found = root:FindFirstChild(name, true)
	if found ~= nil and found:IsA("TextLabel") then
		return found
	end

	return nil
end

local function getHighlightInfoLabels(info: Frame): (TextLabel?, TextLabel?, TextLabel?)
	local titleLabel = findHighlightTextLabel(info, "Title")
	local badgeInfo = info:FindFirstChild("Info")

	if badgeInfo ~= nil and badgeInfo:IsA("Frame") then
		local rarityLabel = badgeInfo:FindFirstChild("Rarity")
		local exclusiveLabel = badgeInfo:FindFirstChild("Exclusive")

		return titleLabel,
			if rarityLabel ~= nil and rarityLabel:IsA("TextLabel")
				then rarityLabel
				else findHighlightTextLabel(info, "Rarity"),
			if exclusiveLabel ~= nil and exclusiveLabel:IsA("TextLabel")
				then exclusiveLabel
				else findHighlightTextLabel(info, "Exclusive")
	end

	return titleLabel, findHighlightTextLabel(info, "Rarity"), findHighlightTextLabel(info, "Exclusive")
end

local function updateSpinItems()
	local drawConfig = getDrawConfig(currentDrawId)
	if drawConfig == nil then
		return
	end

	clearHighlightItemClones()

	local template = getHighlightItemTemplate()
	if template == nil or spinItems == nil then
		return
	end

	local highlightEntries = getHighlightDrawEntries(drawConfig)

	for index, entry in highlightEntries do
		local frame = template:Clone()
		frame.Name = `HighlightItem_{index}`
		frame.LayoutOrder = index
		frame:SetAttribute(HIGHLIGHT_ITEM_CLONE_ATTRIBUTE, true)
		frame.Parent = spinItems

		local info = frame:FindFirstChild("Info")
		if info == nil or not info:IsA("Frame") then
			warn(`[DrawController] missing Info frame inside {frame:GetFullName()}`)
			frame.Visible = false
			continue
		end

		local titleLabel, rarityLabel, exclusiveLabel = getHighlightInfoLabels(info)
		local rarity = getInventoryRarity(entry.Category, entry.ItemId)
		applyHighlightRarityStyle(frame, rarity)

		if rarityLabel ~= nil and rarityLabel:IsA("TextLabel") then
			rarityLabel.Text = rarity
			rarityLabel.TextColor3 = getRarityColor(rarity)
		else
			warn(`[DrawController] missing Info.Rarity TextLabel inside {frame:GetFullName()}`)
		end

		if titleLabel ~= nil and titleLabel:IsA("TextLabel") then
			titleLabel.Text = getInventoryDisplayName(entry.Category, entry.ItemId)
		else
			warn(`[DrawController] missing Info.Title TextLabel inside {frame:GetFullName()}`)
		end

		if exclusiveLabel ~= nil and exclusiveLabel:IsA("TextLabel") then
			exclusiveLabel.Text = "Exclusive!"
			exclusiveLabel.Visible = entry.exclusive
		elseif entry.exclusive then
			warn(`[DrawController] missing Info.Exclusive TextLabel inside {frame:GetFullName()}`)
		end

		frame.Visible = true
	end
end

local function readBalanceAttribute()
	local coins = localPlayer:GetAttribute("Coins")
	currentBalance = if typeof(coins) == "number" then coins else 0
end

local function updateCurrencyLabels()
	readBalanceAttribute()

	if coinsText ~= nil then
		coinsText.Text = tostring(currentBalance)
	end
end

local function setButtonTitle(button: TextButton?, text: string)
	if button == nil then
		return
	end

	local title = button:FindFirstChild("Title", true)
	if title ~= nil and title:IsA("TextLabel") then
		title.Text = text
	else
		button.Text = text
	end
end

local function setDrawButtonEnabled(button: TextButton?, enabled: boolean)
	if button == nil then
		return
	end

	button.Active = enabled
	button.Interactable = enabled
	button.AutoButtonColor = enabled
	button.BackgroundTransparency = if enabled then 1 else 0.85
end

local function setPriceIcons(image: string)
	if price1xIcon ~= nil then
		price1xIcon.Image = image
	end

	if price5xIcon ~= nil then
		price5xIcon.Image = image
	end
end

local function isCoinDrawCountAllowed(drawConfig, count: number): boolean
	local allowedCounts = drawConfig.AllowedCounts
	if type(allowedCounts) ~= "table" then
		return false
	end

	for _, allowedCount in allowedCounts do
		if allowedCount == count then
			return true
		end
	end

	return false
end

local function updateDrawPrices()
	local resolvedDraw = resolveDraw(currentDrawId)
	if resolvedDraw == nil then
		return
	end

	if resolvedDraw.kind == DRAW_KIND_ROBUX then
		setPriceIcons(ROBUX_PRICE_ICON)

		local product1x = findRobuxDrawProduct(currentDrawId, 1)
		local product5x = findRobuxDrawProduct(currentDrawId, 5)

		if price1x ~= nil then
			price1x.Text = if product1x ~= nil then tostring(product1x.robuxPrice) else "--"
		end

		if price5x ~= nil then
			price5x.Text = if product5x ~= nil then tostring(product5x.robuxPrice) else "--"
		end

		if coinsDrawPrice ~= nil then
			coinsDrawPrice.Text = if product1x ~= nil then tostring(product1x.robuxPrice) else "--"
		end

		if gemsDrawPrice ~= nil then
			gemsDrawPrice.Text = if product5x ~= nil then tostring(product5x.robuxPrice) else "--"
		end

		if spin1xButton ~= nil then
			spin1xButton.Visible = product1x ~= nil
			setButtonTitle(spin1xButton, "Buy x1")
			setDrawButtonEnabled(spin1xButton, product1x ~= nil and product1x.productId > 0)
		end

		if spin5xButton ~= nil then
			spin5xButton.Visible = product5x ~= nil
			setButtonTitle(spin5xButton, "Buy x5")
			setDrawButtonEnabled(spin5xButton, product5x ~= nil and product5x.productId > 0)
		end

		return
	end

	setPriceIcons(COIN_PRICE_ICON)

	local drawConfig = resolvedDraw.config
	local cost = drawConfig.Cost
	if type(cost) ~= "number" or cost <= 0 then
		warn(`[DrawController] coin draw {currentDrawId} has invalid Cost`)
		setDrawButtonEnabled(spin1xButton, false)
		setDrawButtonEnabled(spin5xButton, false)
		return
	end

	local totalCost = cost * currentCount

	if price1x ~= nil then
		price1x.Text = if isCoinDrawCountAllowed(drawConfig, 1) then tostring(cost) else "--"
	end

	if price5x ~= nil then
		price5x.Text = if isCoinDrawCountAllowed(drawConfig, 5) then tostring(cost * 5) else "--"
	end

	if coinsDrawPrice ~= nil then
		coinsDrawPrice.Text = tostring(totalCost)
	end

	if gemsDrawPrice ~= nil then
		gemsDrawPrice.Text = tostring(totalCost)
	end

	if spin1xButton ~= nil then
		spin1xButton.Visible = true
		setButtonTitle(spin1xButton, "Draw x1")
		setDrawButtonEnabled(spin1xButton, isCoinDrawCountAllowed(drawConfig, 1))
	end

	if spin5xButton ~= nil then
		spin5xButton.Visible = true
		setButtonTitle(spin5xButton, "Draw x5")
		setDrawButtonEnabled(spin5xButton, isCoinDrawCountAllowed(drawConfig, 5))
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

local function getOrderedDraws(): { ResolvedDraw }
	local orderedDraws = {} :: { ResolvedDraw }

	for _, drawId in DrawConfig.DrawOrder do
		if type(drawId) ~= "string" then
			warn("[DrawController] DrawOrder contains a non-string draw id")
			continue
		end

		local resolvedDraw = resolveDraw(drawId)
		if resolvedDraw ~= nil then
			table.insert(orderedDraws, resolvedDraw)
		end
	end

	return orderedDraws
end

local function setSpinTypeButtonText(button: TextButton, resolvedDraw: ResolvedDraw)
	local titleLabel = button:FindFirstChild("Title", true)
	local categoryLabel = button:FindFirstChild("Category", true)
	local drawConfig = resolvedDraw.config

	if titleLabel ~= nil and titleLabel:IsA("TextLabel") then
		titleLabel.Text = drawConfig.DisplayName
	end

	if categoryLabel ~= nil and categoryLabel:IsA("TextLabel") then
		categoryLabel.Text = if resolvedDraw.kind == DRAW_KIND_ROBUX then "Robux" else "Coins"
	end
end

local function getSortedTaggedSpinTypeButtons(): { TextButton }
	local buttons = {} :: { TextButton }

	for _, instance in CollectionService:GetTagged("SPIN_TYPE_BUTTON") do
		if instance:IsDescendantOf(playerGui) and instance:IsA("TextButton") then
			table.insert(buttons, instance)
		end
	end

	table.sort(buttons, function(left, right)
		if left.LayoutOrder ~= right.LayoutOrder then
			return left.LayoutOrder < right.LayoutOrder
		end

		return left.Name < right.Name
	end)

	return buttons
end

local function syncSpinTypeButtonsWithConfig()
	local orderedDraws = getOrderedDraws()
	local existingButtons = getSortedTaggedSpinTypeButtons()
	local template: TextButton? = existingButtons[1]

	if template == nil then
		warn("[DrawController] no SPIN_TYPE_BUTTON template found")
		spinTypesButtons = {}
		return
	end

	for index, resolvedDraw in orderedDraws do
		local button: TextButton? = existingButtons[index]
		if button == nil then
			local clonedButton = template:Clone() :: TextButton
			clonedButton.Parent = template.Parent
			CollectionService:AddTag(clonedButton, "SPIN_TYPE_BUTTON")
			button = clonedButton
		end

		local resolvedButton = button :: TextButton
		resolvedButton.Name = resolvedDraw.drawId
		resolvedButton.LayoutOrder = index
		resolvedButton.Visible = true
		resolvedButton:SetAttribute(DRAW_ID_ATTRIBUTE, resolvedDraw.drawId)
		resolvedButton:SetAttribute(SELECTED_ATTRIBUTE, false)
		resolvedButton:SetAttribute(AUDIO_CLICK_EVENT_ATTRIBUTE, TAB_SWITCH_AUDIO_EVENT)
		setSpinTypeButtonText(resolvedButton, resolvedDraw)
	end

	for index = #orderedDraws + 1, #existingButtons do
		local button = existingButtons[index]
		button.Visible = false
		button:SetAttribute(DRAW_ID_ATTRIBUTE, nil)
		button:SetAttribute(SPIN_TYPE_CONNECTED_ATTRIBUTE, nil)
		CollectionService:RemoveTag(button, "SPIN_TYPE_BUTTON")
	end

	spinTypesButtons = {}
	for _, button in getSortedTaggedSpinTypeButtons() do
		table.insert(spinTypesButtons, button)
	end

	if currentDrawId == "" or resolveDraw(currentDrawId) == nil then
		currentDrawId = getDefaultDrawId()
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
	if type(drawConfig.Cost) == "number" then
		print(`[DrawController] cost: {drawConfig.Cost}`)
	end

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
		rarity = getInventoryRarity(entry.Category, entry.ItemId),
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

local function fireDrawRollTick()
	EventBus.Fire(LOCAL_DRAW_ROLL_TICK_EVENT)
end

local function fireDrawRollStopped()
	EventBus.Fire(LOCAL_DRAW_ROLL_STOPPED_EVENT)
end

local function hasRareDrawReward(result: SkinDrawResultPayload?): boolean
	if result == nil then
		return false
	end

	for _, reward in result.rewards do
		if reward.rarity ~= "Common" then
			return true
		end
	end

	return false
end

local function fireDrawResultRevealed(result: SkinDrawResultPayload?)
	EventBus.Fire(LOCAL_DRAW_RESULT_REVEALED_EVENT, hasRareDrawReward(result))
end

local function getSortedRollEntries(drawConfig): { any }
	local entries = {}

	for _, entry in drawConfig.Entries do
		table.insert(entries, entry)
	end

	table.sort(entries, function(a, b)
		local leftRarity = getInventoryRarity(a.Category, a.ItemId)
		local rightRarity = getInventoryRarity(b.Category, b.ItemId)
		local leftRank = rarityRank[leftRarity] or 0
		local rightRank = rarityRank[rightRarity] or 0

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

local function getRollTickDistancePixels(targetClone: GuiObject): number
	local spacing = 0
	if rollScrollingFrame ~= nil then
		local layout = rollScrollingFrame:FindFirstChildWhichIsA("UIListLayout")
		if layout ~= nil then
			spacing = layout.Padding.Offset
		end
	end

	return math.max(ROLL_TICK_MIN_DISTANCE_PIXELS, targetClone.AbsoluteSize.X + spacing)
end

local function connectRollTickPlayback(
	token: number,
	tween: Tween,
	startCanvasX: number,
	tickDistancePixels: number
): RBXScriptConnection
	local lastCanvasX = startCanvasX
	local distanceSinceTick = tickDistancePixels
	local lastTickAt = 0

	return RunService.RenderStepped:Connect(function()
		if token ~= rollToken or rollScrollingFrame == nil or rollTween ~= tween then
			return
		end

		local currentCanvasX = rollScrollingFrame.CanvasPosition.X
		local delta = math.abs(currentCanvasX - lastCanvasX)
		lastCanvasX = currentCanvasX

		if delta <= 0 then
			return
		end

		distanceSinceTick += delta

		local now = os.clock()
		while distanceSinceTick >= tickDistancePixels do
			if now - lastTickAt < ROLL_TICK_MIN_INTERVAL_SECONDS then
				break
			end

			distanceSinceTick -= tickDistancePixels
			lastTickAt = now
			fireDrawRollTick()
		end
	end)
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
	fireDrawResultRevealed(latestDrawResult)
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

	fireDrawRollStopped()
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
	local tickConnection = connectRollTickPlayback(
		token,
		tween,
		rollScrollingFrame.CanvasPosition.X,
		getRollTickDistancePixels(targetClone)
	)

	tween:Play()

	while not completed and token == rollToken do
		task.wait(0.03)
	end

	tickConnection:Disconnect()
	completedConnection:Disconnect()

	if rollTween == tween then
		rollTween = nil
	end

	if token ~= rollToken then
		return false
	end

	rollScrollingFrame.CanvasPosition = targetCanvasPosition
	setRollExplanation(reward.displayName)
	fireDrawRollStopped()

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

local function requestCoinDraw(drawConfig: any, count: number)
	readBalanceAttribute()

	if type(drawConfig.Cost) ~= "number" or drawConfig.Cost <= 0 then
		warn(`[DrawController] coin draw {currentDrawId} has invalid Cost`)
		return
	end

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

local function requestRobuxDraw(count: number)
	local product = findRobuxDrawProduct(currentDrawId, count)
	if product == nil then
		warn(`[DrawController] no Robux product configured for draw {currentDrawId} x{count}`)
		return
	end

	if product.productId <= 0 then
		warn(`[DrawController] Robux product {product.productKey} for draw {currentDrawId} has no ProductId configured`)
		return
	end

	setCurrentCount(count)
	isDrawing = true
	isWaitingForDrawResult = true
	isRollFinished = false

	local purchaseFinishedConnection: RBXScriptConnection?
	purchaseFinishedConnection = MarketplaceService.PromptProductPurchaseFinished:Connect(
		function(userId: number, productId: number, wasPurchased: boolean)
			if userId ~= localPlayer.UserId or productId ~= product.productId then
				return
			end

			if purchaseFinishedConnection ~= nil then
				purchaseFinishedConnection:Disconnect()
				purchaseFinishedConnection = nil
			end

			if not wasPurchased then
				isDrawing = false
				isWaitingForDrawResult = false
				setGuiVisible(chooseDrawFrame, true)
				setGuiVisible(rngFrame, false)
				updateDrawPrices()
			end
		end
	)

	local ok, err = pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, localPlayer, product.productId)
	if not ok then
		if purchaseFinishedConnection ~= nil then
			purchaseFinishedConnection:Disconnect()
			purchaseFinishedConnection = nil
		end

		isDrawing = false
		isWaitingForDrawResult = false
		warn(`[DrawController] failed to prompt Robux product {product.productKey}: {tostring(err)}`)
	end
end

local function requestDraw(count: number)
	if isDrawing or isRolling or isWaitingForDrawResult then
		return
	end

	local resolvedDraw = resolveDraw(currentDrawId)
	if resolvedDraw == nil then
		return
	end

	if resolvedDraw.kind == DRAW_KIND_ROBUX then
		requestRobuxDraw(count)
		return
	end

	requestCoinDraw(resolvedDraw.config, count)
end

local function onDrawButtonClicked(count: number)
	requestDraw(count)
end

local function connectSpinTypeButtons()
	print("[DrawController] connect spin type buttons")

	syncSpinTypeButtonsWithConfig()

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
		button:SetAttribute(AUDIO_CLICK_EVENT_ATTRIBUTE, TAB_SWITCH_AUDIO_EVENT)

		if button:GetAttribute(SPIN_TYPE_CONNECTED_ATTRIBUTE) == true then
			continue
		end

		if type(drawId) ~= "string" then
			warn(`[DrawController] missing/invalid {DRAW_ID_ATTRIBUTE} attribute on {button:GetFullName()}`)
			continue
		end

		button:SetAttribute(SPIN_TYPE_CONNECTED_ATTRIBUTE, true)
		connectGuiAction(button, function()
			local currentButtonDrawId = button:GetAttribute(DRAW_ID_ATTRIBUTE)
			if type(currentButtonDrawId) == "string" then
				setCurrentDraw(currentButtonDrawId)
			end
		end)
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
		connectGuiAction(drawClose, closeDrawUi)
		return
	end

	connectGuiAction(drawClose, closeDrawUi)
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

			if isInside and not wasInsideGachaPart and not isLocalPlayerLockedForRound() then
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
			task.defer(syncDrawEntryButtons)
		end)
	)
end

function DrawController:GetReferences()
	preventDrawGuiResetOnSpawn()

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

	if coinsDrawPrice ~= nil and coinsDrawPrice.Parent ~= nil then
		local icon = coinsDrawPrice.Parent:FindFirstChild("Icon")
		if icon ~= nil and icon:IsA("ImageLabel") then
			price1xIcon = icon
		end
	end

	if gemsDrawPrice ~= nil and gemsDrawPrice.Parent ~= nil then
		local icon = gemsDrawPrice.Parent:FindFirstChild("Icon")
		if icon ~= nil and icon:IsA("ImageLabel") then
			price5xIcon = icon
		end
	end
end

function DrawController:BuildUI()
	if didBuildUI then
		syncSpinTypeButtonsWithConfig()
		updateCurrencyLabels()
		updateDrawPrices()
		updateSpinItems()
		updateOddsFrame()
		updateSpinTypeButtonsVisual()
		return
	end

	didBuildUI = true

	self:GetReferences()
	syncSpinTypeButtonsWithConfig()

	setScreenEnabled(false)
	setHudVisible(true)
	startGachaPartWatcher()
	syncDrawEntryButtons()

	setGuiVisible(chooseDrawFrame, true)
	setGuiVisible(rngFrame, false)
	setSkipButtonTitle("SKIP")

	updateCurrencyLabels()
	updateDrawPrices()
	updateSpinItems()
	updateOddsFrame()

	if drawButton == nil then
		warn("[DrawController] draw button not found")
	end

	table.insert(connections, CollectionService:GetInstanceAddedSignal("DRAW_BUTTON"):Connect(connectDrawEntryButton))
	table.insert(connections, CollectionService:GetInstanceAddedSignal("SPIN_SCREEN"):Connect(handleDrawScreenAdded))
	table.insert(connections, CollectionService:GetInstanceAddedSignal("SIDEMENU"):Connect(handleSideMenuAdded))

	connectDrawClose()

	if spin1xButton ~= nil then
		connectGuiAction(spin1xButton, function()
			onDrawButtonClicked(1)
		end)
	end

	if spin5xButton ~= nil then
		connectGuiAction(spin5xButton, function()
			onDrawButtonClicked(5)
		end)
	end

	if skipDrawButton ~= nil then
		connectGuiAction(skipDrawButton, function()
			if isRolling or isWaitingForDrawResult then
				skipRoll()
				return
			end

			if isRollFinished then
				claimRollUi()
				return
			end
		end)
	end

	connectSpinTypeButtons()

	table.insert(
		connections,
		localPlayer:GetAttributeChangedSignal("Coins"):Connect(function()
			updateCurrencyLabels()
			updateDrawPrices()
		end)
	)

	table.insert(connections, localPlayer:GetAttributeChangedSignal("SkinTokens"):Connect(updateCurrencyLabels))

	table.insert(
		connections,
		localPlayer:GetAttributeChangedSignal("PlayerState"):Connect(function()
			updateDrawEntryVisibility()

			if isLocalPlayerLockedForRound() then
				closeDrawUi()
			end
		end)
	)

	table.insert(
		connections,
		economyBalanceChangedRemote.OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" then
				return
			end

			local balance = payload.balance
			if typeof(balance) == "number" then
				currentBalance = balance
			end

			updateCurrencyLabels()
			updateDrawPrices()
		end)
	)

	table.insert(
		connections,
		inventoryUpdatedRemote.OnClientEvent:Connect(function()
			updateSpinItems()
		end)
	)

	table.insert(
		connections,
		skinDrawResultRemote.OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" then
				return
			end

			handleSkinDrawResult(payload :: SkinDrawResultPayload)
		end)
	)
end

function DrawController:Open()
	if isLocalPlayerLockedForRound() then
		closeDrawUi()
		updateDrawEntryVisibility()
		return
	end

	setScreenEnabled(true)
	setHudVisible(false)
	syncSpinTypeButtonsWithConfig()

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

function DrawController:OpenDraw(drawId: string)
	setCurrentDraw(drawId)
	self:Open()
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
