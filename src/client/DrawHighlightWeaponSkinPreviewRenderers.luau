--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local CombatConfig = require(Config:WaitForChild("CombatConfig"))
local DrawHighlightPreviewSupport = require(script.Parent:WaitForChild("DrawHighlightPreviewSupport"))
local DrawHighlightPreviewWorld = require(script.Parent:WaitForChild("DrawHighlightPreviewWorld"))
local PlayerAnimationConfig = require(Config:WaitForChild("PlayerAnimationConfig"))

local DrawHighlightWeaponSkinPreviewRenderers = {}

local EXPLOSION_REFERENCE_VISUAL_DIAMETER_STUDS = 140
local EXPLOSION_VISUAL_SCALE_MULTIPLIER = 2
local ABSOLUTE_ZERO_CHARGE_SECONDS = 4
local ABSOLUTE_ZERO_PROJECTILE_SECONDS = 2
local ABSOLUTE_ZERO_PLAYER_LOCAL_X = -5.45
local FIREBALL_CAST_HOLD_TIME_SECONDS = 0.3

local previewConnections: { RBXScriptConnection } = {}
local previewGeneration = 0
local localPlayer = Players.LocalPlayer
local playerScripts = localPlayer:WaitForChild("PlayerScripts")
local AnimationManager: any =
	require(playerScripts:WaitForChild("ClientPackages"):WaitForChild("CommonKit"):WaitForChild("AnimationManager"))
local FireballChargeVFX = require(
	playerScripts
		:WaitForChild("Client")
		:WaitForChild("Effects")
		:WaitForChild("CombatVFX")
		:WaitForChild("FireballChargeVFX")
)
local VFXSystem: any =
	require(playerScripts:WaitForChild("ClientPackages"):WaitForChild("CommonKit"):WaitForChild("VFXSystem"))

local PreviewFireballChargeVFX: any = {
	_heldFireballCast = nil,
	_remoteHeldFireballCastsByUserId = {},
	_remoteFireballChargeStartedAtByUserId = {},
}

function PreviewFireballChargeVFX:_getCharacterRootPart(character: Model?): BasePart?
	local targetCharacter = character
	if targetCharacter == nil then
		return nil
	end

	local rootPart = targetCharacter:FindFirstChild("HumanoidRootPart")
	return if rootPart ~= nil and rootPart:IsA("BasePart") then rootPart else nil
end

function PreviewFireballChargeVFX:_resolveEffectByPath(effectPath: string): Instance?
	return DrawHighlightPreviewSupport.ResolveEffectPath(effectPath)
end

FireballChargeVFX.Install(PreviewFireballChargeVFX, VFXSystem)

function DrawHighlightWeaponSkinPreviewRenderers.Clear()
	previewGeneration += 1
	PreviewFireballChargeVFX:CancelHeldFireballCast()
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

local function getDefaultFireballCastAnimationEntry(): any?
	local characterSet = PlayerAnimationConfig.CharacterSets[PlayerAnimationConfig.DefaultCharacterSetId]
	if type(characterSet) ~= "table" then
		return nil
	end

	local actions = characterSet.Actions
	if type(actions) ~= "table" then
		return nil
	end

	return actions[PlayerAnimationConfig.ActionKeys.FireballCast]
end

local function playFireballCastAnimation(playerPreview: Instance?, startTime: number?, pauseAtHold: boolean)
	if playerPreview == nil or not playerPreview:IsA("Model") then
		return nil
	end

	local entry = getDefaultFireballCastAnimationEntry()
	local animationId = if type(entry) == "table" then entry.AnimationId else nil
	if type(animationId) ~= "string" or animationId == "" then
		warn("[DrawController] missing FireballCast animation for Absolute Zero highlight preview")
		return nil
	end

	local track = AnimationManager.PlayByAssetId(playerPreview, animationId, {
		fadeTime = entry.FadeTime or 0.05,
		weight = entry.Weight or 1,
		speed = entry.Speed or 1,
		looped = false,
		force = true,
		priority = entry.Priority or Enum.AnimationPriority.Action,
	})
	if track == nil then
		return nil
	end

	if type(startTime) == "number" and startTime > 0 then
		track.TimePosition = startTime
	end
	if pauseAtHold then
		task.delay(FIREBALL_CAST_HOLD_TIME_SECONDS, function()
			if track.IsPlaying then
				track.TimePosition = FIREBALL_CAST_HOLD_TIME_SECONDS
				track:AdjustSpeed(0)
			end
		end)
	end

	return track
end

local function playEmitOnceAtAnchor(path: string, anchor: BasePart, scale: number?, previewRuntime: any)
	local previewWorld = previewRuntime.GetWorld()
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

local function playPersistentAtAnchor(
	path: string,
	anchor: BasePart,
	scale: number?,
	initialEmitFromRate: boolean?,
	previewRuntime: any
)
	local previewWorld = previewRuntime.GetWorld()
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

local function waitForEffectRemoved(effect: Instance?, generation: number)
	while generation == previewGeneration and effect ~= nil and effect.Parent ~= nil do
		task.wait()
	end
end

local function getLookFrame(position: Vector3, direction: Vector3): CFrame
	if direction.Magnitude <= 0 then
		return CFrame.new(position)
	end

	return CFrame.lookAt(position, position + direction.Unit)
end

local function getFireballTier(tierName: string): any
	for _, tier in CombatConfig.Fireball.Charge.Tiers do
		if tier.Name == tierName then
			return tier
		end
	end

	error(`[DrawController] Fireball charge tier {tierName} is missing`)
end

local function getNonNegativeNumber(value: any, message: string): number
	if type(value) ~= "number" or value < 0 then
		error(`[DrawController] {message}`)
	end

	return value
end

local function moveAnchorOverDuration(
	anchor: BasePart,
	fromCFrame: CFrame,
	toCFrame: CFrame,
	durationSeconds: number,
	generation: number,
	previewRuntime: any
): boolean
	local elapsed = 0
	while generation == previewGeneration and anchor:IsDescendantOf(game) and elapsed < durationSeconds do
		local deltaTime = RunService.RenderStepped:Wait()
		elapsed += deltaTime
		local alpha = math.clamp(elapsed / durationSeconds, 0, 1)
		previewRuntime.SetItemLocalCFrame(anchor, fromCFrame:Lerp(toCFrame, alpha))
	end

	return generation == previewGeneration and anchor:IsDescendantOf(game)
end

function DrawHighlightWeaponSkinPreviewRenderers.RenderFootballShoes(previewRuntime: any?)
	local runtime = previewRuntime or DrawHighlightPreviewWorld
	if
		not runtime.Begin({
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
		CFrame.new(-1.65, 0.65, 0) * CFrame.Angles(0, math.rad(-38), math.rad(12)),
		runtime
	)

	local projectilePath = getFireballPath("football_shoes", "Fast") or getFireballPath("football_shoes", "Heavy")
	local explosionPath = getFireballEffectField("football_shoes", "ExplosionEffectPath")
	local projectileFrame = CFrame.lookAt(Vector3.new(1.45, 0.08, -0.32), Vector3.new(2.45, 0.08, -0.32))
	local projectileAnchor = runtime.CreateAnchor("FootballProjectileAnchor", projectileFrame)
	local explosionAnchor = runtime.CreateAnchor("FootballExplosionAnchor", projectileFrame)
	if projectileAnchor == nil or explosionAnchor == nil then
		return
	end

	local generation = previewGeneration
	local cycleSeconds = 2.9
	task.spawn(function()
		while generation == previewGeneration and projectileAnchor:IsDescendantOf(game) do
			local projectileEffect: Instance? = nil
			if type(projectilePath) == "string" then
				runtime.FlushLayout()
				projectileEffect = playPersistentAtAnchor(projectilePath, projectileAnchor, 0.78, true, runtime)
			end

			task.wait(cycleSeconds)
			if generation ~= previewGeneration or not projectileAnchor:IsDescendantOf(game) then
				return
			end

			if projectileEffect ~= nil and type(projectilePath) == "string" then
				VFXSystem.Stop(projectileAnchor, projectilePath)
			end

			local explosionEffect: Instance? = nil
			if type(explosionPath) == "string" then
				explosionEffect = playEmitOnceAtAnchor(explosionPath, explosionAnchor, getExplosionScale(), runtime)
			end
			waitForEffectRemoved(explosionEffect, generation)

			if generation ~= previewGeneration or not projectileAnchor:IsDescendantOf(game) then
				return
			end
			task.wait(0.5)
		end
	end)
end

function DrawHighlightWeaponSkinPreviewRenderers.RenderBigBoneStaff(previewRuntime: any?)
	local runtime = previewRuntime or DrawHighlightPreviewWorld
	if
		not runtime.Begin({
			distance = 30,
			offset = Vector3.new(0, -0.85, 0),
			screenOffset = Vector2.new(0, 0.04),
			rotation = CFrame.Angles(math.rad(-2), math.rad(-10), 0),
			orbitSpeed = 0.16,
		})
	then
		return
	end

	DrawHighlightPreviewSupport.CloneWeaponSkinModel(
		"big_bone_staff",
		CFrame.new(0, 0.55, 0) * CFrame.Angles(0, math.rad(-38), math.rad(12)),
		runtime
	)
end

function DrawHighlightWeaponSkinPreviewRenderers.RenderAbsoluteZero(previewRuntime: any?)
	local runtime = previewRuntime or DrawHighlightPreviewWorld
	if
		not runtime.Begin({
			distance = 30,
			offset = Vector3.new(0, -2.15, 0),
			screenOffset = Vector2.new(0, 0.08),
			rotation = CFrame.Angles(math.rad(-5), math.rad(10), 0),
		})
	then
		return
	end

	local fallbackSize = DrawHighlightPreviewSupport.GetPlayerSizeFallback()
	local playerDirection = Vector3.new(1, 0, -0.28).Unit
	local playerPosition = Vector3.new(ABSOLUTE_ZERO_PLAYER_LOCAL_X, fallbackSize.Y * 0.5, 0)
	local player = DrawHighlightPreviewSupport.CloneLocalPlayerPreviewCharacter(
		"AbsoluteZeroPlayerPreview",
		0,
		getLookFrame(playerPosition, playerDirection),
		runtime
	)
	if player == nil then
		return
	end

	local playerSize = DrawHighlightPreviewSupport.GetCharacterSize(player)
	playerPosition = Vector3.new(ABSOLUTE_ZERO_PLAYER_LOCAL_X, playerSize.Y * 0.5, 0)
	runtime.SetItemLocalCFrame(player, getLookFrame(playerPosition, playerDirection))
	DrawHighlightPreviewSupport.AttachWeaponSkinToCharacter(
		"absolute_zero",
		player,
		CFrame.new(0.85, playerSize.Y * 0.32, -1.05) * CFrame.Angles(0, math.rad(-28), math.rad(12))
	)

	local projectilePath = getFireballPath("absolute_zero", "Fast")
	local explosionPath = getFireballEffectField("absolute_zero", "ExplosionEffectPath")
	local fastTier = getFireballTier("Fast")
	local projectileScale = DrawHighlightPreviewSupport.GetPositiveNumber(
		fastTier.SizeMultiplier,
		"Fast fireball size multiplier must be positive"
	)
	local spawnForwardOffset = DrawHighlightPreviewSupport.GetPositiveNumber(
		CombatConfig.Fireball.SpawnForwardOffset,
		"Fireball spawn forward offset must be positive"
	)
	local spawnHeightOffset = getNonNegativeNumber(
		CombatConfig.Fireball.SpawnHeightOffset,
		"Fireball spawn height offset must be non-negative"
	)
	local projectileStart = playerPosition + Vector3.new(0, spawnHeightOffset, 0) + playerDirection * spawnForwardOffset
	local projectileEnd = projectileStart + playerDirection * 6.4
	local projectileStartFrame = getLookFrame(projectileStart, playerDirection)
	local projectileEndFrame = getLookFrame(projectileEnd, playerDirection)
	local projectileAnchor = runtime.CreateAnchor("AbsoluteZeroProjectileAnchor", projectileStartFrame)
	local explosionAnchor = runtime.CreateAnchor("AbsoluteZeroExplosionAnchor", projectileEndFrame)
	local previewWorld = runtime.GetWorld()
	if projectileAnchor == nil or explosionAnchor == nil or previewWorld == nil or not player:IsA("Model") then
		return
	end

	local generation = previewGeneration
	task.spawn(function()
		while generation == previewGeneration and projectileAnchor:IsDescendantOf(game) do
			playFireballCastAnimation(player, nil, true)

			local vfxOptions = {
				parent = previewWorld,
				weaponSkinId = "absolute_zero",
			}
			PreviewFireballChargeVFX:StartHeldFireballCast(player, playerDirection, vfxOptions)
			local chargeElapsed = 0
			local completedStageCount = 0
			while
				generation == previewGeneration
				and projectileAnchor:IsDescendantOf(game)
				and chargeElapsed < ABSOLUTE_ZERO_CHARGE_SECONDS
			do
				local deltaTime = RunService.RenderStepped:Wait()
				chargeElapsed = math.min(chargeElapsed + deltaTime, ABSOLUTE_ZERO_CHARGE_SECONDS)
				PreviewFireballChargeVFX:UpdateHeldFireballCast(player, playerDirection, chargeElapsed)
				if chargeElapsed >= 1 and completedStageCount < 1 then
					completedStageCount = 1
					PreviewFireballChargeVFX:PlayFireballChargeStep(player, playerDirection, vfxOptions)
				end
				if chargeElapsed >= 3 and completedStageCount < 2 then
					completedStageCount = 2
					PreviewFireballChargeVFX:PlayFireballChargeStep(player, playerDirection, vfxOptions)
				end
			end

			if generation ~= previewGeneration or not projectileAnchor:IsDescendantOf(game) then
				return
			end

			playFireballCastAnimation(player, FIREBALL_CAST_HOLD_TIME_SECONDS, false)
			PreviewFireballChargeVFX:ReleaseHeldFireballCast(player, playerDirection, vfxOptions)

			runtime.SetItemLocalCFrame(projectileAnchor, projectileStartFrame)
			runtime.FlushLayout()
			local projectileEffect: Instance? = nil
			if type(projectilePath) == "string" then
				projectileEffect =
					playPersistentAtAnchor(projectilePath, projectileAnchor, projectileScale, true, runtime)
			end
			if
				not moveAnchorOverDuration(
					projectileAnchor,
					projectileStartFrame,
					projectileEndFrame,
					ABSOLUTE_ZERO_PROJECTILE_SECONDS,
					generation,
					runtime
				)
			then
				return
			end
			if projectileEffect ~= nil and type(projectilePath) == "string" then
				VFXSystem.Stop(projectileAnchor, projectilePath)
			end
			local explosionEffect: Instance? = nil
			if type(explosionPath) == "string" then
				explosionEffect = playEmitOnceAtAnchor(explosionPath, explosionAnchor, getExplosionScale(), runtime)
			end
			waitForEffectRemoved(explosionEffect, generation)

			if generation ~= previewGeneration or not projectileAnchor:IsDescendantOf(game) then
				return
			end
			task.wait(0.5)
		end
	end)
end

function DrawHighlightWeaponSkinPreviewRenderers.RenderDefault(itemId: string, previewRuntime: any?)
	local runtime = previewRuntime or DrawHighlightPreviewWorld
	if not runtime.Begin({
		distance = 8,
		offset = Vector3.new(0, 0.05, 0),
		orbitSpeed = 0.18,
	}) then
		return
	end

	DrawHighlightPreviewSupport.CloneWeaponSkinModel(
		itemId,
		CFrame.new(0, 0.1, 0) * CFrame.Angles(0, math.rad(-30), math.rad(12)),
		runtime
	)
end

function DrawHighlightWeaponSkinPreviewRenderers.Render(itemId: string, previewRuntime: any?)
	if itemId == "football_shoes" then
		DrawHighlightWeaponSkinPreviewRenderers.RenderFootballShoes(previewRuntime)
	elseif itemId == "big_bone_staff" then
		DrawHighlightWeaponSkinPreviewRenderers.RenderBigBoneStaff(previewRuntime)
	elseif itemId == "absolute_zero" then
		DrawHighlightWeaponSkinPreviewRenderers.RenderAbsoluteZero(previewRuntime)
	else
		DrawHighlightWeaponSkinPreviewRenderers.RenderDefault(itemId, previewRuntime)
	end
end

return DrawHighlightWeaponSkinPreviewRenderers
