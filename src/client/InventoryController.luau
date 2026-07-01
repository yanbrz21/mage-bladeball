--!strict

local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Network = Shared:WaitForChild("Network")
local Parabellum = ReplicatedStorage:WaitForChild("Parabellum")

local DrawConfig = require(Config:WaitForChild("DrawConfig"))
local DrawController: any = require(Parabellum:WaitForChild("DrawController"))
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local InventoryAbilityText = require(Parabellum:WaitForChild("InventoryAbilityText"))
local InventoryConfig = require(Config:WaitForChild("InventoryConfig"))
local InventoryItemVisuals = require(Parabellum:WaitForChild("InventoryItemVisuals"))
local InventoryUpgradeConfirm = require(Parabellum:WaitForChild("InventoryUpgradeConfirm"))
local MatchConfig = require(Config:WaitForChild("MatchConfig"))
local Remotes = require(Network:WaitForChild("Remotes"))

local requestEquipItemRemote = Remotes.GetClientToServer(Network, Remotes.ClientToServer.RequestEquipItem)
local requestUpgradeAbilityRemote = Remotes.GetClientToServer(Network, Remotes.ClientToServer.RequestUpgradeAbility)

local inventoryUpdatedRemote = Remotes.GetServerToClient(Network, Remotes.ServerToClient.InventoryUpdated)
local abilityUpgradeResultRemote = Remotes.GetServerToClient(Network, Remotes.ServerToClient.AbilityUpgradeResult)

local InventoryController = {
	Name = "InventoryController",
}

local CATEGORY_ABILITY = "Ability"
local CATEGORY_WEAPON_SKIN = "WeaponSkin"

local PAGE_ABILITIES = "Abilities"
local PAGE_SKINS = "Skins"
local PAGE_SHOP = "Shop"

local ITEMS_PER_ROW = 3
local INVENTORY_CANVAS_BOTTOM_PADDING = 24
local SHOP_TEMPLATE_RARITY = "Common"

local CLONE_ATTRIBUTE = "IS_CLONE"
local ROW_CLONE_ATTRIBUTE = "IS_ROW_CLONE"
local CATEGORY_ATTRIBUTE = "CATEGORY"
local ITEM_ID_ATTRIBUTE = "ITEM_ID"
local RARITY_ATTRIBUTE = "RARITY"
local OWNED_ATTRIBUTE = "OWNED"

local ABILITY_PROGRESS_NAME = "AbilityUpgradeProgress"
local ABILITY_PROGRESS_FILL_NAME = "Fill"
local ABILITY_PROGRESS_TEXT_NAME = "Count"
local ABILITY_LEVEL_BADGE_NAME = "AbilityLevelBadge"
local ABILITY_LEVEL_TEXT_NAME = "Level"

local SELECTED_PAGE_COLOR = Color3.fromRGB(255, 221, 64)
local UNSELECTED_PAGE_COLOR = Color3.fromRGB(255, 221, 64)
local SELECTED_PAGE_TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local UNSELECTED_PAGE_TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local SELECTED_PAGE_STROKE_COLOR = Color3.fromRGB(255, 246, 170)
local UNSELECTED_PAGE_STROKE_COLOR = Color3.fromRGB(173, 119, 24)
local SELECTED_PAGE_BACKGROUND_TRANSPARENCY = 0.08
local UNSELECTED_PAGE_BACKGROUND_TRANSPARENCY = 0.35
local SELECTED_PAGE_STROKE_TRANSPARENCY = 0.1
local UNSELECTED_PAGE_STROKE_TRANSPARENCY = 0.35
local PROGRESS_FILL_COLOR = Color3.fromRGB(97, 235, 164)
local PROGRESS_READY_FILL_COLOR = Color3.fromRGB(248, 210, 86)
local ACTION_BUTTON_DISABLED_TEXT_COLOR = Color3.fromRGB(150, 150, 150)
local ACTION_BUTTON_DISABLED_IMAGE_COLOR = Color3.fromRGB(105, 105, 105)
local ACTION_BUTTON_SIZE = UDim2.fromScale(0.925853252, 0.105)
local HIDDEN_ACTION_BUTTON_SIZE = UDim2.fromScale(0.925853252, 0)

local ORIGINAL_TEXT_COLOR_ATTRIBUTE = "OriginalActionTextColor"
local ORIGINAL_TEXT_TRANSPARENCY_ATTRIBUTE = "OriginalActionTextTransparency"
local ORIGINAL_GRADIENT_ENABLED_ATTRIBUTE = "OriginalActionGradientEnabled"
local ORIGINAL_IMAGE_COLOR_ATTRIBUTE = "OriginalActionImageColor"
local ORIGINAL_IMAGE_TRANSPARENCY_ATTRIBUTE = "OriginalActionImageTransparency"
local ORIGINAL_STROKE_TRANSPARENCY_ATTRIBUTE = "OriginalActionStrokeTransparency"
local AUDIO_CLICK_EVENT_ATTRIBUTE = "AudioClickEvent"
local TAB_SWITCH_AUDIO_EVENT = "TabSwitch"
local INVENTORY_ENTRY_CONNECTED_ATTRIBUTE = "ParabellumInventoryEntryConnected"
local INVENTORY_CLOSE_CONNECTED_ATTRIBUTE = "ParabellumInventoryCloseConnected"
local INVENTORY_EQUIP_CONNECTED_ATTRIBUTE = "ParabellumInventoryEquipConnected"
local INVENTORY_UPGRADE_CONNECTED_ATTRIBUTE = "ParabellumInventoryUpgradeConnected"
local INVENTORY_PAGE_CONNECTED_ATTRIBUTE = "ParabellumInventoryPageConnected"

local rarityRank = {
	Common = 1,
	Rare = 2,
	Epic = 3,
	Legendary = 4,
	Mythic = 5,
}

type InventorySnapshot = {
	userId: number,
	skinTokens: number,
	abilityFragments: { [string]: number },
	abilityLevels: { [string]: number },
	ownedAbilities: { string },
	equippedAbility: string,
	ownedWeaponSkins: { string },
	equippedWeaponSkin: string,
	changedAt: number,
}

type ShopProduct = {
	kind: string,
	productKey: string,
	productId: number,
	gamePassKey: string?,
	gamePassId: number?,
	displayName: string,
	description: string,
	rewardText: string,
	rarity: string,
	robuxPrice: number?,
	iconAssetId: string?,
}

local inventoryScrollFrame: ScrollingFrame?
local screen: Instance?
local inventoryItemInfo: GuiObject?
local itemName: TextLabel?
local itemImage: ImageLabel?
local itemDescription: TextLabel?
local itemEquipButton: TextButton?
local abilityUpgradeButton: TextButton?
local closeButton: GuiButton?
local inventoryButton: GuiButton?

local abilitiesButton: TextButton?
local skinsButton: TextButton?
local shopButton: TextButton?
local HUD_SCREENGUI: ScreenGui?

local ownedRowTemplate: Frame?
local unownedRowTemplate: Frame?
local unownedTitle: GuiObject?
local templateFolder: Folder?

local currentInventorySnapshot: InventorySnapshot?
local selectedCategory: string?
local selectedItemId: string?
local selectedItemOwned = false
local selectedShopProductKey: string?
local currentPage = PAGE_ABILITIES

local inventoryCanvasUpdateToken = 0

local connections: { RBXScriptConnection } = {}
local inventoryChangedEvent = Instance.new("BindableEvent")

local getItemRarity: (category: string, itemId: string) -> string
local refreshScreenReferences: () -> ()
local clearSelectedItem: () -> ()
local updateSelectedActionButtons: () -> ()
local ShopProducts = {}

local function getReferenceByTag(tag: string, timeout: number?): Instance?
	local startedAt = os.clock()
	local maxWait = timeout or 10

	while os.clock() - startedAt < maxWait do
		local items = CollectionService:GetTagged(tag)

		for _, item in items do
			if item:IsDescendantOf(ReplicatedStorage) then
				continue
			end

			if item:IsDescendantOf(playerGui) then
				return item
			end
		end

		task.wait(0.1)
	end

	warn(`[InventoryController] no tagged player gui item found: {tag}`)
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

local function setScreenVisible(visible: boolean)
	if screen == nil then
		return
	end

	if screen:IsA("ScreenGui") then
		screen.Enabled = visible
	elseif screen:IsA("GuiObject") then
		screen.Visible = visible
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

local function preventInventoryGuiResetOnSpawn()
	preventTaggedGuiResetOnSpawn("INVENTORY_BUTTON")
	preventTaggedGuiResetOnSpawn("SIDEMENU")
	preventTaggedGuiResetOnSpawn("INVENTORY_SCREEN")
end

local function setHudVisible(visible: boolean)
	setGuiVisible(HUD_SCREENGUI, visible)
end

local function isLocalPlayerLockedForRound(): boolean
	local playerState = localPlayer:GetAttribute("PlayerState")
	return playerState == MatchConfig.PlayerStates.AliveInRound or playerState == MatchConfig.PlayerStates.DeadInRound
end

local function updateInventoryEntryVisibility()
	local shouldShow = not isLocalPlayerLockedForRound()
	for _, instance in CollectionService:GetTagged("INVENTORY_BUTTON") do
		if instance:IsDescendantOf(playerGui) and instance:IsA("GuiObject") then
			instance.Visible = shouldShow
		end
	end
end

local function connectInventoryEntryButton(instance: Instance)
	if not instance:IsDescendantOf(playerGui) or not instance:IsA("GuiButton") then
		return
	end

	preventGuiResetOnSpawn(instance)
	inventoryButton = instance
	instance.Visible = not isLocalPlayerLockedForRound()

	if instance:GetAttribute(INVENTORY_ENTRY_CONNECTED_ATTRIBUTE) == true then
		return
	end

	instance:SetAttribute(INVENTORY_ENTRY_CONNECTED_ATTRIBUTE, true)
	table.insert(
		connections,
		instance.Activated:Connect(function()
			print("[InventoryController] inventory button clicked")
			InventoryController:Open()
		end)
	)
end

local function syncInventoryEntryButtons()
	preventInventoryGuiResetOnSpawn()
	for _, instance in CollectionService:GetTagged("INVENTORY_BUTTON") do
		connectInventoryEntryButton(instance)
	end
	updateInventoryEntryVisibility()
end

local function handleInventoryScreenAdded(instance: Instance)
	if not instance:IsDescendantOf(playerGui) then
		return
	end

	screen = instance
	preventGuiResetOnSpawn(instance)
	if isLocalPlayerLockedForRound() then
		setScreenVisible(false)
	end

	task.defer(function()
		refreshScreenReferences()
	end)
end

local function handleSideMenuAdded(instance: Instance)
	if not instance:IsDescendantOf(playerGui) then
		return
	end

	HUD_SCREENGUI = instance :: any
	preventGuiResetOnSpawn(instance)
	setHudVisible(true)
	syncInventoryEntryButtons()
end

local function closeInventoryUi()
	InventoryUpgradeConfirm.Hide()
	setScreenVisible(false)
	setHudVisible(true)
end

local function setEquipButtonText(text: string)
	if itemEquipButton == nil then
		return
	end

	local coin = itemEquipButton:FindFirstChild("Coin")
	if coin == nil then
		warn(`[InventoryController] missing Coin inside {itemEquipButton:GetFullName()}`)
		return
	end

	local count = coin:FindFirstChild("Count", true)
	if count == nil or not count:IsA("TextLabel") then
		warn(`[InventoryController] missing Coin.Count TextLabel inside {itemEquipButton:GetFullName()}`)
		return
	end

	count.Text = text
end

local function rememberAttribute(instance: Instance, attributeName: string, value: any)
	if instance:GetAttribute(attributeName) == nil then
		instance:SetAttribute(attributeName, value)
	end
end

local function getColorAttribute(instance: Instance, attributeName: string, fallback: Color3): Color3
	local value = instance:GetAttribute(attributeName)
	return if typeof(value) == "Color3" then value else fallback
end

local function getNumberAttribute(instance: Instance, attributeName: string, fallback: number): number
	local value = instance:GetAttribute(attributeName)
	return if typeof(value) == "number" then value else fallback
end

local function getBooleanAttribute(instance: Instance, attributeName: string, fallback: boolean): boolean
	local value = instance:GetAttribute(attributeName)
	return if typeof(value) == "boolean" then value else fallback
end

local function setActionButtonVisual(button: TextButton?, enabled: boolean)
	if button == nil then
		return
	end

	button.Active = enabled
	button.AutoButtonColor = enabled
	button.Selectable = enabled
	button.Interactable = enabled

	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			rememberAttribute(descendant, ORIGINAL_TEXT_COLOR_ATTRIBUTE, descendant.TextColor3)
			rememberAttribute(descendant, ORIGINAL_TEXT_TRANSPARENCY_ATTRIBUTE, descendant.TextTransparency)

			local originalColor = getColorAttribute(descendant, ORIGINAL_TEXT_COLOR_ATTRIBUTE, descendant.TextColor3)
			local originalTransparency =
				getNumberAttribute(descendant, ORIGINAL_TEXT_TRANSPARENCY_ATTRIBUTE, descendant.TextTransparency)

			descendant.TextColor3 = if enabled then originalColor else ACTION_BUTTON_DISABLED_TEXT_COLOR
			descendant.TextTransparency = if enabled
				then originalTransparency
				else math.clamp(originalTransparency + 0.15, 0, 1)

			for _, child in ipairs(descendant:GetChildren()) do
				if child:IsA("UIGradient") then
					rememberAttribute(child, ORIGINAL_GRADIENT_ENABLED_ATTRIBUTE, child.Enabled)
					child.Enabled = if enabled
						then getBooleanAttribute(child, ORIGINAL_GRADIENT_ENABLED_ATTRIBUTE, child.Enabled)
						else false
				end
			end
		elseif descendant:IsA("ImageLabel") then
			rememberAttribute(descendant, ORIGINAL_IMAGE_COLOR_ATTRIBUTE, descendant.ImageColor3)
			rememberAttribute(descendant, ORIGINAL_IMAGE_TRANSPARENCY_ATTRIBUTE, descendant.ImageTransparency)

			local originalColor = getColorAttribute(descendant, ORIGINAL_IMAGE_COLOR_ATTRIBUTE, descendant.ImageColor3)
			local originalTransparency =
				getNumberAttribute(descendant, ORIGINAL_IMAGE_TRANSPARENCY_ATTRIBUTE, descendant.ImageTransparency)

			descendant.ImageColor3 = if enabled then originalColor else ACTION_BUTTON_DISABLED_IMAGE_COLOR
			descendant.ImageTransparency = if enabled
				then originalTransparency
				else math.clamp(originalTransparency + 0.35, 0, 1)
		elseif descendant:IsA("UIStroke") then
			rememberAttribute(descendant, ORIGINAL_STROKE_TRANSPARENCY_ATTRIBUTE, descendant.Transparency)

			local originalTransparency =
				getNumberAttribute(descendant, ORIGINAL_STROKE_TRANSPARENCY_ATTRIBUTE, descendant.Transparency)
			descendant.Transparency = if enabled
				then originalTransparency
				else math.clamp(originalTransparency + 0.45, 0, 1)
		end
	end
end

local function setEquipButtonEnabled(enabled: boolean)
	setActionButtonVisual(itemEquipButton, enabled)
end

local function setButtonText(button: TextButton?, text: string)
	if button == nil then
		return
	end

	local coin = button:FindFirstChild("Coin")
	if coin == nil then
		warn(`[InventoryController] missing Coin inside {button:GetFullName()}`)
		return
	end

	local count = coin:FindFirstChild("Count", true)
	if count == nil or not count:IsA("TextLabel") then
		warn(`[InventoryController] missing Coin.Count TextLabel inside {button:GetFullName()}`)
		return
	end

	count.Text = text
end

local function setUpgradeButtonText(text: string)
	setButtonText(abilityUpgradeButton, text)
end

local function setUpgradeButtonEnabled(enabled: boolean)
	setActionButtonVisual(abilityUpgradeButton, enabled)
end

local function getAbilityInitialLevel(abilityId: string): number
	local abilityCategory = (InventoryConfig.Categories :: any).Ability
	if type(abilityCategory) ~= "table" or type(abilityCategory.Items) ~= "table" then
		return 1
	end

	local abilityItem = abilityCategory.Items[abilityId]
	if type(abilityItem) ~= "table" or type(abilityItem.Rarity) ~= "string" then
		return 1
	end

	local upgradeConfig = (EconomyConfig :: any).AbilityUpgrade
	if type(upgradeConfig) ~= "table" or type(upgradeConfig.InitialLevelByRarity) ~= "table" then
		return 1
	end

	local initialLevel = upgradeConfig.InitialLevelByRarity[abilityItem.Rarity]
	return if type(initialLevel) == "number" and initialLevel >= 1 then math.floor(initialLevel) else 1
end

local function getAbilityLevelValue(abilityId: string): number
	local initialLevel = getAbilityInitialLevel(abilityId)
	local snapshot = currentInventorySnapshot
	if snapshot == nil then
		return initialLevel
	end

	local level = snapshot.abilityLevels[abilityId]
	return if type(level) == "number" and level >= initialLevel then math.floor(level) else initialLevel
end

local function getAbilityFragments(abilityId: string): number
	local snapshot = currentInventorySnapshot
	if snapshot == nil then
		return 0
	end

	local fragments = snapshot.abilityFragments[abilityId]
	return if type(fragments) == "number" and fragments > 0 then math.floor(fragments) else 0
end

local function getAbilityMaxLevel(): number
	local upgradeConfig = (EconomyConfig :: any).AbilityUpgrade
	if type(upgradeConfig) ~= "table" or type(upgradeConfig.MaxLevel) ~= "number" then
		return 1
	end

	return math.max(1, math.floor(upgradeConfig.MaxLevel))
end

local function getAbilityUpgradeCost(abilityId: string): number?
	local currentLevel = getAbilityLevelValue(abilityId)
	local maxLevel = getAbilityMaxLevel()
	if currentLevel >= maxLevel then
		return nil
	end

	local upgradeConfig = (EconomyConfig :: any).AbilityUpgrade
	if type(upgradeConfig) ~= "table" or type(upgradeConfig.FragmentCostsByNextLevelOffset) ~= "table" then
		return nil
	end

	local nextLevel = currentLevel + 1
	local nextLevelOffset = nextLevel - getAbilityInitialLevel(abilityId)
	local cost = upgradeConfig.FragmentCostsByNextLevelOffset[nextLevelOffset]
	return if type(cost) == "number" and cost > 0 then math.floor(cost) else nil
end

local function getInventoryItemConfig(category: string, itemId: string): any?
	local categories = InventoryConfig.Categories :: any
	local categoryConfig = categories[category]

	if type(categoryConfig) ~= "table" then
		return nil
	end

	local itemConfig = categoryConfig.Items[itemId]
	if type(itemConfig) ~= "table" then
		return nil
	end

	return itemConfig
end

local function getItemDisplayName(category: string, itemId: string): string
	return InventoryItemVisuals.GetDisplayName(category, itemId)
end

local function isDefaultOwnedItem(category: string, itemId: string): boolean
	local itemConfig = getInventoryItemConfig(category, itemId)

	if itemConfig == nil then
		return false
	end

	return itemConfig.IsDefaultOwned == true
end

local function getDefaultItemId(category: string): string?
	local categories = InventoryConfig.Categories :: any
	local categoryConfig = categories[category]

	if type(categoryConfig) ~= "table" then
		return nil
	end

	if type(categoryConfig.DefaultItemId) ~= "string" then
		return nil
	end

	return categoryConfig.DefaultItemId
end

do
	local gamePassPriceCache: { [string]: number } = {}
	local gamePassPriceRequests: { [string]: boolean } = {}
	local shopProductRarityByKey = {
		coins_medium = "Rare",
		coins_large = "Epic",
		coins_huge = "Legendary",
		["gamepass:double_coins"] = "Legendary",
	}

	local function getShopRarity(productKey: string, productConfig: any): string
		local rarity = productConfig.Rarity
		if type(rarity) == "string" and rarity ~= "" then
			return rarity
		end

		return shopProductRarityByKey[productKey] or SHOP_TEMPLATE_RARITY
	end

	local function normalizeShopProduct(productKey: string, productConfig: any): ShopProduct?
		if type(productConfig) ~= "table" then
			warn(`[InventoryController] Robux shop product {productKey} must be a table.`)
			return nil
		end

		local productId = productConfig.ProductId
		if type(productId) ~= "number" or productId < 0 or math.floor(productId) ~= productId then
			warn(`[InventoryController] Robux shop product {productKey} has invalid ProductId.`)
			return nil
		end

		local displayName = productConfig.DisplayName
		if type(displayName) ~= "string" or displayName == "" then
			warn(`[InventoryController] Robux shop product {productKey} is missing DisplayName.`)
			return nil
		end

		local description = productConfig.Description
		if type(description) ~= "string" then
			warn(`[InventoryController] Robux shop product {productKey} has invalid Description.`)
			return nil
		end

		local rewardText = productConfig.RewardText
		if type(rewardText) ~= "string" or rewardText == "" then
			warn(`[InventoryController] Robux shop product {productKey} is missing RewardText.`)
			return nil
		end

		local robuxPrice = productConfig.RobuxPrice
		if type(robuxPrice) ~= "number" or robuxPrice < 0 then
			warn(`[InventoryController] Robux shop product {productKey} has invalid RobuxPrice.`)
			return nil
		end

		local iconAssetId = productConfig.IconAssetId
		if iconAssetId ~= nil and type(iconAssetId) ~= "string" then
			warn(`[InventoryController] Robux shop product {productKey} has invalid IconAssetId.`)
			return nil
		end

		return {
			kind = "DeveloperProduct",
			productKey = productKey,
			productId = productId,
			gamePassKey = nil,
			gamePassId = nil,
			displayName = displayName,
			description = description,
			rewardText = rewardText,
			rarity = getShopRarity(productKey, productConfig),
			robuxPrice = math.floor(robuxPrice),
			iconAssetId = iconAssetId,
		}
	end

	local function formatGamePassRewardText(gamePassConfig: any): string
		local multiplier = gamePassConfig.Multiplier
		if type(multiplier) == "number" and multiplier > 1 then
			return `{multiplier}X coins`
		end

		return "GamePass"
	end

	local function formatGamePassDescription(gamePassConfig: any): string
		if type(gamePassConfig.Multiplier) == "number" and gamePassConfig.Multiplier > 1 then
			return ""
		end

		local appliesTo = gamePassConfig.AppliesTo
		if type(appliesTo) ~= "table" then
			return "Unlocks a persistent account benefit."
		end

		local sourceNames = {}
		for source, enabled in appliesTo do
			if type(source) == "string" and enabled == true then
				table.insert(sourceNames, source)
			end
		end

		table.sort(sourceNames)
		if #sourceNames <= 0 then
			return "Unlocks a persistent account benefit."
		end

		return `Applies to: {table.concat(sourceNames, ", ")}.`
	end

	local function normalizeGamePassProduct(gamePassKey: string, gamePassConfig: any): ShopProduct?
		if type(gamePassConfig) ~= "table" then
			warn(`[InventoryController] GamePass product {gamePassKey} must be a table.`)
			return nil
		end

		local gamePassId = gamePassConfig.GamePassId
		if type(gamePassId) ~= "number" or gamePassId < 0 or math.floor(gamePassId) ~= gamePassId then
			warn(`[InventoryController] GamePass product {gamePassKey} has invalid GamePassId.`)
			return nil
		end

		local displayName = gamePassConfig.DisplayName
		if type(displayName) ~= "string" or displayName == "" then
			warn(`[InventoryController] GamePass product {gamePassKey} is missing DisplayName.`)
			return nil
		end

		local iconAssetId = gamePassConfig.IconAssetId
		if iconAssetId ~= nil and type(iconAssetId) ~= "string" then
			warn(`[InventoryController] GamePass product {gamePassKey} has invalid IconAssetId.`)
			return nil
		end

		return {
			kind = "GamePass",
			productKey = `gamepass:{gamePassKey}`,
			productId = 0,
			gamePassKey = gamePassKey,
			gamePassId = gamePassId,
			displayName = displayName,
			description = formatGamePassDescription(gamePassConfig),
			rewardText = formatGamePassRewardText(gamePassConfig),
			rarity = getShopRarity(`gamepass:{gamePassKey}`, gamePassConfig),
			robuxPrice = gamePassPriceCache[gamePassKey],
			iconAssetId = iconAssetId,
		}
	end

	local function getShopProduct(productKey: string): ShopProduct?
		local catalog = (EconomyConfig :: any).RobuxShopCatalog
		if type(catalog) ~= "table" then
			warn("[InventoryController] EconomyConfig.RobuxShopCatalog must be configured.")
			return nil
		end

		return normalizeShopProduct(productKey, catalog[productKey])
	end

	local function getGamePassProduct(gamePassKey: string): ShopProduct?
		local catalog = (EconomyConfig :: any).GamePassCatalog
		if type(catalog) ~= "table" then
			warn("[InventoryController] EconomyConfig.GamePassCatalog must be configured.")
			return nil
		end

		return normalizeGamePassProduct(gamePassKey, catalog[gamePassKey])
	end

	function ShopProducts.GetEntry(productKey: string): ShopProduct?
		if string.sub(productKey, 1, 9) == "gamepass:" then
			return getGamePassProduct(string.sub(productKey, 10))
		end

		return getShopProduct(productKey)
	end

	function ShopProducts.RequestGamePassPrice(gamePassKey: string, gamePassId: number)
		if gamePassId <= 0 or gamePassPriceCache[gamePassKey] ~= nil or gamePassPriceRequests[gamePassKey] == true then
			return
		end

		gamePassPriceRequests[gamePassKey] = true
		task.spawn(function()
			local ok, productInfo =
				pcall(MarketplaceService.GetProductInfoAsync, MarketplaceService, gamePassId, Enum.InfoType.GamePass)
			gamePassPriceRequests[gamePassKey] = nil

			if not ok or type(productInfo) ~= "table" then
				warn(
					`[InventoryController] failed to load GamePass product info for {gamePassKey}: {tostring(
						productInfo
					)}`
				)
				return
			end

			local price = productInfo.PriceInRobux
			if type(price) ~= "number" or price < 0 then
				return
			end

			gamePassPriceCache[gamePassKey] = math.floor(price)
			if currentPage == PAGE_SHOP and selectedShopProductKey == `gamepass:{gamePassKey}` then
				updateSelectedActionButtons()
			end
		end)
	end

	function ShopProducts.GetProducts(): { ShopProduct }
		local order = (EconomyConfig :: any).RobuxShopOrder
		if type(order) ~= "table" then
			warn("[InventoryController] EconomyConfig.RobuxShopOrder must be configured.")
			return {}
		end

		local products = {} :: { ShopProduct }
		local gamePassCatalog = (EconomyConfig :: any).GamePassCatalog
		if type(gamePassCatalog) == "table" then
			local gamePassProducts = {} :: { ShopProduct }
			for gamePassKey, _gamePassConfig in gamePassCatalog do
				if type(gamePassKey) ~= "string" or gamePassKey == "" then
					warn("[InventoryController] GamePassCatalog contains an invalid key.")
					continue
				end

				local product = getGamePassProduct(gamePassKey)
				if product ~= nil then
					table.insert(gamePassProducts, product)
					if product.gamePassId ~= nil then
						ShopProducts.RequestGamePassPrice(gamePassKey, product.gamePassId)
					end
				end
			end

			table.sort(gamePassProducts, function(a, b)
				return a.displayName < b.displayName
			end)

			for _, product in gamePassProducts do
				table.insert(products, product)
			end
		elseif gamePassCatalog ~= nil then
			warn("[InventoryController] EconomyConfig.GamePassCatalog must be a table when configured.")
		end

		for _, productKey in order do
			if type(productKey) ~= "string" or productKey == "" then
				warn("[InventoryController] RobuxShopOrder contains an invalid product key.")
				continue
			end

			local product = getShopProduct(productKey)
			if product ~= nil then
				table.insert(products, product)
			end
		end

		return products
	end
end

getItemRarity = function(category: string, itemId: string): string
	return InventoryItemVisuals.GetRarity(category, itemId)
end

local function getAllItemIds(category: string): { string }
	local categories = InventoryConfig.Categories :: any
	local categoryConfig = categories[category]

	if type(categoryConfig) ~= "table" or type(categoryConfig.Items) ~= "table" then
		return {}
	end

	local itemIds = {}

	for itemId in categoryConfig.Items do
		table.insert(itemIds, itemId)
	end

	table.sort(itemIds, function(a, b)
		local aRarity = getItemRarity(category, a)
		local bRarity = getItemRarity(category, b)
		local aRank = rarityRank[aRarity] or 0
		local bRank = rarityRank[bRarity] or 0

		if aRank ~= bRank then
			return aRank > bRank
		end

		return getItemDisplayName(category, a) < getItemDisplayName(category, b)
	end)

	return itemIds
end

local function isEquipped(category: string, itemId: string): boolean
	local snapshot = currentInventorySnapshot

	if category == CATEGORY_ABILITY then
		if snapshot ~= nil and type(snapshot.equippedAbility) == "string" then
			return snapshot.equippedAbility == itemId
		end

		local equippedAbility = localPlayer:GetAttribute("EquippedAbility")
		if type(equippedAbility) == "string" and equippedAbility ~= "" then
			return equippedAbility == itemId
		end

		return getDefaultItemId(category) == itemId
	end

	if category == CATEGORY_WEAPON_SKIN then
		if snapshot ~= nil and type(snapshot.equippedWeaponSkin) == "string" then
			return snapshot.equippedWeaponSkin == itemId
		end

		local equippedWeaponSkin = localPlayer:GetAttribute("EquippedWeaponSkin")
		if type(equippedWeaponSkin) == "string" and equippedWeaponSkin ~= "" then
			return equippedWeaponSkin == itemId
		end

		return getDefaultItemId(category) == itemId
	end

	return false
end

local function getOwnedItems(category: string): { string }
	local snapshot = currentInventorySnapshot
	local ownedSet = {} :: { [string]: boolean }
	local ownedItems = {} :: { string }

	if snapshot ~= nil then
		local snapshotOwnedItems = {} :: { string }

		if category == CATEGORY_ABILITY then
			snapshotOwnedItems = snapshot.ownedAbilities or {}
		elseif category == CATEGORY_WEAPON_SKIN then
			snapshotOwnedItems = snapshot.ownedWeaponSkins or {}
		end

		for _, itemId in snapshotOwnedItems do
			if ownedSet[itemId] ~= true then
				ownedSet[itemId] = true
				table.insert(ownedItems, itemId)
			end
		end
	end

	for _, itemId in getAllItemIds(category) do
		if isDefaultOwnedItem(category, itemId) and ownedSet[itemId] ~= true then
			ownedSet[itemId] = true
			table.insert(ownedItems, itemId)
		end
	end

	table.sort(ownedItems, function(a, b)
		local aRarity = getItemRarity(category, a)
		local bRarity = getItemRarity(category, b)
		local aRank = rarityRank[aRarity] or 0
		local bRank = rarityRank[bRarity] or 0

		if aRank ~= bRank then
			return aRank > bRank
		end

		return getItemDisplayName(category, a) < getItemDisplayName(category, b)
	end)

	return ownedItems
end

local function getOwnedItemSet(category: string): { [string]: boolean }
	local ownedSet = {}

	for _, itemId in getOwnedItems(category) do
		ownedSet[itemId] = true
	end

	return ownedSet
end

local function getUnownedItems(category: string): { string }
	local ownedSet = getOwnedItemSet(category)
	local unownedItems = {}

	for _, itemId in getAllItemIds(category) do
		if ownedSet[itemId] ~= true then
			table.insert(unownedItems, itemId)
		end
	end

	return unownedItems
end

local function getCurrentPageCategory(): string
	if currentPage == PAGE_SKINS then
		return CATEGORY_WEAPON_SKIN
	end

	return CATEGORY_ABILITY
end

local function getTemplateFolder(): Folder?
	if templateFolder ~= nil then
		return templateFolder
	end

	if inventoryScrollFrame == nil then
		return nil
	end

	local foundTemplate = inventoryScrollFrame:FindFirstChild("Template")

	if foundTemplate ~= nil and foundTemplate:IsA("Folder") then
		templateFolder = foundTemplate
		return foundTemplate
	end

	warn("[InventoryController] missing Template folder inside INVENTORY_SCROLL_FRAME")
	return nil
end

local function findRarityTemplate(rarity: string): GuiObject?
	local folder = getTemplateFolder()

	if folder == nil then
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
		local found = folder:FindFirstChild(name, true)

		if found ~= nil and found:IsA("GuiObject") then
			return found
		end
	end

	warn(`[InventoryController] missing rarity template for {rarity} inside Template folder`)
	return nil
end

local function clearRowItemClones(row: Instance?)
	if row == nil then
		return
	end

	for _, child in row:GetDescendants() do
		if child:GetAttribute(CLONE_ATTRIBUTE) == true then
			child:Destroy()
		end
	end
end

local function clearGeneratedRows()
	if inventoryScrollFrame == nil then
		return
	end

	for _, child in inventoryScrollFrame:GetChildren() do
		if child:GetAttribute(ROW_CLONE_ATTRIBUTE) == true then
			child:Destroy()
		end
	end

	clearRowItemClones(ownedRowTemplate)
	clearRowItemClones(unownedRowTemplate)
end

local function getEffectiveUIScale(instance: Instance): number
	local scale = 1
	local current: Instance? = instance

	while current ~= nil do
		for _, child in current:GetChildren() do
			if child:IsA("UIScale") then
				scale *= child.Scale
			end
		end

		current = current.Parent
	end

	return math.max(scale, 0.001)
end

local function updateInventoryCanvasSize()
	if inventoryScrollFrame == nil then
		return
	end

	inventoryScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y

	local listLayout = inventoryScrollFrame:FindFirstChildOfClass("UIListLayout")
	if listLayout ~= nil then
		local canvasHeight = math.ceil(listLayout.AbsoluteContentSize.Y / getEffectiveUIScale(inventoryScrollFrame))
			+ INVENTORY_CANVAS_BOTTOM_PADDING
		inventoryScrollFrame.CanvasSize = UDim2.fromOffset(0, canvasHeight)
	else
		inventoryScrollFrame.CanvasSize = UDim2.fromOffset(0, 0)
	end

	local maxCanvasY =
		math.max(0, inventoryScrollFrame.AbsoluteCanvasSize.Y - inventoryScrollFrame.AbsoluteWindowSize.Y)
	local currentCanvasPosition = inventoryScrollFrame.CanvasPosition
	if currentCanvasPosition.Y > maxCanvasY then
		inventoryScrollFrame.CanvasPosition = Vector2.new(currentCanvasPosition.X, maxCanvasY)
	end
end

local function scheduleInventoryCanvasSizeUpdate()
	inventoryCanvasUpdateToken += 1
	local token = inventoryCanvasUpdateToken

	task.defer(function()
		updateInventoryCanvasSize()

		RunService.Heartbeat:Wait()
		if token ~= inventoryCanvasUpdateToken then
			return
		end
		updateInventoryCanvasSize()

		RunService.Heartbeat:Wait()
		if token ~= inventoryCanvasUpdateToken then
			return
		end
		updateInventoryCanvasSize()
	end)
end

local function setCloneEquippedVisible(clone: Instance, equipped: boolean)
	local equippedImage = clone:FindFirstChild("EQUIPPED", true)

	if equippedImage == nil then
		return
	end

	if equippedImage:IsA("GuiObject") then
		equippedImage.Visible = equipped
	end
end

local function setCloneTitle(clone: Instance, title: string)
	local states = clone:FindFirstChild("States", true)

	if states ~= nil then
		local titleLabel = states:FindFirstChild("Title", true)

		if titleLabel ~= nil and titleLabel:IsA("TextLabel") then
			titleLabel.Text = title
			return
		end
	end

	local fallbackTitle = clone:FindFirstChild("Title", true)

	if fallbackTitle ~= nil and fallbackTitle:IsA("TextLabel") then
		fallbackTitle.Text = title
		return
	end

	warn(`[InventoryController] missing Title TextLabel inside {clone:GetFullName()}`)
end

local function findItemIcon(root: Instance): ImageLabel?
	local found = root:FindFirstChild("ItemIcon", true)
	if found ~= nil and found:IsA("ImageLabel") then
		return found
	end

	return nil
end

local function setImageAsset(imageLabel: ImageLabel?, iconAssetId: string?)
	if imageLabel == nil then
		return
	end

	if iconAssetId == nil then
		imageLabel.Image = ""
		imageLabel.Visible = false
		return
	end

	imageLabel.Image = iconAssetId
	imageLabel.Visible = true
	imageLabel.Active = false
	imageLabel.Selectable = false
	imageLabel.Interactable = false
end

local function setItemIcon(imageLabel: ImageLabel?, category: string, itemId: string)
	setImageAsset(imageLabel, InventoryItemVisuals.GetIconAssetId(category, itemId))
end

local function setCloneIcon(clone: Instance, category: string, itemId: string)
	setItemIcon(findItemIcon(clone), category, itemId)
end

local function getClickableFromClone(clone: GuiObject): GuiButton?
	if clone:IsA("GuiButton") then
		return clone
	end

	local button = clone:FindFirstChildWhichIsA("GuiButton", true)

	if button ~= nil then
		return button
	end

	return nil
end

local function applyPageButtonVisual(button: TextButton?, selected: boolean)
	if button == nil then
		return
	end

	button.AutoButtonColor = true
	button.BackgroundColor3 = if selected then SELECTED_PAGE_COLOR else UNSELECTED_PAGE_COLOR
	button.BackgroundTransparency = if selected
		then SELECTED_PAGE_BACKGROUND_TRANSPARENCY
		else UNSELECTED_PAGE_BACKGROUND_TRANSPARENCY

	local outline = button:FindFirstChild("TabOutline")
	if outline ~= nil and outline:IsA("UIStroke") then
		outline.Color = if selected then SELECTED_PAGE_STROKE_COLOR else UNSELECTED_PAGE_STROKE_COLOR
		outline.Transparency = if selected
			then SELECTED_PAGE_STROKE_TRANSPARENCY
			else UNSELECTED_PAGE_STROKE_TRANSPARENCY
		outline.Thickness = if selected then 2 else 1.25
	end

	local underline = button:FindFirstChild("ActiveUnderline")
	if underline ~= nil and underline:IsA("GuiObject") then
		underline.Visible = selected
		underline.BackgroundColor3 = SELECTED_PAGE_STROKE_COLOR
	end

	local title = button:FindFirstChild("Title")
	if title ~= nil and title:IsA("TextLabel") then
		title.TextColor3 = if selected then SELECTED_PAGE_TEXT_COLOR else UNSELECTED_PAGE_TEXT_COLOR
		title.TextTransparency = if selected then 0 else 0.08

		local titleStroke = title:FindFirstChild("Outer")
		if titleStroke ~= nil and titleStroke:IsA("UIStroke") then
			titleStroke.Color = Color3.fromRGB(24, 18, 35)
			titleStroke.Transparency = if selected then 0 else 0.25
			titleStroke.Thickness = if selected then 0.11 else 0.08
		end
	end
end

local function updatePageButtonsVisual()
	applyPageButtonVisual(abilitiesButton, currentPage == PAGE_ABILITIES)
	applyPageButtonVisual(skinsButton, currentPage == PAGE_SKINS)
	applyPageButtonVisual(shopButton, currentPage == PAGE_SHOP)
end

local function updateEquipButton()
	if itemEquipButton == nil then
		return
	end

	if currentPage == PAGE_SHOP then
		local product = if selectedShopProductKey ~= nil then ShopProducts.GetEntry(selectedShopProductKey) else nil
		if product == nil then
			setEquipButtonText("BUY")
			setEquipButtonEnabled(false)
			return
		end

		setEquipButtonText(if product.robuxPrice ~= nil then `R$ {product.robuxPrice}` else "BUY")
		setEquipButtonEnabled(product.productId > 0 or (product.gamePassId ~= nil and product.gamePassId > 0))
		return
	end

	if selectedCategory == nil or selectedItemId == nil then
		setEquipButtonText("EQUIP")
		setEquipButtonEnabled(false)
		return
	end

	local category = selectedCategory
	local itemId = selectedItemId

	if not selectedItemOwned then
		setEquipButtonText("DRAW")
		setEquipButtonEnabled(true)
		return
	end

	if isEquipped(category, itemId) then
		setEquipButtonText("EQUIPPED")
		setEquipButtonEnabled(false)
		return
	end

	setEquipButtonEnabled(true)
	setEquipButtonText("EQUIP")
end

local function updateUpgradeButton()
	if abilityUpgradeButton == nil then
		return
	end

	local shouldShow = currentPage ~= PAGE_SHOP
		and selectedCategory == CATEGORY_ABILITY
		and selectedItemId ~= nil
		and selectedItemOwned
	abilityUpgradeButton.Visible = shouldShow
	abilityUpgradeButton.Size = if shouldShow then ACTION_BUTTON_SIZE else HIDDEN_ACTION_BUTTON_SIZE

	if not shouldShow or selectedItemId == nil then
		setUpgradeButtonEnabled(false)
		setUpgradeButtonText("UPGRADE")
		return
	end

	local abilityId = selectedItemId
	local level = getAbilityLevelValue(abilityId)
	local maxLevel = getAbilityMaxLevel()
	local fragments = getAbilityFragments(abilityId)
	local cost = getAbilityUpgradeCost(abilityId)

	if cost == nil or level >= maxLevel then
		setUpgradeButtonText(`MAX LV {maxLevel}`)
		setUpgradeButtonEnabled(false)
		return
	end

	setUpgradeButtonText(`UPGRADE {fragments}/{cost}`)
	setUpgradeButtonEnabled(fragments >= cost)
end

updateSelectedActionButtons = function()
	updateEquipButton()
	updateUpgradeButton()
end

local function setCloneAbilityProgress(clone: GuiObject, category: string, itemId: string, owned: boolean)
	local progress = clone:FindFirstChild(ABILITY_PROGRESS_NAME)
	if progress == nil or not progress:IsA("Frame") then
		warn(`[InventoryController] missing {ABILITY_PROGRESS_NAME} frame in {clone:GetFullName()}`)
		return
	end

	progress.Visible = category == CATEGORY_ABILITY and owned

	if not progress.Visible then
		return
	end

	local fragments = getAbilityFragments(itemId)
	local cost = getAbilityUpgradeCost(itemId)
	local maxLevel = getAbilityMaxLevel()
	local level = getAbilityLevelValue(itemId)
	local fillRatio = 1
	local text = `LV {level} MAX`

	if cost ~= nil and level < maxLevel then
		fillRatio = math.clamp(fragments / cost, 0, 1)
		text = `{fragments}/{cost}`
	end

	local fill = progress:FindFirstChild(ABILITY_PROGRESS_FILL_NAME)
	if fill == nil or not fill:IsA("Frame") then
		warn(`[InventoryController] missing {ABILITY_PROGRESS_FILL_NAME} frame in {progress:GetFullName()}`)
		return
	end

	fill.Size = UDim2.fromScale(fillRatio, 1)
	fill.BackgroundColor3 = if cost ~= nil and fragments >= cost then PROGRESS_READY_FILL_COLOR else PROGRESS_FILL_COLOR

	local label = progress:FindFirstChild(ABILITY_PROGRESS_TEXT_NAME)
	if label == nil or not label:IsA("TextLabel") then
		warn(`[InventoryController] missing {ABILITY_PROGRESS_TEXT_NAME} text in {progress:GetFullName()}`)
		return
	end

	label.Text = text
end

local function setCloneAbilityLevelBadge(clone: GuiObject, category: string, itemId: string, owned: boolean)
	local badge = clone:FindFirstChild(ABILITY_LEVEL_BADGE_NAME)
	if badge == nil or not badge:IsA("Frame") then
		warn(`[InventoryController] missing {ABILITY_LEVEL_BADGE_NAME} frame in {clone:GetFullName()}`)
		return
	end

	badge.Visible = category == CATEGORY_ABILITY and owned

	if not badge.Visible then
		return
	end

	local level = getAbilityLevelValue(itemId)

	local label = badge:FindFirstChild(ABILITY_LEVEL_TEXT_NAME)
	if label == nil or not label:IsA("TextLabel") then
		warn(`[InventoryController] missing {ABILITY_LEVEL_TEXT_NAME} text in {badge:GetFullName()}`)
		return
	end

	label.Text = `Lv.{level}`
end

local function selectItem(category: string, itemId: string, owned: boolean)
	selectedCategory = category
	selectedItemId = itemId
	selectedItemOwned = owned
	selectedShopProductKey = nil

	local displayName = getItemDisplayName(category, itemId)
	local rarity = getItemRarity(category, itemId)

	if itemName ~= nil then
		itemName.Text = displayName
	end

	if itemDescription ~= nil then
		if category == CATEGORY_ABILITY then
			local level = getAbilityLevelValue(itemId)
			itemDescription.Text = InventoryAbilityText.GetEffectDescription(itemId, level)
		else
			itemDescription.Text = `Rarity: {rarity}`
		end
	end

	setItemIcon(itemImage, category, itemId)

	if inventoryItemInfo ~= nil then
		inventoryItemInfo.Visible = true
	end

	updateSelectedActionButtons()
end

local function selectShopProduct(productKey: string)
	selectedCategory = nil
	selectedItemId = nil
	selectedItemOwned = false
	selectedShopProductKey = productKey
	InventoryUpgradeConfirm.Hide()

	local product = ShopProducts.GetEntry(productKey)
	if product == nil then
		clearSelectedItem()
		return
	end

	if itemName ~= nil then
		itemName.Text = product.displayName
	end

	if itemDescription ~= nil then
		itemDescription.Text = if product.description == ""
			then product.rewardText
			else `{product.rewardText}\n{product.description}`
	end

	setImageAsset(itemImage, product.iconAssetId)

	if inventoryItemInfo ~= nil then
		inventoryItemInfo.Visible = true
	end

	updateSelectedActionButtons()
end

clearSelectedItem = function()
	selectedCategory = nil
	selectedItemId = nil
	selectedItemOwned = false
	selectedShopProductKey = nil
	InventoryUpgradeConfirm.Hide()

	if inventoryItemInfo ~= nil then
		inventoryItemInfo.Visible = false
	end

	if itemName ~= nil then
		itemName.Text = ""
	end

	if itemDescription ~= nil then
		itemDescription.Text = ""
	end

	if itemImage ~= nil then
		itemImage.Image = ""
		itemImage.Visible = false
	end

	updateSelectedActionButtons()
end

local function getDrawIdForItem(category: string, itemId: string): string?
	local drawCatalog = DrawConfig.DrawCatalog :: any
	local robuxDrawCatalog = DrawConfig.RobuxDrawCatalog :: any
	for _, drawId in DrawConfig.DrawOrder do
		local drawConfig = drawCatalog[drawId] or robuxDrawCatalog[drawId]
		if type(drawId) ~= "string" or type(drawConfig) ~= "table" then
			continue
		end

		local entries = drawConfig.Entries
		if type(entries) ~= "table" then
			continue
		end

		for _, entry in entries do
			if type(entry) == "table" and entry.Category == category and entry.ItemId == itemId then
				return drawId
			end
		end
	end

	return nil
end

local function openDrawForItem(category: string, itemId: string)
	local drawId = getDrawIdForItem(category, itemId)
	if drawId == nil then
		return
	end

	setScreenVisible(false)
	DrawController:Start()
	DrawController:OpenDraw(drawId)
end

local function equipSelectedItem()
	if currentPage == PAGE_SHOP then
		local product = if selectedShopProductKey ~= nil then ShopProducts.GetEntry(selectedShopProductKey) else nil
		if product == nil then
			updateEquipButton()
			return
		end

		if product.kind == "GamePass" then
			local gamePassId = product.gamePassId
			if gamePassId == nil or gamePassId <= 0 then
				warn(`[InventoryController] GamePass product {product.productKey} has no GamePassId configured`)
				updateEquipButton()
				return
			end

			local ok, err =
				pcall(MarketplaceService.PromptGamePassPurchase, MarketplaceService, localPlayer, gamePassId)
			if not ok then
				warn(`[InventoryController] failed to prompt GamePass product {product.productKey}: {tostring(err)}`)
			end
		else
			if product.productId <= 0 then
				warn(`[InventoryController] Robux product {product.productKey} has no ProductId configured`)
				updateEquipButton()
				return
			end

			local ok, err =
				pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, localPlayer, product.productId)
			if not ok then
				warn(`[InventoryController] failed to prompt Robux product {product.productKey}: {tostring(err)}`)
			end
		end
		return
	end

	if selectedCategory == nil or selectedItemId == nil then
		return
	end

	if not selectedItemOwned then
		openDrawForItem(selectedCategory, selectedItemId)
		return
	end

	local category = selectedCategory
	local itemId = selectedItemId

	if isEquipped(category, itemId) then
		updateEquipButton()
		return
	end

	requestEquipItemRemote:FireServer({
		category = category,
		itemId = itemId,
	})
end

local function submitUpgradeAbility(abilityId: string)
	local cost = getAbilityUpgradeCost(abilityId)
	if cost == nil then
		updateUpgradeButton()
		return
	end

	if getAbilityFragments(abilityId) < cost then
		updateUpgradeButton()
		return
	end

	setUpgradeButtonEnabled(false)
	setUpgradeButtonText("UPGRADING...")

	requestUpgradeAbilityRemote:FireServer({
		abilityId = abilityId,
	})
end

local function showUpgradeConfirmation(abilityId: string)
	local currentLevel = getAbilityLevelValue(abilityId)
	local maxLevel = getAbilityMaxLevel()
	local cost = getAbilityUpgradeCost(abilityId)
	if cost == nil or currentLevel >= maxLevel then
		updateUpgradeButton()
		return
	end

	if getAbilityFragments(abilityId) < cost then
		updateUpgradeButton()
		return
	end

	local displayName = getItemDisplayName(CATEGORY_ABILITY, abilityId)
	InventoryUpgradeConfirm.Show({
		abilityId = abilityId,
		bodyText = InventoryAbilityText.GetUpgradeSummary(abilityId, currentLevel),
		cost = cost,
		currentLevel = currentLevel,
		displayName = displayName,
		fragments = getAbilityFragments(abilityId),
		onConfirm = submitUpgradeAbility,
	})
end

local function upgradeSelectedAbility()
	if selectedCategory ~= CATEGORY_ABILITY or selectedItemId == nil or not selectedItemOwned then
		updateUpgradeButton()
		return
	end

	showUpgradeConfirmation(selectedItemId)
end

local function setOptionalGuiObjectVisible(root: Instance, name: string, visible: boolean)
	local found = root:FindFirstChild(name, true)
	if found ~= nil and found:IsA("GuiObject") then
		found.Visible = visible
	end
end

local function createShopProductItem(row: Frame, product: ShopProduct, layoutOrder: number)
	local template = findRarityTemplate(product.rarity)

	if template == nil then
		return
	end

	local clone = template:Clone()
	clone.Name = `Shop_{product.productKey}`
	clone.Visible = true
	clone.LayoutOrder = layoutOrder
	clone:SetAttribute(CLONE_ATTRIBUTE, true)
	clone:SetAttribute(CATEGORY_ATTRIBUTE, PAGE_SHOP)
	clone:SetAttribute(ITEM_ID_ATTRIBUTE, product.productKey)
	clone:SetAttribute(RARITY_ATTRIBUTE, product.rarity)
	clone:SetAttribute(OWNED_ATTRIBUTE, false)
	clone.Parent = row

	setCloneTitle(clone, product.displayName)
	setImageAsset(findItemIcon(clone), product.iconAssetId)
	setCloneEquippedVisible(clone, false)
	setOptionalGuiObjectVisible(clone, ABILITY_LEVEL_BADGE_NAME, false)
	setOptionalGuiObjectVisible(clone, ABILITY_PROGRESS_NAME, false)

	local clickable = getClickableFromClone(clone)

	if clickable == nil then
		warn(`[InventoryController] shop product clone has no GuiButton: {clone:GetFullName()}`)
		return
	end

	table.insert(
		connections,
		clickable.Activated:Connect(function()
			selectShopProduct(product.productKey)
		end)
	)
end

local function createInventoryItem(row: Frame, category: string, itemId: string, owned: boolean, layoutOrder: number)
	local rarity = getItemRarity(category, itemId)
	local template = findRarityTemplate(rarity)

	if template == nil then
		return
	end

	local clone = template:Clone()
	clone.Name = `{if owned then "Owned" else "Unowned"}_{category}_{itemId}`
	clone.Visible = true
	clone.LayoutOrder = layoutOrder
	clone:SetAttribute(CLONE_ATTRIBUTE, true)
	clone:SetAttribute(CATEGORY_ATTRIBUTE, category)
	clone:SetAttribute(ITEM_ID_ATTRIBUTE, itemId)
	clone:SetAttribute(RARITY_ATTRIBUTE, rarity)
	clone:SetAttribute(OWNED_ATTRIBUTE, owned)
	clone.Parent = row

	setCloneTitle(clone, getItemDisplayName(category, itemId))
	setCloneIcon(clone, category, itemId)

	local equipped = owned and isEquipped(category, itemId)
	setCloneEquippedVisible(clone, equipped)
	setCloneAbilityLevelBadge(clone, category, itemId, owned)
	setCloneAbilityProgress(clone, category, itemId, owned)

	local clickable = getClickableFromClone(clone)

	if clickable == nil then
		warn(`[InventoryController] inventory clone has no GuiButton: {clone:GetFullName()}`)
		return
	end

	table.insert(
		connections,
		clickable.Activated:Connect(function()
			selectItem(category, itemId, owned)
		end)
	)
end

local function getOrCreateRow(baseRow: Frame?, rowName: string, rowIndex: number, layoutOrder: number): Frame?
	if baseRow == nil then
		return nil
	end

	local row: Frame

	if rowIndex == 1 then
		row = baseRow
	else
		row = baseRow:Clone()
		row.Name = `{rowName}{rowIndex - 1}`
		row:SetAttribute(ROW_CLONE_ATTRIBUTE, true)
		row.Parent = inventoryScrollFrame
	end

	row.Visible = true
	row.LayoutOrder = layoutOrder
	clearRowItemClones(row)

	return row
end

local function renderItemsInRows(
	items: { string },
	category: string,
	owned: boolean,
	baseRow: Frame?,
	rowName: string,
	firstLayoutOrder: number
)
	if baseRow == nil then
		return
	end

	if #items <= 0 then
		baseRow.Visible = false
		clearRowItemClones(baseRow)
		return
	end

	local rowIndex = 1
	local itemIndexInRow = 0
	local currentRow = getOrCreateRow(baseRow, rowName, rowIndex, firstLayoutOrder)

	for _, itemId in items do
		itemIndexInRow += 1

		if itemIndexInRow > ITEMS_PER_ROW then
			rowIndex += 1
			itemIndexInRow = 1
			currentRow = getOrCreateRow(baseRow, rowName, rowIndex, firstLayoutOrder + rowIndex - 1)
		end

		if currentRow ~= nil then
			createInventoryItem(currentRow, category, itemId, owned, itemIndexInRow)
		end
	end
end

local function renderShopProducts()
	local products = ShopProducts.GetProducts()

	if unownedTitle ~= nil then
		unownedTitle.Visible = false
	end

	if unownedRowTemplate ~= nil then
		unownedRowTemplate.Visible = false
		clearRowItemClones(unownedRowTemplate)
	end

	if #products <= 0 then
		if ownedRowTemplate ~= nil then
			ownedRowTemplate.Visible = false
			clearRowItemClones(ownedRowTemplate)
		end
		return
	end

	local rowIndex = 1
	local itemIndexInRow = 0
	local currentRow = getOrCreateRow(ownedRowTemplate, "Shop", rowIndex, 1)

	for _, product in products do
		itemIndexInRow += 1

		if itemIndexInRow > ITEMS_PER_ROW then
			rowIndex += 1
			itemIndexInRow = 1
			currentRow = getOrCreateRow(ownedRowTemplate, "Shop", rowIndex, rowIndex)
		end

		if currentRow ~= nil then
			createShopProductItem(currentRow, product, itemIndexInRow)
		end
	end
end

function InventoryController:RenderInventory()
	clearGeneratedRows()
	updatePageButtonsVisual()

	if currentPage == PAGE_SHOP then
		renderShopProducts()
		updateSelectedActionButtons()
		scheduleInventoryCanvasSizeUpdate()
		return
	end

	local category = getCurrentPageCategory()
	local ownedItems = getOwnedItems(category)
	local unownedItems = getUnownedItems(category)

	renderItemsInRows(ownedItems, category, true, ownedRowTemplate, "Owned", 1)

	if unownedTitle ~= nil then
		unownedTitle.Visible = #unownedItems > 0
		unownedTitle.LayoutOrder = 100
	end

	renderItemsInRows(unownedItems, category, false, unownedRowTemplate, "Unowned", 101)

	updateSelectedActionButtons()
	scheduleInventoryCanvasSizeUpdate()
end

local function setCurrentPage(page: string)
	print(`[InventoryController] set page: {page}`)

	if page ~= PAGE_ABILITIES and page ~= PAGE_SKINS and page ~= PAGE_SHOP then
		warn(`[InventoryController] invalid page: {page}`)
		return
	end

	if currentPage == page then
		updatePageButtonsVisual()
		return
	end

	currentPage = page
	clearSelectedItem()
	InventoryController:RenderInventory()
end

local function connectCharacterReset()
	table.insert(
		connections,
		localPlayer.CharacterAdded:Connect(function()
			closeInventoryUi()
			task.defer(syncInventoryEntryButtons)
		end)
	)
end

function InventoryController:GetReferences()
	preventInventoryGuiResetOnSpawn()

	inventoryScrollFrame = nil
	screen = nil
	inventoryItemInfo = nil
	itemName = nil
	itemImage = nil
	itemDescription = nil
	itemEquipButton = nil
	abilityUpgradeButton = nil
	closeButton = nil
	inventoryButton = nil
	abilitiesButton = nil
	skinsButton = nil
	shopButton = nil
	HUD_SCREENGUI = nil
	ownedRowTemplate = nil
	unownedRowTemplate = nil
	unownedTitle = nil
	templateFolder = nil

	inventoryScrollFrame = getReferenceByTag("INVENTORY_SCROLL_FRAME") :: ScrollingFrame?
	screen = getReferenceByTag("INVENTORY_SCREEN")
	inventoryItemInfo = getReferenceByTag("INVENTORY_ITEM_INFO") :: GuiObject?

	closeButton = getReferenceByTag("INVENTORY_CLOSE") :: GuiButton?
	inventoryButton = getOptionalReferenceByTag("INVENTORY_BUTTON") :: GuiButton?

	itemDescription = getReferenceByTag("INVENTORY_DESCRIPTION") :: TextLabel?
	itemName = getReferenceByTag("INVENTORY_ITEM_NAME") :: TextLabel?
	itemImage = getOptionalReferenceByTag("INVENTORY_ITEM_IMAGE") :: ImageLabel?
	itemEquipButton = getReferenceByTag("INVENTORY_EQUIP_BUTTON") :: TextButton?
	abilityUpgradeButton = getOptionalReferenceByTag("INVENTORY_UPGRADE_BUTTON") :: TextButton?

	HUD_SCREENGUI = getReferenceByTag("SIDEMENU") :: ScreenGui?

	abilitiesButton = getReferenceByTag("INVENTORY_ABILITIES_BUTTON") :: TextButton?
	skinsButton = getReferenceByTag("INVENTORY_SKINS_BUTTON") :: TextButton?
	shopButton = getOptionalReferenceByTag("INVENTORY_SHOP_BUTTON") :: TextButton?
	if abilitiesButton ~= nil then
		abilitiesButton:SetAttribute(AUDIO_CLICK_EVENT_ATTRIBUTE, TAB_SWITCH_AUDIO_EVENT)
	end
	if skinsButton ~= nil then
		skinsButton:SetAttribute(AUDIO_CLICK_EVENT_ATTRIBUTE, TAB_SWITCH_AUDIO_EVENT)
	end
	if shopButton ~= nil then
		shopButton:SetAttribute(AUDIO_CLICK_EVENT_ATTRIBUTE, TAB_SWITCH_AUDIO_EVENT)
	end

	if inventoryScrollFrame ~= nil then
		local owned = inventoryScrollFrame:FindFirstChild("Owned")
		local unowned = inventoryScrollFrame:FindFirstChild("Unowned")
		local title = inventoryScrollFrame:FindFirstChild("UnownedTitle")
		local template = inventoryScrollFrame:FindFirstChild("Template")

		if owned ~= nil and owned:IsA("Frame") then
			ownedRowTemplate = owned
		else
			warn("[InventoryController] missing Owned frame inside INVENTORY_SCROLL_FRAME")
		end

		if unowned ~= nil and unowned:IsA("Frame") then
			unownedRowTemplate = unowned
		else
			warn("[InventoryController] missing Unowned frame inside INVENTORY_SCROLL_FRAME")
		end

		if title ~= nil and title:IsA("GuiObject") then
			unownedTitle = title
		end

		if template ~= nil and template:IsA("Folder") then
			templateFolder = template
		else
			warn("[InventoryController] missing Template folder inside INVENTORY_SCROLL_FRAME")
		end
	end
end

function InventoryController:ConnectScreenControls()
	if closeButton ~= nil and closeButton:GetAttribute(INVENTORY_CLOSE_CONNECTED_ATTRIBUTE) ~= true then
		closeButton:SetAttribute(INVENTORY_CLOSE_CONNECTED_ATTRIBUTE, true)
		table.insert(
			connections,
			closeButton.Activated:Connect(function()
				closeInventoryUi()
			end)
		)
	end

	if itemEquipButton ~= nil and itemEquipButton:GetAttribute(INVENTORY_EQUIP_CONNECTED_ATTRIBUTE) ~= true then
		itemEquipButton:SetAttribute(INVENTORY_EQUIP_CONNECTED_ATTRIBUTE, true)
		table.insert(
			connections,
			itemEquipButton.Activated:Connect(function()
				equipSelectedItem()
			end)
		)
	end

	if
		abilityUpgradeButton ~= nil
		and abilityUpgradeButton:GetAttribute(INVENTORY_UPGRADE_CONNECTED_ATTRIBUTE) ~= true
	then
		abilityUpgradeButton:SetAttribute(INVENTORY_UPGRADE_CONNECTED_ATTRIBUTE, true)
		table.insert(
			connections,
			abilityUpgradeButton.Activated:Connect(function()
				upgradeSelectedAbility()
			end)
		)
	end

	if abilitiesButton ~= nil and abilitiesButton:GetAttribute(INVENTORY_PAGE_CONNECTED_ATTRIBUTE) ~= true then
		abilitiesButton:SetAttribute(INVENTORY_PAGE_CONNECTED_ATTRIBUTE, true)
		table.insert(
			connections,
			abilitiesButton.Activated:Connect(function()
				print("[InventoryController] abilities page clicked")
				setCurrentPage(PAGE_ABILITIES)
			end)
		)
	end

	if skinsButton ~= nil and skinsButton:GetAttribute(INVENTORY_PAGE_CONNECTED_ATTRIBUTE) ~= true then
		skinsButton:SetAttribute(INVENTORY_PAGE_CONNECTED_ATTRIBUTE, true)
		table.insert(
			connections,
			skinsButton.Activated:Connect(function()
				print("[InventoryController] skins page clicked")
				setCurrentPage(PAGE_SKINS)
			end)
		)
	end

	if shopButton ~= nil and shopButton:GetAttribute(INVENTORY_PAGE_CONNECTED_ATTRIBUTE) ~= true then
		shopButton:SetAttribute(INVENTORY_PAGE_CONNECTED_ATTRIBUTE, true)
		table.insert(
			connections,
			shopButton.Activated:Connect(function()
				print("[InventoryController] shop page clicked")
				setCurrentPage(PAGE_SHOP)
			end)
		)
	end
end

refreshScreenReferences = function()
	InventoryController:GetReferences()
	InventoryController:ConnectScreenControls()
	updatePageButtonsVisual()
	clearSelectedItem()
	InventoryController:RenderInventory()
	updateSelectedActionButtons()
	syncInventoryEntryButtons()
end

function InventoryController:BuildScreen()
	if self._didBuildScreen then
		return
	end

	self._didBuildScreen = true

	self:GetReferences()

	currentPage = PAGE_ABILITIES
	updatePageButtonsVisual()

	setScreenVisible(false)
	setHudVisible(true)
	connectCharacterReset()
	syncInventoryEntryButtons()

	if inventoryItemInfo ~= nil then
		inventoryItemInfo.Visible = false
	end

	if inventoryButton == nil then
		warn("[InventoryController] inventory button not found")
	end

	table.insert(
		connections,
		CollectionService:GetInstanceAddedSignal("INVENTORY_BUTTON"):Connect(connectInventoryEntryButton)
	)
	table.insert(
		connections,
		CollectionService:GetInstanceAddedSignal("INVENTORY_SCREEN"):Connect(handleInventoryScreenAdded)
	)
	table.insert(connections, CollectionService:GetInstanceAddedSignal("SIDEMENU"):Connect(handleSideMenuAdded))

	self:ConnectScreenControls()

	if abilitiesButton ~= nil then
		print("[InventoryController] abilities button connected")
	else
		warn("[InventoryController] abilities button not found")
	end

	if skinsButton ~= nil then
		print("[InventoryController] skins button connected")
	else
		warn("[InventoryController] skins button not found")
	end

	if shopButton ~= nil then
		print("[InventoryController] shop button connected")
	end

	table.insert(
		connections,
		localPlayer:GetAttributeChangedSignal("PlayerState"):Connect(function()
			updateInventoryEntryVisibility()

			if isLocalPlayerLockedForRound() then
				closeInventoryUi()
			end
		end)
	)

	table.insert(
		connections,
		inventoryUpdatedRemote.OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" then
				return
			end

			local snapshot = payload.inventory

			if type(snapshot) ~= "table" then
				return
			end

			currentInventorySnapshot = snapshot :: InventorySnapshot

			self:RenderInventory()
			updateSelectedActionButtons()
			inventoryChangedEvent:Fire(currentInventorySnapshot, payload)
		end)
	)

	table.insert(
		connections,
		abilityUpgradeResultRemote.OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" then
				return
			end

			local abilityId = payload.abilityId
			if type(abilityId) ~= "string" or abilityId == "" then
				updateUpgradeButton()
				return
			end

			local snapshot = currentInventorySnapshot
			if payload.success == true and snapshot ~= nil then
				local levelAfter = payload.levelAfter
				local fragmentsAfter = payload.fragmentsAfter

				if type(levelAfter) == "number" then
					snapshot.abilityLevels[abilityId] = math.floor(levelAfter)
				end

				if type(fragmentsAfter) == "number" then
					snapshot.abilityFragments[abilityId] = math.max(0, math.floor(fragmentsAfter))
				end

				self:RenderInventory()
			end

			updateSelectedActionButtons()
		end)
	)

	updateSelectedActionButtons()
end

function InventoryController:Init(context)
	if self._didInit then
		return
	end

	self._didInit = true
	self._context = context
	self._localPlayer = localPlayer
	self._connections = connections

	print("[InventoryController] Init")
end

function InventoryController:GetSnapshot(): InventorySnapshot?
	return currentInventorySnapshot
end

function InventoryController:GetEquippedAbility(): string?
	local snapshot = currentInventorySnapshot
	if snapshot ~= nil and type(snapshot.equippedAbility) == "string" and snapshot.equippedAbility ~= "" then
		return snapshot.equippedAbility
	end

	local equippedAbility = localPlayer:GetAttribute("EquippedAbility")
	if type(equippedAbility) == "string" and equippedAbility ~= "" then
		return equippedAbility
	end

	return getDefaultItemId(CATEGORY_ABILITY)
end

function InventoryController:GetEquippedWeaponSkin(): string?
	local snapshot = currentInventorySnapshot
	if snapshot ~= nil and type(snapshot.equippedWeaponSkin) == "string" and snapshot.equippedWeaponSkin ~= "" then
		return snapshot.equippedWeaponSkin
	end

	local equippedWeaponSkin = localPlayer:GetAttribute("EquippedWeaponSkin")
	if type(equippedWeaponSkin) == "string" and equippedWeaponSkin ~= "" then
		return equippedWeaponSkin
	end

	return getDefaultItemId(CATEGORY_WEAPON_SKIN)
end

function InventoryController:GetAbilityLevel(abilityId: string): number
	return getAbilityLevelValue(abilityId)
end

function InventoryController:OnInventoryChanged(callback: (InventorySnapshot?, any?) -> ()): RBXScriptConnection
	return inventoryChangedEvent.Event:Connect(callback)
end

function InventoryController:Open()
	if isLocalPlayerLockedForRound() then
		closeInventoryUi()
		updateInventoryEntryVisibility()
		return
	end

	refreshScreenReferences()
	setScreenVisible(true)
	setHudVisible(false)

	if currentPage ~= PAGE_ABILITIES and currentPage ~= PAGE_SKINS and currentPage ~= PAGE_SHOP then
		currentPage = PAGE_ABILITIES
	end

	self:RenderInventory()
	updateSelectedActionButtons()
end

function InventoryController:Close()
	closeInventoryUi()
end

function InventoryController:Start()
	self:BuildScreen()
end

return InventoryController
