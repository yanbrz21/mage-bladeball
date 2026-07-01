--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = Shared:WaitForChild("Network")

local QuestConfig = require(Shared.Config.QuestConfig)
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
local SEGMENT_TEMPLATE_NAME = "SegmentTemplate"

local QUEST_CLONE_ATTRIBUTE = "IS_QUEST_CLONE"
local QUEST_SEGMENT_CLONE_ATTRIBUTE = "IS_QUEST_SEGMENT_CLONE"

local DAILY_KILL_QUEST_ID = "daily_kills"

type ClaimedMilestones = {
	[string]: boolean,
}

type QuestDefinition = QuestConfig.QuestDefinition
type QuestKillMilestone = QuestConfig.QuestKillMilestone

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

local questKillBar: Frame?
local questKillBarFill: Frame?
local questKillBarSegmentTemplate: Frame?
local questRewardItems: Frame?

local currentSnapshot: QuestSnapshot?
local connections: { RBXScriptConnection } = {}
local renderConnections: { RBXScriptConnection } = {}

local lastTimerUpdate = 0
local isResolvingReferences = false
local referencesReady = false

local function log(message: string)
	if DEBUG then
		print(`[QuestController] {message}`)
	end
end

local function getTaggedInstance(tag: string, timeout: number?): Instance?
	local startedAt = os.clock()
	local maxWait = timeout or 10

	while os.clock() - startedAt < maxWait do
		local tagged = CollectionService:GetTagged(tag)

		log(`searching tag {tag}, found {#tagged}`)

		for _, instance in tagged do
			log(`tag {tag} candidate: {instance:GetFullName()} class={instance.ClassName}`)

			if instance:IsDescendantOf(Workspace) then
				log(`tag {tag} selected: {instance:GetFullName()}`)
				return instance
			end
		end

		task.wait(0.1)
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

local function getDailyKillDefinition(quest: QuestSnapshotEntry): QuestDefinition?
	if quest.questId ~= DAILY_KILL_QUEST_ID then
		return nil
	end

	local definition = QuestConfig.Definitions[quest.questId]
	if definition == nil or definition.KillMilestones == nil then
		return nil
	end

	return definition
end

local function getKillMilestones(quest: QuestSnapshotEntry): { QuestKillMilestone }?
	local definition = getDailyKillDefinition(quest)
	if definition == nil then
		return nil
	end

	return definition.KillMilestones
end

local function getMilestoneTarget(milestones: { QuestKillMilestone }): number
	local finalMilestone = milestones[#milestones]
	if finalMilestone == nil then
		return 1
	end

	return math.max(1, finalMilestone.Kills)
end

local function getDailyKillPercentage(quest: QuestSnapshotEntry, milestones: { QuestKillMilestone }): number
	return math.clamp(quest.progress / getMilestoneTarget(milestones), 0, 1)
end

local function getMilestonePositionScale(milestone: QuestKillMilestone, milestones: { QuestKillMilestone }): number
	return math.clamp(milestone.Kills / getMilestoneTarget(milestones), 0, 1)
end

local function clampByCloneWidth(scale: number, clone: GuiObject): number
	local halfWidthScale = math.max(0, clone.Size.X.Scale) * 0.5
	if halfWidthScale >= 0.5 then
		return 0.5
	end

	return math.clamp(scale, halfWidthScale, 1 - halfWidthScale)
end

local function clearRenderConnections()
	for _, connection in renderConnections do
		connection:Disconnect()
	end

	table.clear(renderConnections)
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
	milestone: QuestKillMilestone,
	reached: boolean,
	claimed: boolean
)
	local canClaim = reached and not claimed
	local claimButton = findGuiButton(clone, "Claim")
	local itemButton = findGuiButton(clone, "Item")

	local function tryClaim(source: string)
		log(`{source} clicked quest={quest.questId} milestone={milestone.Kills} reached={reached} claimed={claimed}`)

		if canClaim then
			fireClaimQuest(quest, milestone.Kills)
		end
	end

	if claimButton ~= nil then
		setClaimButtonVisual(claimButton, reached, claimed)

		table.insert(
			renderConnections,
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
			renderConnections,
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
			renderConnections,
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
	clearRenderConnections()

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

local function clearKillBarSegmentClones()
	if questKillBar == nil then
		return
	end

	for _, child in questKillBar:GetChildren() do
		if child:GetAttribute(QUEST_SEGMENT_CLONE_ATTRIBUTE) == true then
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

local function renderRewardMilestone(
	quest: QuestSnapshotEntry,
	milestone: QuestKillMilestone,
	milestones: { QuestKillMilestone }
)
	if questRewardItems == nil then
		warn("[QuestController] questRewardItems nil")
		return
	end

	local template = questRewardItems:FindFirstChild(REWARD_ITEM_TEMPLATE_NAME)

	if template == nil or not template:IsA("Frame") then
		warn(`[QuestController] missing Template inside {questRewardItems:GetFullName()}`)
		return
	end

	local reached = quest.progress >= milestone.Kills
	local claimedMilestones = quest.claimedMilestones or {}
	local claimed = claimedMilestones[tostring(milestone.Kills)] == true

	local clone = template:Clone()
	clone.Name = `Reward_{quest.questId}_{milestone.Kills}Kills`
	clone.Visible = true
	clone:SetAttribute(QUEST_CLONE_ATTRIBUTE, true)
	clone:SetAttribute("QUEST_ID", quest.questId)
	clone:SetAttribute("REWARD_KILLS", milestone.Kills)
	clone.AnchorPoint = Vector2.new(0.5, clone.AnchorPoint.Y)
	clone.Position = UDim2.fromScale(
		clampByCloneWidth(getMilestonePositionScale(milestone, milestones), clone),
		clone.Position.Y.Scale
	)
	clone.Parent = questRewardItems

	log(`created reward clone {clone:GetFullName()} reached={reached} claimed={claimed}`)

	connectRewardButtons(clone, quest, milestone, reached, claimed)

	local coins = clone:FindFirstChild("Coins", true)

	if coins ~= nil and coins:IsA("GuiObject") then
		coins.Visible = milestone.RewardCoins > 0

		local count = findTextLabel(coins, "Count") or findTextLabel(coins, "Amount") or findTextLabel(coins, "Title")

		if count ~= nil then
			count.Text = tostring(milestone.RewardCoins)
		end
	end
end

local function renderKillBarSegment(
	milestone: QuestKillMilestone,
	milestones: { QuestKillMilestone },
	previousPositionScale: number
)
	if questKillBar == nil or questKillBarSegmentTemplate == nil then
		return
	end

	local positionScale = getMilestonePositionScale(milestone, milestones)
	local segmentWidthScale = math.max(0.001, positionScale - previousPositionScale)
	local clone = questKillBarSegmentTemplate:Clone()
	clone.Name = `Segment_{milestone.Kills}`
	clone.Visible = true
	clone:SetAttribute(QUEST_SEGMENT_CLONE_ATTRIBUTE, true)
	clone.AnchorPoint = Vector2.new(1, clone.AnchorPoint.Y)
	clone.Position = UDim2.fromScale(positionScale, clone.Position.Y.Scale)
	clone.Size = UDim2.fromScale(segmentWidthScale, clone.Size.Y.Scale)
	clone.Parent = questKillBar

	local title = findTextLabel(clone, "Title")
	if title ~= nil then
		title.Text = tostring(milestone.Kills)
	end
end

local function renderQuests()
	clearQuestClones()
	clearRewardItemClones()
	clearKillBarSegmentClones()

	if currentSnapshot == nil then
		return
	end

	local killQuest: QuestSnapshotEntry? = nil

	for index, quest in currentSnapshot.quests do
		renderQuest(quest, index)

		if killQuest == nil and getDailyKillDefinition(quest) ~= nil then
			killQuest = quest
		end
	end

	if killQuest ~= nil then
		local quest = killQuest :: QuestSnapshotEntry
		local milestones = getKillMilestones(quest)
		if milestones == nil then
			return
		end

		local percentage = getDailyKillPercentage(quest, milestones)

		if questKillBarFill ~= nil then
			questKillBarFill.Size = UDim2.fromScale(percentage, questKillBarFill.Size.Y.Scale)
			log(
				`QUEST_KILL_BAR_FILL updated by daily kills {quest.progress}/{getMilestoneTarget(milestones)} = {percentage}`
			)
		end

		local previousPositionScale = 0
		for _, milestone in milestones do
			renderKillBarSegment(milestone, milestones, previousPositionScale)
			renderRewardMilestone(quest, milestone, milestones)
			previousPositionScale = getMilestonePositionScale(milestone, milestones)
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
	if isResolvingReferences then
		return
	end

	isResolvingReferences = true
	referencesReady = false

	log("GetReferences called")

	questContainer = nil
	questTimer = nil
	questTemplate = nil
	questKillBar = nil
	questKillBarFill = nil
	questKillBarSegmentTemplate = nil
	questRewardItems = nil

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

	if questKillBarFill ~= nil then
		local filling = questKillBarFill.Parent
		local bar = if filling ~= nil then filling.Parent else nil

		if bar ~= nil and bar:IsA("Frame") then
			questKillBar = bar
			local segmentTemplate = bar:FindFirstChild(SEGMENT_TEMPLATE_NAME)

			if segmentTemplate ~= nil and segmentTemplate:IsA("Frame") then
				questKillBarSegmentTemplate = segmentTemplate
				questKillBarSegmentTemplate.Visible = false
			else
				warn(`[QuestController] missing {SEGMENT_TEMPLATE_NAME} inside {bar:GetFullName()}`)
			end

			for _, child in bar:GetChildren() do
				if string.match(child.Name, "^Bar%d+$") and child:IsA("GuiObject") then
					child.Visible = false
				end
			end
		end
	end

	if questRewardItems ~= nil and not questRewardItems:IsA("Frame") then
		questRewardItems = nil
	end

	referencesReady = questContainer ~= nil
		and questTemplate ~= nil
		and questTimer ~= nil
		and questKillBarFill ~= nil
		and questRewardItems ~= nil
	isResolvingReferences = false

	if referencesReady and currentSnapshot ~= nil then
		renderQuests()
		updateTimer()
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

			if not referencesReady then
				task.spawn(function()
					self:GetReferences()
				end)
				return
			end

			renderQuests()
			updateTimer()
		end)
	)

	for _, tag in { QUEST_SCROLLING_FRAME_TAG, QUEST_TIMER_TAG, QUEST_KILL_BAR_FILL_TAG, QUEST_REWARD_ITEMS_TAG } do
		table.insert(
			connections,
			CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
				task.defer(function()
					if not instance:IsDescendantOf(Workspace) then
						return
					end

					self:GetReferences()
				end)
			end)
		)
	end

	task.spawn(function()
		self:GetReferences()
	end)

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
