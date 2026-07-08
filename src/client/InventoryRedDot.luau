--!strict

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local InventoryRedDot = {}
InventoryRedDot.__index = InventoryRedDot

type RedDotDeps = {
	network: Instance,
	remotes: any,
	getSnapshot: () -> any?,
	getAbilityUpgradeCost: (string) -> number?,
	getAbilityFragments: (string) -> number,
	abilityCategory: string,
	weaponSkinCategory: string,
}

type ShakeState = {
	token: number,
	originalRotation: number,
	scale: UIScale,
	originalScale: number,
	activeTween: Tween?,
}

export type Controller = typeof(setmetatable(
	{} :: {
		_deps: RedDotDeps,
		_shakeStates: { [Instance]: ShakeState },
	},
	InventoryRedDot
))

local function getInventoryItemKey(category: string, itemId: string): string
	return `{category}:{itemId}`
end

local function setRedDotVisible(parent: GuiObject?, visible: boolean)
	if parent == nil then
		return
	end

	local dot = parent:FindFirstChild("InventoryRedDot")
	if dot == nil and visible then
		local created = Instance.new("Frame")
		created.Name = "InventoryRedDot"
		created.AnchorPoint = Vector2.new(0.5, 0.5)
		created.Position = UDim2.new(1, -7, 0, 7)
		created.Size = UDim2.fromOffset(14, 14)
		created.BackgroundColor3 = Color3.fromRGB(235, 48, 64)
		created.BorderSizePixel = 0
		created.Active = false
		created.Selectable = false
		created.Interactable = false
		created.ZIndex = parent.ZIndex + 20
		created.Parent = parent

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = created

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 242, 242)
		stroke.Thickness = 1.5
		stroke.Parent = created

		dot = created
	end

	if dot ~= nil and dot:IsA("GuiObject") then
		dot.Visible = visible
	end
end

function InventoryRedDot.new(deps: RedDotDeps): Controller
	return setmetatable({
		_deps = deps,
		_shakeStates = {},
	}, InventoryRedDot)
end

function InventoryRedDot:_stopShake(button: GuiObject)
	local states = self._shakeStates
	local state = states[button]
	if state == nil then
		return
	end

	state.token += 1
	if state.activeTween ~= nil then
		state.activeTween:Cancel()
		state.activeTween = nil
	end
	button.Rotation = state.originalRotation
	state.scale.Scale = state.originalScale
	states[button] = nil
end

function InventoryRedDot:_stopShakeForEntry(entry: GuiObject)
	for target in self._shakeStates do
		if target == entry or target:IsDescendantOf(entry) then
			self:_stopShake(target :: GuiObject)
		end
	end
end

function InventoryRedDot:_playShakeTween(
	button: GuiObject,
	state: ShakeState,
	rotation: number,
	scale: number,
	duration: number
)
	if state.activeTween ~= nil then
		state.activeTween:Cancel()
	end

	local tween = TweenService:Create(
		button,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Rotation = rotation }
	)
	local scaleTween = TweenService:Create(
		state.scale,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = scale }
	)
	state.activeTween = tween
	tween:Play()
	scaleTween:Play()
	tween.Completed:Wait()
	if state.activeTween == tween then
		state.activeTween = nil
	end
end

function InventoryRedDot:_getAttentionTarget(entry: GuiObject): GuiObject
	local icon = entry:FindFirstChild("Icon", true)
	if icon ~= nil and icon:IsA("GuiObject") then
		return icon
	end

	return entry
end

function InventoryRedDot:_getOrCreateShakeScale(target: GuiObject): UIScale
	local existing = target:FindFirstChild("InventoryAttentionScale")
	if existing ~= nil and existing:IsA("UIScale") then
		return existing
	end

	local scale = Instance.new("UIScale")
	scale.Name = "InventoryAttentionScale"
	scale.Scale = 1
	scale.Parent = target
	return scale
end

function InventoryRedDot:_ensureShake(entry: GuiObject)
	local button = self:_getAttentionTarget(entry)
	local states = self._shakeStates
	if states[button] ~= nil then
		return
	end

	local scale = self:_getOrCreateShakeScale(button)
	local state: ShakeState = {
		token = 0,
		originalRotation = button.Rotation,
		scale = scale,
		originalScale = scale.Scale,
		activeTween = nil,
	}
	states[button] = state

	task.spawn(function()
		local token = state.token
		while states[button] == state and state.token == token and button.Parent ~= nil do
			task.wait(0.5)
			if states[button] ~= state or state.token ~= token or button.Parent == nil then
				break
			end

			local function isActive(): boolean
				return states[button] == state and state.token == token and button.Parent ~= nil
			end

			self:_playShakeTween(button, state, state.originalRotation - 7, state.originalScale * 1.08, 0.06)
			if not isActive() then
				break
			end
			self:_playShakeTween(button, state, state.originalRotation + 7, state.originalScale * 1.12, 0.08)
			if not isActive() then
				break
			end
			self:_playShakeTween(button, state, state.originalRotation - 5, state.originalScale * 1.06, 0.07)
			if not isActive() then
				break
			end
			self:_playShakeTween(button, state, state.originalRotation, state.originalScale, 0.08)
		end

		if states[button] == state then
			self:_stopShake(button)
		end
	end)
end

function InventoryRedDot:IsInventoryItemUnseen(category: string, itemId: string): boolean
	local snapshot = self._deps.getSnapshot()
	if snapshot == nil or type(snapshot.unseenItems) ~= "table" then
		return false
	end

	return snapshot.unseenItems[getInventoryItemKey(category, itemId)] == true
end

function InventoryRedDot:CanUpgradeAbility(abilityId: string): boolean
	local cost = self._deps.getAbilityUpgradeCost(abilityId)
	if cost == nil then
		return false
	end

	local fragments: number = self._deps.getAbilityFragments(abilityId)
	return fragments >= cost
end

function InventoryRedDot:ShouldShowItemBadge(category: string, itemId: string, owned: boolean): boolean
	if not owned then
		return false
	end

	if self:IsInventoryItemUnseen(category, itemId) then
		return true
	end

	return category == self._deps.abilityCategory and self:CanUpgradeAbility(itemId)
end

function InventoryRedDot:SetVisible(parent: GuiObject?, visible: boolean)
	setRedDotVisible(parent, visible)
end

function InventoryRedDot:MarkInventoryItemSeen(category: string, itemId: string)
	if not self:IsInventoryItemUnseen(category, itemId) then
		return
	end

	local snapshot = self._deps.getSnapshot()
	if snapshot ~= nil and type(snapshot.unseenItems) == "table" then
		snapshot.unseenItems[getInventoryItemKey(category, itemId)] = nil
	end

	local remotes = self._deps.remotes
	remotes.GetClientToServer(self._deps.network, remotes.ClientToServer.RequestMarkInventoryItemSeen):FireServer({
		category = category,
		itemId = itemId,
	})
end

function InventoryRedDot:UpdateInventoryEntryBadges(playerGui: Instance, getOwnedItems: (string) -> { string })
	local shouldShow = false
	for _, category in { self._deps.abilityCategory, self._deps.weaponSkinCategory } do
		for _, itemId in getOwnedItems(category) do
			if self:ShouldShowItemBadge(category, itemId, true) then
				shouldShow = true
				break
			end
		end

		if shouldShow then
			break
		end
	end

	for _, instance in CollectionService:GetTagged("INVENTORY_BUTTON") do
		if instance:IsDescendantOf(playerGui) and instance:IsA("GuiObject") then
			setRedDotVisible(instance, shouldShow)
			if shouldShow then
				self:_ensureShake(instance)
			else
				self:_stopShakeForEntry(instance)
			end
		end
	end

	for instance in self._shakeStates do
		if instance:IsA("GuiObject") and not instance:IsDescendantOf(playerGui) then
			self:_stopShake(instance)
		end
	end
end

return InventoryRedDot
