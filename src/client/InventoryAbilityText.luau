--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local AbilityLevelScaling = require(Config:WaitForChild("AbilityLevelScaling"))
local InventoryConfig = require(Config:WaitForChild("InventoryConfig"))

local InventoryAbilityText = {}

local function formatStatNumber(value: number): string
	if math.abs(value - math.round(value)) < 0.001 then
		return tostring(math.round(value))
	end

	if math.abs(value * 10 - math.round(value * 10)) < 0.001 then
		return string.format("%.1f", value)
	end

	return string.format("%.2f", value)
end

local function formatSeconds(value: number): string
	return `{formatStatNumber(value)}s`
end

local function formatPercentMultiplier(value: number): string
	return `{formatStatNumber(value * 100)}%`
end

local function getResolvedAbilityData(abilityId: string, level: number): any?
	return AbilityLevelScaling.ResolveAbilityData(abilityId, level)
end

local function getAbilityInventoryItem(abilityId: string): any?
	local abilityCategory = InventoryConfig.Categories.Ability
	if type(abilityCategory) ~= "table" or type(abilityCategory.Items) ~= "table" then
		return nil
	end

	return abilityCategory.Items[abilityId]
end

local function getStringField(itemConfig: any?, fieldName: string): string?
	if type(itemConfig) ~= "table" then
		return nil
	end

	local value = itemConfig[fieldName]
	if type(value) ~= "string" or value == "" then
		return nil
	end

	return value
end

function InventoryAbilityText.GetEffectDescription(abilityId: string, _level: number): string
	return getStringField(getAbilityInventoryItem(abilityId), "EffectDescription") or "Effect details are unavailable."
end

local function addUpgradeChange(
	changes: { string },
	label: string,
	before: number?,
	after: number?,
	formatter: ((number) -> string)?
)
	if type(before) ~= "number" or type(after) ~= "number" or math.abs(after - before) < 0.001 then
		return
	end

	local formatValue = formatter or formatStatNumber
	table.insert(changes, `{label}: {formatValue(before)} -> {formatValue(after)}`)
end

function InventoryAbilityText.GetUpgradeSummary(abilityId: string, currentLevel: number): string
	local nextLevel = currentLevel + 1
	local currentData = getResolvedAbilityData(abilityId, currentLevel)
	local nextData = getResolvedAbilityData(abilityId, nextLevel)

	if currentData == nil or nextData == nil then
		return "Upgrade details are unavailable."
	end

	local changes = {} :: { string }
	addUpgradeChange(changes, "Cooldown", currentData.CooldownSeconds, nextData.CooldownSeconds, formatSeconds)
	addUpgradeChange(changes, "Duration", currentData.DurationSeconds, nextData.DurationSeconds, formatSeconds)
	addUpgradeChange(changes, "Distance", currentData.Distance, nextData.Distance, formatStatNumber)
	addUpgradeChange(changes, "Radius", currentData.Radius, nextData.Radius, formatStatNumber)
	addUpgradeChange(changes, "Damage", currentData.Damage, nextData.Damage, formatStatNumber)
	addUpgradeChange(
		changes,
		"Damage taken",
		currentData.DamageTakenMultiplier,
		nextData.DamageTakenMultiplier,
		formatPercentMultiplier
	)
	addUpgradeChange(changes, "Knockback", currentData.KnockbackDistance, nextData.KnockbackDistance, formatStatNumber)
	addUpgradeChange(
		changes,
		"Knockback upward",
		currentData.KnockbackUpwardVelocity,
		nextData.KnockbackUpwardVelocity,
		formatStatNumber
	)
	addUpgradeChange(
		changes,
		"Knockback taken",
		currentData.KnockbackMultiplier,
		nextData.KnockbackMultiplier,
		formatPercentMultiplier
	)
	addUpgradeChange(
		changes,
		"Move speed",
		currentData.WalkSpeedMultiplier,
		nextData.WalkSpeedMultiplier,
		formatPercentMultiplier
	)
	addUpgradeChange(
		changes,
		"Attack invulnerability",
		currentData.InvulnerabilitySeconds,
		nextData.InvulnerabilitySeconds,
		formatSeconds
	)
	addUpgradeChange(
		changes,
		"Jump force",
		currentData.DoubleJumpVelocity,
		nextData.DoubleJumpVelocity,
		formatStatNumber
	)
	addUpgradeChange(changes, "Air control", currentData.AirControlSpeed, nextData.AirControlSpeed, formatStatNumber)
	addUpgradeChange(
		changes,
		"Air move bonus",
		currentData.HorizontalAirMoveBonus,
		nextData.HorizontalAirMoveBonus,
		formatStatNumber
	)
	addUpgradeChange(changes, "Deflect range", currentData.DeflectRange, nextData.DeflectRange, formatStatNumber)
	addUpgradeChange(
		changes,
		"Deflect arc",
		currentData.DeflectArcDegrees,
		nextData.DeflectArcDegrees,
		formatStatNumber
	)
	addUpgradeChange(changes, "Heal amount", currentData.HealAmount, nextData.HealAmount, formatStatNumber)
	addUpgradeChange(
		changes,
		"Charge speed",
		currentData.ChargeSpeedMultiplier,
		nextData.ChargeSpeedMultiplier,
		formatPercentMultiplier
	)
	addUpgradeChange(changes, "Wall scale", currentData.WallScale, nextData.WallScale, formatPercentMultiplier)
	addUpgradeChange(
		changes,
		"Self transparency",
		currentData.SelfTransparency,
		nextData.SelfTransparency,
		formatPercentMultiplier
	)
	addUpgradeChange(
		changes,
		"Enemy transparency",
		currentData.OtherTransparency,
		nextData.OtherTransparency,
		formatPercentMultiplier
	)

	if nextLevel == 5 then
		local level5Text = getStringField(getAbilityInventoryItem(abilityId), "Level5AwakeningDescription")
		if level5Text ~= nil then
			table.insert(changes, level5Text)
		end
	end

	if #changes == 0 then
		return "No visible stat change."
	end

	return table.concat(changes, "\n")
end

return table.freeze(InventoryAbilityText)
