--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local AbilityConfig = require(Config:WaitForChild("AbilityConfig"))
local DrawHighlightPreviewSupport = require(script.Parent:WaitForChild("DrawHighlightPreviewSupport"))
local DrawHighlightPreviewWorld = require(script.Parent:WaitForChild("DrawHighlightPreviewWorld"))

local DrawHighlightHealingZonePreviewRenderer = {}

local HEALING_ZONE_CIRCLE_PREVIEW_PATH = "Ability/HealingZone/HealCircle"
local HEALING_ZONE_PARTICLES_PREVIEW_PATH = "Ability/HealingZone/Heal"
local HEALING_TARGET_OFFSET = Vector3.new(0, 1, 0)
local HEALING_ZONE_REPLAY_DELAY_SECONDS = 1
local HEALING_ZONE_REFERENCE_RADIUS = 12
local HEALING_ZONE_PLAYER_FEET_LIFT = 0.42

local previewGeneration = 0
local localPlayer = Players.LocalPlayer
local playerScripts = localPlayer:WaitForChild("PlayerScripts")
local VFXSystem: any =
	require(playerScripts:WaitForChild("ClientPackages"):WaitForChild("CommonKit"):WaitForChild("VFXSystem"))

function DrawHighlightHealingZonePreviewRenderer.Clear()
	previewGeneration += 1
end

local function getDuration(config: any, fieldName: string, message: string): number
	return DrawHighlightPreviewSupport.GetPositiveNumber(config[fieldName], message)
end

local function getHealingZoneRadiusScale(): number
	local radius = DrawHighlightPreviewSupport.GetPositiveNumber(
		AbilityConfig.HealingZone.Radius,
		"Healing Zone radius must be positive"
	)

	return math.max(radius / HEALING_ZONE_REFERENCE_RADIUS, 0.01)
end

local function getHealingZoneCircleSurfaceY(scale: number): number
	local circleSource = DrawHighlightPreviewSupport.ResolveEffectPath(HEALING_ZONE_CIRCLE_PREVIEW_PATH)
	if circleSource == nil then
		return 0
	end

	local _sourcePivot, sourceSize = DrawHighlightPreviewSupport.GetInstanceBounds(circleSource)
	if sourceSize == nil then
		return 0
	end

	return sourceSize.Y * scale * 0.5
end

local function playHealingZoneHeal(rootPart: BasePart): boolean
	local previewWorld = DrawHighlightPreviewWorld.GetWorld()
	if previewWorld == nil or rootPart.Parent == nil then
		return false
	end

	local heal = VFXSystem.PlayEmitOnceWithTweens(HEALING_ZONE_PARTICLES_PREVIEW_PATH, {
		target = rootPart,
		offset = HEALING_TARGET_OFFSET,
		followPositionOnly = true,
		parent = previewWorld,
	})
	if heal == nil then
		warn(`[DrawController] missing highlight preview effect: {HEALING_ZONE_PARTICLES_PREVIEW_PATH}`)
	end

	return true
end

local function addHealingZonePlaybackLoop(circle: Instance, playerPreview: Instance, rootPart: BasePart)
	local generation = previewGeneration
	local durationSeconds =
		getDuration(AbilityConfig.HealingZone, "DurationSeconds", "Healing Zone duration must be positive")
	local tickSeconds =
		getDuration(AbilityConfig.HealingZone, "TickSeconds", "Healing Zone tick seconds must be positive")

	task.spawn(function()
		RunService.RenderStepped:Wait()

		while generation == previewGeneration and playerPreview:IsDescendantOf(game) and circle:IsDescendantOf(game) do
			local playbackEndTime = DrawHighlightPreviewWorld.PlayParticlePlaybackOnce(circle)

			local elapsed = 0
			while
				elapsed < durationSeconds
				and generation == previewGeneration
				and playerPreview:IsDescendantOf(game)
			do
				if not playHealingZoneHeal(rootPart) then
					return
				end

				local waitSeconds = math.min(tickSeconds, durationSeconds - elapsed)
				task.wait(waitSeconds)
				elapsed += waitSeconds
			end

			if generation ~= previewGeneration or not playerPreview:IsDescendantOf(game) then
				return
			end

			task.wait(math.max(0, playbackEndTime - durationSeconds))
			task.wait(HEALING_ZONE_REPLAY_DELAY_SECONDS)
		end
	end)
end

function DrawHighlightHealingZonePreviewRenderer.Render()
	if
		not DrawHighlightPreviewWorld.Begin({
			distance = 35,
			offset = Vector3.new(0, -2.35, 0),
			screenOffset = Vector2.new(0, 0.16),
			rotation = CFrame.Angles(math.rad(-8), 0, 0),
		})
	then
		return
	end

	local circleScale = getHealingZoneRadiusScale()
	local circle = DrawHighlightPreviewSupport.CloneEffectPath(
		HEALING_ZONE_CIRCLE_PREVIEW_PATH,
		"HealingZoneCirclePreview",
		CFrame.new(0, 0, 0),
		circleScale,
		false
	)

	local playerPreview = DrawHighlightPreviewSupport.CloneLocalPlayerPreviewCharacter(
		"HealingZonePlayerPreview",
		getHealingZoneCircleSurfaceY(circleScale) + HEALING_ZONE_PLAYER_FEET_LIFT,
		nil
	)
	if circle ~= nil and playerPreview ~= nil then
		local rootPart = DrawHighlightPreviewSupport.GetRootPart(playerPreview)
		if rootPart ~= nil then
			addHealingZonePlaybackLoop(circle, playerPreview, rootPart)
		end
	end
end

return DrawHighlightHealingZonePreviewRenderer
