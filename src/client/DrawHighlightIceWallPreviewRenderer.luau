--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local AbilityConfig = require(Config:WaitForChild("AbilityConfig"))
local AnimationManager = require(
	Players.LocalPlayer
		:WaitForChild("PlayerScripts")
		:WaitForChild("ClientPackages")
		:WaitForChild("CommonKit")
		:WaitForChild("AnimationManager")
)
local CombatConfig = require(Config:WaitForChild("CombatConfig"))
local DrawHighlightPreviewSupport = require(script.Parent:WaitForChild("DrawHighlightPreviewSupport"))
local DrawHighlightPreviewWorld = require(script.Parent:WaitForChild("DrawHighlightPreviewWorld"))
local PlayerAnimationConfig = require(Config:WaitForChild("PlayerAnimationConfig"))

local DrawHighlightIceWallPreviewRenderer = {}

local FAST_FIREBALL_PROJECTILE_PREVIEW_PATH = "Fireball/Projectiles/Fast"
local QUICK_FIREBALL_PROJECTILE_PREVIEW_PATH = "Fireball/Projectiles/Quick"
local FIREBALL_CAST_PREVIEW_PATH = "Fireball/FireballCast"
local FIREBALL_EXPLOSION_PREVIEW_PATH = "Fireball/Explosion"
local ICE_WALL_PREVIEW_PATH = "Ability/IceWall/Ice Wall"
local FIREBALL_CAST_TOP_TO_FORWARD_CORRECTION = CFrame.Angles(-math.pi / 2, 0, 0)
local FIREBALL_EXPLOSION_REFERENCE_VISUAL_DIAMETER_STUDS = 140
local FIREBALL_EXPLOSION_VISUAL_SCALE_MULTIPLIER = 2
local FIREBALL_CAST_SCALE = 0.75
local ICE_WALL_REFERENCE_WIDTH = 17.072
local ICE_WALL_REFERENCE_HEIGHT = 10.406
local ICE_WALL_PLAYER_LOCAL_X = 6.2
local ICE_WALL_PLAYER_LOCAL_Z = 1.75
local ICE_WALL_YAW_DEGREES = 50
local ICE_WALL_AFTER_IMPACT_DELAY_SECONDS = 1
local ICE_WALL_QUICK_RELEASE_DELAY_SECONDS = 0.3
local ICE_WALL_AFTER_QUICK_EXIT_DELAY_SECONDS = 1
local FAST_FIREBALL_TIER_NAME = "Fast"
local QUICK_FIREBALL_TIER_NAME = "Quick"

local localPlayer = Players.LocalPlayer
local playerScripts = localPlayer:WaitForChild("PlayerScripts")
local VFXSystem: any =
	require(playerScripts:WaitForChild("ClientPackages"):WaitForChild("CommonKit"):WaitForChild("VFXSystem"))

local previewGeneration = 0

function DrawHighlightIceWallPreviewRenderer.Clear()
	previewGeneration += 1
end

local function getDuration(config: any, fieldName: string, message: string): number
	return DrawHighlightPreviewSupport.GetPositiveNumber(config[fieldName], message)
end

local function getIceWallScale(): number
	local wallScale = DrawHighlightPreviewSupport.GetPositiveNumber(
		AbilityConfig.IceWall.WallScale,
		"Ice Wall scale must be positive"
	)
	local width =
		DrawHighlightPreviewSupport.GetPositiveNumber(AbilityConfig.IceWall.Width, "Ice Wall width must be positive")
	local height =
		DrawHighlightPreviewSupport.GetPositiveNumber(AbilityConfig.IceWall.Height, "Ice Wall height must be positive")
	local thickness = DrawHighlightPreviewSupport.GetPositiveNumber(
		AbilityConfig.IceWall.Thickness,
		"Ice Wall thickness must be positive"
	)
	local wallSize = Vector3.new(width * wallScale, height * wallScale, thickness)

	return math.max(wallSize.X / ICE_WALL_REFERENCE_WIDTH, wallSize.Y / ICE_WALL_REFERENCE_HEIGHT, 0.01)
end

local function getFireballExplosionScale(): number
	local radius = DrawHighlightPreviewSupport.GetPositiveNumber(
		CombatConfig.Fireball.ExplosionRadius,
		"Fireball explosion radius must be positive"
	)

	return math.max(
		(radius * 2 * FIREBALL_EXPLOSION_VISUAL_SCALE_MULTIPLIER) / FIREBALL_EXPLOSION_REFERENCE_VISUAL_DIAMETER_STUDS,
		0.01
	)
end

local function getFireballTier(tierName: string): any
	for _, tier in CombatConfig.Fireball.Charge.Tiers do
		if tier.Name == tierName then
			return tier
		end
	end

	error(`[DrawController] Fireball charge tier {tierName} is missing`)
end

local function getFireballTierSpeed(tierName: string): number
	local baseSpeed =
		DrawHighlightPreviewSupport.GetPositiveNumber(CombatConfig.Fireball.Speed, "Fireball speed must be positive")
	local tier = getFireballTier(tierName)
	local speedMultiplier = DrawHighlightPreviewSupport.GetPositiveNumber(
		tier.SpeedMultiplier,
		`{tierName} fireball speed must be positive`
	)

	return baseSpeed * speedMultiplier
end

local function getFireballTierVisualScale(tierName: string): number
	local tier = getFireballTier(tierName)
	return DrawHighlightPreviewSupport.GetPositiveNumber(
		tier.SizeMultiplier,
		`{tierName} fireball visual scale must be positive`
	)
end

local function getTravelSeconds(startPosition: Vector3, endPosition: Vector3, tierName: string): number
	return (endPosition - startPosition).Magnitude / getFireballTierSpeed(tierName)
end

local function getPlayerFireballStartPosition(playerPosition: Vector3, playerHeight: number): Vector3
	return Vector3.new(playerPosition.X, playerHeight * 0.64, playerPosition.Z)
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

local function playFireballCastAnimation(playerPreview: Instance?)
	if playerPreview == nil or not playerPreview:IsA("Model") then
		return
	end

	local entry = getDefaultFireballCastAnimationEntry()
	local animationId = if type(entry) == "table" then entry.AnimationId else nil
	if type(animationId) ~= "string" or animationId == "" then
		warn("[DrawController] missing FireballCast animation for Ice Wall highlight preview")
		return
	end

	AnimationManager.PlayByAssetId(playerPreview, animationId, {
		fadeTime = entry.FadeTime or 0.05,
		weight = entry.Weight or 1,
		speed = entry.Speed or 1,
		looped = false,
		force = true,
		priority = entry.Priority or Enum.AnimationPriority.Action,
	})
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

local function getLookFrame(position: Vector3, direction: Vector3): CFrame
	if direction.Magnitude <= 0 then
		return CFrame.new(position)
	end

	return CFrame.lookAt(position, position + direction.Unit)
end

local function tweenAnchorLocalCFrame(
	anchor: BasePart,
	generation: number,
	fromCFrame: CFrame,
	toCFrame: CFrame,
	durationSeconds: number,
	previewRuntime: any
): boolean
	local elapsed = 0
	while elapsed < durationSeconds do
		if generation ~= previewGeneration or not anchor:IsDescendantOf(game) then
			return false
		end

		local deltaTime = RunService.RenderStepped:Wait()
		elapsed += deltaTime
		local alpha = math.clamp(elapsed / durationSeconds, 0, 1)
		previewRuntime.SetItemLocalCFrame(anchor, fromCFrame:Lerp(toCFrame, alpha))
	end

	return generation == previewGeneration and anchor:IsDescendantOf(game)
end

local function playFireballCastVfxAtAnchor(anchor: BasePart, previewRuntime: any)
	local previewWorld = previewRuntime.GetWorld()
	if previewWorld == nil then
		return
	end

	VFXSystem.PlayEmitOnceWithTweens(FIREBALL_CAST_PREVIEW_PATH, {
		target = anchor,
		rotation = FIREBALL_CAST_TOP_TO_FORWARD_CORRECTION,
		scale = FIREBALL_CAST_SCALE,
		followRotation = false,
		parent = previewWorld,
	})
end

function DrawHighlightIceWallPreviewRenderer.Render(previewRuntime: any?)
	local runtime = previewRuntime or DrawHighlightPreviewWorld
	if
		not runtime.Begin({
			distance = 30,
			offset = Vector3.new(0, -2.3, 0),
			screenOffset = Vector2.new(0, 0.08),
			rotation = CFrame.Angles(math.rad(-7), math.rad(-12), 0),
		})
	then
		return
	end

	local playerSize = DrawHighlightPreviewSupport.GetPlayerSizeFallback()
	local playerPosition = Vector3.new(ICE_WALL_PLAYER_LOCAL_X, playerSize.Y * 0.5, ICE_WALL_PLAYER_LOCAL_Z)
	local quickStart = getPlayerFireballStartPosition(playerPosition, playerSize.Y)
	local quickEnd = Vector3.new(-34, playerSize.Y * 0.66, -5.4)
	local fastStart = Vector3.new(-28, playerSize.Y * 0.6, -4.3)
	local fastImpact = Vector3.new(-0.55, playerSize.Y * 0.58, -0.25)
	local quickDirection = quickEnd - quickStart
	local fastDirection = fastImpact - fastStart
	local wall = DrawHighlightPreviewSupport.CloneEffectPath(
		ICE_WALL_PREVIEW_PATH,
		"IceWallPreview",
		CFrame.new(0, 2.15, 0) * CFrame.Angles(0, math.rad(ICE_WALL_YAW_DEGREES), 0),
		getIceWallScale(),
		nil,
		runtime
	)
	local player = DrawHighlightPreviewSupport.CloneLocalPlayerPreviewCharacter(
		"IceWallPlayerPreview",
		0,
		getLookFrame(playerPosition, quickDirection),
		runtime
	)

	if wall ~= nil then
		runtime.PlayParticlePlaybackLoop(
			wall,
			getDuration(AbilityConfig.IceWall, "DurationSeconds", "Ice Wall duration must be positive")
		)
	end
	if player ~= nil then
		local measured = DrawHighlightPreviewSupport.GetCharacterSize(player)
		playerPosition = Vector3.new(ICE_WALL_PLAYER_LOCAL_X, measured.Y * 0.5, ICE_WALL_PLAYER_LOCAL_Z)
		quickStart = getPlayerFireballStartPosition(playerPosition, measured.Y)
		quickEnd = Vector3.new(-34, measured.Y * 0.66, -5.4)
		fastStart = Vector3.new(-28, measured.Y * 0.6, -4.3)
		fastImpact = Vector3.new(-0.55, measured.Y * 0.58, -0.25)
		quickDirection = quickEnd - quickStart
		fastDirection = fastImpact - fastStart
		runtime.SetItemLocalCFrame(player, getLookFrame(playerPosition, quickDirection))
	end

	local fastAnchor = runtime.CreateAnchor("IceWallFastFireballAnchor", getLookFrame(fastStart, fastDirection))
	local quickAnchor = runtime.CreateAnchor("IceWallQuickFireballAnchor", getLookFrame(quickStart, quickDirection))
	local castAnchor = runtime.CreateAnchor("IceWallFireballCastAnchor", getLookFrame(quickStart, quickDirection))
	local explosionAnchor = runtime.CreateAnchor("IceWallFastImpactAnchor", getLookFrame(fastImpact, -fastDirection))
	if fastAnchor == nil or quickAnchor == nil or castAnchor == nil or explosionAnchor == nil then
		return
	end

	local generation = previewGeneration
	task.spawn(function()
		while generation == previewGeneration and fastAnchor:IsDescendantOf(game) do
			local fastStartFrame = getLookFrame(fastStart, fastDirection)
			runtime.SetItemLocalCFrame(fastAnchor, fastStartFrame)
			runtime.FlushLayout()
			local fastEffect = playPersistentAtAnchor(
				FAST_FIREBALL_PROJECTILE_PREVIEW_PATH,
				fastAnchor,
				getFireballTierVisualScale(FAST_FIREBALL_TIER_NAME),
				true,
				runtime
			)
			local didReachWall = tweenAnchorLocalCFrame(
				fastAnchor,
				generation,
				getLookFrame(fastStart, fastDirection),
				getLookFrame(fastImpact, fastDirection),
				getTravelSeconds(fastStart, fastImpact, FAST_FIREBALL_TIER_NAME),
				runtime
			)
			if not didReachWall then
				return
			end
			if fastEffect ~= nil then
				VFXSystem.Stop(fastAnchor, FAST_FIREBALL_PROJECTILE_PREVIEW_PATH)
			end
			playEmitOnceAtAnchor(FIREBALL_EXPLOSION_PREVIEW_PATH, explosionAnchor, getFireballExplosionScale(), runtime)

			task.wait(ICE_WALL_AFTER_IMPACT_DELAY_SECONDS)
			if generation ~= previewGeneration or not fastAnchor:IsDescendantOf(game) then
				return
			end

			playFireballCastAnimation(player)
			task.wait(ICE_WALL_QUICK_RELEASE_DELAY_SECONDS)
			if generation ~= previewGeneration or not quickAnchor:IsDescendantOf(game) then
				return
			end

			local quickStartFrame = getLookFrame(quickStart, quickDirection)
			runtime.SetItemLocalCFrame(castAnchor, quickStartFrame)
			runtime.SetItemLocalCFrame(quickAnchor, quickStartFrame)
			runtime.FlushLayout()
			playFireballCastVfxAtAnchor(castAnchor, runtime)
			local quickEffect = playPersistentAtAnchor(
				QUICK_FIREBALL_PROJECTILE_PREVIEW_PATH,
				quickAnchor,
				getFireballTierVisualScale(QUICK_FIREBALL_TIER_NAME),
				true,
				runtime
			)
			local didExitFrame = tweenAnchorLocalCFrame(
				quickAnchor,
				generation,
				getLookFrame(quickStart, quickDirection),
				getLookFrame(quickEnd, quickDirection),
				getTravelSeconds(quickStart, quickEnd, QUICK_FIREBALL_TIER_NAME),
				runtime
			)
			if not didExitFrame then
				return
			end
			if quickEffect ~= nil then
				VFXSystem.Stop(quickAnchor, QUICK_FIREBALL_PROJECTILE_PREVIEW_PATH)
			end

			task.wait(ICE_WALL_AFTER_QUICK_EXIT_DELAY_SECONDS)
		end
	end)
end

return DrawHighlightIceWallPreviewRenderer
