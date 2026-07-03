--!strict

local DrawCatalogUtils = {}

DrawCatalogUtils.DRAW_KIND_COIN = "Coin"
DrawCatalogUtils.DRAW_KIND_ROBUX = "Robux"

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

type InventoryVisuals = {
	GetDisplayName: (category: string, itemId: string) -> string,
	GetRarity: (category: string, itemId: string) -> string,
	GetIconAssetId: (category: string, itemId: string) -> string?,
}

export type ResolvedDraw = {
	drawId: string,
	kind: string,
	config: any,
}

export type RobuxDrawProduct = {
	productKey: string,
	productId: number,
	robuxPrice: number,
	displayName: string,
	count: number,
}

export type HighlightVisualEntry = {
	Category: string,
	ItemId: string,
	Weight: number?,
	exclusive: boolean,
}

export type RollVisualItem = {
	category: string,
	itemId: string,
	displayName: string,
	rarity: string,
	iconAssetId: string?,
}

export type SkinDrawRewardPayload = {
	category: string,
	itemId: string,
	displayName: string,
	rarity: string,
	isNew: boolean,
	duplicateConversionType: string?,
	duplicateConversionAmount: number?,
}

export type SkinDrawResultPayload = {
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

function DrawCatalogUtils.ResolveDraw(drawConfigModule: any, drawId: string): ResolvedDraw?
	local drawCatalog = drawConfigModule.DrawCatalog :: any
	local coinDrawConfig = drawCatalog[drawId]

	if type(coinDrawConfig) == "table" then
		return {
			drawId = drawId,
			kind = DrawCatalogUtils.DRAW_KIND_COIN,
			config = coinDrawConfig,
		}
	end

	local robuxDrawCatalog = drawConfigModule.RobuxDrawCatalog :: any
	local robuxDrawConfig = robuxDrawCatalog[drawId]

	if type(robuxDrawConfig) == "table" then
		return {
			drawId = drawId,
			kind = DrawCatalogUtils.DRAW_KIND_ROBUX,
			config = robuxDrawConfig,
		}
	end

	warn(`[DrawController] invalid draw id: {drawId}`)
	return nil
end

function DrawCatalogUtils.GetDrawConfig(drawConfigModule: any, drawId: string): any?
	local resolvedDraw = DrawCatalogUtils.ResolveDraw(drawConfigModule, drawId)
	return if resolvedDraw ~= nil then resolvedDraw.config else nil
end

function DrawCatalogUtils.GetDefaultDrawId(drawConfigModule: any): string
	for _, drawId in drawConfigModule.DrawOrder do
		if type(drawId) == "string" and DrawCatalogUtils.ResolveDraw(drawConfigModule, drawId) ~= nil then
			return drawId
		end
	end

	return ""
end

function DrawCatalogUtils.FindRobuxDrawProduct(
	economyConfigModule: any,
	drawId: string,
	count: number
): RobuxDrawProduct?
	local robuxCatalog = economyConfigModule.RobuxShopCatalog :: any

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

function DrawCatalogUtils.GetInventoryDisplayName(
	inventoryVisuals: InventoryVisuals,
	category: string,
	itemId: string
): string
	return inventoryVisuals.GetDisplayName(category, itemId)
end

function DrawCatalogUtils.GetInventoryRarity(
	inventoryVisuals: InventoryVisuals,
	category: string,
	itemId: string
): string
	return inventoryVisuals.GetRarity(category, itemId)
end

function DrawCatalogUtils.GetRarityColor(rarity: string): Color3
	return rarityColors[rarity] or Color3.fromRGB(167, 157, 194)
end

local function getBestDrawEntries(inventoryVisuals: InventoryVisuals, drawConfig): { any }
	local entries = {}

	for _, entry in drawConfig.Entries do
		table.insert(entries, entry)
	end

	table.sort(entries, function(a, b)
		local leftRarity = DrawCatalogUtils.GetInventoryRarity(inventoryVisuals, a.Category, a.ItemId)
		local rightRarity = DrawCatalogUtils.GetInventoryRarity(inventoryVisuals, b.Category, b.ItemId)
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

local function getAutoHighlightEntries(inventoryVisuals: InventoryVisuals, drawConfig): { HighlightVisualEntry }
	local entries = {}

	for _, entry in getBestDrawEntries(inventoryVisuals, drawConfig) do
		table.insert(entries, {
			Category = entry.Category,
			ItemId = entry.ItemId,
			Weight = entry.Weight,
			exclusive = false,
		})
	end

	return entries
end

local function findDrawEntry(drawConfig, category: string, itemId: string): any?
	for _, entry in drawConfig.Entries do
		if entry.Category == category and entry.ItemId == itemId then
			return entry
		end
	end

	return nil
end

function DrawCatalogUtils.GetHighlightDrawEntries(
	inventoryVisuals: InventoryVisuals,
	drawConfig
): { HighlightVisualEntry }
	local highlights = drawConfig.Highlights
	if type(highlights) ~= "table" or #highlights <= 0 then
		return getAutoHighlightEntries(inventoryVisuals, drawConfig)
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
		return getAutoHighlightEntries(inventoryVisuals, drawConfig)
	end

	return entries
end

function DrawCatalogUtils.FormatPercent(value: number): string
	if value <= 0 then
		return "0%"
	end

	if value >= 10 then
		return string.format("%.1f%%", value)
	end

	return string.format("%.2f%%", value)
end

function DrawCatalogUtils.GetDrawRarityOdds(inventoryVisuals: InventoryVisuals, drawConfig): { [string]: number }
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
			local rarity = DrawCatalogUtils.GetInventoryRarity(inventoryVisuals, entry.Category, entry.ItemId)
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

local function getSortedRollEntries(inventoryVisuals: InventoryVisuals, drawConfig): { any }
	local entries = {}

	for _, entry in drawConfig.Entries do
		table.insert(entries, entry)
	end

	table.sort(entries, function(a, b)
		local leftRarity = DrawCatalogUtils.GetInventoryRarity(inventoryVisuals, a.Category, a.ItemId)
		local rightRarity = DrawCatalogUtils.GetInventoryRarity(inventoryVisuals, b.Category, b.ItemId)
		local leftRank = rarityRank[leftRarity] or 0
		local rightRank = rarityRank[rightRarity] or 0

		if leftRank ~= rightRank then
			return leftRank > rightRank
		end

		return DrawCatalogUtils.GetInventoryDisplayName(inventoryVisuals, a.Category, a.ItemId)
			< DrawCatalogUtils.GetInventoryDisplayName(inventoryVisuals, b.Category, b.ItemId)
	end)

	return entries
end

function DrawCatalogUtils.GetRollVisualItemFromEntry(inventoryVisuals: InventoryVisuals, entry): RollVisualItem
	return {
		category = entry.Category,
		itemId = entry.ItemId,
		displayName = DrawCatalogUtils.GetInventoryDisplayName(inventoryVisuals, entry.Category, entry.ItemId),
		rarity = DrawCatalogUtils.GetInventoryRarity(inventoryVisuals, entry.Category, entry.ItemId),
		iconAssetId = inventoryVisuals.GetIconAssetId(entry.Category, entry.ItemId),
	}
end

function DrawCatalogUtils.GetRollVisualItemFromReward(
	inventoryVisuals: InventoryVisuals,
	reward: SkinDrawRewardPayload
): RollVisualItem
	return {
		category = reward.category,
		itemId = reward.itemId,
		displayName = reward.displayName,
		rarity = reward.rarity,
		iconAssetId = inventoryVisuals.GetIconAssetId(reward.category, reward.itemId),
	}
end

function DrawCatalogUtils.HasHighlightDrawReward(drawConfig, result: SkinDrawResultPayload?): boolean
	if drawConfig == nil or result == nil then
		return false
	end

	local highlights = drawConfig.Highlights
	if type(highlights) ~= "table" then
		return false
	end

	for _, highlight in highlights do
		if type(highlight) ~= "table" then
			continue
		end

		local highlightConfig = highlight :: any
		local category = highlightConfig.Category
		local itemId = highlightConfig.ItemId
		if type(category) ~= "string" or type(itemId) ~= "string" then
			continue
		end

		for _, reward in result.rewards do
			if reward.category == category and reward.itemId == itemId then
				return true
			end
		end
	end

	return false
end

function DrawCatalogUtils.BuildRollVisualItems(
	inventoryVisuals: InventoryVisuals,
	drawConfig,
	reward: SkinDrawRewardPayload,
	leadCardCount: number,
	trailCardCount: number
): ({ RollVisualItem }, number)
	local entries = getSortedRollEntries(inventoryVisuals, drawConfig)
	local targetItem = DrawCatalogUtils.GetRollVisualItemFromReward(inventoryVisuals, reward)

	if #entries <= 0 then
		return { targetItem }, 1
	end

	local items = {} :: { RollVisualItem }

	for index = 1, leadCardCount do
		local entry = entries[((index - 1) % #entries) + 1]
		table.insert(items, DrawCatalogUtils.GetRollVisualItemFromEntry(inventoryVisuals, entry))
	end

	local targetIndex = #items + 1
	table.insert(items, targetItem)

	for index = 1, trailCardCount do
		local entry = entries[((index - 1) % #entries) + 1]
		table.insert(items, DrawCatalogUtils.GetRollVisualItemFromEntry(inventoryVisuals, entry))
	end

	return items, targetIndex
end

return DrawCatalogUtils
