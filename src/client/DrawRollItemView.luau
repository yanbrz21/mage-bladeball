--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Parabellum = ReplicatedStorage:WaitForChild("Parabellum")
local DrawCatalogUtils = require(Parabellum:WaitForChild("DrawCatalogUtils"))

local DrawRollItemView = {}

local ROLL_CLONE_ATTRIBUTE = "IS_ROLL_CLONE"
local ROLL_TEMPLATE_ATTRIBUTE = "IS_ROLL_TEMPLATE"

type RollVisualItem = DrawCatalogUtils.RollVisualItem

function DrawRollItemView.ClearClones(rollScrollingFrame: ScrollingFrame?)
	if rollScrollingFrame == nil then
		return
	end

	for _, child in rollScrollingFrame:GetChildren() do
		if child:GetAttribute(ROLL_CLONE_ATTRIBUTE) == true then
			child:Destroy()
		end
	end

	rollScrollingFrame.CanvasPosition = Vector2.new(0, rollScrollingFrame.CanvasPosition.Y)
end

function DrawRollItemView.EnsureListLayout(rollScrollingFrame: ScrollingFrame?): UIListLayout?
	if rollScrollingFrame == nil then
		return nil
	end

	local existingLayout = rollScrollingFrame:FindFirstChildWhichIsA("UIListLayout")

	if existingLayout ~= nil then
		existingLayout.FillDirection = Enum.FillDirection.Horizontal
		existingLayout.SortOrder = Enum.SortOrder.LayoutOrder
		return existingLayout
	end

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 12)
	layout.Parent = rollScrollingFrame

	return layout
end

local function findRollTemplateByRarity(rollScrollingFrame: ScrollingFrame?, rarity: string): GuiObject?
	if rollScrollingFrame == nil then
		return nil
	end

	local upperRarity = string.upper(rarity)

	local namesToTry = {
		rarity,
		upperRarity,
		`{rarity}Template`,
		`{upperRarity}_TEMPLATE`,
		`{upperRarity}TEMPLATE`,
	}

	for _, name in namesToTry do
		local found = rollScrollingFrame:FindFirstChild(name, true)

		if found ~= nil and found:IsA("GuiObject") and found:GetAttribute(ROLL_CLONE_ATTRIBUTE) ~= true then
			found:SetAttribute(ROLL_TEMPLATE_ATTRIBUTE, true)
			return found
		end
	end

	warn(`[DrawController] missing roll template for rarity: {rarity}`)
	return nil
end

local function findFirstTextLabel(parent: Instance, names: { string }): TextLabel?
	for _, name in names do
		local found = parent:FindFirstChild(name, true)

		if found ~= nil and found:IsA("TextLabel") then
			return found
		end
	end

	return nil
end

local function findItemIcon(root: Instance): ImageLabel?
	local found = root:FindFirstChild("ItemIcon", true)
	if found ~= nil and found:IsA("ImageLabel") then
		return found
	end

	return nil
end

local function setRollCloneIcon(clone: GuiObject, item: RollVisualItem)
	local icon = findItemIcon(clone)
	if icon == nil then
		return
	end

	local iconAssetId = item.iconAssetId
	if iconAssetId == nil then
		icon.Image = ""
		icon.Visible = false
		return
	end

	icon.Image = iconAssetId
	icon.Visible = true
	icon.Active = false
	icon.Selectable = false
	icon.Interactable = false
end

local function setRollCloneInfo(clone: GuiObject, item: RollVisualItem)
	local titleLabel = findFirstTextLabel(clone, { "Title", "Name", "ItemName" })
	local rarityLabel = findFirstTextLabel(clone, { "Rarity" })

	if titleLabel ~= nil then
		titleLabel.Text = item.displayName
	end

	if rarityLabel ~= nil then
		rarityLabel.Text = item.rarity
		rarityLabel.TextColor3 = DrawCatalogUtils.GetRarityColor(item.rarity)
	end

	setRollCloneIcon(clone, item)
end

function DrawRollItemView.CreateClone(
	rollScrollingFrame: ScrollingFrame?,
	item: RollVisualItem,
	layoutOrder: number
): GuiObject?
	if rollScrollingFrame == nil then
		return nil
	end

	local template = findRollTemplateByRarity(rollScrollingFrame, item.rarity)
	if template == nil then
		return nil
	end

	local clone = template:Clone()
	clone.Name = `ROLL_{layoutOrder}_{item.itemId}`
	clone.Visible = true
	clone.LayoutOrder = layoutOrder
	clone:SetAttribute(ROLL_CLONE_ATTRIBUTE, true)
	clone:SetAttribute("ITEM_ID", item.itemId)
	clone:SetAttribute("RARITY", item.rarity)
	clone:SetAttribute("CATEGORY", item.category)
	clone.Parent = rollScrollingFrame

	setRollCloneInfo(clone, item)

	return clone
end

function DrawRollItemView.UpdateCanvasSize(rollScrollingFrame: ScrollingFrame?)
	if rollScrollingFrame == nil then
		return
	end

	local layout = rollScrollingFrame:FindFirstChildWhichIsA("UIListLayout")

	if layout ~= nil then
		rollScrollingFrame.CanvasSize = UDim2.fromOffset(layout.AbsoluteContentSize.X, 0)
	end
end

function DrawRollItemView.GetTargetCanvasPosition(rollScrollingFrame: ScrollingFrame?, targetClone: GuiObject): Vector2
	if rollScrollingFrame == nil then
		return Vector2.zero
	end

	local targetCenterX = targetClone.AbsolutePosition.X
		- rollScrollingFrame.AbsolutePosition.X
		+ rollScrollingFrame.CanvasPosition.X
		+ (targetClone.AbsoluteSize.X * 0.5)

	local viewportCenterX = rollScrollingFrame.AbsoluteSize.X * 0.5
	local wantedX = math.max(0, targetCenterX - viewportCenterX)

	return Vector2.new(wantedX, rollScrollingFrame.CanvasPosition.Y)
end

function DrawRollItemView.GetTickDistancePixels(
	rollScrollingFrame: ScrollingFrame?,
	targetClone: GuiObject,
	minDistancePixels: number
): number
	local spacing = 0
	if rollScrollingFrame ~= nil then
		local layout = rollScrollingFrame:FindFirstChildWhichIsA("UIListLayout")
		if layout ~= nil then
			spacing = layout.Padding.Offset
		end
	end

	return math.max(minDistancePixels, targetClone.AbsoluteSize.X + spacing)
end

return DrawRollItemView
