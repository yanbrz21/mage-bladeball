--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Network = Shared:WaitForChild("Network")

local InventoryConfig = require(Config:WaitForChild("InventoryConfig"))
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local Remotes = require(Network:WaitForChild("Remotes"))

local requestEquipItemRemote = Remotes.GetClientToServer(
	Network,
	Remotes.ClientToServer.RequestEquipItem
)

local inventoryUpdatedRemote = Remotes.GetServerToClient(
	Network,
	Remotes.ServerToClient.InventoryUpdated
)

local InventoryController = {
	Name = "InventoryController",
}

local CATEGORY_ABILITY = "Ability"
local CATEGORY_WEAPON_SKIN = "WeaponSkin"

local CLONE_ATTRIBUTE = "IS_CLONE"
local CATEGORY_ATTRIBUTE = "CATEGORY"
local ITEM_ID_ATTRIBUTE = "ITEM_ID"
local RARITY_ATTRIBUTE = "RARITY"

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

local inventoryScrollFrame: ScrollingFrame?
local screen: Instance?
local inventoryItemInfo: GuiObject?
local itemName: TextLabel?
local itemImage: ImageLabel?
local itemDescription: TextLabel?
local itemEquipButton: TextButton?
local closeButton: GuiButton?

local currentInventorySnapshot: InventorySnapshot?
local selectedCategory: string?
local selectedItemId: string?

local connections: { RBXScriptConnection } = {}

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

local function setEquipButtonEnabled(enabled: boolean)
	if itemEquipButton == nil then
		return
	end

	itemEquipButton.Active = enabled
	itemEquipButton.AutoButtonColor = enabled
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

local function getScreenByTag(tag: string): Instance?
	local instance = getReferenceByTag(tag)

	if instance == nil then
		return nil
	end

	if instance:IsA("ScreenGui") or instance:IsA("GuiObject") then
		return instance
	end

	warn(`[InventoryController] {tag} is not ScreenGui/GuiObject, got {instance.ClassName}`)
	return nil
end

local function getGuiObjectByTag(tag: string): GuiObject?
	local instance = getReferenceByTag(tag)

	if instance == nil then
		return nil
	end

	if not instance:IsA("GuiObject") then
		warn(`[InventoryController] {tag} is not a GuiObject, got {instance.ClassName}`)
		return nil
	end

	return instance
end

local function getTextLabelByTag(tag: string): TextLabel?
	local instance = getReferenceByTag(tag)

	if instance == nil then
		return nil
	end

	if not instance:IsA("TextLabel") then
		warn(`[InventoryController] {tag} is not a TextLabel, got {instance.ClassName}`)
		return nil
	end

	return instance
end

local function getOptionalImageLabelByTag(tag: string): ImageLabel?
	local instance = getOptionalReferenceByTag(tag)

	if instance == nil then
		return nil
	end

	if not instance:IsA("ImageLabel") then
		warn(`[InventoryController] {tag} is not an ImageLabel, got {instance.ClassName}`)
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
		warn(`[InventoryController] {tag} is not a TextButton, got {instance.ClassName}`)
		return nil
	end

	return instance
end

local function getGuiButtonByTag(tag: string): GuiButton?
	local instance = getReferenceByTag(tag)

	if instance == nil then
		return nil
	end

	if not instance:IsA("GuiButton") then
		warn(`[InventoryController] {tag} is not a GuiButton, got {instance.ClassName}`)
		return nil
	end

	return instance
end

local function getScrollingFrameByTag(tag: string): ScrollingFrame?
	local instance = getReferenceByTag(tag)

	if instance == nil then
		return nil
	end

	if not instance:IsA("ScrollingFrame") then
		warn(`[InventoryController] {tag} is not a ScrollingFrame, got {instance.ClassName}`)
		return nil
	end

	return instance
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
	local itemConfig = getInventoryItemConfig(category, itemId)

	if itemConfig == nil then
		return itemId
	end

	if type(itemConfig.DisplayName) ~= "string" then
		return itemId
	end

	return itemConfig.DisplayName
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

local function getItemRarity(category: string, itemId: string): string
	local drawCatalog = EconomyConfig.DrawCatalog :: any

	for _, drawConfig in drawCatalog do
		if type(drawConfig) ~= "table" or type(drawConfig.Entries) ~= "table" then
			continue
		end

		for _, entry in drawConfig.Entries do
			if entry.Category == category and entry.ItemId == itemId and type(entry.Rarity) == "string" then
				return entry.Rarity
			end
		end
	end

	local tokenShopCatalog = EconomyConfig.SkinTokenShopCatalog :: any
	local categoryShop = tokenShopCatalog[category]

	if type(categoryShop) == "table" then
		local shopItem = categoryShop[itemId]

		if type(shopItem) == "table" and type(shopItem.Rarity) == "string" then
			return shopItem.Rarity
		end
	end

	return "Common"
end

local function isEquipped(category: string, itemId: string): boolean
	local snapshot = currentInventorySnapshot

	if snapshot == nil then
		return false
	end

	if category == CATEGORY_ABILITY then
		return snapshot.equippedAbility == itemId
	end

	if category == CATEGORY_WEAPON_SKIN then
		return snapshot.equippedWeaponSkin == itemId
	end

	return false
end

local function isDefaultItem(category: string, itemId: string): boolean
	local defaultItemId = getDefaultItemId(category)
	return defaultItemId == itemId
end

local function getOwnedItems(category: string): { string }
	local snapshot = currentInventorySnapshot

	if snapshot == nil then
		return {}
	end

	if category == CATEGORY_ABILITY then
		return snapshot.ownedAbilities or {}
	end

	if category == CATEGORY_WEAPON_SKIN then
		return snapshot.ownedWeaponSkins or {}
	end

	return {}
end

local function findRarityTemplate(rarity: string): GuiObject?
	if inventoryScrollFrame == nil then
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
		local found = inventoryScrollFrame:FindFirstChild(name, true)

		if found ~= nil and found:IsA("GuiObject") then
			return found
		end
	end

	warn(`[InventoryController] missing rarity template for {rarity}`)
	return nil
end

local function clearInventoryClones()
	if inventoryScrollFrame == nil then
		return
	end

	for _, child in inventoryScrollFrame:GetDescendants() do
		if child:GetAttribute(CLONE_ATTRIBUTE) == true then
			child:Destroy()
		end
	end
end

local function setCloneTitle(clone: Instance, title: string)
	local states = clone:FindFirstChild("States", true)

	if states == nil then
		warn(`[InventoryController] missing States inside {clone:GetFullName()}`)
		return
	end

	local titleLabel = states:FindFirstChild("Title", true)

	if titleLabel == nil or not titleLabel:IsA("TextLabel") then
		warn(`[InventoryController] missing States.Title TextLabel inside {clone:GetFullName()}`)
		return
	end

	titleLabel.Text = title
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

local function updateEquipButton()
	if itemEquipButton == nil then
		return
	end

	if selectedCategory == nil or selectedItemId == nil then
		setEquipButtonText("EQUIP")
		setEquipButtonEnabled(false)
		return
	end

	local category = selectedCategory
	local itemId = selectedItemId

	if isEquipped(category, itemId) and isDefaultItem(category, itemId) then
		setEquipButtonText("cant unequip default")
		setEquipButtonEnabled(false)
		return
	end

	setEquipButtonEnabled(true)

	if isEquipped(category, itemId) then
		setEquipButtonText("UNEQUIP")
	else
		setEquipButtonText("EQUIP")
	end
end

local function selectItem(category: string, itemId: string)
	selectedCategory = category
	selectedItemId = itemId

	local displayName = getItemDisplayName(category, itemId)
	local rarity = getItemRarity(category, itemId)

	if itemName ~= nil then
		itemName.Text = displayName
	end

	if itemDescription ~= nil then
		itemDescription.Text = `Rarity: {rarity}`
	end

	if itemImage ~= nil then
		itemImage.Image = ""
	end

	if inventoryItemInfo ~= nil then
		inventoryItemInfo.Visible = true
	end

	updateEquipButton()
end

local function equipSelectedItem()
	if selectedCategory == nil or selectedItemId == nil then
		return
	end

	local category = selectedCategory
	local itemId = selectedItemId

	if isEquipped(category, itemId) then
		local defaultItemId = getDefaultItemId(category)

		if defaultItemId == nil then
			return
		end

		if defaultItemId == itemId then
			setEquipButtonText("cant unequip default")
			setEquipButtonEnabled(false)
			return
		end

		requestEquipItemRemote:FireServer({
			category = category,
			itemId = defaultItemId,
		})

		return
	end

	requestEquipItemRemote:FireServer({
		category = category,
		itemId = itemId,
	})
end

local function createInventoryItem(category: string, itemId: string, layoutOrder: number)
	if inventoryScrollFrame == nil then
		return
	end

	local rarity = getItemRarity(category, itemId)
	local template = findRarityTemplate(rarity)

	if template == nil then
		return
	end

	local clone = template:Clone()
	clone.Name = `{category}_{itemId}`
	clone.Visible = true
	clone.LayoutOrder = layoutOrder
	clone:SetAttribute(CLONE_ATTRIBUTE, true)
	clone:SetAttribute(CATEGORY_ATTRIBUTE, category)
	clone:SetAttribute(ITEM_ID_ATTRIBUTE, itemId)
	clone:SetAttribute(RARITY_ATTRIBUTE, rarity)
	clone.Parent = inventoryScrollFrame

	setCloneTitle(clone, getItemDisplayName(category, itemId))

	local clickable = getClickableFromClone(clone)

	if clickable == nil then
		warn(`[InventoryController] inventory clone has no GuiButton: {clone:GetFullName()}`)
		return
	end

	table.insert(
		connections,
		clickable.Activated:Connect(function()
			selectItem(category, itemId)
		end)
	)
end

function InventoryController:RenderInventory()
	clearInventoryClones()

	local layoutOrder = 0

	for _, abilityId in getOwnedItems(CATEGORY_ABILITY) do
		layoutOrder += 1
		createInventoryItem(CATEGORY_ABILITY, abilityId, layoutOrder)
	end

	for _, skinId in getOwnedItems(CATEGORY_WEAPON_SKIN) do
		layoutOrder += 1
		createInventoryItem(CATEGORY_WEAPON_SKIN, skinId, layoutOrder)
	end

	updateEquipButton()
end

function InventoryController:GetReferences()
	inventoryScrollFrame = getScrollingFrameByTag("INVENTORY_SCROLL_FRAME")
	screen = getScreenByTag("INVENTORY_SCREEN")
	inventoryItemInfo = getGuiObjectByTag("INVENTORY_ITEM_INFO")

	closeButton = getGuiButtonByTag("INVENTORY_CLOSE")

	itemDescription = getTextLabelByTag("INVENTORY_DESCRIPTION")
	itemName = getTextLabelByTag("INVENTORY_ITEM_NAME")
	itemImage = getOptionalImageLabelByTag("INVENTORY_ITEM_IMAGE")
	itemEquipButton = getTextButtonByTag("INVENTORY_EQUIP_BUTTON")
end

function InventoryController:BuildScreen()
	if self._didBuildScreen then
		return
	end

	self._didBuildScreen = true

	self:GetReferences()

	if inventoryItemInfo ~= nil then
		inventoryItemInfo.Visible = false
	end

	if closeButton ~= nil then
		table.insert(
			connections,
			closeButton.Activated:Connect(function()
				setScreenVisible(false)
			end)
		)
	end

	if itemEquipButton ~= nil then
		table.insert(
			connections,
			itemEquipButton.Activated:Connect(function()
				equipSelectedItem()
			end)
		)
	end

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
			updateEquipButton()
		end)
	)

	updateEquipButton()
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

function InventoryController:Open()
	setScreenVisible(true)
	self:RenderInventory()
	updateEquipButton()
end

function InventoryController:Start()
	self:BuildScreen()
end

return InventoryController