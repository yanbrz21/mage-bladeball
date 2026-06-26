--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local InventoryConfig = require(Config:WaitForChild("InventoryConfig"))

local InventoryItemVisuals = {}

local function getItemConfig(category: string, itemId: string): any?
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

function InventoryItemVisuals.GetDisplayName(category: string, itemId: string): string
	local itemConfig = getItemConfig(category, itemId)
	if itemConfig == nil or type(itemConfig.DisplayName) ~= "string" then
		return itemId
	end

	return itemConfig.DisplayName
end

function InventoryItemVisuals.GetRarity(category: string, itemId: string): string
	local itemConfig = getItemConfig(category, itemId)
	if itemConfig == nil or type(itemConfig.Rarity) ~= "string" or itemConfig.Rarity == "" then
		return "Common"
	end

	return itemConfig.Rarity
end

function InventoryItemVisuals.GetIconAssetId(category: string, itemId: string): string?
	local itemConfig = getItemConfig(category, itemId)
	if itemConfig == nil or type(itemConfig.IconAssetId) ~= "string" or itemConfig.IconAssetId == "" then
		return nil
	end

	return itemConfig.IconAssetId
end

return table.freeze(InventoryItemVisuals)
