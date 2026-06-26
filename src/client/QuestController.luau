--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = Shared:WaitForChild("Network")

local Remotes = require(Network:WaitForChild("Remotes"))

local questUpdatedRemote = Remotes.GetServerToClient(Network, Remotes.ServerToClient.QuestUpdated)
local requestClaimQuestRewardRemote = Remotes.GetClientToServer(Network, Remotes.ClientToServer.RequestClaimQuestReward)

local QuestController = {
	Name = "QuestController",
}

local DEBUG = false

local QUEST_SCROLLING_FRAME_TAG = "QUEST_SCROLLING_FRAME"
local QUEST_TIMER_TAG = "QUEST_TIMER"

local TEMPLATE_NAME = "QuestTemplate"
local QUEST_CLONE_ATTRIBUTE = "IS_QUEST_CLONE"

type QuestSnapshotEntry = {
	questId: string,
	displayName: string,
	description: string,
	progress: number,
	target: number,
	rewardCoins: number,
	claimed: boolean,
	completed: boolean,
}

type QuestSnapshot = {
	dateKey: string,
	quests: { QuestSnapshotEntry },
	changedAt: number,
}

local questScrollingFrame: ScrollingFrame?
local questTimer: TextLabel?
local questTemplate: Frame?

local currentSnapshot: QuestSnapshot?
local connections: { RBXScriptConnection } = {}

local lastTimerUpdate = 0

local function log(message: string)
	if DEBUG then
		print(`[QuestController] {message}`)
	end
end

local function getTaggedInstance(tag: string): Instance?
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsDescendantOf(Workspace) then
			return instance
		end
	end

	warn(`[QuestController] missing tagged workspace instance: {tag}`)
	return nil
end

local function findTextLabel(parent: Instance, name: string): TextLabel?
	local found = parent:FindFirstChild(name, true)

	if found ~= nil and found:IsA("TextLabel") then
		return found
	end

	return nil
end

local function findFrame(parent: Instance, name: string): Frame?
	local found = parent:FindFirstChild(name, true)

	if found ~= nil and found:IsA("Frame") then
		return found
	end

	return nil
end

local function findGuiButton(parent: Instance, name: string): GuiButton?
	local found = parent:FindFirstChild(name, true)

	if found ~= nil and found:IsA("GuiButton") then
		return found
	end

	return nil
end

local function setClaimButtonState(claimButton: GuiButton, quest: QuestSnapshotEntry)
	local shouldShowClaim = quest.completed and not quest.claimed

	claimButton.Visible = shouldShowClaim or quest.claimed
	claimButton.Active = shouldShowClaim
	claimButton.Interactable = shouldShowClaim
	claimButton.AutoButtonColor = shouldShowClaim

	local title = findTextLabel(claimButton, "Title")

	if title ~= nil then
		if quest.claimed then
			title.Text = "Claimed"
		elseif quest.completed then
			title.Text = "Claim"
		else
			title.Text = "Claim"
		end
	end
end

local function setRewards(rewardsFrame: Frame, quest: QuestSnapshotEntry)
	local coins = rewardsFrame:FindFirstChild("Coins")

	if coins ~= nil and coins:IsA("GuiObject") then
		coins.Visible = quest.rewardCoins > 0

		local count = findTextLabel(coins, "Count") or findTextLabel(coins, "Amount") or findTextLabel(coins, "Title")

		if count ~= nil then
			count.Text = tostring(quest.rewardCoins)
		end
	else
		warn(`[QuestController] missing Rewards.Coins inside {rewardsFrame:GetFullName()}`)
	end

	local claimButton = findGuiButton(rewardsFrame, "Claim")

	if claimButton ~= nil then
		setClaimButtonState(claimButton, quest)

		table.insert(
			connections,
			claimButton.Activated:Connect(function()
				if quest.completed and not quest.claimed then
					requestClaimQuestRewardRemote:FireServer({
						questId = quest.questId,
					})
				end
			end)
		)
	else
		warn(`[QuestController] missing Rewards.Claim button inside {rewardsFrame:GetFullName()}`)
	end
end

local function getQuestTitle(quest: QuestSnapshotEntry): string
	return `{quest.description} ({quest.progress}/{quest.target})`
end

local function clearQuestClones()
	if questScrollingFrame == nil then
		return
	end

	for _, child in questScrollingFrame:GetChildren() do
		if child:GetAttribute(QUEST_CLONE_ATTRIBUTE) == true then
			child:Destroy()
		end
	end
end

local function updateCanvasSize()
	if questScrollingFrame == nil then
		return
	end

	local layout = questScrollingFrame:FindFirstChildWhichIsA("UIListLayout")

	if layout ~= nil then
		questScrollingFrame.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y)
	end
end

local function renderQuest(quest: QuestSnapshotEntry, layoutOrder: number)
	if questScrollingFrame == nil or questTemplate == nil then
		return
	end

	local clone = questTemplate:Clone()
	clone.Name = `Quest_{quest.questId}`
	clone.Visible = true
	clone.LayoutOrder = layoutOrder
	clone:SetAttribute(QUEST_CLONE_ATTRIBUTE, true)
	clone:SetAttribute("QUEST_ID", quest.questId)
	clone.Parent = questScrollingFrame

	local info = clone:FindFirstChild("Info")
	local rewards = clone:FindFirstChild("Rewards")

	if info ~= nil and info:IsA("Frame") then
		local title = findTextLabel(info, "Title")
		local bar = findFrame(info, "Bar")

		if title ~= nil then
			title.Text = getQuestTitle(quest)
		end

		if bar ~= nil then
			local percentage = math.clamp(quest.progress / math.max(quest.target, 1), 0, 1)

			local percentageLabel = findTextLabel(bar, "Percentage")
			local fill = findFrame(bar, "Fill")

			if percentageLabel ~= nil then
				percentageLabel.Text = `{math.floor(percentage * 100)}%`
			end

			if fill ~= nil then
				fill.Size = UDim2.fromScale(percentage, fill.Size.Y.Scale)
			end
		end
	end

	if rewards ~= nil and rewards:IsA("Frame") then
		setRewards(rewards, quest)
	else
		warn(`[QuestController] missing Rewards frame inside {clone:GetFullName()}`)
	end
end

local function renderQuests()
	clearQuestClones()

	if currentSnapshot == nil then
		return
	end

	for index, quest in currentSnapshot.quests do
		renderQuest(quest, index)
	end

	task.defer(updateCanvasSize)
end

local function getSecondsUntilUtcReset(dateKey: string): number
	local year, month, day = string.match(dateKey, "^(%d+)%-(%d+)%-(%d+)$")

	if year == nil or month == nil or day == nil then
		return 0
	end

	local resetTime = DateTime.fromUniversalTime(
		tonumber(year) :: number,
		tonumber(month) :: number,
		(tonumber(day) :: number) + 1,
		0,
		0,
		0
	)

	return math.max(0, resetTime.UnixTimestamp - DateTime.now().UnixTimestamp)
end

local function formatResetTime(seconds: number): string
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)

	return string.format("Resets in: %02dh:%02dm", hours, minutes)
end

local function updateTimer()
	if questTimer == nil or currentSnapshot == nil then
		return
	end

	local seconds = getSecondsUntilUtcReset(currentSnapshot.dateKey)
	questTimer.Text = formatResetTime(seconds)
end

function QuestController:GetReferences()
	questScrollingFrame = getTaggedInstance(QUEST_SCROLLING_FRAME_TAG) :: ScrollingFrame?
	questTimer = getTaggedInstance(QUEST_TIMER_TAG) :: TextLabel?

	if questScrollingFrame ~= nil then
		if not questScrollingFrame:IsA("ScrollingFrame") then
			warn(`[QuestController] QUEST_SCROLLING_FRAME is not ScrollingFrame, got {questScrollingFrame.ClassName}`)
			questScrollingFrame = nil
			return
		end

		local foundTemplate = questScrollingFrame:FindFirstChild(TEMPLATE_NAME)

		if foundTemplate ~= nil and foundTemplate:IsA("Frame") then
			questTemplate = foundTemplate
			questTemplate.Visible = false
		else
			warn(`[QuestController] missing {TEMPLATE_NAME} inside QUEST_SCROLLING_FRAME`)
		end
	end

	if questTimer ~= nil and not questTimer:IsA("TextLabel") then
		warn(`[QuestController] QUEST_TIMER is not TextLabel, got {questTimer.ClassName}`)
		questTimer = nil
	end
end

function QuestController:Init(context)
	if self._didInit then
		return
	end

	self._didInit = true
	self._context = context
	self._connections = connections
end

function QuestController:Start()
	if self._didStart then
		return
	end

	self._didStart = true
	self:GetReferences()

	table.insert(
		connections,
		questUpdatedRemote.OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" then
				return
			end

			local snapshot = payload.snapshot

			if type(snapshot) ~= "table" then
				return
			end

			currentSnapshot = snapshot :: QuestSnapshot

			renderQuests()
			updateTimer()
		end)
	)

	table.insert(
		connections,
		RunService.Heartbeat:Connect(function()
			local now = os.clock()

			if now - lastTimerUpdate < 1 then
				return
			end

			lastTimerUpdate = now
			updateTimer()
		end)
	)
end

return QuestController