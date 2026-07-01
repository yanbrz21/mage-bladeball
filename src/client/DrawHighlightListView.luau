--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Parabellum = ReplicatedStorage:WaitForChild("Parabellum")
local DrawCatalogUtils = require(Parabellum:WaitForChild("DrawCatalogUtils"))
local InventoryItemVisuals = require(Parabellum:WaitForChild("InventoryItemVisuals"))

local DrawHighlightListView = {}

local HIGHLIGHT_TEMPLATE_FOLDER_NAME = "Template"
local HIGHLIGHT_ITEM_TEMPLATE_NAME = "HighlightItem"
local HIGHLIGHT_GRADIENTS_FOLDER_NAME = "Gradients"
local HIGHLIGHT_ITEM_CLONE_ATTRIBUTE = "ParabellumHighlightItemClone"
local CATEGORY_ATTRIBUTE = "CATEGORY"
local ITEM_ID_ATTRIBUTE = "ITEM_ID"
local SELECTED_STROKE_IMAGE_COLOR = Color3.fromRGB(255, 234, 142)
local UNSELECTED_STROKE_IMAGE_COLOR = Color3.fromRGB(23, 14, 33)
local SELECTED_STROKE_TRANSPARENCY = 0
local UNSELECTED_STROKE_TRANSPARENCY = 0.28

local rarityHighlightStyles = {
	Common = {
		gradientName = "Blue",
	},
	Rare = {
		gradientName = "Blue",
	},
	Epic = {
		gradientName = "Purple",
	},
	Legendary = {
		gradientName = "Yellow",
	},
	Mythic = {
		gradientName = "Yellow",
	},
}

type HighlightVisualEntry = DrawCatalogUtils.HighlightVisualEntry

export type RenderResult = {
	selectedKey: string?,
	selectedEntry: HighlightVisualEntry?,
}

export type RenderParams = {
	spinItems: Frame?,
	drawConfig: any?,
	selectedKey: string?,
	onSelect: (HighlightVisualEntry) -> (),
}

function DrawHighlightListView.MakeKey(category: string, itemId: string): string
	return `{category}:{itemId}`
end

local function getTemplateFolder(spinItems: Frame?): Folder?
	if spinItems == nil then
		return nil
	end

	local templateFolder = spinItems:FindFirstChild(HIGHLIGHT_TEMPLATE_FOLDER_NAME)
	if templateFolder == nil or not templateFolder:IsA("Folder") then
		return nil
	end

	return templateFolder
end

local function getItemTemplate(spinItems: Frame?): Frame?
	local templateFolder = getTemplateFolder(spinItems)
	if templateFolder ~= nil then
		local template = templateFolder:FindFirstChild(HIGHLIGHT_ITEM_TEMPLATE_NAME)
		if template ~= nil and template:IsA("Frame") then
			template.Visible = false
			return template
		end

		warn("[DrawController] missing Template.HighlightItem under SPIN_ITEMS")
	end

	if spinItems == nil then
		return nil
	end

	for _, child in spinItems:GetChildren() do
		if child:IsA("Frame") and child:GetAttribute(HIGHLIGHT_ITEM_CLONE_ATTRIBUTE) ~= true then
			child.Visible = false
			return child
		end
	end

	warn("[DrawController] no highlight item template found")
	return nil
end

local function clearClones(spinItems: Frame?)
	if spinItems == nil then
		return
	end

	for _, child in spinItems:GetChildren() do
		if child:GetAttribute(HIGHLIGHT_ITEM_CLONE_ATTRIBUTE) == true then
			child:Destroy()
		elseif child:IsA("Frame") then
			child.Visible = false
		end
	end
end

local function getGradientSource(spinItems: Frame?, rarity: string): UIGradient?
	local style = rarityHighlightStyles[rarity]
	if style == nil then
		warn(`[DrawController] unsupported highlight rarity style: {rarity}`)
		style = rarityHighlightStyles.Rare
	end

	local templateFolder = getTemplateFolder(spinItems)
	if templateFolder == nil then
		return nil
	end

	local gradientsFolder = templateFolder:FindFirstChild(HIGHLIGHT_GRADIENTS_FOLDER_NAME)
	if gradientsFolder == nil or not gradientsFolder:IsA("Folder") then
		warn("[DrawController] missing Template.Gradients under SPIN_ITEMS")
		return nil
	end

	local gradientName = style.gradientName
	local gradient = gradientsFolder:FindFirstChild(gradientName)
	if gradient ~= nil and gradient:IsA("UIGradient") then
		return gradient
	end

	warn(`[DrawController] missing highlight gradient source: {gradientName}`)
	return nil
end

local function applyGradientProperties(target: UIGradient, source: UIGradient)
	target.Color = source.Color
	target.Transparency = source.Transparency
	target.Rotation = source.Rotation
	target.Offset = source.Offset
	target.Enabled = source.Enabled
end

local function applyRarityStyle(spinItems: Frame?, frame: Frame, rarity: string)
	local deco = frame:FindFirstChild("Deco")
	if deco == nil then
		warn(`[DrawController] missing Deco folder inside {frame:GetFullName()}`)
		return
	end

	local bg = deco:FindFirstChild("Bg")
	if bg == nil or not bg:IsA("GuiObject") then
		warn(`[DrawController] missing Deco.Bg inside {frame:GetFullName()}`)
		return
	end

	local gradientSource = getGradientSource(spinItems, rarity)
	if gradientSource == nil then
		return
	end

	local targetGradient = bg:FindFirstChildWhichIsA("UIGradient")
	if targetGradient == nil then
		local clonedGradient = gradientSource:Clone()
		clonedGradient.Name = "Gradient"
		clonedGradient.Parent = bg
	else
		applyGradientProperties(targetGradient, gradientSource)
	end
end

local function findTextLabel(root: Instance, name: string): TextLabel?
	local found = root:FindFirstChild(name, true)
	if found ~= nil and found:IsA("TextLabel") then
		return found
	end

	return nil
end

local function getInfoLabels(info: Frame): (TextLabel?, TextLabel?, TextLabel?)
	local rarityLabel = findTextLabel(info, "Rarity")
	local titleLabel = findTextLabel(info, "Title") or findTextLabel(info, "Name")
	local exclusiveLabel = findTextLabel(info, "Exclusive")

	return titleLabel, rarityLabel, exclusiveLabel
end

local function setImageLikeStrokeSelected(stroke: Instance, selected: boolean)
	local imageStroke = stroke :: any
	imageStroke.ImageColor3 = if selected then SELECTED_STROKE_IMAGE_COLOR else UNSELECTED_STROKE_IMAGE_COLOR
	imageStroke.ImageTransparency = if selected then SELECTED_STROKE_TRANSPARENCY else UNSELECTED_STROKE_TRANSPARENCY
end

local function setFrameSelected(frame: Frame, selected: boolean)
	frame:SetAttribute("SELECTED", selected)

	local stroke = frame:FindFirstChild("Stroke", true)
	if stroke == nil then
		return
	end

	if stroke:IsA("UIStroke") then
		stroke.Enabled = selected
	elseif stroke:IsA("ImageLabel") or stroke:IsA("ImageButton") then
		setImageLikeStrokeSelected(stroke, selected)
	end
end

local function findEntryByKey(entries: { HighlightVisualEntry }, key: string?): HighlightVisualEntry?
	if key == nil then
		return nil
	end

	for _, entry in entries do
		if DrawHighlightListView.MakeKey(entry.Category, entry.ItemId) == key then
			return entry
		end
	end

	return nil
end

local function isClickInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

function DrawHighlightListView.Render(params: RenderParams): RenderResult
	local spinItems = params.spinItems
	local drawConfig = params.drawConfig
	clearClones(spinItems)

	if spinItems == nil or drawConfig == nil then
		return {
			selectedKey = nil,
			selectedEntry = nil,
		}
	end

	local highlightEntries = DrawCatalogUtils.GetHighlightDrawEntries(InventoryItemVisuals, drawConfig)
	if #highlightEntries <= 0 then
		return {
			selectedKey = nil,
			selectedEntry = nil,
		}
	end

	local selectedEntry = findEntryByKey(highlightEntries, params.selectedKey)
	local selectedKey = params.selectedKey
	if selectedEntry == nil then
		selectedEntry = highlightEntries[1]
		if selectedEntry ~= nil then
			selectedKey = DrawHighlightListView.MakeKey(selectedEntry.Category, selectedEntry.ItemId)
		end
	end

	local template = getItemTemplate(spinItems)
	if template == nil then
		return {
			selectedKey = selectedKey,
			selectedEntry = selectedEntry,
		}
	end

	for index, entry in highlightEntries do
		local frame = template:Clone()
		frame.Name = `HighlightItem_{index}`
		frame.LayoutOrder = index
		frame:SetAttribute(HIGHLIGHT_ITEM_CLONE_ATTRIBUTE, true)
		frame:SetAttribute(CATEGORY_ATTRIBUTE, entry.Category)
		frame:SetAttribute(ITEM_ID_ATTRIBUTE, entry.ItemId)
		frame.Active = true
		frame.Selectable = true
		frame.Interactable = true
		frame.Parent = spinItems

		local highlightKey = DrawHighlightListView.MakeKey(entry.Category, entry.ItemId)
		frame.InputBegan:Connect(function(input)
			if not isClickInput(input) then
				return
			end

			params.onSelect(entry)
		end)

		local info = frame:FindFirstChild("Info")
		if info == nil or not info:IsA("Frame") then
			warn(`[DrawController] missing Info frame inside {frame:GetFullName()}`)
			frame.Visible = false
			continue
		end

		local titleLabel, rarityLabel, exclusiveLabel = getInfoLabels(info)
		local rarity = DrawCatalogUtils.GetInventoryRarity(InventoryItemVisuals, entry.Category, entry.ItemId)
		applyRarityStyle(spinItems, frame, rarity)

		if rarityLabel ~= nil and rarityLabel:IsA("TextLabel") then
			rarityLabel.Text = rarity
			rarityLabel.TextColor3 = DrawCatalogUtils.GetRarityColor(rarity)
		else
			warn(`[DrawController] missing Info.Rarity TextLabel inside {frame:GetFullName()}`)
		end

		if titleLabel ~= nil and titleLabel:IsA("TextLabel") then
			titleLabel.Text =
				DrawCatalogUtils.GetInventoryDisplayName(InventoryItemVisuals, entry.Category, entry.ItemId)
		else
			warn(`[DrawController] missing Info.Title TextLabel inside {frame:GetFullName()}`)
		end

		if exclusiveLabel ~= nil and exclusiveLabel:IsA("TextLabel") then
			exclusiveLabel.Text = "Exclusive!"
			exclusiveLabel.Visible = entry.exclusive
		elseif entry.exclusive then
			warn(`[DrawController] missing Info.Exclusive TextLabel inside {frame:GetFullName()}`)
		end

		setFrameSelected(frame, highlightKey == selectedKey)
		frame.Visible = true
	end

	return {
		selectedKey = selectedKey,
		selectedEntry = selectedEntry,
	}
end

return DrawHighlightListView
