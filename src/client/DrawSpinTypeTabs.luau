--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local DrawConfig = require(Config:WaitForChild("DrawConfig"))

local Parabellum = ReplicatedStorage:WaitForChild("Parabellum")
local DrawCatalogUtils = require(Parabellum:WaitForChild("DrawCatalogUtils"))

local DrawSpinTypeTabs = {}

local DRAW_ID_ATTRIBUTE = "ID"
local SELECTED_ATTRIBUTE = "SELECTED"
local AUDIO_CLICK_EVENT_ATTRIBUTE = "AudioClickEvent"
local TAB_SWITCH_AUDIO_EVENT = "TabSwitch"
local SPIN_TYPE_CONNECTED_ATTRIBUTE = "ParabellumSpinTypeConnected"
local SELECTED_STROKE_COLOR = Color3.fromRGB(193, 134, 251)
local UNSELECTED_STROKE_COLOR = Color3.fromRGB(38, 38, 38)

type ResolvedDraw = DrawCatalogUtils.ResolvedDraw

local function resolveDraw(drawId: string): ResolvedDraw?
	return DrawCatalogUtils.ResolveDraw(DrawConfig, drawId)
end

local function getDefaultDrawId(): string
	return DrawCatalogUtils.GetDefaultDrawId(DrawConfig)
end

local function setButtonVisual(button: TextButton, selected: boolean)
	button:SetAttribute(SELECTED_ATTRIBUTE, selected)

	local deco = button:FindFirstChild("Deco")
	if deco ~= nil then
		local glow = deco:FindFirstChild("Glow", true)

		if glow ~= nil and glow:IsA("GuiObject") then
			glow.Visible = selected
		end
	end

	local inner = button:FindFirstChild("Inner", true)
	if inner ~= nil and inner:IsA("UIStroke") then
		inner.Color = if selected then SELECTED_STROKE_COLOR else UNSELECTED_STROKE_COLOR
	end
end

function DrawSpinTypeTabs.UpdateVisual(buttons: { Instance }, playerGui: PlayerGui, currentDrawId: string)
	for _, instance in buttons do
		if not instance:IsDescendantOf(playerGui) then
			continue
		end

		if not instance:IsA("TextButton") then
			continue
		end

		local button = instance :: TextButton
		local drawId = button:GetAttribute(DRAW_ID_ATTRIBUTE)
		local isSelected = drawId == currentDrawId

		setButtonVisual(button, isSelected)
	end
end

local function getOrderedDraws(): { ResolvedDraw }
	local orderedDraws = {} :: { ResolvedDraw }

	for _, drawId in DrawConfig.DrawOrder do
		if type(drawId) ~= "string" then
			warn("[DrawController] DrawOrder contains a non-string draw id")
			continue
		end

		local resolvedDraw = resolveDraw(drawId)
		if resolvedDraw ~= nil then
			table.insert(orderedDraws, resolvedDraw)
		end
	end

	return orderedDraws
end

local function setButtonText(button: TextButton, resolvedDraw: ResolvedDraw)
	local titleLabel = button:FindFirstChild("Title", true)
	local categoryLabel = button:FindFirstChild("Category", true)
	local drawConfig = resolvedDraw.config

	if titleLabel ~= nil and titleLabel:IsA("TextLabel") then
		titleLabel.Text = drawConfig.DisplayName
	end

	if categoryLabel ~= nil and categoryLabel:IsA("TextLabel") then
		categoryLabel.Text = if resolvedDraw.kind == DrawCatalogUtils.DRAW_KIND_ROBUX then "Robux" else "Coins"
	end
end

local function getSortedTaggedButtons(playerGui: PlayerGui): { TextButton }
	local buttons = {} :: { TextButton }

	for _, instance in CollectionService:GetTagged("SPIN_TYPE_BUTTON") do
		if instance:IsDescendantOf(playerGui) and instance:IsA("TextButton") then
			table.insert(buttons, instance)
		end
	end

	table.sort(buttons, function(left, right)
		if left.LayoutOrder ~= right.LayoutOrder then
			return left.LayoutOrder < right.LayoutOrder
		end

		return left.Name < right.Name
	end)

	return buttons
end

function DrawSpinTypeTabs.SyncWithConfig(playerGui: PlayerGui, currentDrawId: string): ({ Instance }, string)
	local orderedDraws = getOrderedDraws()
	local existingButtons = getSortedTaggedButtons(playerGui)
	local template: TextButton? = existingButtons[1]

	if template == nil then
		warn("[DrawController] no SPIN_TYPE_BUTTON template found")
		return {}, currentDrawId
	end

	for index, resolvedDraw in orderedDraws do
		local button: TextButton? = existingButtons[index]
		if button == nil then
			local clonedButton = template:Clone() :: TextButton
			clonedButton.Parent = template.Parent
			CollectionService:AddTag(clonedButton, "SPIN_TYPE_BUTTON")
			button = clonedButton
		end

		local resolvedButton = button :: TextButton
		resolvedButton.Name = resolvedDraw.drawId
		resolvedButton.LayoutOrder = index
		resolvedButton.Visible = true
		resolvedButton:SetAttribute(DRAW_ID_ATTRIBUTE, resolvedDraw.drawId)
		resolvedButton:SetAttribute(SELECTED_ATTRIBUTE, false)
		resolvedButton:SetAttribute(AUDIO_CLICK_EVENT_ATTRIBUTE, TAB_SWITCH_AUDIO_EVENT)
		setButtonText(resolvedButton, resolvedDraw)
	end

	for index = #orderedDraws + 1, #existingButtons do
		local button = existingButtons[index]
		button.Visible = false
		button:SetAttribute(DRAW_ID_ATTRIBUTE, nil)
		button:SetAttribute(SPIN_TYPE_CONNECTED_ATTRIBUTE, nil)
		CollectionService:RemoveTag(button, "SPIN_TYPE_BUTTON")
	end

	local buttons = {} :: { Instance }
	for _, button in getSortedTaggedButtons(playerGui) do
		table.insert(buttons, button)
	end

	local resolvedCurrentDrawId = currentDrawId
	if resolvedCurrentDrawId == "" or resolveDraw(resolvedCurrentDrawId) == nil then
		resolvedCurrentDrawId = getDefaultDrawId()
	end

	return buttons, resolvedCurrentDrawId
end

return DrawSpinTypeTabs
