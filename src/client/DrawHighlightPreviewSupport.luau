--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local DrawHighlightPreviewCharacterSetup = require(script.Parent:WaitForChild("DrawHighlightPreviewCharacterSetup"))
local DrawHighlightPreviewWorld = require(script.Parent:WaitForChild("DrawHighlightPreviewWorld"))
local PlayerAnimationConfig = require(Config:WaitForChild("PlayerAnimationConfig"))
local WeaponSkinVFXConfig = require(Config:WaitForChild("WeaponSkinVFXConfig"))

local DrawHighlightPreviewSupport = {}

local PLAYER_SIZE_FALLBACK = Vector3.new(3.88, 5.95, 2.22)

local localPlayer = Players.LocalPlayer

function DrawHighlightPreviewSupport.ConfigureVFXSystem(vfxSystem: any)
	local effectsRoot = ReplicatedStorage:FindFirstChild("Effects")
	if effectsRoot ~= nil then
		vfxSystem.SetEffectsFolder(effectsRoot)
	end
end

function DrawHighlightPreviewSupport.ResolveEffectPath(path: string): Instance?
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

function DrawHighlightPreviewSupport.ResolveInstancePath(path: string): Instance?
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

function DrawHighlightPreviewSupport.CloneEffectPath(
	path: string,
	name: string,
	localCFrame: CFrame,
	scale: number?,
	playParticles: boolean?
): Instance?
	local source = DrawHighlightPreviewSupport.ResolveEffectPath(path)
	if source == nil then
		warn(`[DrawController] missing highlight preview effect: {path}`)
		return nil
	end

	return DrawHighlightPreviewWorld.CloneResource(source, name, localCFrame, scale, playParticles)
end

function DrawHighlightPreviewSupport.GetSkinConfig(itemId: string): any?
	local weaponSkins = (PlayerAnimationConfig :: any).WeaponSkins
	local skinConfig = if type(weaponSkins) == "table" then weaponSkins[itemId] else nil
	return if type(skinConfig) == "table" then skinConfig else nil
end

function DrawHighlightPreviewSupport.GetSkinFireballConfig(itemId: string): any?
	local weaponSkins = (WeaponSkinVFXConfig :: any).WeaponSkins
	local skinConfig = if type(weaponSkins) == "table" then weaponSkins[itemId] else nil
	if type(skinConfig) ~= "table" then
		return nil
	end

	return skinConfig.Fireball
end

function DrawHighlightPreviewSupport.CloneWeaponSkinModel(itemId: string, localCFrame: CFrame): Instance?
	local skinConfig = DrawHighlightPreviewSupport.GetSkinConfig(itemId)
	local weaponModelPath = if type(skinConfig) == "table" then skinConfig.WeaponModelPath else nil
	if type(weaponModelPath) ~= "string" then
		warn(`[DrawController] missing weapon model path for highlight skin: {itemId}`)
		return nil
	end

	local source = DrawHighlightPreviewSupport.ResolveInstancePath(weaponModelPath)
	if source == nil then
		warn(`[DrawController] missing weapon model for highlight skin: {weaponModelPath}`)
		return nil
	end

	return DrawHighlightPreviewWorld.CloneResource(source, `Weapon_{itemId}`, localCFrame, nil)
end

function DrawHighlightPreviewSupport.GetRootPart(character: Instance): BasePart?
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

function DrawHighlightPreviewSupport.GetInstanceBounds(instance: Instance): (CFrame?, Vector3?)
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

function DrawHighlightPreviewSupport.GetPlayerSizeFallback(): Vector3
	return PLAYER_SIZE_FALLBACK
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

function DrawHighlightPreviewSupport.CloneLocalPlayerPreviewCharacter(
	name: string,
	feetY: number,
	localCFrame: CFrame?
): Instance?
	local character = localPlayer.Character
	if character == nil then
		warn("[DrawController] missing local character for highlight preview; using measured fallback only")
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
	local _sourcePivot, sourceSize = DrawHighlightPreviewSupport.GetInstanceBounds(characterSource)
	if sourceSize == nil then
		characterSource:Destroy()
		return nil
	end

	local baseCFrame = CFrame.new(0, feetY + sourceSize.Y * 0.5, 0)
	if localCFrame ~= nil then
		baseCFrame = localCFrame
	end

	local previewCharacter = DrawHighlightPreviewWorld.CloneResource(characterSource, name, baseCFrame, nil, false)
	characterSource:Destroy()

	if previewCharacter ~= nil then
		cleanupPreviewCharacter(previewCharacter)
		DrawHighlightPreviewCharacterSetup.Setup(previewCharacter)
	end

	return previewCharacter
end

function DrawHighlightPreviewSupport.GetCharacterSize(character: Instance?): Vector3
	if character ~= nil then
		local _pivot, size = DrawHighlightPreviewSupport.GetInstanceBounds(character)
		if size ~= nil then
			return size
		end
	end

	return PLAYER_SIZE_FALLBACK
end

function DrawHighlightPreviewSupport.GetPositiveNumber(value: any, message: string): number
	if type(value) ~= "number" or value <= 0 then
		error(`[DrawController] {message}`)
	end

	return value
end

function DrawHighlightPreviewSupport.AttachWeaponSkinToCharacter(
	itemId: string,
	character: Instance,
	_fallbackLocalCFrame: CFrame
): Instance?
	DrawHighlightPreviewCharacterSetup.RemovePreviewWeapon(character)

	local skinConfig = DrawHighlightPreviewSupport.GetSkinConfig(itemId)
	local weaponModelPath = if type(skinConfig) == "table" then skinConfig.WeaponModelPath else nil
	if type(weaponModelPath) ~= "string" then
		warn(`[DrawController] missing weapon model path for highlight skin: {itemId}`)
		return nil
	end

	local source = DrawHighlightPreviewSupport.ResolveInstancePath(weaponModelPath)
	if source == nil then
		warn(`[DrawController] missing weapon model for highlight skin: {weaponModelPath}`)
		return nil
	end

	local weapon = source:Clone()
	weapon.Name = `Weapon_{itemId}`
	DrawHighlightPreviewCharacterSetup.SetWeaponPartProperties(weapon)

	local rightHand = character:FindFirstChild("RightHand")
	if rightHand == nil or not rightHand:IsA("BasePart") then
		weapon:Destroy()
		warn("[DrawController] preview character has no R15 RightHand for weapon grip")
		return nil
	end

	local gripPart = DrawHighlightPreviewCharacterSetup.FindGripPart(weapon)
	if gripPart == nil then
		weapon:Destroy()
		warn(`[DrawController] weapon skin {itemId} has no grip part for highlight preview`)
		return nil
	end
	if weapon:IsA("Model") and weapon.PrimaryPart == nil then
		weapon.PrimaryPart = gripPart
	end

	weapon.Parent = character

	local handAttachmentName = if type(skinConfig) == "table" then skinConfig.HandAttachmentName else nil
	local gripAttachmentName = if type(skinConfig) == "table" then skinConfig.GripAttachmentName else nil
	local handAttachment = DrawHighlightPreviewCharacterSetup.FindAttachment(rightHand, handAttachmentName)
	local gripAttachment = if type(gripAttachmentName) == "string"
		then weapon:FindFirstChild(gripAttachmentName, true)
		else nil
	local targetCFrame = rightHand.CFrame

	if handAttachment ~= nil and gripAttachment ~= nil and gripAttachment:IsA("Attachment") then
		targetCFrame = handAttachment.WorldCFrame * gripAttachment.CFrame:Inverse()
	elseif handAttachment ~= nil and weapon:IsA("Tool") then
		targetCFrame = handAttachment.WorldCFrame * weapon.Grip
		warn(`[DrawController] weapon skin {itemId} grip attachment missing; using Tool.Grip alignment`)
	elseif handAttachment ~= nil then
		targetCFrame = handAttachment.WorldCFrame
		warn(`[DrawController] weapon skin {itemId} grip attachment missing; using hand attachment alignment`)
	else
		warn(`[DrawController] weapon skin {itemId} hand attachment missing; using RightHand alignment`)
	end
	DrawHighlightPreviewCharacterSetup.PivotInstanceToPartCFrame(weapon, gripPart, targetCFrame)

	local weld = Instance.new("WeldConstraint")
	weld.Name = "WeaponGripWeld"
	weld.Part0 = rightHand
	weld.Part1 = gripPart
	weld.Parent = gripPart

	return weapon
end

return DrawHighlightPreviewSupport
