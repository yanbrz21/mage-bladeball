--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

type ShowOptions = {
	abilityId: string,
	bodyText: string,
	cost: number,
	currentLevel: number,
	displayName: string,
	fragments: number,
	onConfirm: (string) -> (),
}

local ROOT_TAG = "INVENTORY_UPGRADE_CONFIRM"
local TITLE_TAG = "INVENTORY_UPGRADE_CONFIRM_TITLE"
local BODY_TAG = "INVENTORY_UPGRADE_CONFIRM_BODY"
local COST_TAG = "INVENTORY_UPGRADE_CONFIRM_COST"
local CONFIRM_TAG = "INVENTORY_UPGRADE_CONFIRM_CONFIRM"
local CANCEL_TAG = "INVENTORY_UPGRADE_CONFIRM_CANCEL"

local CONNECTED_ATTRIBUTE = "ParabellumUpgradeConfirmConnected"

local screenGui: ScreenGui?
local titleLabel: TextLabel?
local bodyLabel: TextLabel?
local costLabel: TextLabel?
local confirmButton: GuiButton?
local cancelButton: GuiButton?
local panelFrame: GuiObject?
local pendingAbilityId: string?
local pendingConfirm: ((string) -> ())?

local InventoryUpgradeConfirm = {}

local function getTaggedPlayerGuiInstance(tag: string): Instance?
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsDescendantOf(playerGui) then
			return instance
		end
	end

	return nil
end

local function waitForTaggedPlayerGuiInstance(tag: string, timeout: number): Instance?
	local startedAt = os.clock()
	local instance = getTaggedPlayerGuiInstance(tag)

	while instance == nil and os.clock() - startedAt < timeout do
		task.wait(0.1)
		instance = getTaggedPlayerGuiInstance(tag)
	end

	if instance == nil then
		warn(`[InventoryUpgradeConfirm] missing tagged PlayerGui instance: {tag}`)
	end

	return instance
end

local function getButtonTextLabel(button: GuiButton?): TextLabel?
	if button == nil then
		return nil
	end

	local count = button:FindFirstChild("Count", true)
	if count ~= nil and count:IsA("TextLabel") then
		return count
	end

	return nil
end

local function setButtonText(button: GuiButton?, text: string)
	local count = getButtonTextLabel(button)
	if count ~= nil then
		count.Text = text
	elseif button ~= nil and button:IsA("TextButton") then
		button.Text = text
	end
end

local function findPanel(root: ScreenGui): GuiObject?
	local backdrop = root:FindFirstChild("Backdrop")
	if backdrop ~= nil then
		local panel = backdrop:FindFirstChild("Main") or backdrop:FindFirstChild("Panel")
		if panel ~= nil and panel:IsA("GuiObject") then
			return panel
		end
	end

	local panel = root:FindFirstChild("Main", true) or root:FindFirstChild("Panel", true)
	if panel ~= nil and panel:IsA("GuiObject") then
		return panel
	end

	return nil
end

local function refreshLayout()
	local panel = panelFrame
	if panel == nil then
		return
	end

	local viewportSize = workspace.CurrentCamera ~= nil and workspace.CurrentCamera.ViewportSize
		or Vector2.new(1280, 720)
	local isCompact = viewportSize.X < 760 or viewportSize.Y < 520

	panel.Size = if isCompact then UDim2.fromScale(0.82, 0.42) else UDim2.fromScale(0.38, 0.44)

	local scale = panel:FindFirstChild("Scale")
	if scale ~= nil and scale:IsA("UIScale") then
		scale.Scale = if isCompact then 0.94 else 1
	end
end

local function connectButton(button: GuiButton?, callback: () -> ())
	if button == nil or button:GetAttribute(CONNECTED_ATTRIBUTE) == true then
		return
	end

	button:SetAttribute(CONNECTED_ATTRIBUTE, true)
	button.Active = true
	button.AutoButtonColor = true
	button.Selectable = true
	button.Interactable = true
	button.Activated:Connect(callback)
end

local function ensureGui(): boolean
	if screenGui ~= nil then
		return true
	end

	local root = waitForTaggedPlayerGuiInstance(ROOT_TAG, 10)
	if root == nil or not root:IsA("ScreenGui") then
		warn("[InventoryUpgradeConfirm] INVENTORY_UPGRADE_CONFIRM must tag a ScreenGui prefab.")
		return false
	end

	root.ResetOnSpawn = false
	screenGui = root
	panelFrame = findPanel(root)

	local title = waitForTaggedPlayerGuiInstance(TITLE_TAG, 2)
	local body = waitForTaggedPlayerGuiInstance(BODY_TAG, 2)
	local cost = waitForTaggedPlayerGuiInstance(COST_TAG, 2)
	local confirm = waitForTaggedPlayerGuiInstance(CONFIRM_TAG, 2)
	local cancel = waitForTaggedPlayerGuiInstance(CANCEL_TAG, 2)

	titleLabel = if title ~= nil and title:IsA("TextLabel") then title else nil
	bodyLabel = if body ~= nil and body:IsA("TextLabel") then body else nil
	costLabel = if cost ~= nil and cost:IsA("TextLabel") then cost else nil
	confirmButton = if confirm ~= nil and confirm:IsA("GuiButton") then confirm else nil
	cancelButton = if cancel ~= nil and cancel:IsA("GuiButton") then cancel else nil

	if titleLabel == nil or bodyLabel == nil or costLabel == nil or confirmButton == nil or cancelButton == nil then
		warn("[InventoryUpgradeConfirm] prefab is missing one or more required tagged controls.")
		return false
	end

	connectButton(cancelButton, function()
		InventoryUpgradeConfirm.Hide()
	end)

	connectButton(confirmButton, function()
		local abilityId = pendingAbilityId
		local onConfirm = pendingConfirm
		InventoryUpgradeConfirm.Hide()
		if type(abilityId) == "string" and abilityId ~= "" and onConfirm ~= nil then
			onConfirm(abilityId)
		end
	end)

	root.Enabled = false
	return true
end

function InventoryUpgradeConfirm.Hide()
	pendingAbilityId = nil
	pendingConfirm = nil
	if screenGui ~= nil then
		screenGui.Enabled = false
	end
end

function InventoryUpgradeConfirm.Show(options: ShowOptions)
	if not ensureGui() then
		return
	end

	refreshLayout()

	if titleLabel ~= nil then
		titleLabel.Text = `UPGRADE {string.upper(options.displayName)}`
	end

	if bodyLabel ~= nil then
		bodyLabel.Text = options.bodyText
	end

	if costLabel ~= nil then
		costLabel.Text = `Cost: {options.cost} fragments    Owned: {options.fragments}`
	end

	setButtonText(confirmButton, `UPGRADE TO LV {options.currentLevel + 1}`)
	setButtonText(cancelButton, "CANCEL")

	pendingAbilityId = options.abilityId
	pendingConfirm = options.onConfirm
	if screenGui ~= nil then
		screenGui.Enabled = true
	end
end

return table.freeze(InventoryUpgradeConfirm)
