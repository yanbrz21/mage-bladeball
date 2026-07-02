--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Network = Shared:WaitForChild("Network")

local DrawConfig = require(Config:WaitForChild("DrawConfig"))
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local MatchConfig = require(Config:WaitForChild("MatchConfig"))
local Remotes = require(Network:WaitForChild("Remotes"))
local Parabellum = ReplicatedStorage:WaitForChild("Parabellum")
local DrawCatalogUtils = require(Parabellum:WaitForChild("DrawCatalogUtils"))
local DrawHighlightListView = require(Parabellum:WaitForChild("DrawHighlightListView"))
local DrawHighlightPreview = require(Parabellum:WaitForChild("DrawHighlightPreview"))
local DrawPresentationState = require(Parabellum:WaitForChild("DrawPresentationState"))
local DrawPricingView = require(Parabellum:WaitForChild("DrawPricingView"))
local DrawRequestFlow = require(Parabellum:WaitForChild("DrawRequestFlow"))
local DrawRollSequence = require(Parabellum:WaitForChild("DrawRollSequence"))
local DrawSpinTypeTabs = require(Parabellum:WaitForChild("DrawSpinTypeTabs"))
local DrawWorldEntryPrompts = require(Parabellum:WaitForChild("DrawWorldEntryPrompts"))
local DrawWorldHighlightPreviewManager = require(Parabellum:WaitForChild("DrawWorldHighlightPreviewManager"))
local InventoryItemVisuals = require(Parabellum:WaitForChild("InventoryItemVisuals"))

local HUD_SCREENGUI: ScreenGui?

local requestSkinDrawRemote = Remotes.GetClientToServer(Network, Remotes.ClientToServer.RequestSkinDraw)

local skinDrawResultRemote = Remotes.GetServerToClient(Network, Remotes.ServerToClient.SkinDrawResult)

local economyBalanceChangedRemote = Remotes.GetServerToClient(Network, Remotes.ServerToClient.EconomyBalanceChanged)

local inventoryUpdatedRemote = Remotes.GetServerToClient(Network, Remotes.ServerToClient.InventoryUpdated)

local DrawController = {
	Name = "DrawController",
}

local DRAW_ID_ATTRIBUTE = "ID"
local AUDIO_CLICK_EVENT_ATTRIBUTE = "AudioClickEvent"
local TAB_SWITCH_AUDIO_EVENT = "TabSwitch"
local SPIN_TYPE_CONNECTED_ATTRIBUTE = "ParabellumSpinTypeConnected"

local DRAW_ENTRY_CONNECTED_ATTRIBUTE = "ParabellumDrawEntryConnected"
local NORMAL_DRAW_ID = "NormalDraw"
local PREMIUM_DRAW_ID = "LaunchRobuxMixedDraw"
local DRAW_WORLD_ENTRIES = table.freeze({
	table.freeze({
		modelName = "NormalDraw",
		drawId = NORMAL_DRAW_ID,
		actionText = "Open",
		objectText = "Normal Draw",
		worldName = "NormalDraw",
	}),
	table.freeze({
		modelName = "PremiumDraw",
		drawId = PREMIUM_DRAW_ID,
		actionText = "Open",
		objectText = "Premium Draw",
		worldName = "PremiumDraw",
	}),
})

type SkinDrawResultPayload = DrawCatalogUtils.SkinDrawResultPayload
type ResolvedDraw = DrawCatalogUtils.ResolvedDraw
type HighlightVisualEntry = DrawCatalogUtils.HighlightVisualEntry

local screen: Instance?

local coinsText: TextLabel?

local spinItems: Frame?

local spin1xButton: TextButton?
local spin5xButton: TextButton?

local drawButton: GuiButton?
local drawClose: GuiObject?

local gemsDrawPrice: TextLabel?
local coinsDrawPrice: TextLabel?

local spinPrices: Frame?
local price1x: TextLabel?
local price5x: TextLabel?
local price1xIcon: ImageLabel?
local price5xIcon: ImageLabel?

local rngFrame: Frame?
local chooseDrawFrame: Frame?
local oddsFrame: Frame?

local rollExplanationText: TextLabel?
local skipDrawButton: TextButton?
local rollScrollingFrame: ScrollingFrame?

local spinTypesButtons: { Instance } = {}

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local currentDrawId = ""
local currentCount = 1
local currentBalance = 0

local selectedHighlightKey: string?

local connections: { RBXScriptConnection } = {}
local didBuildUI = false
local stopWorldEntryPrompts: (() -> ())?
local worldHighlightPreviewManager: any?

function DrawController:Init(context)
	if self._didInit then
		return
	end

	self._didInit = true
	self._context = context
	self._localPlayer = localPlayer
	self._connections = connections
	self._screen = screen
end

local function getReferenceByTag(tag: string, timeout: number?): Instance?
	local startedAt = os.clock()
	local maxWait = timeout or 10

	while os.clock() - startedAt < maxWait do
		local items = CollectionService:GetTagged(tag)

		for _, item in items do
			if item:IsDescendantOf(playerGui) then
				return item
			end
		end

		task.wait(0.1)
	end

	warn(`[DrawController] no tagged player gui item found: {tag}`)
	return nil
end

local function getOptionalReferenceByTag(tag: string): Instance?
	local items = CollectionService:GetTagged(tag)

	for _, item in items do
		if item:IsDescendantOf(playerGui) then
			return item
		end
	end

	return nil
end

local function setScreenEnabled(enabled: boolean)
	if screen == nil then
		return
	end

	if screen:IsA("ScreenGui") then
		screen.Enabled = enabled
	elseif screen:IsA("GuiObject") then
		screen.Visible = enabled
	end
end

local function isScreenShown(): boolean
	if screen == nil then
		return false
	end

	if screen:IsA("ScreenGui") then
		return screen.Enabled
	end

	if screen:IsA("GuiObject") then
		return screen.Visible
	end

	return false
end

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

local function preventGuiResetOnSpawn(instance: Instance?)
	local current = instance
	while current ~= nil do
		if current:IsA("ScreenGui") then
			current.ResetOnSpawn = false
			return
		end

		current = current.Parent
	end
end

local function preventTaggedGuiResetOnSpawn(tag: string)
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsDescendantOf(playerGui) or instance:IsDescendantOf(StarterGui) then
			preventGuiResetOnSpawn(instance)
		end
	end
end

local function preventDrawGuiResetOnSpawn()
	preventTaggedGuiResetOnSpawn("DRAW_BUTTON")
	preventTaggedGuiResetOnSpawn("SIDEMENU")
	preventTaggedGuiResetOnSpawn("SPIN_SCREEN")
end

local function setHudVisible(visible: boolean)
	setGuiVisible(HUD_SCREENGUI, visible)
end

local function isLocalPlayerLockedForRound(): boolean
	local playerState = localPlayer:GetAttribute("PlayerState")
	return playerState == MatchConfig.PlayerStates.AliveInRound or playerState == MatchConfig.PlayerStates.DeadInRound
end

local function updateDrawEntryVisibility()
	local shouldShow = not isLocalPlayerLockedForRound()
	for _, instance in CollectionService:GetTagged("DRAW_BUTTON") do
		if instance:IsDescendantOf(playerGui) and instance:IsA("GuiObject") then
			instance.Visible = shouldShow
		end
	end
end

local function connectDrawEntryButton(instance: Instance)
	if not instance:IsDescendantOf(playerGui) or not instance:IsA("GuiButton") then
		return
	end

	preventGuiResetOnSpawn(instance)
	drawButton = instance
	instance.Visible = not isLocalPlayerLockedForRound()

	if instance:GetAttribute(DRAW_ENTRY_CONNECTED_ATTRIBUTE) == true then
		return
	end

	instance:SetAttribute(DRAW_ENTRY_CONNECTED_ATTRIBUTE, true)
	table.insert(
		connections,
		instance.Activated:Connect(function()
			print("[DrawController] draw button clicked")
			DrawController:Open()
		end)
	)
end

local function syncDrawEntryButtons()
	preventDrawGuiResetOnSpawn()
	for _, instance in CollectionService:GetTagged("DRAW_BUTTON") do
		connectDrawEntryButton(instance)
	end
	updateDrawEntryVisibility()
end

local function handleDrawScreenAdded(instance: Instance)
	if not instance:IsDescendantOf(playerGui) then
		return
	end

	screen = instance
	preventGuiResetOnSpawn(instance)
	setScreenEnabled(false)
end

local function handleSideMenuAdded(instance: Instance)
	if not instance:IsDescendantOf(playerGui) then
		return
	end

	HUD_SCREENGUI = instance :: any
	preventGuiResetOnSpawn(instance)
	setHudVisible(true)
	syncDrawEntryButtons()
end

local function resolveDraw(drawId: string): ResolvedDraw?
	return DrawCatalogUtils.ResolveDraw(DrawConfig, drawId)
end

local function getDrawConfig(drawId: string)
	return DrawCatalogUtils.GetDrawConfig(DrawConfig, drawId)
end

local function findRobuxDrawProduct(drawId: string, count: number): DrawCatalogUtils.RobuxDrawProduct?
	return DrawCatalogUtils.FindRobuxDrawProduct(EconomyConfig, drawId, count)
end

local function getRarityColor(rarity: string): Color3
	return DrawCatalogUtils.GetRarityColor(rarity)
end

local function formatPercent(value: number): string
	return DrawCatalogUtils.FormatPercent(value)
end

local function getDrawRarityOdds(drawConfig): { [string]: number }
	return DrawCatalogUtils.GetDrawRarityOdds(InventoryItemVisuals, drawConfig)
end

local function updateOddsFrame()
	if oddsFrame == nil then
		return
	end

	local drawConfig = getDrawConfig(currentDrawId)
	if drawConfig == nil then
		return
	end

	local rarityOdds = getDrawRarityOdds(drawConfig)

	for _, rarityFrame in oddsFrame:GetChildren() do
		if not rarityFrame:IsA("GuiObject") then
			continue
		end

		local rarityName = rarityFrame.Name
		local percent = rarityOdds[rarityName] or 0
		rarityFrame.Visible = percent > 0

		if percent <= 0 then
			continue
		end

		local percentLabel = rarityFrame:FindFirstChild("Percentage")

		if percentLabel == nil or not percentLabel:IsA("TextLabel") then
			warn(`[DrawController] missing Percentage TextLabel inside odds rarity frame: {rarityFrame:GetFullName()}`)
			continue
		end

		local rarityLabel = rarityFrame:FindFirstChild("Rarity")

		if rarityLabel ~= nil and rarityLabel:IsA("TextLabel") then
			rarityLabel.Text = rarityName
			rarityLabel.TextColor3 = getRarityColor(rarityName)
		end

		percentLabel.Text = formatPercent(percent)
	end
end

local function clearHighlightPreview()
	DrawHighlightPreview.Clear()
end

local function resolveHighlightPreviewReferences()
	DrawHighlightPreview.ResolveReferences(screen)
end

local function renderHighlightPreview(category: string, itemId: string)
	DrawHighlightPreview.Render(category, itemId)
end

local function renderSelectedHighlightPreview(entry: HighlightVisualEntry?)
	if entry == nil then
		selectedHighlightKey = nil
		clearHighlightPreview()
		return
	end

	if not isScreenShown() then
		clearHighlightPreview()
		return
	end

	renderHighlightPreview(entry.Category, entry.ItemId)
end

local updateSpinItems

local function selectHighlightEntry(entry: HighlightVisualEntry)
	local highlightKey = DrawHighlightListView.MakeKey(entry.Category, entry.ItemId)
	if selectedHighlightKey == highlightKey then
		return
	end

	selectedHighlightKey = highlightKey
	updateSpinItems()
end

function updateSpinItems()
	local drawConfig = getDrawConfig(currentDrawId)
	local result = DrawHighlightListView.Render({
		spinItems = spinItems,
		drawConfig = drawConfig,
		selectedKey = selectedHighlightKey,
		onSelect = selectHighlightEntry,
	})

	selectedHighlightKey = result.selectedKey
	renderSelectedHighlightPreview(result.selectedEntry)
end

local function readBalanceAttribute()
	local coins = localPlayer:GetAttribute("Coins")
	currentBalance = if typeof(coins) == "number" then coins else 0
end

local function updateCurrencyLabels()
	readBalanceAttribute()

	if coinsText ~= nil then
		coinsText.Text = tostring(currentBalance)
	end
end

local function updateDrawPrices()
	local resolvedDraw = resolveDraw(currentDrawId)
	if resolvedDraw == nil then
		return
	end

	DrawPricingView.Update({
		refs = {
			spin1xButton = spin1xButton,
			spin5xButton = spin5xButton,
			price1x = price1x,
			price5x = price5x,
			coinsDrawPrice = coinsDrawPrice,
			gemsDrawPrice = gemsDrawPrice,
			price1xIcon = price1xIcon,
			price5xIcon = price5xIcon,
		},
		currentDrawId = currentDrawId,
		currentCount = currentCount,
		resolvedDraw = resolvedDraw,
		findRobuxDrawProduct = findRobuxDrawProduct,
	})
end

local function updateSpinTypeButtonsVisual()
	DrawSpinTypeTabs.UpdateVisual(spinTypesButtons, playerGui, currentDrawId)
end

local function syncSpinTypeButtonsWithConfig()
	spinTypesButtons, currentDrawId = DrawSpinTypeTabs.SyncWithConfig(playerGui, currentDrawId)
end

local rollSequence = DrawRollSequence.new({
	getDrawConfig = getDrawConfig,
	refreshIdleUi = function()
		updateCurrencyLabels()
		updateDrawPrices()
		updateSpinItems()
		updateOddsFrame()
		updateSpinTypeButtonsVisual()
	end,
})

local function setCurrentDraw(drawId: string)
	local drawConfig = getDrawConfig(drawId)
	if drawConfig == nil then
		return
	end

	currentDrawId = drawId

	print(`[DrawController] selected draw: {drawId}`)
	print(`[DrawController] display name: {drawConfig.DisplayName}`)
	if type(drawConfig.Cost) == "number" then
		print(`[DrawController] cost: {drawConfig.Cost}`)
	end

	updateDrawPrices()
	updateSpinItems()
	updateOddsFrame()
	updateSpinTypeButtonsVisual()
end

local function setCurrentCount(count: number)
	currentCount = count
	print(`[DrawController] selected count: {count}`)
	updateDrawPrices()
end

local function getDrawResultMessage(result: SkinDrawResultPayload): string
	if result.success then
		return "draw complete"
	end

	if result.code == "InsufficientCoins" then
		return "not enough coins"
	elseif result.code == "ProfileNotLoaded" then
		return "profile still loading"
	elseif result.code == "InvalidDraw" then
		return "draw unavailable"
	elseif result.code == "DirtyMarkFailed" then
		return "could not save draw"
	end

	return result.code
end

local function handleSkinDrawResult(payload: SkinDrawResultPayload)
	if payload.balanceAfter ~= nil then
		currentBalance = payload.balanceAfter
	end

	updateCurrencyLabels()
	updateDrawPrices()

	if not payload.success then
		rollSequence:ResetAfterFailure()

		warn(`[DrawController] draw failed: {getDrawResultMessage(payload)}`)
		return
	end

	if #payload.rewards <= 0 then
		rollSequence:ResetAfterEmptyResult()

		warn("[DrawController] draw succeeded but returned no rewards")
		return
	end

	rollSequence:Start(payload)
end

local function onDrawButtonClicked(count: number)
	DrawRequestFlow.Request({
		count = count,
		currentDrawId = currentDrawId,
		localPlayer = localPlayer,
		requestSkinDrawRemote = requestSkinDrawRemote,
		rollSequence = rollSequence,
		resolveDraw = resolveDraw,
		findRobuxDrawProduct = findRobuxDrawProduct,
		readBalance = readBalanceAttribute,
		getBalance = function()
			return currentBalance
		end,
		setCurrentCount = setCurrentCount,
		updateDrawPrices = updateDrawPrices,
	})
end

local function connectSpinTypeButtons()
	print("[DrawController] connect spin type buttons")

	syncSpinTypeButtonsWithConfig()

	for _, instance in spinTypesButtons do
		if not instance:IsDescendantOf(playerGui) then
			continue
		end

		if not instance:IsA("TextButton") then
			warn(`[DrawController] SPIN_TYPE_BUTTON is not TextButton: {instance:GetFullName()}`)
			continue
		end

		local button = instance :: TextButton
		local drawId = button:GetAttribute(DRAW_ID_ATTRIBUTE)
		button:SetAttribute(AUDIO_CLICK_EVENT_ATTRIBUTE, TAB_SWITCH_AUDIO_EVENT)

		if button:GetAttribute(SPIN_TYPE_CONNECTED_ATTRIBUTE) == true then
			continue
		end

		if type(drawId) ~= "string" then
			warn(`[DrawController] missing/invalid {DRAW_ID_ATTRIBUTE} attribute on {button:GetFullName()}`)
			continue
		end

		button:SetAttribute(SPIN_TYPE_CONNECTED_ATTRIBUTE, true)
		table.insert(
			connections,
			button.Activated:Connect(function()
				local currentButtonDrawId = button:GetAttribute(DRAW_ID_ATTRIBUTE)
				if type(currentButtonDrawId) == "string" then
					setCurrentDraw(currentButtonDrawId)
				end
			end)
		)
	end

	updateSpinTypeButtonsVisual()
end

local function closeDrawUi()
	clearHighlightPreview()
	DrawPresentationState.Disable()
	setScreenEnabled(false)
	setHudVisible(true)
	if worldHighlightPreviewManager ~= nil then
		worldHighlightPreviewManager:Resume()
	end
end

local function pauseWorldHighlightPreviews()
	if worldHighlightPreviewManager ~= nil then
		worldHighlightPreviewManager:Pause()
	end
end

local function startDrawWorldEntries()
	if stopWorldEntryPrompts == nil then
		stopWorldEntryPrompts = DrawWorldEntryPrompts.Start(DRAW_WORLD_ENTRIES :: any, function(drawId: string)
			DrawController:OpenDraw(drawId)
		end)
	end

	if worldHighlightPreviewManager == nil then
		local manager = DrawWorldHighlightPreviewManager.new(DRAW_WORLD_ENTRIES :: any, 20)
		worldHighlightPreviewManager = manager
		manager:Start()
	end
end

local function connectDrawClose()
	if drawClose == nil then
		warn("[DrawController] draw close not found")
		return
	end

	if drawClose:IsA("GuiButton") then
		table.insert(
			connections,
			drawClose.Activated:Connect(function()
				closeDrawUi()
			end)
		)

		return
	end

	drawClose.Active = true

	table.insert(
		connections,
		drawClose.InputBegan:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				closeDrawUi()
			end
		end)
	)
end

local function connectCharacterReset()
	table.insert(
		connections,
		localPlayer.CharacterAdded:Connect(function()
			closeDrawUi()
			task.defer(syncDrawEntryButtons)
		end)
	)
end

function DrawController:GetReferences()
	preventDrawGuiResetOnSpawn()

	coinsText = getReferenceByTag("SPIN_COINS") :: TextLabel?

	spin1xButton = getReferenceByTag("SPIN_1X_BUTTON") :: TextButton?
	spin5xButton = getReferenceByTag("SPIN_5X_BUTTON") :: TextButton?

	drawButton = getOptionalReferenceByTag("DRAW_BUTTON") :: GuiButton?

	gemsDrawPrice = getReferenceByTag("GEMS_DRAW_PRICE") :: TextLabel?
	coinsDrawPrice = getReferenceByTag("COINS_DRAW_PRICE") :: TextLabel?

	spinPrices = getReferenceByTag("SPIN_PRICES") :: Frame?
	spinItems = getReferenceByTag("SPIN_ITEMS") :: Frame?

	screen = getReferenceByTag("SPIN_SCREEN") :: ScreenGui?
	resolveHighlightPreviewReferences()

	chooseDrawFrame = getReferenceByTag("CHOOSE_DRAW_FRAME") :: Frame?
	rngFrame = getReferenceByTag("RNG_FRAME") :: Frame?
	oddsFrame = getReferenceByTag("ODDS_FRAME") :: Frame?

	rollScrollingFrame = getReferenceByTag("ROLL_SCROLLING_FRAME") :: ScrollingFrame?
	skipDrawButton = getReferenceByTag("ROLL_SKIP_BUTTON") :: TextButton?
	rollExplanationText = getReferenceByTag("ROLL_EXPLANATION_TEXT") :: TextLabel?

	HUD_SCREENGUI = getReferenceByTag("SIDEMENU") :: ScreenGui?

	local foundDrawClose = getOptionalReferenceByTag("DRAW_CLOSE")
		or getOptionalReferenceByTag("DRAWCLOSE")
		or getOptionalReferenceByTag("DRAW_CLOSE_BUTTON")

	if foundDrawClose ~= nil and foundDrawClose:IsA("GuiObject") then
		drawClose = foundDrawClose
	end

	if spinPrices ~= nil then
		local foundPrice1x = spinPrices:FindFirstChild("x1", true)
		local foundPrice5x = spinPrices:FindFirstChild("x5", true)

		if foundPrice1x ~= nil and foundPrice1x:IsA("TextLabel") then
			price1x = foundPrice1x
		end

		if foundPrice5x ~= nil and foundPrice5x:IsA("TextLabel") then
			price5x = foundPrice5x
		end
	end

	if coinsDrawPrice ~= nil and coinsDrawPrice.Parent ~= nil then
		local icon = coinsDrawPrice.Parent:FindFirstChild("Icon")
		if icon ~= nil and icon:IsA("ImageLabel") then
			price1xIcon = icon
		end
	end

	if gemsDrawPrice ~= nil and gemsDrawPrice.Parent ~= nil then
		local icon = gemsDrawPrice.Parent:FindFirstChild("Icon")
		if icon ~= nil and icon:IsA("ImageLabel") then
			price5xIcon = icon
		end
	end

	rollSequence:SetRefs({
		chooseDrawFrame = chooseDrawFrame,
		rngFrame = rngFrame,
		rollScrollingFrame = rollScrollingFrame,
		rollExplanationText = rollExplanationText,
		skipDrawButton = skipDrawButton,
	})
end

function DrawController:BuildUI()
	if didBuildUI then
		syncSpinTypeButtonsWithConfig()
		updateCurrencyLabels()
		updateDrawPrices()
		updateSpinItems()
		updateOddsFrame()
		updateSpinTypeButtonsVisual()
		return
	end

	didBuildUI = true

	self:GetReferences()
	syncSpinTypeButtonsWithConfig()

	setScreenEnabled(false)
	setHudVisible(true)
	connectCharacterReset()
	syncDrawEntryButtons()

	rollSequence:ResetToChoose(false)

	updateCurrencyLabels()
	updateDrawPrices()
	updateSpinItems()
	updateOddsFrame()

	if drawButton == nil then
		warn("[DrawController] draw button not found")
	end

	table.insert(connections, CollectionService:GetInstanceAddedSignal("DRAW_BUTTON"):Connect(connectDrawEntryButton))
	table.insert(connections, CollectionService:GetInstanceAddedSignal("SPIN_SCREEN"):Connect(handleDrawScreenAdded))
	table.insert(connections, CollectionService:GetInstanceAddedSignal("SIDEMENU"):Connect(handleSideMenuAdded))

	connectDrawClose()

	if spin1xButton ~= nil then
		table.insert(
			connections,
			spin1xButton.Activated:Connect(function()
				onDrawButtonClicked(1)
			end)
		)
	end

	if spin5xButton ~= nil then
		table.insert(
			connections,
			spin5xButton.Activated:Connect(function()
				onDrawButtonClicked(5)
			end)
		)
	end

	if skipDrawButton ~= nil then
		table.insert(
			connections,
			skipDrawButton.Activated:Connect(function()
				rollSequence:HandleSkipOrClaim()
			end)
		)
	end

	connectSpinTypeButtons()
	startDrawWorldEntries()

	table.insert(
		connections,
		localPlayer:GetAttributeChangedSignal("Coins"):Connect(function()
			updateCurrencyLabels()
			updateDrawPrices()
		end)
	)

	table.insert(connections, localPlayer:GetAttributeChangedSignal("SkinTokens"):Connect(updateCurrencyLabels))

	table.insert(
		connections,
		localPlayer:GetAttributeChangedSignal("PlayerState"):Connect(function()
			updateDrawEntryVisibility()

			if isLocalPlayerLockedForRound() then
				closeDrawUi()
			end
		end)
	)

	table.insert(
		connections,
		economyBalanceChangedRemote.OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" then
				return
			end

			local balance = payload.balance
			if typeof(balance) == "number" then
				currentBalance = balance
			end

			updateCurrencyLabels()
			updateDrawPrices()
		end)
	)

	table.insert(
		connections,
		inventoryUpdatedRemote.OnClientEvent:Connect(function()
			updateSpinItems()
		end)
	)

	table.insert(
		connections,
		skinDrawResultRemote.OnClientEvent:Connect(function(payload)
			if type(payload) ~= "table" then
				return
			end

			handleSkinDrawResult(payload :: SkinDrawResultPayload)
		end)
	)
end

function DrawController:Open()
	if isLocalPlayerLockedForRound() then
		closeDrawUi()
		updateDrawEntryVisibility()
		return
	end

	pauseWorldHighlightPreviews()
	setScreenEnabled(true)
	setHudVisible(false)
	DrawPresentationState.Enable()
	syncSpinTypeButtonsWithConfig()
	resolveHighlightPreviewReferences()

	if not rollSequence:IsBusy() and not rollSequence:IsRollFinished() then
		setGuiVisible(chooseDrawFrame, true)
		setGuiVisible(rngFrame, false)
	end

	updateCurrencyLabels()
	updateDrawPrices()
	updateSpinItems()
	updateOddsFrame()
	updateSpinTypeButtonsVisual()
end

function DrawController:OpenDraw(drawId: string)
	setCurrentDraw(drawId)
	self:Open()
end

function DrawController:Close()
	closeDrawUi()
end

function DrawController:Start()
	print("[DrawController] started")

	if self._didStart then
		return
	end

	self._didStart = true
	self:BuildUI()
end

return DrawController
