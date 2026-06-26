--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local AbilityLevelScaling = require(Config:WaitForChild("AbilityLevelScaling"))

local InventoryAbilityText = {}

local LEVEL_5_UPGRADE_TEXT_BY_ABILITY_ID = {
	dash = "DASH: Greatly increases dash speed.",
	barrier = "BARRIER: Greatly strengthens knockback resistance while blocking.",
	stone_form = "GOLDEN BODY: Immediately cancels knockback.",
	qi_burst = "QI BURST: Greatly increases the burst knockback.",
	sprint = "SPRINT: Greatly reduces cooldown.",
	double_jump = "DOUBLE JUMP: Greatly improves movement control while airborne.",
	healing_zone = "HEALING ZONE: Unlocks a restorative area that heals allies over time.",
	ice_wall = "ICE WALL: Unlocks a wall that blocks movement and projectiles.",
} :: { [string]: string }

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

function InventoryAbilityText.GetEffectDescription(abilityId: string, level: number): string
	local abilityData = getResolvedAbilityData(abilityId, level)
	if abilityData == nil then
		return "Effect details are unavailable."
	end

	if abilityId == "dash" then
		return "Dash in your current movement direction."
	elseif abilityId == "barrier" then
		return "Create a barrier that blocks damage and reduces knockback."
	elseif abilityId == "stone_form" then
		return "Enter Golden Body, becoming immune to damage and knockback for a short time."
	elseif abilityId == "qi_burst" then
		return "Release a burst of qi that damages and knocks back nearby enemies."
	elseif abilityId == "sprint" then
		return "Move faster for a short time."
	elseif abilityId == "double_jump" then
		return "Unlock a second jump while airborne."
	elseif abilityId == "deflect_shield" then
		return "Raise a shield that deflects incoming fireballs."
	elseif abilityId == "healing_zone" then
		return "Create a healing zone that restores health over time."
	elseif abilityId == "ice_wall" then
		return "Raise an ice wall that blocks movement and projectiles."
	end

	return "Use this skill to gain a combat advantage."
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
	addUpgradeChange(changes, "Knockback", currentData.KnockbackDistance, nextData.KnockbackDistance, formatStatNumber)
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
	addUpgradeChange(changes, "Wall scale", currentData.WallScale, nextData.WallScale, formatPercentMultiplier)

	if currentData.EnterVelocityZero ~= nextData.EnterVelocityZero then
		local before = if currentData.EnterVelocityZero == true then "enabled" else "disabled"
		local after = if nextData.EnterVelocityZero == true then "enabled" else "disabled"
		table.insert(changes, `Movement stop: {before} -> {after}`)
	end

	if nextLevel == 5 then
		local level5Text = LEVEL_5_UPGRADE_TEXT_BY_ABILITY_ID[abilityId]
		if level5Text ~= nil then
			table.insert(changes, level5Text)
		end
	end

	if #changes == 0 then
		return `Level {currentLevel} -> {nextLevel}: no visible stat change.`
	end

	return `Level {currentLevel} -> {nextLevel}\n` .. table.concat(changes, "\n")
end

return table.freeze(InventoryAbilityText)
