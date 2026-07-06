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
local DrawHighlightPreviewSupport = require(script.Parent:WaitForChild("DrawHighlightPreviewSupport"))
local DrawHighlightPreviewWorld = require(script.Parent:WaitForChild("DrawHighlightPreviewWorld"))
local PlayerAnimationConfig = require(Config:WaitForChild("PlayerAnimationConfig"))

local DrawHighlightInvisibilityPreviewRenderer = {}

local NOOB_MODEL_NAME = "Noob R15"
local PREVIEW_PLAYER_LOCAL_Z = 1.2
local PASSERBY_LOCAL_Z = -1.7
local PASSERBY_SECONDARY_LOCAL_Z = -2.25
local PASSERBY_TRAVEL_DISTANCE = 13
local PASSERBY_FEET_LIFT = 0
local PASSERBY_WALK_SECONDS = 5.4
local PASSERBY_FADE_SECONDS = 0.8
local PASSERBY_REPLAY_DELAY_SECONDS = 1.1
local SECOND_PASSERBY_START_DELAY_SECONDS = 1.75
local SELF_BREATH_MIN_TRANSPARENCY = 0.35
local SELF_BREATH_MAX_TRANSPARENCY = 0.75
local SELF_BREATH_CYCLE_SECONDS = 2.8

local previewGeneration = 0

function DrawHighlightInvisibilityPreviewRenderer.Clear()
	previewGeneration += 1
end

local function getLookFrame(position: Vector3, direction: Vector3): CFrame
	if direction.Magnitude <= 0 then
		return CFrame.new(position)
	end

	return CFrame.lookAt(position, position + direction.Unit)
end

local function getMoveForwardAnimationEntry(): any?
	local characterSet = PlayerAnimationConfig.CharacterSets[PlayerAnimationConfig.DefaultCharacterSetId]
	if type(characterSet) ~= "table" then
		return nil
	end

	local groundLoops = characterSet.GroundLoops
	if type(groundLoops) ~= "table" then
		return nil
	end

	return groundLoops[PlayerAnimationConfig.LoopKeys.MoveForward]
end

local function playMoveForward(character: Instance)
	if not character:IsA("Model") then
		return
	end

	local entry = getMoveForwardAnimationEntry()
	local animationId = if type(entry) == "table" then entry.AnimationId else nil
	if type(animationId) ~= "string" or animationId == "" then
		warn("[DrawController] missing MoveForward animation for invisibility highlight preview")
		return
	end

	AnimationManager.PlayByAssetId(character, animationId, {
		fadeTime = entry.FadeTime or 0.12,
		weight = entry.Weight or 1,
		speed = entry.Speed or 1,
		looped = if entry.Looped ~= nil then entry.Looped else true,
		force = true,
		priority = entry.Priority or Enum.AnimationPriority.Movement,
	})
end

local function setCharacterTransparency(character: Instance, transparency: number)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = transparency
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			(descendant :: any).Transparency = transparency
		end
	end
end

local function getPasserbyTransparency(elapsedSeconds: number): number
	local remainingSeconds = PASSERBY_WALK_SECONDS - elapsedSeconds
	if elapsedSeconds < PASSERBY_FADE_SECONDS then
		return 1 - math.clamp(elapsedSeconds / PASSERBY_FADE_SECONDS, 0, 1)
	end
	if remainingSeconds < PASSERBY_FADE_SECONDS then
		return 1 - math.clamp(remainingSeconds / PASSERBY_FADE_SECONDS, 0, 1)
	end

	return 0
end

local function addSelfTransparencyBreathing(character: Instance)
	local generation = previewGeneration
	task.spawn(function()
		local elapsed = 0
		while generation == previewGeneration and character:IsDescendantOf(game) do
			local deltaTime = RunService.RenderStepped:Wait()
			elapsed += deltaTime
			local alpha = (math.sin((elapsed / SELF_BREATH_CYCLE_SECONDS) * math.pi * 2 - math.pi * 0.5) + 1) * 0.5
			local transparency = SELF_BREATH_MIN_TRANSPARENCY
				+ (SELF_BREATH_MAX_TRANSPARENCY - SELF_BREATH_MIN_TRANSPARENCY) * alpha
			setCharacterTransparency(character, transparency)
		end
	end)
end

local function prepareAnimatedCharacter(character: Instance)
	local rootPart = DrawHighlightPreviewSupport.GetRootPart(character)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = descendant == rootPart
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
			descendant.Massless = true
		elseif descendant:IsA("Humanoid") then
			descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		elseif descendant:IsA("BaseScript") or descendant:IsA("Tool") then
			descendant:Destroy()
		end
	end
end

local function cloneNoob(name: string, localCFrame: CFrame, previewRuntime: any): Instance?
	local source = ReplicatedStorage:FindFirstChild(NOOB_MODEL_NAME)
	if source == nil then
		warn(`[DrawController] missing ReplicatedStorage.{NOOB_MODEL_NAME} for invisibility highlight preview`)
		return nil
	end

	local noob = previewRuntime.CloneResource(source, name, localCFrame, nil, false)
	if noob ~= nil then
		prepareAnimatedCharacter(noob)
		setCharacterTransparency(noob, 1)
		playMoveForward(noob)
	end

	return noob
end

local function tweenPasserbyLocalCFrame(
	character: Instance,
	generation: number,
	fromCFrame: CFrame,
	toCFrame: CFrame,
	durationSeconds: number,
	previewRuntime: any
): boolean
	local elapsed = 0
	while elapsed < durationSeconds do
		if generation ~= previewGeneration or not character:IsDescendantOf(game) then
			return false
		end

		local deltaTime = RunService.RenderStepped:Wait()
		elapsed += deltaTime
		local alpha = math.clamp(elapsed / durationSeconds, 0, 1)
		previewRuntime.SetItemLocalCFrame(character, fromCFrame:Lerp(toCFrame, alpha))
		setCharacterTransparency(character, getPasserbyTransparency(elapsed))
	end

	return generation == previewGeneration and character:IsDescendantOf(game)
end

local function addPasserbyLoop(
	character: Instance,
	startFrame: CFrame,
	endFrame: CFrame,
	startDelaySeconds: number,
	previewRuntime: any
)
	local generation = previewGeneration
	task.spawn(function()
		task.wait(startDelaySeconds)

		while generation == previewGeneration and character:IsDescendantOf(game) do
			previewRuntime.SetItemLocalCFrame(character, startFrame)
			setCharacterTransparency(character, 1)
			previewRuntime.FlushLayout()
			if
				not tweenPasserbyLocalCFrame(
					character,
					generation,
					startFrame,
					endFrame,
					PASSERBY_WALK_SECONDS,
					previewRuntime
				)
			then
				return
			end

			setCharacterTransparency(character, 1)
			task.wait(PASSERBY_REPLAY_DELAY_SECONDS)
		end
	end)
end

function DrawHighlightInvisibilityPreviewRenderer.Render(previewRuntime: any?)
	local runtime = previewRuntime or DrawHighlightPreviewWorld
	if
		not runtime.Begin({
			distance = 34,
			offset = Vector3.new(0, -2.25, 0),
			screenOffset = Vector2.new(0, 0.12),
			rotation = CFrame.Angles(math.rad(-7), 0, 0),
		})
	then
		return
	end

	local playerSize = DrawHighlightPreviewSupport.GetPlayerSizeFallback()
	local playerPosition = Vector3.new(0, playerSize.Y * 0.5, PREVIEW_PLAYER_LOCAL_Z)
	local player = DrawHighlightPreviewSupport.CloneLocalPlayerPreviewCharacter(
		"InvisibilityPlayerPreview",
		0,
		CFrame.new(playerPosition),
		runtime
	)
	if player ~= nil then
		local measured = DrawHighlightPreviewSupport.GetCharacterSize(player)
		playerPosition = Vector3.new(0, measured.Y * 0.5, PREVIEW_PLAYER_LOCAL_Z)
		runtime.SetItemLocalCFrame(player, CFrame.new(playerPosition))
		DrawHighlightPreviewSupport.GetPositiveNumber(
			AbilityConfig.Invisibility.SelfTransparency,
			"Invisibility self transparency must be positive"
		)
		setCharacterTransparency(player, SELF_BREATH_MIN_TRANSPARENCY)
		addSelfTransparencyBreathing(player)
		playerSize = measured
	end

	local passerbyY = playerSize.Y * 0.5 + PASSERBY_FEET_LIFT
	local leftStart = Vector3.new(-PASSERBY_TRAVEL_DISTANCE, passerbyY, PASSERBY_LOCAL_Z)
	local rightEnd = Vector3.new(PASSERBY_TRAVEL_DISTANCE, passerbyY, PASSERBY_LOCAL_Z)
	local rightStart = Vector3.new(PASSERBY_TRAVEL_DISTANCE, passerbyY, PASSERBY_SECONDARY_LOCAL_Z)
	local leftEnd = Vector3.new(-PASSERBY_TRAVEL_DISTANCE, passerbyY, PASSERBY_SECONDARY_LOCAL_Z)

	local leftToRightStart = getLookFrame(leftStart, rightEnd - leftStart)
	local leftToRightEnd = getLookFrame(rightEnd, rightEnd - leftStart)
	local rightToLeftStart = getLookFrame(rightStart, leftEnd - rightStart)
	local rightToLeftEnd = getLookFrame(leftEnd, leftEnd - rightStart)

	local leftToRightNoob = cloneNoob("InvisibilityLeftToRightNoobPreview", leftToRightStart, runtime)
	local rightToLeftNoob = cloneNoob("InvisibilityRightToLeftNoobPreview", rightToLeftStart, runtime)
	if leftToRightNoob ~= nil then
		addPasserbyLoop(leftToRightNoob, leftToRightStart, leftToRightEnd, 0, runtime)
	end
	if rightToLeftNoob ~= nil then
		addPasserbyLoop(rightToLeftNoob, rightToLeftStart, rightToLeftEnd, SECOND_PASSERBY_START_DELAY_SECONDS, runtime)
	end
end

return DrawHighlightInvisibilityPreviewRenderer
