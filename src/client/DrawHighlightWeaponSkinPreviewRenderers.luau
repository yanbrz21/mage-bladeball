--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local CombatConfig = require(Config:WaitForChild("CombatConfig"))
local DrawHighlightPreviewSupport = require(script.Parent:WaitForChild("DrawHighlightPreviewSupport"))
local DrawHighlightPreviewWorld = require(script.Parent:WaitForChild("DrawHighlightPreviewWorld"))

local DrawHighlightWeaponSkinPreviewRenderers = {}

local EXPLOSION_REFERENCE_VISUAL_DIAMETER_STUDS = 140
local EXPLOSION_VISUAL_SCALE_MULTIPLIER = 2

local previewConnections: { RBXScriptConnection } = {}
local previewGeneration = 0
local localPlayer = Players.LocalPlayer
local playerScripts = localPlayer:WaitForChild("PlayerScripts")
local VFXSystem: any =
	require(playerScripts:WaitForChild("ClientPackages"):WaitForChild("CommonKit"):WaitForChild("VFXSystem"))

function DrawHighlightWeaponSkinPreviewRenderers.Clear()
	previewGeneration += 1
	for _, connection in previewConnections do
		connection:Disconnect()
	end
	table.clear(previewConnections)
end

local function getExplosionScale(): number
	local radius = DrawHighlightPreviewSupport.GetPositiveNumber(
		CombatConfig.Fireball.ExplosionRadius,
		"Fireball explosion radius must be positive"
	)

	return math.max((radius * 2 * EXPLOSION_VISUAL_SCALE_MULTIPLIER) / EXPLOSION_REFERENCE_VISUAL_DIAMETER_STUDS, 0.01)
end

local function getFireballPath(itemId: string, tierName: string): string?
	local fireballConfig = DrawHighlightPreviewSupport.GetSkinFireballConfig(itemId)
	local projectilePaths = if type(fireballConfig) == "table" then fireballConfig.ProjectileEffectPathsByTier else nil
	return if type(projectilePaths) == "table" then projectilePaths[tierName] else nil
end

local function getFireballEffectField(itemId: string, fieldName: string): string?
	local fireballConfig = DrawHighlightPreviewSupport.GetSkinFireballConfig(itemId)
	local value = if type(fireballConfig) == "table" then fireballConfig[fieldName] else nil
	return if type(value) == "string" then value else nil
end

local function playEmitOnceAtAnchor(path: string, anchor: BasePart, scale: number?)
	local previewWorld = DrawHighlightPreviewWorld.GetWorld()
	if previewWorld == nil then
		return nil
	end

	return VFXSystem.PlayEmitOnceWithTweens(path, {
		target = anchor,
		scale = scale,
		followRotation = false,
		parent = previewWorld,
	})
end

local function playPersistentAtAnchor(path: string, anchor: BasePart, scale: number?, initialEmitFromRate: boolean?)
	local previewWorld = DrawHighlightPreviewWorld.GetWorld()
	if previewWorld == nil then
		return nil
	end

	return VFXSystem.Play(path, {
		target = anchor,
		scale = scale,
		followRotation = false,
		initialEmitFromRate = initialEmitFromRate == true,
		parent = previewWorld,
	})
end

local function addMovingAnchorLoop(anchor: BasePart, cycleSeconds: number, getFrame: (number) -> CFrame)
	local elapsed = 0
	table.insert(
		previewConnections,
		RunService.RenderStepped:Connect(function(deltaTime: number)
			if anchor.Parent == nil then
				return
			end

			elapsed = (elapsed + deltaTime) % cycleSeconds
			DrawHighlightPreviewWorld.SetItemLocalCFrame(anchor, getFrame(elapsed / cycleSeconds))
		end)
	)
end

function DrawHighlightWeaponSkinPreviewRenderers.RenderFootballShoes()
	if
		not DrawHighlightPreviewWorld.Begin({
			distance = 43,
			offset = Vector3.new(0, -1.5, 0),
			screenOffset = Vector2.new(0, 0.04),
			rotation = CFrame.Angles(math.rad(-2), math.rad(-10), 0),
			orbitSpeed = 0.16,
		})
	then
		return
	end

	DrawHighlightPreviewSupport.CloneWeaponSkinModel(
		"football_shoes",
		CFrame.new(-1.65, 0.65, 0) * CFrame.Angles(0, math.rad(-38), math.rad(12))
	)

	local projectilePath = getFireballPath("football_shoes", "Fast") or getFireballPath("football_shoes", "Heavy")
	local explosionPath = getFireballEffectField("football_shoes", "ExplosionEffectPath")
	local projectileAnchor = DrawHighlightPreviewWorld.CreateAnchor(
		"FootballProjectileAnchor",
		CFrame.lookAt(Vector3.new(0.4, 0.55, -0.15), Vector3.new(1.4, 0.55, -0.15))
	)
	local explosionAnchor =
		DrawHighlightPreviewWorld.CreateAnchor("FootballExplosionAnchor", CFrame.new(2.35, -0.45, -0.45))
	if projectileAnchor == nil or explosionAnchor == nil then
		return
	end

	if type(projectilePath) == "string" then
		playPersistentAtAnchor(projectilePath, projectileAnchor, 0.78, true)
	end

	local generation = previewGeneration
	local cycleSeconds = 2.9
	addMovingAnchorLoop(projectileAnchor, cycleSeconds, function(alpha: number): CFrame
		if alpha < 0.62 then
			local travelAlpha = alpha / 0.62
			local position =
				Vector3.new(0.25 + 2.05 * travelAlpha, 0.55 - 0.85 * travelAlpha, -0.15 - 0.35 * travelAlpha)
			return CFrame.lookAt(position, position + Vector3.new(1, -0.2, -0.08))
		end

		return CFrame.new(2.3, -0.3, -0.5)
	end)

	task.spawn(function()
		while generation == previewGeneration and projectileAnchor:IsDescendantOf(game) do
			task.wait(cycleSeconds * 0.62)
			if generation ~= previewGeneration or not projectileAnchor:IsDescendantOf(game) then
				return
			end
			if type(explosionPath) == "string" then
				playEmitOnceAtAnchor(explosionPath, explosionAnchor, getExplosionScale())
			end
			task.wait(cycleSeconds * 0.38)
		end
	end)
end

function DrawHighlightWeaponSkinPreviewRenderers.RenderAbsoluteZero()
	if
		not DrawHighlightPreviewWorld.Begin({
			distance = 55,
			offset = Vector3.new(0, -2.2, 0),
			screenOffset = Vector2.new(0, 0.08),
			rotation = CFrame.Angles(math.rad(-5), math.rad(-10), 0),
		})
	then
		return
	end

	local fallbackSize = DrawHighlightPreviewSupport.GetPlayerSizeFallback()
	local player = DrawHighlightPreviewSupport.CloneLocalPlayerPreviewCharacter(
		"AbsoluteZeroPlayerPreview",
		0,
		CFrame.new(-1.55, fallbackSize.Y * 0.5, 0) * CFrame.Angles(0, math.rad(-16), 0)
	)
	if player == nil then
		return
	end

	local playerSize = DrawHighlightPreviewSupport.GetCharacterSize(player)
	DrawHighlightPreviewWorld.SetItemLocalCFrame(
		player,
		CFrame.new(-1.55, playerSize.Y * 0.5, 0) * CFrame.Angles(0, math.rad(-16), 0)
	)
	DrawHighlightPreviewSupport.AttachWeaponSkinToCharacter(
		"absolute_zero",
		player,
		CFrame.new(1.35, playerSize.Y * 0.3, -1.1) * CFrame.Angles(0, math.rad(-28), math.rad(12))
	)

	local chargePath = getFireballEffectField("absolute_zero", "ChargeEffectPath")
	local projectilePath = getFireballPath("absolute_zero", "Heavy") or getFireballPath("absolute_zero", "Fast")
	local explosionPath = getFireballEffectField("absolute_zero", "HeavyExplosionEffectPath")
		or getFireballEffectField("absolute_zero", "ExplosionEffectPath")
	local chargeAnchor = DrawHighlightPreviewWorld.CreateAnchor(
		"AbsoluteZeroChargeAnchor",
		CFrame.lookAt(Vector3.new(0.35, playerSize.Y * 0.62, -1.45), Vector3.new(1.1, playerSize.Y * 0.6, -2.2))
	)
	local projectileAnchor = DrawHighlightPreviewWorld.CreateAnchor(
		"AbsoluteZeroProjectileAnchor",
		CFrame.lookAt(Vector3.new(0.35, playerSize.Y * 0.62, -1.45), Vector3.new(1.1, playerSize.Y * 0.6, -2.2))
	)
	local explosionAnchor = DrawHighlightPreviewWorld.CreateAnchor(
		"AbsoluteZeroExplosionAnchor",
		CFrame.new(3.1, playerSize.Y * 0.22, -2.65)
	)
	if chargeAnchor == nil or projectileAnchor == nil or explosionAnchor == nil then
		return
	end

	local generation = previewGeneration
	task.spawn(function()
		while generation == previewGeneration and chargeAnchor:IsDescendantOf(game) do
			local chargeEffect: Instance? = nil
			if type(chargePath) == "string" then
				chargeEffect = playPersistentAtAnchor(chargePath, chargeAnchor, 0.55, true)
			end
			task.wait(1.25)

			if generation ~= previewGeneration or not chargeAnchor:IsDescendantOf(game) then
				return
			end
			if chargeEffect ~= nil and type(chargePath) == "string" then
				VFXSystem.Stop(chargeAnchor, chargePath)
			end
			local projectileEffect: Instance? = nil
			if type(projectilePath) == "string" then
				projectileEffect = playPersistentAtAnchor(projectilePath, projectileAnchor, 0.85, true)
			end

			task.wait(0.85)
			if generation ~= previewGeneration or not projectileAnchor:IsDescendantOf(game) then
				return
			end
			if projectileEffect ~= nil and type(projectilePath) == "string" then
				VFXSystem.Stop(projectileAnchor, projectilePath)
			end
			if type(explosionPath) == "string" then
				playEmitOnceAtAnchor(explosionPath, explosionAnchor, getExplosionScale())
			end

			task.wait(1.8)
		end
	end)

	addMovingAnchorLoop(projectileAnchor, 3.9, function(alpha: number): CFrame
		if alpha < 0.32 then
			return CFrame.lookAt(
				Vector3.new(0.35, playerSize.Y * 0.62, -1.45),
				Vector3.new(1.1, playerSize.Y * 0.6, -2.2)
			)
		elseif alpha < 0.54 then
			local travelAlpha = (alpha - 0.32) / 0.22
			local position = Vector3.new(
				0.35 + 2.75 * travelAlpha,
				playerSize.Y * (0.62 - 0.4 * travelAlpha),
				-1.45 - 1.2 * travelAlpha
			)
			return CFrame.lookAt(position, position + Vector3.new(1, -0.12, -0.35))
		end

		return CFrame.new(3.1, playerSize.Y * 0.22, -2.65)
	end)
end

function DrawHighlightWeaponSkinPreviewRenderers.RenderDefault(itemId: string)
	if
		not DrawHighlightPreviewWorld.Begin({
			distance = 8,
			offset = Vector3.new(0, 0.05, 0),
			orbitSpeed = 0.18,
		})
	then
		return
	end

	DrawHighlightPreviewSupport.CloneWeaponSkinModel(
		itemId,
		CFrame.new(0, 0.1, 0) * CFrame.Angles(0, math.rad(-30), math.rad(12))
	)
end

function DrawHighlightWeaponSkinPreviewRenderers.Render(itemId: string)
	if itemId == "football_shoes" then
		DrawHighlightWeaponSkinPreviewRenderers.RenderFootballShoes()
	elseif itemId == "absolute_zero" then
		DrawHighlightWeaponSkinPreviewRenderers.RenderAbsoluteZero()
	else
		DrawHighlightWeaponSkinPreviewRenderers.RenderDefault(itemId)
	end
end

return DrawHighlightWeaponSkinPreviewRenderers
