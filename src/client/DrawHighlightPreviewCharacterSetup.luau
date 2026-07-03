--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local PlayerAnimationConfig = require(Config:WaitForChild("PlayerAnimationConfig"))

local DrawHighlightPreviewCharacterSetup = {}

local WEAPON_MODEL_NAME = "SwordnWizardEquippedWeapon"
local PREVIEW_COLLISION_GUARD_ATTRIBUTE = "DrawHighlightPreviewCollisionGuard"

local localPlayer = Players.LocalPlayer
local playerScripts = localPlayer:WaitForChild("PlayerScripts")
local AnimationManager: any =
	require(playerScripts:WaitForChild("ClientPackages"):WaitForChild("CommonKit"):WaitForChild("AnimationManager"))

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

local function getSkinConfig(itemId: string): any?
	local weaponSkins = (PlayerAnimationConfig :: any).WeaponSkins
	local skinConfig = if type(weaponSkins) == "table" then weaponSkins[itemId] else nil
	return if type(skinConfig) == "table" then skinConfig else nil
end

local function getEquippedWeaponSkinId(): string
	local equippedSkinId = localPlayer:GetAttribute("EquippedWeaponSkin")
	if type(equippedSkinId) == "string" and equippedSkinId ~= "" then
		return equippedSkinId
	end

	return PlayerAnimationConfig.DefaultWeaponSkinId
end

local function getFirstBasePart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end

	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function getBasePartByName(instance: Instance, name: string): BasePart?
	if instance.Name == name and instance:IsA("BasePart") then
		return instance
	end

	local descendant = instance:FindFirstChild(name, true)
	return if descendant ~= nil and descendant:IsA("BasePart") then descendant else nil
end

local function findGripPart(instance: Instance): BasePart?
	if instance:IsA("Model") and instance.PrimaryPart ~= nil then
		return instance.PrimaryPart
	end

	return getBasePartByName(instance, "Handle") or getFirstBasePart(instance)
end

local function findAttachment(part: BasePart, attachmentName: string?): Attachment?
	if type(attachmentName) ~= "string" or attachmentName == "" then
		return nil
	end

	local attachment = part:FindFirstChild(attachmentName)
	return if attachment ~= nil and attachment:IsA("Attachment") then attachment else nil
end

local function pivotInstanceToPartCFrame(instance: Instance, gripPart: BasePart, targetCFrame: CFrame)
	local delta = targetCFrame * gripPart.CFrame:Inverse()

	if instance:IsA("Model") then
		instance:PivotTo(delta * instance:GetPivot())
	elseif instance:IsA("BasePart") then
		instance.CFrame = targetCFrame
	else
		for _, descendant in instance:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CFrame = delta * descendant.CFrame
			end
		end
	end
end

local function setWeaponPartProperties(instance: Instance)
	if instance:IsA("BasePart") then
		instance.Anchored = false
		instance.CanCollide = false
		instance.CanTouch = false
		instance.CanQuery = false
		instance.CastShadow = false
		instance.Massless = true
	end

	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
			descendant.Massless = true
		end
	end
end

local function preparePreviewCharacterForAnimation(character: Instance)
	local rootPart = getRootPart(character)

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = descendant == rootPart
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
			descendant.Massless = true
		end
	end
end

local function setPreviewPartNonColliding(part: BasePart, rootPart: BasePart?)
	part.Anchored = part == rootPart
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
end

local function enforcePreviewCharacterNoCollision(character: Instance)
	local rootPart = getRootPart(character)
	if character:IsA("BasePart") then
		setPreviewPartNonColliding(character, rootPart)
	end

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			setPreviewPartNonColliding(descendant, rootPart)
		end
	end
end

local function installPreviewCollisionGuard(character: Instance)
	if character:GetAttribute(PREVIEW_COLLISION_GUARD_ATTRIBUTE) == true then
		return
	end
	character:SetAttribute(PREVIEW_COLLISION_GUARD_ATTRIBUTE, true)

	enforcePreviewCharacterNoCollision(character)
	local descendantAddedConnection = character.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("BasePart") then
			setPreviewPartNonColliding(descendant, getRootPart(character))
		end
	end)

	task.spawn(function()
		while character:IsDescendantOf(game) do
			enforcePreviewCharacterNoCollision(character)
			RunService.Heartbeat:Wait()
		end

		descendantAddedConnection:Disconnect()
	end)
end

local function removeExistingPreviewWeapon(character: Instance)
	local existing = character:FindFirstChild(WEAPON_MODEL_NAME)
	if existing ~= nil then
		existing:Destroy()
	end
end

local function attachEquippedWeaponToPreviewCharacter(character: Instance)
	if not character:IsA("Model") then
		return
	end

	removeExistingPreviewWeapon(character)

	local skinId = getEquippedWeaponSkinId()
	local skinConfig = getSkinConfig(skinId)
	if skinConfig == nil then
		skinId = PlayerAnimationConfig.DefaultWeaponSkinId
		skinConfig = getSkinConfig(skinId)
	end
	if skinConfig == nil then
		warn("[DrawController] missing default weapon skin config for highlight preview character")
		return
	end

	local weaponModelPath = skinConfig.WeaponModelPath
	if type(weaponModelPath) ~= "string" or weaponModelPath == "" then
		warn(`[DrawController] missing weapon model path for highlight preview skin: {skinId}`)
		return
	end

	local source = resolveInstancePath(weaponModelPath)
	if source == nil then
		warn(`[DrawController] missing weapon model for highlight preview skin: {weaponModelPath}`)
		return
	end

	local rightHand = character:FindFirstChild("RightHand")
	if rightHand == nil or not rightHand:IsA("BasePart") then
		warn("[DrawController] preview character has no R15 RightHand for weapon grip")
		return
	end

	local weapon = source:Clone()
	weapon.Name = WEAPON_MODEL_NAME
	weapon:SetAttribute("WeaponSkinId", skinId)
	weapon:SetAttribute("WeaponType", skinConfig.WeaponType)
	setWeaponPartProperties(weapon)

	local gripPart = findGripPart(weapon)
	if gripPart == nil then
		weapon:Destroy()
		warn(`[DrawController] weapon model {weaponModelPath} has no grip part for highlight preview`)
		return
	end
	if weapon:IsA("Model") and weapon.PrimaryPart == nil then
		weapon.PrimaryPart = gripPart
	end

	weapon.Parent = character

	local handAttachment = findAttachment(rightHand, skinConfig.HandAttachmentName)
	local gripAttachment = findAttachment(gripPart, skinConfig.GripAttachmentName)
	local targetGripCFrame = rightHand.CFrame
	if handAttachment ~= nil and gripAttachment ~= nil then
		targetGripCFrame = handAttachment.WorldCFrame * gripAttachment.CFrame:Inverse()
	elseif handAttachment ~= nil and weapon:IsA("Tool") then
		targetGripCFrame = handAttachment.WorldCFrame * weapon.Grip
	elseif handAttachment ~= nil then
		targetGripCFrame = handAttachment.WorldCFrame
	end
	pivotInstanceToPartCFrame(weapon, gripPart, targetGripCFrame)

	local weld = Instance.new("WeldConstraint")
	weld.Name = "WeaponGripWeld"
	weld.Part0 = rightHand
	weld.Part1 = gripPart
	weld.Parent = gripPart
end

local function getDefaultIdleAnimationEntry(): any?
	local characterSet = PlayerAnimationConfig.CharacterSets[PlayerAnimationConfig.DefaultCharacterSetId]
	if type(characterSet) ~= "table" then
		return nil
	end

	local groundLoops = characterSet.GroundLoops
	if type(groundLoops) ~= "table" then
		return nil
	end

	return groundLoops[PlayerAnimationConfig.LoopKeys.Idle]
end

local function playPreviewIdle(character: Instance)
	if not character:IsA("Model") then
		return
	end

	local entry = getDefaultIdleAnimationEntry()
	local animationId = if type(entry) == "table" then entry.AnimationId else nil
	if type(animationId) ~= "string" or animationId == "" then
		warn("[DrawController] missing Idle animation for highlight preview character")
		return
	end

	AnimationManager.PlayByAssetId(character, animationId, {
		fadeTime = entry.FadeTime or 0.16,
		weight = entry.Weight or 1,
		speed = entry.Speed or 1,
		looped = if entry.Looped ~= nil then entry.Looped else true,
		force = true,
		priority = entry.Priority or Enum.AnimationPriority.Idle,
	})
end

function DrawHighlightPreviewCharacterSetup.Setup(character: Instance)
	preparePreviewCharacterForAnimation(character)
	attachEquippedWeaponToPreviewCharacter(character)
	installPreviewCollisionGuard(character)
	playPreviewIdle(character)
end

function DrawHighlightPreviewCharacterSetup.RemovePreviewWeapon(character: Instance)
	removeExistingPreviewWeapon(character)
end

function DrawHighlightPreviewCharacterSetup.SetWeaponPartProperties(instance: Instance)
	setWeaponPartProperties(instance)
end

function DrawHighlightPreviewCharacterSetup.FindGripPart(instance: Instance): BasePart?
	return findGripPart(instance)
end

function DrawHighlightPreviewCharacterSetup.FindAttachment(part: BasePart, attachmentName: string?): Attachment?
	return findAttachment(part, attachmentName)
end

function DrawHighlightPreviewCharacterSetup.PivotInstanceToPartCFrame(
	instance: Instance,
	gripPart: BasePart,
	targetCFrame: CFrame
)
	pivotInstanceToPartCFrame(instance, gripPart, targetCFrame)
end

return DrawHighlightPreviewCharacterSetup
