--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Network = Shared:WaitForChild("Network")

local InventoryConfig = require(Config:WaitForChild("InventoryConfig"))
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local Remotes = require(Network:WaitForChild("Remotes"))

local requestEquipItemRemote = Remotes.GetClientToServer(Network, Remotes.ClientToServer.RequestEquipItem)

local inventoryUpdatedRemote = Remotes.GetServerToClient(Network, Remotes.ServerToClient.InventoryUpdated)

local InventoryController = {
	Name = "InventoryController",
}

local CATEGORY_ABILITY = "Ability"
local CATEGORY_WEAPON_SKIN = "WeaponSkin"

local PAGE_ABILITIES = "Abilities"
local PAGE_SKINS = "Skins"

local INVENTORY_PART_TAG = "INVENTORY_PART"
local INVENTORY_PART_MARGIN = 2.5
local INVENTORY_PART_CHECK_INTERVAL = 0.1

local ITEMS_PER_ROW = 3

local CLONE_ATTRIBUTE = "IS_CLONE"
local ROW_CLONE_ATTRIBUTE = "IS_ROW_CLONE"
local CATEGORY_ATTRIBUTE = "CATEGORY"
local ITEM_ID_ATTRIBUTE = "ITEM_ID"
local RARITY_ATTRIBUTE = "RARITY"
local OWNED_ATTRIBUTE = "OWNED"

local SELECTED_PAGE_COLOR = Color3.fromRGB(148, 41, 224)
local UNSELECTED_PAGE_COLOR = Color3.fromRGB(68, 35, 94)

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

local inventoryScrollFrame: ScrollingFrame?
local screen: Instance?
local inventoryItemInfo: GuiObject?
local itemName: TextLabel?
local itemImage: ImageLabel?
local itemDescription: TextLabel?
local itemEquipButton: TextButton?
local closeButton: GuiButton?
local inventoryButton: GuiButton?

local abilitiesButton: TextButton?
local skinsButton: TextButton?
local HUD_SCREENGUI: ScreenGui?

local ownedRowTemplate: Frame?
local unownedRowTemplate: Frame?
local unownedTitle: GuiObject?
local templateFolder: Folder?

local currentInventorySnapshot: InventorySnapshot?
local selectedCategory: string?
local selectedItemId: string?
local selectedItemOwned = false
local currentPage = PAGE_ABILITIES

local lastInventoryPartCheck = 0
local isWatchingInventoryPart = false
local wasInsideInventoryPart = false

local connections: { RBXScriptConnection } = {}

local getItemRarity: (category: string, itemId: string) -> string

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
	elseif instance:IsA("Frame") then
		instance.Visible = visible
	end
end

local function setHudVisible(visible: boolean)
	setGuiVisible(HUD_SCREENGUI, visible)
end

local function closeInventoryUi()
	setScreenVisible(false)
	setHudVisible(true)
end

local function getInventoryBasePart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("Model") then
		if instance.PrimaryPart ~= nil then
			return instance.PrimaryPart
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

	return math.abs(localPosition.X) <= halfSize.X + INVENTORY_PART_MARGIN
		and math.abs(localPosition.Y) <= halfSize.Y + INVENTORY_PART_MARGIN
		and math.abs(localPosition.Z) <= halfSize.Z + INVENTORY_PART_MARGIN
end

local function isInsideAnyInventoryPart(): boolean
	local character = localPlayer.Character
	if character == nil then
		return false
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart == nil or not rootPart:IsA("BasePart") then
		return false
	end

	for _, taggedInstance in CollectionService:GetTagged(INVENTORY_PART_TAG) do
		local inventoryPart = getInventoryBasePart(taggedInstance)

		if inventoryPart ~= nil and inventoryPart:IsDescendantOf(workspace) then
			if isPositionInsidePart(inventoryPart, rootPart.Position) then
				return true
			end
		end
	end

	return false
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

getItemRarity = function(category: string, itemId: string): string
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

	local tokenShopCatalog = (EconomyConfig :: any).SkinTokenShopCatalog

	if type(tokenShopCatalog) == "table" then
		local categoryShop = tokenShopCatalog[category]

		if type(categoryShop) == "table" then
			local shopItem = categoryShop[itemId]

			if type(shopItem) == "table" and type(shopItem.Rarity) == "string" then
				return shopItem.Rarity
			end
		end
	end

	return "Common"
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
	local ownedSet = {}
	local ownedItems = {}

	if snapshot ~= nil then
		local snapshotOwnedItems = {}

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

local function updatePageButtonsVisual()
	if abilitiesButton ~= nil then
		abilitiesButton.BackgroundColor3 = if currentPage == PAGE_ABILITIES
			then SELECTED_PAGE_COLOR
			else UNSELECTED_PAGE_COLOR
	end

	if skinsButton ~= nil then
		skinsButton.BackgroundColor3 = if currentPage == PAGE_SKINS then SELECTED_PAGE_COLOR else UNSELECTED_PAGE_COLOR
	end
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

	if not selectedItemOwned then
		setEquipButtonText("unlocked in the gacha")
		setEquipButtonEnabled(false)
		return
	end

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

local function selectItem(category: string, itemId: string, owned: boolean)
	selectedCategory = category
	selectedItemId = itemId
	selectedItemOwned = owned

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

local function clearSelectedItem()
	selectedCategory = nil
	selectedItemId = nil
	selectedItemOwned = false

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
	end

	updateEquipButton()
end

local function equipSelectedItem()
	if selectedCategory == nil or selectedItemId == nil then
		return
	end

	if not selectedItemOwned then
		setEquipButtonText("unlocked in the gacha")
		setEquipButtonEnabled(false)
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

	local equipped = owned and isEquipped(category, itemId)
	setCloneEquippedVisible(clone, equipped)

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

function InventoryController:RenderInventory()
	clearGeneratedRows()
	updatePageButtonsVisual()

	local category = getCurrentPageCategory()
	local ownedItems = getOwnedItems(category)
	local unownedItems = getUnownedItems(category)

	renderItemsInRows(ownedItems, category, true, ownedRowTemplate, "Owned", 1)

	if unownedTitle ~= nil then
		unownedTitle.Visible = #unownedItems > 0
		unownedTitle.LayoutOrder = 100
	end

	renderItemsInRows(unownedItems, category, false, unownedRowTemplate, "Unowned", 101)

	updateEquipButton()
end

local function setCurrentPage(page: string)
	print(`[InventoryController] set page: {page}`)

	if page ~= PAGE_ABILITIES and page ~= PAGE_SKINS then
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

local function startInventoryPartWatcher()
	if isWatchingInventoryPart then
		return
	end

	isWatchingInventoryPart = true
	wasInsideInventoryPart = false

	table.insert(
		connections,
		RunService.Heartbeat:Connect(function()
			local now = os.clock()

			if now - lastInventoryPartCheck < INVENTORY_PART_CHECK_INTERVAL then
				return
			end

			lastInventoryPartCheck = now

			local isInside = isInsideAnyInventoryPart()

			if isInside and not wasInsideInventoryPart then
				InventoryController:Open()
			end

			wasInsideInventoryPart = isInside
		end)
	)

	table.insert(
		connections,
		localPlayer.CharacterAdded:Connect(function()
			wasInsideInventoryPart = false
			closeInventoryUi()
		end)
	)
end

function InventoryController:GetReferences()
	inventoryScrollFrame = getReferenceByTag("INVENTORY_SCROLL_FRAME") :: ScrollingFrame?
	screen = getReferenceByTag("INVENTORY_SCREEN")
	inventoryItemInfo = getReferenceByTag("INVENTORY_ITEM_INFO") :: GuiObject?

	closeButton = getReferenceByTag("INVENTORY_CLOSE") :: GuiButton?
	inventoryButton = getOptionalReferenceByTag("INVENTORY_BUTTON") :: GuiButton?

	itemDescription = getReferenceByTag("INVENTORY_DESCRIPTION") :: TextLabel?
	itemName = getReferenceByTag("INVENTORY_ITEM_NAME") :: TextLabel?
	itemImage = getOptionalReferenceByTag("INVENTORY_ITEM_IMAGE") :: ImageLabel?
	itemEquipButton = getReferenceByTag("INVENTORY_EQUIP_BUTTON") :: TextButton?

	HUD_SCREENGUI = getReferenceByTag("SIDEMENU") :: ScreenGui?

	abilitiesButton = getReferenceByTag("INVENTORY_ABILITIES_BUTTON") :: TextButton?
	skinsButton = getReferenceByTag("INVENTORY_SKINS_BUTTON") :: TextButton?

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
	startInventoryPartWatcher()

	if inventoryItemInfo ~= nil then
		inventoryItemInfo.Visible = false
	end

	if closeButton ~= nil then
		table.insert(
			connections,
			closeButton.Activated:Connect(function()
				closeInventoryUi()
			end)
		)
	end

	if inventoryButton ~= nil then
		print("[InventoryController] inventory button connected")

		table.insert(
			connections,
			inventoryButton.Activated:Connect(function()
				print("[InventoryController] inventory button clicked")
				InventoryController:Open()
			end)
		)
	else
		warn("[InventoryController] inventory button not found")
	end

	if itemEquipButton ~= nil then
		table.insert(
			connections,
			itemEquipButton.Activated:Connect(function()
				equipSelectedItem()
			end)
		)
	end

	if abilitiesButton ~= nil then
		print("[InventoryController] abilities button connected")

		table.insert(
			connections,
			abilitiesButton.Activated:Connect(function()
				print("[InventoryController] abilities page clicked")
				setCurrentPage(PAGE_ABILITIES)
			end)
		)
	else
		warn("[InventoryController] abilities button not found")
	end

	if skinsButton ~= nil then
		print("[InventoryController] skins button connected")

		table.insert(
			connections,
			skinsButton.Activated:Connect(function()
				print("[InventoryController] skins page clicked")
				setCurrentPage(PAGE_SKINS)
			end)
		)
	else
		warn("[InventoryController] skins button not found")
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
	setHudVisible(false)

	if currentPage ~= PAGE_ABILITIES and currentPage ~= PAGE_SKINS then
		currentPage = PAGE_ABILITIES
	end

	self:RenderInventory()
	updateEquipButton()
end

function InventoryController:Close()
	closeInventoryUi()
end

function InventoryController:Start()
	self:BuildScreen()
end

return InventoryController