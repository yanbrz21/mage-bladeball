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

local DEBUG = true

local QUEST_SCROLLING_FRAME_TAG = "QUEST_SCROLLING_FRAME"
local QUEST_TIMER_TAG = "QUEST_TIMER"
local QUEST_KILL_BAR_FILL_TAG = "QUEST_KILL_BAR_FILL"
local QUEST_REWARD_ITEMS_TAG = "QUEST_REWARD_ITEMS"

local TEMPLATE_NAME = "QuestTemplate"
local REWARD_ITEM_TEMPLATE_NAME = "Template"

local QUEST_CLONE_ATTRIBUTE = "IS_QUEST_CLONE"

local DAILY_KILL_TARGET = 15

local KILL_REWARD_MILESTONES = table.freeze({
	{ kills = 5, rewardCoins = 100, positionScale = 0.3 },
	{ kills = 10, rewardCoins = 100, positionScale = 0.6 },
	{ kills = 15, rewardCoins = 100, positionScale = 0.9 },
})

type KillRewardMilestone = {
	kills: number,
	rewardCoins: number,
	positionScale: number,
}

type ClaimedMilestones = {
	[string]: boolean,
}

type QuestSnapshotEntry = {
	questId: string,
	displayName: string,
	description: string,
	eventName: string?,
	progress: number,
	target: number,
	rewardCoins: number,
	claimed: boolean,
	completed: boolean,
	claimedMilestones: ClaimedMilestones?,
}

type QuestSnapshot = {
	dateKey: string,
	quests: { QuestSnapshotEntry },
	changedAt: number,
}

local questContainer: GuiObject?
local questTimer: TextLabel?
local questTemplate: Frame?

local questKillBarFill: Frame?
local questRewardItems: Frame?

local currentSnapshot: QuestSnapshot?
local connections: { RBXScriptConnection } = {}

local lastTimerUpdate = 0

local function log(message: string)
	if DEBUG then
		print(`[QuestController] {message}`)
	end
end

local function getTaggedInstance(tag: string): Instance?
	local tagged = CollectionService:GetTagged(tag)

	log(`searching tag {tag}, found {#tagged}`)

	for _, instance in tagged do
		log(`tag {tag} candidate: {instance:GetFullName()} class={instance.ClassName}`)

		if instance:IsDescendantOf(Workspace) then
			log(`tag {tag} selected: {instance:GetFullName()}`)
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

local function getQuestPercentage(quest: QuestSnapshotEntry): number
	return math.clamp(quest.progress / math.max(quest.target, 1), 0, 1)
end

local function getDailyKillPercentage(quest: QuestSnapshotEntry): number
	return math.clamp(quest.progress / DAILY_KILL_TARGET, 0, 1)
end

local function isKillQuest(quest: QuestSnapshotEntry): boolean
	local questId = string.lower(quest.questId)
	local displayName = string.lower(quest.displayName)
	local description = string.lower(quest.description)
	local eventName = string.lower(quest.eventName or "")

	return string.find(questId, "daily_kills") ~= nil
		or string.find(questId, "kill") ~= nil
		or string.find(displayName, "kill") ~= nil
		or string.find(description, "kill") ~= nil
		or string.find(eventName, "kill") ~= nil
end

local function setClaimButtonTitle(button: GuiButton, text: string)
	local title = button:FindFirstChild("Title")

	if title ~= nil and title:IsA("TextLabel") then
		title.Text = text
		log(`button title set: {button:GetFullName()} -> {text}`)
	else
		warn(`[QuestController] missing TextLabel Title inside button {button:GetFullName()}`)
	end
end

local function setButtonInteractable(button: GuiButton, canClick: boolean)
	button.Visible = true
	button.Active = canClick
	button.Interactable = canClick
	button.AutoButtonColor = canClick
end

local function setClaimButtonVisual(claimButton: GuiButton, reached: boolean, claimed: boolean)
	local canClaim = reached and not claimed

	setButtonInteractable(claimButton, canClaim)

	if claimed then
		setClaimButtonTitle(claimButton, "Claimed")
	elseif reached then
		setClaimButtonTitle(claimButton, "Claim")
	else
		setClaimButtonTitle(claimButton, "Locked")
	end
end

local function fireClaimQuest(quest: QuestSnapshotEntry, milestoneKills: number?)
	log(`claim requested quest={quest.questId} milestone={milestoneKills or -1}`)

	requestClaimQuestRewardRemote:FireServer({
		questId = quest.questId,
		milestoneKills = milestoneKills,
	})
end

local function connectRewardButtons(
	clone: Frame,
	quest: QuestSnapshotEntry,
	milestone: KillRewardMilestone,
	reached: boolean,
	claimed: boolean
)
	local canClaim = reached and not claimed
	local claimButton = findGuiButton(clone, "Claim")
	local itemButton = findGuiButton(clone, "Item")

	local function tryClaim(source: string)
		log(`{source} clicked quest={quest.questId} milestone={milestone.kills} reached={reached} claimed={claimed}`)

		if canClaim then
			fireClaimQuest(quest, milestone.kills)
		end
	end

	if claimButton ~= nil then
		setClaimButtonVisual(claimButton, reached, claimed)

		table.insert(
			connections,
			claimButton.Activated:Connect(function()
				tryClaim("Claim")
			end)
		)
	else
		warn(`[QuestController] missing Claim button inside {clone:GetFullName()}`)
	end

	if itemButton ~= nil then
		setButtonInteractable(itemButton, canClaim)

		table.insert(
			connections,
			itemButton.Activated:Connect(function()
				tryClaim("Item")
			end)
		)
	else
		warn(`[QuestController] missing Item button inside {clone:GetFullName()}`)
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
	end

	local claimButton = findGuiButton(rewardsFrame, "Claim")

	if claimButton ~= nil then
		setClaimButtonVisual(claimButton, quest.completed, quest.claimed)

		table.insert(
			connections,
			claimButton.Activated:Connect(function()
				if quest.completed and not quest.claimed then
					fireClaimQuest(quest, nil)
				end
			end)
		)
	end
end

local function getQuestTitle(quest: QuestSnapshotEntry): string
	return `{quest.description} ({quest.progress}/{quest.target})`
end

local function clearQuestClones()
	if questContainer == nil then
		return
	end

	for _, child in questContainer:GetChildren() do
		if child:GetAttribute(QUEST_CLONE_ATTRIBUTE) == true then
			child:Destroy()
		end
	end
end

local function clearRewardItemClones()
	if questRewardItems == nil then
		return
	end

	for _, child in questRewardItems:GetChildren() do
		if child:GetAttribute(QUEST_CLONE_ATTRIBUTE) == true then
			child:Destroy()
		end
	end
end

local function updateCanvasSize()
	if questContainer == nil then
		return
	end

	if not questContainer:IsA("ScrollingFrame") then
		return
	end

	local layout = questContainer:FindFirstChildWhichIsA("UIListLayout")

	if layout ~= nil then
		questContainer.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y)
	end
end

local function setQuestInfo(clone: Frame, quest: QuestSnapshotEntry)
	local info = clone:FindFirstChild("Info")

	if info == nil or not info:IsA("Frame") then
		warn(`[QuestController] missing Info frame inside {clone:GetFullName()}`)
		return
	end

	local title = findTextLabel(info, "Title")
	local bar = findFrame(info, "Bar")

	if title ~= nil then
		title.Text = getQuestTitle(quest)
	end

	if bar ~= nil then
		local percentage = getQuestPercentage(quest)
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

local function renderQuest(quest: QuestSnapshotEntry, layoutOrder: number)
	if questContainer == nil or questTemplate == nil then
		return
	end

	local clone = questTemplate:Clone()
	clone.Name = `Quest_{quest.questId}`
	clone.Visible = true
	clone.LayoutOrder = layoutOrder
	clone:SetAttribute(QUEST_CLONE_ATTRIBUTE, true)
	clone:SetAttribute("QUEST_ID", quest.questId)
	clone.Parent = questContainer

	setQuestInfo(clone, quest)

	local rewards = clone:FindFirstChild("Rewards")

	if rewards ~= nil and rewards:IsA("Frame") then
		setRewards(rewards, quest)
	end
end

local function renderRewardMilestone(quest: QuestSnapshotEntry, milestone: KillRewardMilestone)
	if questRewardItems == nil then
		warn("[QuestController] questRewardItems nil")
		return
	end

	local template = questRewardItems:FindFirstChild(REWARD_ITEM_TEMPLATE_NAME)

	if template == nil or not template:IsA("Frame") then
		warn(`[QuestController] missing Template inside {questRewardItems:GetFullName()}`)
		return
	end

	local reached = quest.progress >= milestone.kills
	local claimedMilestones = quest.claimedMilestones or {}
	local claimed = claimedMilestones[tostring(milestone.kills)] == true

	local clone = template:Clone()
	clone.Name = `Reward_{quest.questId}_{milestone.kills}Kills`
	clone.Visible = true
	clone:SetAttribute(QUEST_CLONE_ATTRIBUTE, true)
	clone:SetAttribute("QUEST_ID", quest.questId)
	clone:SetAttribute("REWARD_KILLS", milestone.kills)
	clone.Position = UDim2.fromScale(math.clamp(milestone.positionScale, 0, 0.9), clone.Position.Y.Scale)
	clone.Parent = questRewardItems

	log(`created reward clone {clone:GetFullName()} reached={reached} claimed={claimed}`)

	connectRewardButtons(clone, quest, milestone, reached, claimed)

	local coins = clone:FindFirstChild("Coins", true)

	if coins ~= nil and coins:IsA("GuiObject") then
		coins.Visible = milestone.rewardCoins > 0

		local count = findTextLabel(coins, "Count") or findTextLabel(coins, "Amount") or findTextLabel(coins, "Title")

		if count ~= nil then
			count.Text = tostring(milestone.rewardCoins)
		end
	end
end

local function renderQuests()
	clearQuestClones()
	clearRewardItemClones()

	if currentSnapshot == nil then
		return
	end

	local killQuest: QuestSnapshotEntry? = nil

	for index, quest in currentSnapshot.quests do
		renderQuest(quest, index)

		if killQuest == nil and isKillQuest(quest) then
			killQuest = quest
		end
	end

	if killQuest ~= nil then
		local quest = killQuest :: QuestSnapshotEntry
		local percentage = getDailyKillPercentage(quest)

		if questKillBarFill ~= nil then
			questKillBarFill.Size = UDim2.fromScale(percentage, questKillBarFill.Size.Y.Scale)
			log(`QUEST_KILL_BAR_FILL updated by daily kills {quest.progress}/{DAILY_KILL_TARGET} = {percentage}`)
		end

		for _, milestone in KILL_REWARD_MILESTONES do
			renderRewardMilestone(quest, milestone)
		end
	elseif questKillBarFill ~= nil then
		questKillBarFill.Size = UDim2.fromScale(0, questKillBarFill.Size.Y.Scale)
	end

	task.defer(updateCanvasSize)
end

local function getSecondsUntilUtcReset(dateKey: string): number
	local yearText, monthText, dayText = string.match(dateKey, "^(%d+)%-(%d+)%-(%d+)$")

	local year = tonumber(yearText)
	local month = tonumber(monthText)
	local day = tonumber(dayText)

	if year == nil or month == nil or day == nil then
		return 0
	end

	local resetTimestamp = os.time({
		year = year,
		month = month,
		day = day + 1,
		hour = 0,
		min = 0,
		sec = 0,
	})

	if resetTimestamp == nil then
		return 0
	end

	return math.max(0, resetTimestamp - os.time())
end

local function formatResetTime(seconds: number): string
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)

	return string.format("%02dh:%02dm", hours, minutes)
end

local function updateTimer()
	if questTimer == nil or currentSnapshot == nil then
		return
	end

	local seconds = getSecondsUntilUtcReset(currentSnapshot.dateKey)
	questTimer.Text = formatResetTime(seconds)
end

function QuestController:GetReferences()
	log("GetReferences called")

	questContainer = getTaggedInstance(QUEST_SCROLLING_FRAME_TAG) :: GuiObject?
	questTimer = getTaggedInstance(QUEST_TIMER_TAG) :: TextLabel?
	questKillBarFill = getTaggedInstance(QUEST_KILL_BAR_FILL_TAG) :: Frame?
	questRewardItems = getTaggedInstance(QUEST_REWARD_ITEMS_TAG) :: Frame?

	if questContainer ~= nil then
		local foundTemplate = questContainer:FindFirstChild(TEMPLATE_NAME)

		if foundTemplate ~= nil and foundTemplate:IsA("Frame") then
			questTemplate = foundTemplate
			questTemplate.Visible = false
		else
			warn(`[QuestController] missing {TEMPLATE_NAME} inside QUEST_SCROLLING_FRAME`)
		end
	end

	if questRewardItems ~= nil then
		local rewardTemplate = questRewardItems:FindFirstChild(REWARD_ITEM_TEMPLATE_NAME)

		if rewardTemplate ~= nil and rewardTemplate:IsA("Frame") then
			rewardTemplate.Visible = false
		else
			warn(`[QuestController] missing Template inside {questRewardItems:GetFullName()}`)
		end
	end

	if questTimer ~= nil and not questTimer:IsA("TextLabel") then
		questTimer = nil
	end

	if questKillBarFill ~= nil and not questKillBarFill:IsA("Frame") then
		questKillBarFill = nil
	end

	if questRewardItems ~= nil and not questRewardItems:IsA("Frame") then
		questRewardItems = nil
	end
end

function QuestController:Init(context)
	if self._didInit then
		return
	end

	self._didInit = true
	self._context = context
	self._connections = connections

	log("Init")
end

function QuestController:Start()
	if self._didStart then
		return
	end

	self._didStart = true

	log("Start")

	self:GetReferences()

	table.insert(
		connections,
		questUpdatedRemote.OnClientEvent:Connect(function(payload)
			log("QuestUpdated received")

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