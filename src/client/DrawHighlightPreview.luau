--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local AbilityConfig = require(Config:WaitForChild("AbilityConfig"))
local DrawHighlightPreviewWorld = require(script.Parent:WaitForChild("DrawHighlightPreviewWorld"))
local PlayerAnimationConfig = require(Config:WaitForChild("PlayerAnimationConfig"))
local WeaponSkinVFXConfig = require(Config:WaitForChild("WeaponSkinVFXConfig"))

local DrawHighlightPreview = {}

local CATEGORY_ABILITY = "Ability"
local CATEGORY_WEAPON_SKIN = "WeaponSkin"
local DEFAULT_FIREBALL_PROJECTILE_PREVIEW_PATH = "Fireball/Projectiles/Fast"
local HEALING_ZONE_CIRCLE_PREVIEW_PATH = "Ability/HealingZone/HealCircle"
local HEALING_ZONE_PARTICLES_PREVIEW_PATH = "Ability/HealingZone/Heal"
local ICE_WALL_PREVIEW_PATH = "Ability/IceWall/Ice Wall"
local DEFLECT_SHIELD_PREVIEW_PATH = "Ability/DeflectShield/DeflectShield"
local DEFLECT_PULSE_PREVIEW_PATH = "Ability/DeflectShield/Deflect"
local HEALING_TARGET_OFFSET = Vector3.new(0, 1, 0)
local HEALING_ZONE_REPLAY_DELAY_SECONDS = 1
local HEALING_ZONE_REFERENCE_RADIUS = 12
local HEALING_ZONE_PLAYER_FEET_LIFT = 0.42

local previewConnections: { RBXScriptConnection } = {}
local localPlayer = Players.LocalPlayer
local playerScripts = localPlayer:WaitForChild("PlayerScripts")
local VFXSystem: any =
	require(playerScripts:WaitForChild("ClientPackages"):WaitForChild("CommonKit"):WaitForChild("VFXSystem"))

local function configureVFXSystem()
	local effectsRoot = ReplicatedStorage:FindFirstChild("Effects")
	if effectsRoot ~= nil then
		VFXSystem.SetEffectsFolder(effectsRoot)
	end
end

local function disconnectConnections()
	for _, connection in previewConnections do
		connection:Disconnect()
	end

	table.clear(previewConnections)
end

function DrawHighlightPreview.Clear()
	disconnectConnections()
	DrawHighlightPreviewWorld.Clear()
end

function DrawHighlightPreview.ResolveReferences(screen: Instance?)
	DrawHighlightPreviewWorld.ResolveReferences(screen)
end

local function resolveEffectPath(path: string): Instance?
	local effectsRoot = ReplicatedStorage:FindFirstChild("Effects")
	if effectsRoot == nil then
		return nil
	end

	local current: Instance? = effectsRoot
	for segment in string.gmatch(path, "[^/]+") do
		if current == nil then
			return nil
		end

		current = current:FindFirstChild(segment)
	end

	return current
end

local function resolveInstancePath(path: string): Instance?
	local current: Instance? = nil
	local isFirstSegment = true

	for segment in string.gmatch(path, "[^%.]+") do
		if isFirstSegment then
			if segment == "ReplicatedStorage" then
				current = ReplicatedStorage
			elseif segment == "Workspace" then
				current = Workspace
			else
				current = game:FindFirstChild(segment)
			end

			isFirstSegment = false
		elseif current ~= nil then
			current = current:FindFirstChild(segment)
		end
	end

	return current
end

local function cloneResource(
	source: Instance,
	name: string,
	localCFrame: CFrame,
	scale: number?,
	playParticles: boolean?
): Instance?
	return DrawHighlightPreviewWorld.CloneResource(source, name, localCFrame, scale, playParticles)
end

local function cloneEffectPath(
	path: string,
	name: string,
	localCFrame: CFrame,
	scale: number?,
	playParticles: boolean?
): Instance?
	local source = resolveEffectPath(path)
	if source == nil then
		warn(`[DrawController] missing highlight preview effect: {path}`)
		return nil
	end

	return cloneResource(source, name, localCFrame, scale, playParticles)
end

local function cloneWeaponSkinModel(itemId: string, localCFrame: CFrame): Instance?
	local weaponSkins = (PlayerAnimationConfig :: any).WeaponSkins
	local skinConfig = if type(weaponSkins) == "table" then weaponSkins[itemId] else nil
	local weaponModelPath = if type(skinConfig) == "table" then skinConfig.WeaponModelPath else nil
	if type(weaponModelPath) ~= "string" then
		warn(`[DrawController] missing weapon model path for highlight skin: {itemId}`)
		return nil
	end

	local source = resolveInstancePath(weaponModelPath)
	if source == nil then
		warn(`[DrawController] missing weapon model for highlight skin: {weaponModelPath}`)
		return nil
	end

	return cloneResource(source, `Weapon_{itemId}`, localCFrame, nil)
end

local function getSkinFireballConfig(itemId: string): any?
	local weaponSkins = (WeaponSkinVFXConfig :: any).WeaponSkins
	local skinConfig = if type(weaponSkins) == "table" then weaponSkins[itemId] else nil
	if type(skinConfig) ~= "table" then
		return nil
	end

	return skinConfig.Fireball
end

local function getHealingZoneDurationSeconds(): number
	local durationSeconds = AbilityConfig.HealingZone.DurationSeconds
	if type(durationSeconds) ~= "number" or durationSeconds <= 0 then
		error("[DrawController] Healing Zone duration must be configured as a positive number")
	end

	return durationSeconds
end

local function getHealingZoneTickSeconds(): number
	local tickSeconds = AbilityConfig.HealingZone.TickSeconds
	if type(tickSeconds) ~= "number" or tickSeconds <= 0 then
		error("[DrawController] Healing Zone tick seconds must be configured as a positive number")
	end

	return tickSeconds
end

local function getHealingZoneRadiusScale(): number
	local radius = AbilityConfig.HealingZone.Radius
	if type(radius) ~= "number" or radius <= 0 then
		error("[DrawController] Healing Zone radius must be configured as a positive number")
	end

	return math.max(radius / HEALING_ZONE_REFERENCE_RADIUS, 0.01)
end

local function getRootPart(character: Instance): BasePart?
	if character:IsA("Model") then
		local primaryPart = character.PrimaryPart
		if primaryPart ~= nil then
			return primaryPart
		end

		local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart ~= nil and humanoidRootPart:IsA("BasePart") then
			return humanoidRootPart
		end
	end

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function getInstanceBounds(instance: Instance): (CFrame?, Vector3?)
	if instance:IsA("Model") then
		return instance:GetBoundingBox()
	end

	if instance:IsA("BasePart") then
		return instance.CFrame, instance.Size
	end

	local parts = {}
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	if #parts <= 0 then
		return nil, nil
	end

	local minBounds = Vector3.new(math.huge, math.huge, math.huge)
	local maxBounds = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, part in parts do
		local halfSize = part.Size * 0.5
		for x = -1, 1, 2 do
			for y = -1, 1, 2 do
				for z = -1, 1, 2 do
					local corner = part.CFrame * Vector3.new(halfSize.X * x, halfSize.Y * y, halfSize.Z * z)
					minBounds = Vector3.new(
						math.min(minBounds.X, corner.X),
						math.min(minBounds.Y, corner.Y),
						math.min(minBounds.Z, corner.Z)
					)
					maxBounds = Vector3.new(
						math.max(maxBounds.X, corner.X),
						math.max(maxBounds.Y, corner.Y),
						math.max(maxBounds.Z, corner.Z)
					)
				end
			end
		end
	end

	return CFrame.new((minBounds + maxBounds) * 0.5), maxBounds - minBounds
end

local function cleanupPreviewCharacter(character: Instance)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BaseScript") or descendant:IsA("Tool") then
			descendant:Destroy()
		elseif descendant:IsA("Humanoid") then
			descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
end

local function cloneLocalPlayerPreviewCharacter(feetY: number): Instance?
	local character = localPlayer.Character
	if character == nil then
		return nil
	end

	local wasArchivable = character.Archivable
	character.Archivable = true
	local characterSource = character:Clone()
	character.Archivable = wasArchivable
	if characterSource == nil then
		return nil
	end

	cleanupPreviewCharacter(characterSource)
	local sourcePivot, sourceSize = getInstanceBounds(characterSource)
	if sourcePivot == nil or sourceSize == nil then
		characterSource:Destroy()
		return nil
	end

	local localCFrame = CFrame.new(0, feetY + sourceSize.Y * 0.5 + HEALING_ZONE_PLAYER_FEET_LIFT, 0)
	local previewCharacter = cloneResource(characterSource, "HealingZonePlayerPreview", localCFrame, nil, false)
	characterSource:Destroy()

	if previewCharacter ~= nil then
		cleanupPreviewCharacter(previewCharacter)
	end

	return previewCharacter
end

local function getHealingZoneCircleSurfaceY(scale: number): number
	local circleSource = resolveEffectPath(HEALING_ZONE_CIRCLE_PREVIEW_PATH)
	if circleSource == nil then
		return 0
	end

	local _sourcePivot, sourceSize = getInstanceBounds(circleSource)
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
	local durationSeconds = getHealingZoneDurationSeconds()
	local tickSeconds = getHealingZoneTickSeconds()

	task.spawn(function()
		RunService.RenderStepped:Wait()

		while playerPreview:IsDescendantOf(game) and circle:IsDescendantOf(game) do
			local playbackEndTime = DrawHighlightPreviewWorld.PlayParticlePlaybackOnce(circle)

			local elapsed = 0
			while elapsed < durationSeconds and playerPreview:IsDescendantOf(game) do
				if not playHealingZoneHeal(rootPart) then
					return
				end

				local waitSeconds = math.min(tickSeconds, durationSeconds - elapsed)
				task.wait(waitSeconds)
				elapsed += waitSeconds
			end

			if not playerPreview:IsDescendantOf(game) then
				return
			end

			task.wait(math.max(0, playbackEndTime - durationSeconds))
			task.wait(HEALING_ZONE_REPLAY_DELAY_SECONDS)
		end
	end)
end

local function renderFootballShoesPreview()
	if
		not DrawHighlightPreviewWorld.Begin({
			distance = 5.8,
			offset = Vector3.new(0, 0.05, 0),
			orbitSpeed = 0.24,
		})
	then
		return
	end

	local fireballConfig = getSkinFireballConfig("football_shoes")
	local projectilePaths = if type(fireballConfig) == "table" then fireballConfig.ProjectileEffectPathsByTier else nil
	local projectilePath = if type(projectilePaths) == "table"
		then projectilePaths.Fast or projectilePaths.Heavy
		else nil
	local explosionPath = if type(fireballConfig) == "table" then fireballConfig.ExplosionEffectPath else nil

	cloneWeaponSkinModel("football_shoes", CFrame.new(-1.25, 0.15, 0) * CFrame.Angles(0, math.rad(-35), math.rad(14)))

	if type(projectilePath) == "string" then
		cloneEffectPath(projectilePath, "FootballProjectilePreview", CFrame.new(1.35, 0.12, 0.1), 0.75)
	end

	if type(explosionPath) == "string" then
		cloneEffectPath(explosionPath, "FootballExplosionPreview", CFrame.new(1.95, -0.75, -0.65), 0.38)
	end
end

local function renderAbsoluteZeroPreview()
	if
		not DrawHighlightPreviewWorld.Begin({
			distance = 6.1,
			offset = Vector3.new(0, 0.05, 0),
			orbitSpeed = 0.2,
		})
	then
		return
	end

	local fireballConfig = getSkinFireballConfig("absolute_zero")
	local projectilePaths = if type(fireballConfig) == "table" then fireballConfig.ProjectileEffectPathsByTier else nil
	local projectilePath = if type(projectilePaths) == "table"
		then projectilePaths.Heavy or projectilePaths.Fast
		else nil
	local chargePath = if type(fireballConfig) == "table" then fireballConfig.ChargeEffectPath else nil
	local explosionPath = if type(fireballConfig) == "table"
		then fireballConfig.HeavyExplosionEffectPath or fireballConfig.ExplosionEffectPath
		else nil

	cloneWeaponSkinModel("absolute_zero", CFrame.new(-1.35, 0.25, 0) * CFrame.Angles(0, math.rad(-28), math.rad(10)))

	if type(chargePath) == "string" then
		cloneEffectPath(chargePath, "AbsoluteZeroChargePreview", CFrame.new(0.95, 0.4, 0.05), 0.65)
	end

	if type(projectilePath) == "string" then
		cloneEffectPath(projectilePath, "AbsoluteZeroProjectilePreview", CFrame.new(1.85, -0.25, -0.05), 0.75)
	end

	if type(explosionPath) == "string" then
		cloneEffectPath(explosionPath, "AbsoluteZeroExplosionPreview", CFrame.new(0.65, -0.9, -0.85), 0.28)
	end
end

local function renderIceWallPreview()
	if not DrawHighlightPreviewWorld.Begin({
		distance = 6.4,
		offset = Vector3.new(0, 0.1, 0),
	}) then
		return
	end

	cloneEffectPath(
		ICE_WALL_PREVIEW_PATH,
		"IceWallPreview",
		CFrame.new(0, -0.45, 0) * CFrame.Angles(0, math.rad(180), 0),
		0.38
	)
end

local function renderHealingZonePreview()
	if
		not DrawHighlightPreviewWorld.Begin({
			-- Visual baseline captured from hand-tuned preview:
			-- Preview fill ~= 86.5% width / 89.1% height, margins L/R ~= 47px,
			-- top ~= 66px, bottom bbox ~= -28px including Heal tick effect bounds.
			distance = 35,
			offset = Vector3.new(0, -2.35, 0),
			screenOffset = Vector2.new(0, 0.16),
			rotation = CFrame.Angles(math.rad(-8), 0, 0),
		})
	then
		return
	end

	local circleScale = getHealingZoneRadiusScale()
	local circle = cloneEffectPath(
		HEALING_ZONE_CIRCLE_PREVIEW_PATH,
		"HealingZoneCirclePreview",
		CFrame.new(0, 0, 0),
		circleScale,
		false
	)

	local playerPreview = cloneLocalPlayerPreviewCharacter(getHealingZoneCircleSurfaceY(circleScale))
	if circle ~= nil and playerPreview ~= nil then
		local rootPart = getRootPart(playerPreview)
		if rootPart ~= nil then
			addHealingZonePlaybackLoop(circle, playerPreview, rootPart)
		end
	end
end

local function addDeflectFireballLoop(fireball: Instance)
	local elapsed = 0

	table.insert(
		previewConnections,
		RunService.RenderStepped:Connect(function(deltaTime: number)
			if fireball.Parent == nil then
				return
			end

			elapsed = (elapsed + deltaTime) % 2.25
			local alpha = elapsed / 2.25
			local position: Vector3
			local direction: Vector3

			if alpha < 0.48 then
				local approachAlpha = alpha / 0.48
				position = Vector3.new(-2.75 + 2.55 * approachAlpha, 0, 0.24 - 0.12 * approachAlpha)
				direction = Vector3.new(1, 0, -0.05)
			else
				local reboundAlpha = (alpha - 0.48) / 0.52
				local eased = math.min(1, reboundAlpha)
				position = Vector3.new(-0.2 + 3.05 * eased, 0.18 * eased, 0.12 + 0.62 * eased)
				direction = Vector3.new(1, 0.08, 0.2)
			end

			DrawHighlightPreviewWorld.SetItemLocalCFrame(fireball, CFrame.lookAt(position, position + direction))
		end)
	)
end

local function renderDeflectShieldPreview()
	if not DrawHighlightPreviewWorld.Begin({
		distance = 5.9,
		offset = Vector3.new(0, 0.1, 0),
	}) then
		return
	end

	cloneEffectPath(DEFLECT_SHIELD_PREVIEW_PATH, "DeflectShieldPreview", CFrame.new(0, 0, 0), 0.75)
	cloneEffectPath(DEFLECT_PULSE_PREVIEW_PATH, "DeflectPulsePreview", CFrame.new(0, 0, -0.18), 0.68)

	local fireball = cloneEffectPath(
		DEFAULT_FIREBALL_PROJECTILE_PREVIEW_PATH,
		"DeflectFireballPreview",
		CFrame.new(-2.7, 0, 0.2),
		0.7
	)
	if fireball ~= nil then
		addDeflectFireballLoop(fireball)
	end
end

local function renderWeaponSkinPreview(itemId: string)
	if itemId == "football_shoes" then
		renderFootballShoesPreview()
	elseif itemId == "absolute_zero" then
		renderAbsoluteZeroPreview()
	else
		if
			not DrawHighlightPreviewWorld.Begin({
				distance = 5.5,
				offset = Vector3.new(0, 0.05, 0),
				orbitSpeed = 0.22,
			})
		then
			return
		end

		cloneWeaponSkinModel(itemId, CFrame.new(0, 0.1, 0) * CFrame.Angles(0, math.rad(-30), math.rad(12)))
	end
end

local function renderAbilityPreview(itemId: string)
	if itemId == "ice_wall" then
		renderIceWallPreview()
	elseif itemId == "healing_zone" then
		renderHealingZonePreview()
	elseif itemId == "deflect_shield" then
		renderDeflectShieldPreview()
	else
		warn(`[DrawController] no highlight preview defined for ability: {itemId}`)
	end
end

function DrawHighlightPreview.Render(category: string, itemId: string)
	DrawHighlightPreview.Clear()
	configureVFXSystem()

	if category == CATEGORY_WEAPON_SKIN then
		renderWeaponSkinPreview(itemId)
	elseif category == CATEGORY_ABILITY then
		renderAbilityPreview(itemId)
	else
		warn(`[DrawController] unsupported highlight preview category: {category}`)
	end
end

return DrawHighlightPreview
