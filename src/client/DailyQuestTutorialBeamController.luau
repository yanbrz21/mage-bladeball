--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = Shared:WaitForChild("Network")

local MatchConfig = require(Shared.Config.MatchConfig)
local QuestConfig = require(Shared.Config.QuestConfig)
local Remotes = require(Network:WaitForChild("Remotes"))

local questUpdatedRemote = Remotes.GetServerToClient(Network, Remotes.ServerToClient.QuestUpdated)

local QUEST_REWARD_ITEMS_TAG = "QUEST_REWARD_ITEMS"
local DAILY_KILL_QUEST_ID = "daily_kills"
local BEAM_NAME = "DailyQuestTutorialBeam"
local START_ATTACHMENT_NAME = "DailyQuestTutorialBeamStart"
local END_ATTACHMENT_NAME = "DailyQuestTutorialBeamEnd"

type ClaimedMilestones = {
	[string]: boolean,
}

type QuestSnapshotEntry = {
	questId: string,
	progress: number,
	target: number,
	claimed: boolean,
	completed: boolean,
	claimedMilestones: ClaimedMilestones?,
}

type QuestSnapshot = {
	quests: { QuestSnapshotEntry },
}

local DailyQuestTutorialBeamController = {
	Name = "DailyQuestTutorialBeamController",
	_didInit = false,
	_didStart = false,
}

local localPlayer = Players.LocalPlayer
local connections: { RBXScriptConnection } = {}
local currentSnapshot: QuestSnapshot?
local activeBeam: Beam?
local startAttachment: Attachment?
local endAttachment: Attachment?
local startAnchor: BasePart?
local endAnchor: BasePart?
local activeRootPart: BasePart?
local activeTargetPart: BasePart?
local beamUpdateConnection: RBXScriptConnection?
local warnedMissingTarget = false
local warnedMissingRoot = false

local function findTutorialBeamTemplate(): Beam?
	for _, folderName in { "Effects", "Effect" } do
		local folder = ReplicatedStorage:FindFirstChild(folderName)
		if folder == nil then
			continue
		end

		local template = folder:FindFirstChild("TutorialBeam")
		if template == nil then
			continue
		end

		if template:IsA("Beam") then
			return template
		end

		local beam = template:FindFirstChildWhichIsA("Beam", true)
		if beam ~= nil then
			return beam
		end
	end

	return nil
end

local function createFallbackBeam(): Beam
	local beam = Instance.new("Beam")
	beam.Name = "TutorialBeam"
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 236, 118), Color3.fromRGB(95, 220, 255))
	beam.LightEmission = 0.8
	beam.LightInfluence = 0
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureLength = 2
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureSpeed = 1.5
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 0.25),
	})
	beam.Width0 = 0.22
	beam.Width1 = 0.36
	beam.FaceCamera = true
	beam.Enabled = true

	return beam
end

local function createBeam(): Beam
	local template = findTutorialBeamTemplate()
	if template ~= nil then
		local beam = template:Clone()
		beam.Enabled = true
		return beam
	end

	return createFallbackBeam()
end

local function getRootPart(character: Model?): BasePart?
	if character == nil then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart ~= nil and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function createBeamAnchor(name: string): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Parent = Workspace

	return part
end

local function getBasePartAdornee(adornee: Instance?): BasePart?
	if adornee ~= nil and adornee:IsA("BasePart") then
		return adornee
	end

	return nil
end

local function getAdorneeBasePart(gui: Instance): BasePart?
	if gui:IsA("SurfaceGui") then
		return getBasePartAdornee(gui.Adornee)
	end

	local surfaceGui = gui:FindFirstAncestorWhichIsA("SurfaceGui")
	if surfaceGui ~= nil then
		return getBasePartAdornee(surfaceGui.Adornee)
	end

	if gui:IsA("BillboardGui") then
		return getBasePartAdornee(gui.Adornee)
	end

	local billboardGui = gui:FindFirstAncestorWhichIsA("BillboardGui")
	if billboardGui ~= nil then
		return getBasePartAdornee(billboardGui.Adornee)
	end

	return nil
end

local function getAdorneeBasePartFromAncestorChain(gui: Instance): BasePart?
	local current: Instance? = gui

	while current ~= nil do
		local targetPart = getAdorneeBasePart(current)
		if targetPart ~= nil then
			return targetPart
		end

		current = current.Parent
	end

	return nil
end

local function getTargetBasePart(instance: Instance?): BasePart?
	if instance == nil then
		return nil
	end

	if instance:IsA("BasePart") then
		return instance
	end

	local ancestorPart = instance:FindFirstAncestorWhichIsA("BasePart")
	if ancestorPart ~= nil then
		return ancestorPart
	end

	return getAdorneeBasePartFromAncestorChain(instance)
end

local function findQuestBoardTarget(): BasePart?
	for _, instance in CollectionService:GetTagged(QUEST_REWARD_ITEMS_TAG) do
		if not instance:IsDescendantOf(Workspace) then
			continue
		end

		local targetPart = getTargetBasePart(instance)
		if targetPart ~= nil then
			return targetPart
		end
	end

	return nil
end

local function isDailyKillMilestoneClaimable(quest: QuestSnapshotEntry): boolean
	local definition = QuestConfig.Definitions[DAILY_KILL_QUEST_ID]
	if definition == nil or definition.KillMilestones == nil then
		return false
	end

	local claimedMilestones = quest.claimedMilestones or {}
	for _, milestone in definition.KillMilestones do
		if quest.progress >= milestone.Kills and claimedMilestones[tostring(milestone.Kills)] ~= true then
			return true
		end
	end

	return false
end

local function hasClaimableQuest(snapshot: QuestSnapshot?): boolean
	if snapshot == nil then
		return false
	end

	for _, quest in snapshot.quests do
		if quest.questId == DAILY_KILL_QUEST_ID then
			if isDailyKillMilestoneClaimable(quest) then
				return true
			end
		elseif quest.completed and quest.claimed ~= true then
			return true
		end
	end

	return false
end

function DailyQuestTutorialBeamController:Init(_context)
	if self._didInit then
		return
	end

	self._didInit = true
end

function DailyQuestTutorialBeamController:Start()
	if self._didStart then
		return
	end

	self._didStart = true

	table.insert(
		connections,
		questUpdatedRemote.OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" or type(payload.snapshot) ~= "table" then
				currentSnapshot = nil
				self:_refreshBeam()
				return
			end

			currentSnapshot = payload.snapshot :: QuestSnapshot
			self:_refreshBeam()
		end)
	)

	table.insert(
		connections,
		localPlayer:GetAttributeChangedSignal("PlayerState"):Connect(function()
			self:_refreshBeam()
		end)
	)

	table.insert(
		connections,
		localPlayer.CharacterAdded:Connect(function()
			self:_stopBeam()
			task.defer(function()
				self:_refreshBeam()
			end)
		end)
	)

	table.insert(
		connections,
		CollectionService:GetInstanceAddedSignal(QUEST_REWARD_ITEMS_TAG):Connect(function(instance)
			if instance:IsDescendantOf(Workspace) then
				self:_refreshBeam()
			end
		end)
	)

	table.insert(
		connections,
		CollectionService:GetInstanceRemovedSignal(QUEST_REWARD_ITEMS_TAG):Connect(function()
			self:_refreshBeam()
		end)
	)

	self:_refreshBeam()
end

function DailyQuestTutorialBeamController:Destroy()
	self:_stopBeam()

	for _, connection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
end

function DailyQuestTutorialBeamController:_shouldShowBeam(): boolean
	return localPlayer:GetAttribute("PlayerState") == MatchConfig.PlayerStates.Lobby
		and hasClaimableQuest(currentSnapshot)
end

function DailyQuestTutorialBeamController:_refreshBeam()
	if not self:_shouldShowBeam() then
		self:_stopBeam()
		return
	end

	local rootPart = getRootPart(localPlayer.Character)
	if rootPart == nil then
		self:_stopBeam()
		if not warnedMissingRoot then
			warnedMissingRoot = true
			warn("[DailyQuestTutorialBeamController] missing local HumanoidRootPart; beam skipped.")
		end
		return
	end

	local targetPart = findQuestBoardTarget()
	if targetPart == nil then
		self:_stopBeam()
		if not warnedMissingTarget then
			warnedMissingTarget = true
			warn("[DailyQuestTutorialBeamController] missing QUEST_REWARD_ITEMS target; beam skipped.")
		end
		return
	end

	warnedMissingRoot = false
	warnedMissingTarget = false
	self:_startBeam(rootPart, targetPart)
end

function DailyQuestTutorialBeamController:_startBeam(rootPart: BasePart, targetPart: BasePart)
	if
		startAttachment ~= nil
		and startAttachment.Parent == startAnchor
		and endAttachment ~= nil
		and endAttachment.Parent == endAnchor
		and activeRootPart == rootPart
		and activeTargetPart == targetPart
		and activeBeam ~= nil
		and activeBeam.Parent ~= nil
		and beamUpdateConnection ~= nil
	then
		activeBeam.Enabled = true
		return
	end

	self:_stopBeam()

	local newStartAnchor = createBeamAnchor("DailyQuestTutorialBeamStartAnchor")
	local newEndAnchor = createBeamAnchor("DailyQuestTutorialBeamEndAnchor")

	local newStartAttachment = Instance.new("Attachment")
	newStartAttachment.Name = START_ATTACHMENT_NAME
	newStartAttachment.Parent = newStartAnchor

	local newEndAttachment = Instance.new("Attachment")
	newEndAttachment.Name = END_ATTACHMENT_NAME
	newEndAttachment.Parent = newEndAnchor

	local newBeam = createBeam()
	newBeam.Name = BEAM_NAME
	newBeam.Attachment0 = newStartAttachment
	newBeam.Attachment1 = newEndAttachment
	newBeam.Parent = newStartAnchor

	startAnchor = newStartAnchor
	endAnchor = newEndAnchor
	startAttachment = newStartAttachment
	endAttachment = newEndAttachment
	activeBeam = newBeam
	activeRootPart = rootPart
	activeTargetPart = targetPart

	local function updateAnchors()
		if rootPart.Parent == nil or targetPart.Parent == nil then
			self:_refreshBeam()
			return
		end

		newStartAnchor.CFrame = CFrame.new(rootPart.Position + Vector3.new(0, 1.5, 0))
		newEndAnchor.CFrame = targetPart.CFrame
	end

	updateAnchors()
	beamUpdateConnection = RunService.Heartbeat:Connect(updateAnchors)
end

function DailyQuestTutorialBeamController:_stopBeam()
	if beamUpdateConnection ~= nil then
		beamUpdateConnection:Disconnect()
	end

	if activeBeam ~= nil then
		activeBeam:Destroy()
	end

	if startAttachment ~= nil then
		startAttachment:Destroy()
	end

	if endAttachment ~= nil then
		endAttachment:Destroy()
	end

	if startAnchor ~= nil then
		startAnchor:Destroy()
	end

	if endAnchor ~= nil then
		endAnchor:Destroy()
	end

	beamUpdateConnection = nil
	activeBeam = nil
	startAttachment = nil
	endAttachment = nil
	startAnchor = nil
	endAnchor = nil
	activeRootPart = nil
	activeTargetPart = nil
end

return DailyQuestTutorialBeamController
