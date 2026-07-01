--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Parabellum = ReplicatedStorage:WaitForChild("Parabellum")

local DrawCatalogUtils = require(Parabellum:WaitForChild("DrawCatalogUtils"))
local DrawRollItemView = require(Parabellum:WaitForChild("DrawRollItemView"))
local EventBus = require(Packages.CommonKit.EventBus)
local InventoryItemVisuals = require(Parabellum:WaitForChild("InventoryItemVisuals"))

local DrawRollSequence = {}
DrawRollSequence.__index = DrawRollSequence

local ROLL_LEAD_CARD_COUNT = 48
local ROLL_TRAIL_CARD_COUNT = 7
local ROLL_DURATION_SECONDS = 3.25
local ROLL_RESULT_WAIT_SECONDS = 1.15
local ROLL_TICK_MIN_DISTANCE_PIXELS = 24
local ROLL_TICK_MIN_INTERVAL_SECONDS = 0.035
local LOCAL_DRAW_ROLL_TICK_EVENT = "Client.LocalDrawRollTick"
local LOCAL_DRAW_ROLL_STOPPED_EVENT = "Client.LocalDrawRollStopped"
local LOCAL_DRAW_RESULT_REVEALED_EVENT = "Client.LocalDrawResultRevealed"

type SkinDrawRewardPayload = DrawCatalogUtils.SkinDrawRewardPayload
type SkinDrawResultPayload = DrawCatalogUtils.SkinDrawResultPayload
type RollVisualItem = DrawCatalogUtils.RollVisualItem

export type Refs = {
	chooseDrawFrame: Frame?,
	rngFrame: Frame?,
	rollScrollingFrame: ScrollingFrame?,
	rollExplanationText: TextLabel?,
	skipDrawButton: TextButton?,
}

export type Callbacks = {
	getDrawConfig: (drawId: string) -> any?,
	refreshIdleUi: () -> (),
}

export type DrawRollSequence = typeof(setmetatable(
	{} :: {
		_refs: Refs,
		_callbacks: Callbacks,
		_isDrawing: boolean,
		_isRolling: boolean,
		_isWaitingForDrawResult: boolean,
		_isRollFinished: boolean,
		_rollToken: number,
		_rollTween: Tween?,
		_latestDrawResult: SkinDrawResultPayload?,
	},
	DrawRollSequence
))

local function setGuiVisible(instance: Instance?, visible: boolean)
	if instance == nil then
		return
	end

	if instance:IsA("ScreenGui") then
		instance.Enabled = visible
	elseif instance:IsA("GuiObject") then
		instance.Visible = visible
	end
end

function DrawRollSequence.new(callbacks: Callbacks): DrawRollSequence
	return setmetatable({
		_refs = {
			chooseDrawFrame = nil,
			rngFrame = nil,
			rollScrollingFrame = nil,
			rollExplanationText = nil,
			skipDrawButton = nil,
		},
		_callbacks = callbacks,
		_isDrawing = false,
		_isRolling = false,
		_isWaitingForDrawResult = false,
		_isRollFinished = false,
		_rollToken = 0,
		_rollTween = nil,
		_latestDrawResult = nil,
	}, DrawRollSequence) :: any
end

function DrawRollSequence:SetRefs(refs: Refs)
	self._refs = refs
end

function DrawRollSequence:IsDrawing(): boolean
	return self._isDrawing
end

function DrawRollSequence:IsRolling(): boolean
	return self._isRolling
end

function DrawRollSequence:IsWaitingForDrawResult(): boolean
	return self._isWaitingForDrawResult
end

function DrawRollSequence:IsRollFinished(): boolean
	return self._isRollFinished
end

function DrawRollSequence:IsBusy(): boolean
	return self._isDrawing or self._isRolling or self._isWaitingForDrawResult
end

function DrawRollSequence:_setSkipButtonTitle(text: string)
	local skipDrawButton = self._refs.skipDrawButton
	if skipDrawButton == nil then
		return
	end

	local title = skipDrawButton:FindFirstChild("Title", true)

	if title ~= nil and title:IsA("TextLabel") then
		title.Text = text
		return
	end

	skipDrawButton.Text = text
end

function DrawRollSequence:_setExplanation(text: string)
	local rollExplanationText = self._refs.rollExplanationText
	if rollExplanationText ~= nil then
		rollExplanationText.Text = text
	end
end

function DrawRollSequence:_clearClones()
	DrawRollItemView.ClearClones(self._refs.rollScrollingFrame)
end

function DrawRollSequence:_stopTween()
	if self._rollTween ~= nil then
		self._rollTween:Cancel()
		self._rollTween = nil
	end
end

function DrawRollSequence:BeginWaiting(showRollUi: boolean)
	self._isDrawing = true
	self._isWaitingForDrawResult = true
	self._isRollFinished = false

	if showRollUi then
		setGuiVisible(self._refs.chooseDrawFrame, false)
		setGuiVisible(self._refs.rngFrame, true)
		self:_setSkipButtonTitle("SKIP")
		self:_setExplanation("Rolling...")
		self:_clearClones()
	end
end

function DrawRollSequence:ResetToChoose(refresh: boolean?)
	self._isRolling = false
	self._isDrawing = false
	self._isWaitingForDrawResult = false
	self._isRollFinished = false
	self._latestDrawResult = nil
	self._rollToken += 1

	self:_stopTween()
	self:_clearClones()
	setGuiVisible(self._refs.rngFrame, false)
	setGuiVisible(self._refs.chooseDrawFrame, true)
	self:_setSkipButtonTitle("SKIP")
	self:_setExplanation("")

	if refresh == true then
		self._callbacks.refreshIdleUi()
	end
end

function DrawRollSequence:ResetAfterFailure()
	self._isDrawing = false
	self._isRolling = false
	self._isWaitingForDrawResult = false

	setGuiVisible(self._refs.chooseDrawFrame, true)
	setGuiVisible(self._refs.rngFrame, false)
end

function DrawRollSequence:ResetAfterEmptyResult()
	self._isDrawing = false
	self._isRolling = false
	self._isWaitingForDrawResult = false
end

function DrawRollSequence:_fireRollTick()
	EventBus.Fire(LOCAL_DRAW_ROLL_TICK_EVENT)
end

function DrawRollSequence:_fireRollStopped()
	EventBus.Fire(LOCAL_DRAW_ROLL_STOPPED_EVENT)
end

function DrawRollSequence:_fireResultRevealed(result: SkinDrawResultPayload?)
	EventBus.Fire(LOCAL_DRAW_RESULT_REVEALED_EVENT, DrawCatalogUtils.HasRareDrawReward(result))
end

function DrawRollSequence:_finish()
	self._isRolling = false
	self._isDrawing = false
	self._isWaitingForDrawResult = false
	self._isRollFinished = true

	self:_stopTween()
	self:_setSkipButtonTitle("CLAIM")
	self:_fireResultRevealed(self._latestDrawResult)
end

function DrawRollSequence:Claim()
	self:ResetToChoose(true)
end

function DrawRollSequence:_getVisualItemFromReward(reward: SkinDrawRewardPayload): RollVisualItem
	return DrawCatalogUtils.GetRollVisualItemFromReward(InventoryItemVisuals, reward)
end

function DrawRollSequence:Skip()
	local result = self._latestDrawResult

	if result == nil then
		self:Claim()
		return
	end

	self._rollToken += 1
	self:_stopTween()
	self:_clearClones()

	local lastReward = result.rewards[#result.rewards]
	if lastReward ~= nil then
		local visualItem = self:_getVisualItemFromReward(lastReward)
		DrawRollItemView.CreateClone(self._refs.rollScrollingFrame, visualItem, 1)
		self:_setExplanation(lastReward.displayName)
	end

	self:_fireRollStopped()
	self:_finish()
end

function DrawRollSequence:HandleSkipOrClaim()
	if self._isRolling or self._isWaitingForDrawResult then
		self:Skip()
		return
	end

	if self._isRollFinished then
		self:Claim()
	end
end

function DrawRollSequence:_updateCanvasSize()
	DrawRollItemView.UpdateCanvasSize(self._refs.rollScrollingFrame)
end

function DrawRollSequence:_getTargetCanvasPosition(targetClone: GuiObject): Vector2
	return DrawRollItemView.GetTargetCanvasPosition(self._refs.rollScrollingFrame, targetClone)
end

function DrawRollSequence:_getTickDistancePixels(targetClone: GuiObject): number
	return DrawRollItemView.GetTickDistancePixels(
		self._refs.rollScrollingFrame,
		targetClone,
		ROLL_TICK_MIN_DISTANCE_PIXELS
	)
end

function DrawRollSequence:_connectTickPlayback(
	token: number,
	tween: Tween,
	startCanvasX: number,
	tickDistancePixels: number
): RBXScriptConnection
	local lastCanvasX = startCanvasX
	local distanceSinceTick = tickDistancePixels
	local lastTickAt = 0

	return RunService.RenderStepped:Connect(function()
		local rollScrollingFrame = self._refs.rollScrollingFrame
		if token ~= self._rollToken or rollScrollingFrame == nil or self._rollTween ~= tween then
			return
		end

		local currentCanvasX = rollScrollingFrame.CanvasPosition.X
		local delta = math.abs(currentCanvasX - lastCanvasX)
		lastCanvasX = currentCanvasX

		if delta <= 0 then
			return
		end

		distanceSinceTick += delta

		local now = os.clock()
		while distanceSinceTick >= tickDistancePixels do
			if now - lastTickAt < ROLL_TICK_MIN_INTERVAL_SECONDS then
				break
			end

			distanceSinceTick -= tickDistancePixels
			lastTickAt = now
			self:_fireRollTick()
		end
	end)
end

function DrawRollSequence:_buildVisualItems(drawConfig, reward: SkinDrawRewardPayload): ({ RollVisualItem }, number)
	return DrawCatalogUtils.BuildRollVisualItems(
		InventoryItemVisuals,
		drawConfig,
		reward,
		ROLL_LEAD_CARD_COUNT,
		ROLL_TRAIL_CARD_COUNT
	)
end

function DrawRollSequence:_playSingle(
	token: number,
	drawConfig,
	reward: SkinDrawRewardPayload,
	_index: number,
	_total: number
): boolean
	local rollScrollingFrame = self._refs.rollScrollingFrame
	if rollScrollingFrame == nil then
		return false
	end

	self:_clearClones()
	DrawRollItemView.EnsureListLayout(rollScrollingFrame)

	rollScrollingFrame.CanvasPosition = Vector2.new(0, rollScrollingFrame.CanvasPosition.Y)

	local visualItems, targetIndex = self:_buildVisualItems(drawConfig, reward)
	local targetClone: GuiObject?

	for itemIndex, item in visualItems do
		local clone = DrawRollItemView.CreateClone(rollScrollingFrame, item, itemIndex)

		if itemIndex == targetIndex then
			targetClone = clone
		end
	end

	task.wait()
	self:_updateCanvasSize()
	task.wait()

	if token ~= self._rollToken then
		return false
	end

	if targetClone == nil then
		return false
	end

	self:_setExplanation("Rolling...")

	local targetCanvasPosition = self:_getTargetCanvasPosition(targetClone)

	local tween = TweenService:Create(
		rollScrollingFrame,
		TweenInfo.new(ROLL_DURATION_SECONDS, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{
			CanvasPosition = targetCanvasPosition,
		}
	)

	self._rollTween = tween

	local completed = false
	local completedConnection = tween.Completed:Connect(function()
		completed = true
	end)
	local tickConnection = self:_connectTickPlayback(
		token,
		tween,
		rollScrollingFrame.CanvasPosition.X,
		self:_getTickDistancePixels(targetClone)
	)

	tween:Play()

	while not completed and token == self._rollToken do
		task.wait(0.03)
	end

	tickConnection:Disconnect()
	completedConnection:Disconnect()

	if self._rollTween == tween then
		self._rollTween = nil
	end

	if token ~= self._rollToken then
		return false
	end

	rollScrollingFrame.CanvasPosition = targetCanvasPosition
	self:_setExplanation(reward.displayName)
	self:_fireRollStopped()

	task.wait(ROLL_RESULT_WAIT_SECONDS)

	return token == self._rollToken
end

function DrawRollSequence:Start(result: SkinDrawResultPayload): boolean
	local drawConfig = self._callbacks.getDrawConfig(result.drawId)
	if drawConfig == nil then
		self._isDrawing = false
		self._isWaitingForDrawResult = false
		return false
	end

	self._latestDrawResult = result
	self._isRolling = true
	self._isDrawing = true
	self._isWaitingForDrawResult = false
	self._isRollFinished = false
	self._rollToken += 1

	local token = self._rollToken

	setGuiVisible(self._refs.chooseDrawFrame, false)
	setGuiVisible(self._refs.rngFrame, true)
	self:_setSkipButtonTitle("SKIP")
	self:_setExplanation("Rolling...")

	task.spawn(function()
		for index, reward in result.rewards do
			if token ~= self._rollToken then
				return
			end

			local completed = self:_playSingle(token, drawConfig, reward, index, #result.rewards)
			if not completed then
				return
			end
		end

		if token == self._rollToken then
			self:_finish()
		end
	end)

	return true
end

return DrawRollSequence
