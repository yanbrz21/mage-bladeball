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

local DrawHighlightDeflectShieldPreviewRenderer = {}

local FAST_FIREBALL_PROJECTILE_PREVIEW_PATH = "Fireball/Projectiles/Fast"
local DEFLECT_SHIELD_PREVIEW_PATH = "Ability/DeflectShield/DeflectShield"
local DEFLECT_PULSE_PREVIEW_PATH = "Ability/DeflectShield/Deflect"
local DEFLECT_SHIELD_OFFSET = Vector3.new(0, 1, 0)
local DEFLECT_SHIELD_FRONT_DISTANCE = 3
local DEFLECT_PULSE_FORWARD_OFFSET = 0.5
local DEFLECT_PULSE_SCALE = 0.68
local INCOMING_PROJECTILE_SCALE = 0.75
local OUTGOING_PROJECTILE_SCALE = 0.75
local FAST_FIREBALL_TIER_NAME = "Fast"
local AFTER_OUTGOING_EXIT_DELAY_SECONDS = 0.8
local PLAYER_LOCAL_X = -2.2
local PLAYER_LOCAL_Z = 0
local PROJECTILE_HEIGHT_RATIO = 0.56
local SHIELD_DIRECTION = Vector3.new(1, 0, -0.28).Unit
local INCOMING_START_DISTANCE = 24
local OUTGOING_END_DISTANCE = 26

local localPlayer = Players.LocalPlayer
local playerScripts = localPlayer:WaitForChild("PlayerScripts")
local VFXSystem: any =
	require(playerScripts:WaitForChild("ClientPackages"):WaitForChild("CommonKit"):WaitForChild("VFXSystem"))

local previewGeneration = 0

function DrawHighlightDeflectShieldPreviewRenderer.Clear()
	previewGeneration += 1
end

local function getPositiveNumber(config: any, fieldName: string, message: string): number
	return DrawHighlightPreviewSupport.GetPositiveNumber(config[fieldName], message)
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

local function getDeflectedFireballSpeed(tierName: string): number
	return getFireballTierSpeed(tierName)
		* DrawHighlightPreviewSupport.GetPositiveNumber(
			CombatConfig.Fireball.DeflectSpeedMultiplier,
			"Fireball deflect speed multiplier must be positive"
		)
end

local function getTravelSeconds(startPosition: Vector3, endPosition: Vector3, speed: number): number
	return (endPosition - startPosition).Magnitude / speed
end

local function getLookFrame(position: Vector3, direction: Vector3): CFrame
	if direction.Magnitude <= 0 then
		return CFrame.new(position)
	end

	return CFrame.lookAt(position, position + direction.Unit)
end

local function getDeflectShieldLoopAnimationEntry(): any?
	local characterSet = PlayerAnimationConfig.CharacterSets[PlayerAnimationConfig.DefaultCharacterSetId]
	if type(characterSet) ~= "table" then
		return nil
	end

	local skills = characterSet.Skills
	if type(skills) ~= "table" then
		return nil
	end

	local skill = skills.deflect_shield
	if type(skill) ~= "table" or type(skill.Phases) ~= "table" then
		return nil
	end

	return skill.Phases[PlayerAnimationConfig.SkillPhases.Loop]
end

local function playDeflectShieldAnimation(playerPreview: Instance?)
	if playerPreview == nil or not playerPreview:IsA("Model") then
		return
	end

	local entry = getDeflectShieldLoopAnimationEntry()
	local animationId = if type(entry) == "table" then entry.AnimationId else nil
	if type(animationId) ~= "string" or animationId == "" then
		warn("[DrawController] missing Deflect Shield loop animation for highlight preview")
		return
	end

	AnimationManager.PlayByAssetId(playerPreview, animationId, {
		fadeTime = entry.FadeTime or 0.06,
		weight = entry.Weight or 1,
		speed = entry.Speed or 1,
		looped = if entry.Looped ~= nil then entry.Looped else true,
		force = true,
		priority = entry.Priority or Enum.AnimationPriority.Action,
	})
end

local function setEffectColor(instance: Instance, color: Color3)
	if instance:IsA("BasePart") then
		instance.Color = color
	elseif instance:IsA("ParticleEmitter") or instance:IsA("Beam") or instance:IsA("Trail") then
		(instance :: any).Color = ColorSequence.new(color)
	elseif instance:IsA("Light") then
		(instance :: any).Color = color
	end
end

local function tintEffect(root: Instance?, color: Color3?)
	if root == nil or color == nil then
		return
	end

	setEffectColor(root, color)
	for _, descendant in root:GetDescendants() do
		setEffectColor(descendant, color)
	end
end

local function playPersistentAtAnchor(
	path: string,
	anchor: BasePart,
	scale: number?,
	initialEmitFromRate: boolean?,
	color: Color3?,
	previewRuntime: any
): Instance?
	local previewWorld = previewRuntime.GetWorld()
	if previewWorld == nil then
		return nil
	end

	local effect = VFXSystem.Play(path, {
		target = anchor,
		scale = scale,
		followRotation = false,
		initialEmitFromRate = initialEmitFromRate == true,
		parent = previewWorld,
	})
	tintEffect(effect, color)

	return effect
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

local function playShield(rootPart: BasePart, previewRuntime: any)
	local previewWorld = previewRuntime.GetWorld()
	if previewWorld == nil then
		return
	end

	local effect = VFXSystem.Play(DEFLECT_SHIELD_PREVIEW_PATH, {
		target = rootPart,
		offset = DEFLECT_SHIELD_OFFSET + SHIELD_DIRECTION * DEFLECT_SHIELD_FRONT_DISTANCE,
		rotation = getLookFrame(Vector3.zero, SHIELD_DIRECTION),
		followRotation = false,
		initialEmitFromRate = true,
		parent = previewWorld,
	})
	if effect == nil then
		warn(`[DrawController] missing highlight preview effect: {DEFLECT_SHIELD_PREVIEW_PATH}`)
	end
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

function DrawHighlightDeflectShieldPreviewRenderer.Render(previewRuntime: any?)
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

	local playerSize = DrawHighlightPreviewSupport.GetPlayerSizeFallback()
	local playerPosition = Vector3.new(PLAYER_LOCAL_X, playerSize.Y * 0.5, PLAYER_LOCAL_Z)
	local player = DrawHighlightPreviewSupport.CloneLocalPlayerPreviewCharacter(
		"DeflectShieldPlayerPreview",
		0,
		getLookFrame(playerPosition, SHIELD_DIRECTION),
		runtime
	)
	if player ~= nil then
		local measured = DrawHighlightPreviewSupport.GetCharacterSize(player)
		playerPosition = Vector3.new(PLAYER_LOCAL_X, measured.Y * 0.5, PLAYER_LOCAL_Z)
		playerSize = measured
		runtime.SetItemLocalCFrame(player, getLookFrame(playerPosition, SHIELD_DIRECTION))
		playDeflectShieldAnimation(player)
	end

	local rootPart = if player ~= nil then DrawHighlightPreviewSupport.GetRootPart(player) else nil
	if rootPart == nil then
		return
	end

	playShield(rootPart, runtime)

	local projectileY = playerSize.Y * PROJECTILE_HEIGHT_RATIO
	local impactPosition = playerPosition + DEFLECT_SHIELD_OFFSET + SHIELD_DIRECTION * DEFLECT_SHIELD_FRONT_DISTANCE
	impactPosition = Vector3.new(impactPosition.X, projectileY, impactPosition.Z)
	local incomingStart = impactPosition + SHIELD_DIRECTION * INCOMING_START_DISTANCE
	local outgoingEnd = impactPosition
		+ SHIELD_DIRECTION * OUTGOING_END_DISTANCE
		+ Vector3.new(0, playerSize.Y * 0.08, 0)
	local incomingDirection = impactPosition - incomingStart
	local outgoingDirection = outgoingEnd - impactPosition
	local pulsePosition = impactPosition + outgoingDirection.Unit * DEFLECT_PULSE_FORWARD_OFFSET

	local incomingAnchor =
		runtime.CreateAnchor("DeflectIncomingFireballAnchor", getLookFrame(incomingStart, incomingDirection))
	local outgoingAnchor =
		runtime.CreateAnchor("DeflectOutgoingFireballAnchor", getLookFrame(impactPosition, outgoingDirection))
	local pulseAnchor = runtime.CreateAnchor("DeflectPulseAnchor", getLookFrame(pulsePosition, outgoingDirection))
	if incomingAnchor == nil or outgoingAnchor == nil or pulseAnchor == nil then
		return
	end

	local durationSeconds =
		getPositiveNumber(AbilityConfig.DeflectShield, "DurationSeconds", "Deflect Shield duration must be positive")
	local incomingSpeed = getFireballTierSpeed(FAST_FIREBALL_TIER_NAME)
	local outgoingSpeed = getDeflectedFireballSpeed(FAST_FIREBALL_TIER_NAME)
	local incomingTravelSeconds = getTravelSeconds(incomingStart, impactPosition, incomingSpeed)
	local outgoingTravelSeconds = getTravelSeconds(impactPosition, outgoingEnd, outgoingSpeed)
	local deflectedColor = CombatConfig.Fireball.DeflectedVisualColor

	local generation = previewGeneration
	task.spawn(function()
		while generation == previewGeneration and incomingAnchor:IsDescendantOf(game) do
			local incomingStartFrame = getLookFrame(incomingStart, incomingDirection)
			runtime.SetItemLocalCFrame(incomingAnchor, incomingStartFrame)
			-- Pivot anchors before spawning Trail-based VFX so they do not record stale world positions.
			runtime.FlushLayout()
			local incomingEffect = playPersistentAtAnchor(
				FAST_FIREBALL_PROJECTILE_PREVIEW_PATH,
				incomingAnchor,
				INCOMING_PROJECTILE_SCALE,
				true,
				nil,
				runtime
			)

			local didReachShield = tweenAnchorLocalCFrame(
				incomingAnchor,
				generation,
				incomingStartFrame,
				getLookFrame(impactPosition, incomingDirection),
				incomingTravelSeconds,
				runtime
			)
			if not didReachShield then
				return
			end
			if incomingEffect ~= nil then
				VFXSystem.Stop(incomingAnchor, FAST_FIREBALL_PROJECTILE_PREVIEW_PATH)
			end

			local pulseFrame = getLookFrame(pulsePosition, outgoingDirection)
			runtime.SetItemLocalCFrame(pulseAnchor, pulseFrame)
			runtime.SetItemLocalCFrame(outgoingAnchor, getLookFrame(impactPosition, outgoingDirection))
			-- Keep pulse and rebound projectile aligned on the same rendered frame.
			runtime.FlushLayout()
			playEmitOnceAtAnchor(DEFLECT_PULSE_PREVIEW_PATH, pulseAnchor, DEFLECT_PULSE_SCALE, runtime)
			local outgoingEffect = playPersistentAtAnchor(
				FAST_FIREBALL_PROJECTILE_PREVIEW_PATH,
				outgoingAnchor,
				OUTGOING_PROJECTILE_SCALE,
				true,
				deflectedColor,
				runtime
			)

			local didExitFrame = tweenAnchorLocalCFrame(
				outgoingAnchor,
				generation,
				getLookFrame(impactPosition, outgoingDirection),
				getLookFrame(outgoingEnd, outgoingDirection),
				outgoingTravelSeconds,
				runtime
			)
			if not didExitFrame then
				return
			end
			if outgoingEffect ~= nil then
				VFXSystem.Stop(outgoingAnchor, FAST_FIREBALL_PROJECTILE_PREVIEW_PATH)
			end

			task.wait(
				math.max(
					AFTER_OUTGOING_EXIT_DELAY_SECONDS,
					durationSeconds - incomingTravelSeconds - outgoingTravelSeconds
				)
			)
		end
	end)
end

return DrawHighlightDeflectShieldPreviewRenderer
