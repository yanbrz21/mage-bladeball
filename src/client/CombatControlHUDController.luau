--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local AbilityConfig = require(Config:WaitForChild("AbilityConfig"))
local InventoryItemVisuals = require(script.Parent:WaitForChild("InventoryItemVisuals"))
local MatchConfig = require(Config:WaitForChild("MatchConfig"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local playerScripts = localPlayer:WaitForChild("PlayerScripts")
local clientScripts = playerScripts:WaitForChild("Client")
local ClientEvents = require(clientScripts:WaitForChild("ClientEvents"))

local CombatControlHUDController = {
	Name = "CombatControlHUDController",
	_context = nil :: any?,
}

local mobileAbilities: GuiObject?
local pcAbilities: GuiObject?

local mobileAttackButton: GuiButton?
local mobileAbilityButton: GuiButton?
local jumpButton: GuiButton?
local pcAttackButton: GuiButton?
local pcAbilityButton: GuiButton?

type ButtonVisualDefault = {
	color: Color3?,
	imageColor: Color3?,
	strokeColor: Color3?,
	transparency: number?,
	imageTransparency: number?,
	strokeTransparency: number?,
}

local connections: { any } = {}
local didBuildUI = false
local isAttackHolding = false

local activeMobileActionByInput: { [InputObject]: GuiButton? } = {}
local cooldownEndsAtByName: { [string]: number } = {}
local previousCooldownsByName: { [string]: number } = {}
local buttonScales: { [GuiButton]: UIScale? } = {}
local activeTweens: { [GuiButton]: Tween? } = {}
local readyFlashesByButton: { [GuiButton]: Frame? } = {}
local buttonVisualDefaultsByButton: { [GuiButton]: { [Instance]: ButtonVisualDefault } } = {}
local defaultAbilityIconImagesByButton: { [GuiButton]: string } = {}
local defaultJumpButtonHiddenConnection: RBXScriptConnection?
local defaultJumpButtonListenerActive = false

local PRESS_SCALE = 0.9
local RELEASE_SCALE = 1
local PRESS_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local READY_FLASH_COLOR = Color3.fromRGB(255, 210, 86)

local function getReferenceByTag(tag: string, timeout: number?): Instance?
	local startedAt = os.clock()
	local maxWait = timeout or 10

	while os.clock() - startedAt < maxWait do
		for _, item in CollectionService:GetTagged(tag) do
			if item:IsDescendantOf(playerGui) then
				return item
			end
		end
		task.wait(0.1)
	end

	warn(`[CombatControlHUDController] no tagged player gui item found: {tag}`)
	return nil
end

local function isMobile(): boolean
	return UserInputService.TouchEnabled
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

local function setButtonVisible(button: GuiButton?, visible: boolean)
	if button ~= nil then
		button.Visible = visible
	end
end

local function setButtonEnabled(button: GuiButton?, enabled: boolean)
	if button == nil then
		return
	end
	if button.Interactable then
		button.AutoButtonColor = enabled
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

local function getButtonScale(button: GuiButton): UIScale
	local existing = buttonScales[button]
	if existing ~= nil then
		return existing
	end

	local found = button:FindFirstChild("AbilityButtonScale")
	if found ~= nil and found:IsA("UIScale") then
		buttonScales[button] = found
		return found
	end

	local scale = Instance.new("UIScale")
	scale.Name = "AbilityButtonScale"
	scale.Scale = 1
	scale.Parent = button
	buttonScales[button] = scale
	return scale
end

local function tweenButton(button: GuiButton?, scaleValue: number)
	if button == nil then
		return
	end

	local scale = getButtonScale(button)
	local oldTween = activeTweens[button]
	if oldTween ~= nil then
		oldTween:Cancel()
	end

	local tweenInfo = if scaleValue < 1 then PRESS_TWEEN else RELEASE_TWEEN
	local tween = TweenService:Create(scale, tweenInfo, { Scale = scaleValue })
	activeTweens[button] = tween
	tween:Play()
end

local function getButtonVisualDefaults(button: GuiButton): { [Instance]: ButtonVisualDefault }
	local existing = buttonVisualDefaultsByButton[button]
	if existing ~= nil then
		return existing
	end

	local defaults: { [Instance]: ButtonVisualDefault } = {}
	local function getData(instance: Instance): ButtonVisualDefault
		local data = defaults[instance]
		if data == nil then
			data = {}
			defaults[instance] = data
		end

		return data
	end

	local function captureImageLabel(instance: ImageLabel)
		local data = getData(instance)
		data.imageColor = instance.ImageColor3
		data.imageTransparency = instance.ImageTransparency
	end

	local function captureImageButton(instance: ImageButton)
		local data = getData(instance)
		data.imageColor = instance.ImageColor3
		data.imageTransparency = instance.ImageTransparency
	end

	local function capture(instance: Instance)
		if instance:IsA("GuiObject") then
			local data = getData(instance)
			data.color = instance.BackgroundColor3
			data.transparency = instance.BackgroundTransparency
		end

		if instance:IsA("ImageLabel") then
			captureImageLabel(instance)
		elseif instance:IsA("ImageButton") then
			captureImageButton(instance)
		elseif instance:IsA("UIStroke") then
			local data = getData(instance)
			data.strokeColor = instance.Color
			data.strokeTransparency = instance.Transparency
		end
	end

	capture(button)
	for _, descendant in button:GetDescendants() do
		if
			descendant.Name == "Background"
			or descendant.Name == "Icon"
			or descendant:IsA("UIStroke")
			or descendant:IsA("ImageLabel")
			or descendant:IsA("ImageButton")
		then
			capture(descendant)
		end
	end

	buttonVisualDefaultsByButton[button] = defaults
	return defaults
end

local function setButtonCooldownVisualState(button: GuiButton?, isCoolingDown: boolean)
	if button == nil then
		return
	end

	local defaults = getButtonVisualDefaults(button)
	for instance, data in defaults do
		if instance.Parent == nil then
			continue
		end

		if instance:IsA("GuiObject") and data.color ~= nil and data.transparency ~= nil then
			if isCoolingDown then
				instance.BackgroundColor3 = Color3.fromRGB(92, 96, 104)
				instance.BackgroundTransparency = math.max(data.transparency, 0.28)
			else
				instance.BackgroundColor3 = data.color
				instance.BackgroundTransparency = data.transparency
			end
		end

		local function applyImageLabelCooling(imageInstance: ImageLabel)
			if isCoolingDown then
				imageInstance.ImageColor3 = Color3.fromRGB(150, 154, 162)
				imageInstance.ImageTransparency = math.max(data.imageTransparency or 0, 0.28)
			else
				imageInstance.ImageColor3 = data.imageColor :: Color3
				if data.imageTransparency ~= nil then
					imageInstance.ImageTransparency = data.imageTransparency
				end
			end
		end

		local function applyImageButtonCooling(imageInstance: ImageButton)
			if isCoolingDown then
				imageInstance.ImageColor3 = Color3.fromRGB(150, 154, 162)
				imageInstance.ImageTransparency = math.max(data.imageTransparency or 0, 0.28)
			else
				imageInstance.ImageColor3 = data.imageColor :: Color3
				if data.imageTransparency ~= nil then
					imageInstance.ImageTransparency = data.imageTransparency
				end
			end
		end

		if instance:IsA("ImageLabel") and data.imageColor ~= nil then
			applyImageLabelCooling(instance)
		elseif instance:IsA("ImageButton") and data.imageColor ~= nil then
			applyImageButtonCooling(instance)
		elseif instance:IsA("UIStroke") and data.strokeColor ~= nil and data.strokeTransparency ~= nil then
			if isCoolingDown then
				instance.Color = Color3.fromRGB(122, 126, 134)
				instance.Transparency = math.max(data.strokeTransparency, 0.28)
			else
				instance.Color = data.strokeColor
				instance.Transparency = data.strokeTransparency
			end
		end
	end
end

local function getButtonMaxZIndex(button: GuiButton): number
	local maxZIndex = button.ZIndex
	for _, descendant in button:GetDescendants() do
		if descendant:IsA("GuiObject") and descendant.Name ~= "CooldownReadyFlash" then
			maxZIndex = math.max(maxZIndex, descendant.ZIndex)
		end
	end

	return maxZIndex
end

local function getReadyFlash(button: GuiButton): Frame
	local existing = readyFlashesByButton[button]
	if existing ~= nil then
		existing.ZIndex = getButtonMaxZIndex(button) + 1
		return existing
	end

	local flash = button:FindFirstChild("CooldownReadyFlash")
	if flash ~= nil and flash:IsA("Frame") then
		flash.ZIndex = getButtonMaxZIndex(button) + 1
		readyFlashesByButton[button] = flash
		return flash
	end

	local createdFlash = Instance.new("Frame")
	createdFlash.Name = "CooldownReadyFlash"
	createdFlash.BackgroundColor3 = READY_FLASH_COLOR
	createdFlash.BackgroundTransparency = 1
	createdFlash.BorderSizePixel = 0
	createdFlash.Size = UDim2.fromScale(1, 1)
	createdFlash.ZIndex = getButtonMaxZIndex(button) + 1
	createdFlash.Parent = button

	local background = button:FindFirstChild("Background")
	local corner = if background ~= nil then background:FindFirstChildWhichIsA("UICorner") else nil
	if corner == nil then
		corner = button:FindFirstChildWhichIsA("UICorner", true)
	end
	if corner ~= nil then
		local clonedCorner = corner:Clone()
		clonedCorner.Parent = createdFlash
	end

	readyFlashesByButton[button] = createdFlash
	return createdFlash
end

local function playReadyFlash(button: GuiButton?)
	if button == nil then
		return
	end

	local flash = getReadyFlash(button)
	flash.BackgroundTransparency = 0.12
	TweenService
		:Create(
			flash,
			TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }
		)
		:Play()

	local scale = getButtonScale(button)
	scale.Scale = 1.08
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()

	local stroke = button:FindFirstChildWhichIsA("UIStroke", true)
	if stroke ~= nil then
		local originalColor = stroke.Color
		local originalTransparency = stroke.Transparency
		stroke.Color = READY_FLASH_COLOR
		stroke.Transparency = math.min(originalTransparency, 0.08)
		TweenService:Create(
			stroke,
			TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Color = originalColor, Transparency = originalTransparency }
		):Play()
	end
end

local function getMatchState(): string
	local value = Shared:GetAttribute("MatchState")
	if typeof(value) == "string" then
		return value
	end
	return MatchConfig.MatchStates.WaitingForPlayers
end

local function isRoundRunning(): boolean
	return getMatchState() == MatchConfig.MatchStates.RoundRunning
end

local function getHudCooldown(abilityName: string): number
	local context = CombatControlHUDController._context
	if context == nil then
		return 0
	end

	local hudController = context.Controllers.HUDController
	if hudController == nil then
		return 0
	end

	local hudState = hudController:GetState()
	local cooldown = hudState.cooldowns[abilityName]

	if typeof(cooldown) ~= "number" then
		return 0
	end
	return math.max(0, cooldown)
end

local function getSecondsRemaining(abilityName: string): number
	local hudCooldown = getHudCooldown(abilityName)
	if hudCooldown > 0 then
		return hudCooldown
	end

	local endsAt = cooldownEndsAtByName[abilityName]
	if endsAt == nil then
		return 0
	end

	return math.max(0, endsAt - Workspace:GetServerTimeNow())
end

local function getEquippedAbilityConfig(): any?
	local context = CombatControlHUDController._context
	if context == nil then
		return nil
	end

	local abilityController = context.Controllers.AbilityController
	if abilityController == nil or abilityController.GetEquippedAbilityConfig == nil then
		return nil
	end

	return abilityController:GetEquippedAbilityConfig()
end

local function setButtonTitle(button: GuiButton?, text: string)
	if button == nil then
		return
	end

	local titleLabel = button:FindFirstChild("TITLE", true)
		or button:FindFirstChild("Title", true)
		or button:FindFirstChild("LABEL", true)
		or button:FindFirstChild("Label", true)
		or button:FindFirstChild("NAME", true)
		or button:FindFirstChild("Name", true)

	if titleLabel ~= nil and titleLabel:IsA("TextLabel") then
		titleLabel.Text = text
	elseif button:IsA("TextButton") then
		button.Text = text
	end
end

local function findButtonIconImage(button: GuiButton): (ImageLabel | ImageButton)?
	local namedIcon = button:FindFirstChild("Icon", true)
	if namedIcon ~= nil and namedIcon:IsA("ImageLabel") then
		return namedIcon
	elseif namedIcon ~= nil and namedIcon:IsA("ImageButton") then
		return namedIcon
	end

	for _, descendant in button:GetDescendants() do
		if descendant.Name == "Background" or descendant.Name == "CooldownReadyFlash" then
			continue
		end

		if descendant:IsA("ImageLabel") then
			return descendant
		elseif descendant:IsA("ImageButton") then
			return descendant
		end
	end

	if button:IsA("ImageButton") then
		return button
	end

	return nil
end

local function setButtonIcon(button: GuiButton?, iconAssetId: string?)
	if button == nil then
		return
	end

	local iconImage = findButtonIconImage(button)
	if iconImage == nil then
		return
	end

	if defaultAbilityIconImagesByButton[button] == nil then
		if iconImage:IsA("ImageLabel") then
			defaultAbilityIconImagesByButton[button] = iconImage.Image
		elseif iconImage:IsA("ImageButton") then
			defaultAbilityIconImagesByButton[button] = iconImage.Image
		end
	end

	local resolvedIconAssetId = defaultAbilityIconImagesByButton[button]
	if type(iconAssetId) == "string" and iconAssetId ~= "" then
		resolvedIconAssetId = iconAssetId
	end

	if iconImage:IsA("ImageLabel") then
		iconImage.Image = resolvedIconAssetId
	elseif iconImage:IsA("ImageButton") then
		iconImage.Image = resolvedIconAssetId
	end
end

local function getAbilityIconAssetId(abilityId: string?): string?
	if type(abilityId) ~= "string" or abilityId == "" then
		return nil
	end

	return InventoryItemVisuals.GetIconAssetId("Ability", abilityId)
end

local function updateExtraAbilityDisplay()
	local abilityData = getEquippedAbilityConfig()
	if abilityData == nil or typeof(abilityData.DisplayName) ~= "string" then
		return
	end

	setButtonTitle(mobileAbilityButton, abilityData.DisplayName)
	setButtonTitle(pcAbilityButton, abilityData.DisplayName)
	local iconAssetId = getAbilityIconAssetId(abilityData.Id)
	setButtonIcon(mobileAbilityButton, iconAssetId)
	setButtonIcon(pcAbilityButton, iconAssetId)
end

local function hideOldMobileControls()
	local oldGui = playerGui:FindFirstChild("SwordnWizardMobileControls")
	if oldGui ~= nil then
		oldGui:Destroy()
	end

	local legacyGui = playerGui:FindFirstChild("SwordnWizardTouchControls")
	if legacyGui ~= nil then
		legacyGui:Destroy()
	end
end

local function hideDefaultJumpButton()
	if defaultJumpButtonHiddenConnection ~= nil then
		return
	end

	local function tryHide(): boolean
		local touchGui = playerGui:FindFirstChild("TouchGui")
		if touchGui == nil then
			return false
		end

		local controlFrame = touchGui:FindFirstChild("TouchControlFrame")
		if controlFrame == nil then
			return false
		end

		local robloxJumpButton = controlFrame:FindFirstChild("JumpButton")
		if robloxJumpButton == nil or not robloxJumpButton:IsA("GuiObject") then
			return false
		end

		robloxJumpButton.Visible = false

		defaultJumpButtonHiddenConnection = robloxJumpButton:GetPropertyChangedSignal("Visible"):Connect(function()
			if robloxJumpButton.Visible then
				robloxJumpButton.Visible = false
			end
		end)
		table.insert(connections, defaultJumpButtonHiddenConnection :: RBXScriptConnection)

		return true
	end

	if tryHide() then
		return
	end

	if defaultJumpButtonListenerActive then
		return
	end

	defaultJumpButtonListenerActive = true

	local listenerConnection: RBXScriptConnection? = nil
	listenerConnection = playerGui.DescendantAdded:Connect(function(descendant)
		if descendant.Name ~= "JumpButton" then
			return
		end

		if tryHide() and listenerConnection ~= nil then
			listenerConnection:Disconnect()
			listenerConnection = nil
			defaultJumpButtonListenerActive = false
		end
	end)

	table.insert(connections, listenerConnection :: RBXScriptConnection)
end

local function refreshLayout()
	hideOldMobileControls()
	hideDefaultJumpButton()

	local mobile = isMobile()
	local roundRunning = isRoundRunning()

	setGuiVisible(mobileAbilities, mobile)
	setGuiVisible(pcAbilities, not mobile)

	setButtonVisible(jumpButton, mobile)
	setButtonVisible(mobileAttackButton, mobile)
	setButtonVisible(mobileAbilityButton, mobile)

	setButtonVisible(pcAttackButton, not mobile)
	setButtonVisible(pcAbilityButton, not mobile)

	if not roundRunning then
		isAttackHolding = false
		tweenButton(mobileAttackButton, RELEASE_SCALE)
		tweenButton(pcAttackButton, RELEASE_SCALE)
	end
end

local function updateButtonCooldownVisual(button: GuiButton?, abilityName: string)
	if button == nil then
		return
	end

	local secondsRemaining = getSecondsRemaining(abilityName)
	local isReady = secondsRemaining <= 0.05
	local previousCooldown = previousCooldownsByName[abilityName]

	if abilityName == "Fireball" then
		setButtonEnabled(button, true)
		setButtonCooldownVisualState(button, false)

		local fireballCooldownLabel = button:FindFirstChild("COOLDOWN", true)
		if fireballCooldownLabel ~= nil and fireballCooldownLabel:IsA("TextLabel") then
			fireballCooldownLabel.Visible = false
			fireballCooldownLabel.Text = ""
		end

		previousCooldownsByName[abilityName] = secondsRemaining
		return
	end

	setButtonEnabled(button, isReady)
	setButtonCooldownVisualState(button, not isReady)

	local cooldownLabel = button:FindFirstChild("COOLDOWN", true)
	if cooldownLabel ~= nil and cooldownLabel:IsA("TextLabel") then
		cooldownLabel.Visible = not isReady
		cooldownLabel.Text = if isReady then "" else string.format("%.1f", secondsRemaining)
	end

	if previousCooldown ~= nil and previousCooldown > 0.05 and isReady then
		setButtonCooldownVisualState(button, false)
		playReadyFlash(button)
	end

	previousCooldownsByName[abilityName] = secondsRemaining
end

local function playExtraAbilityReadyFeedback()
	previousCooldownsByName[AbilityConfig.ExtraSlotCooldownName] = 0

	setButtonEnabled(mobileAbilityButton, true)
	setButtonEnabled(pcAbilityButton, true)
	setButtonCooldownVisualState(mobileAbilityButton, false)
	setButtonCooldownVisualState(pcAbilityButton, false)
	playReadyFlash(mobileAbilityButton)
	playReadyFlash(pcAbilityButton)
end

local function emitInputAction(context: any, actionName: string)
	local inputController = context.Controllers.InputController
	if inputController == nil then
		return
	end
	inputController:EmitAction(actionName, "CustomAbilityButton")
end

local function pressAttack(context: any)
	if isAttackHolding then
		return
	end
	if not isRoundRunning() then
		return
	end
	tweenButton(mobileAttackButton, PRESS_SCALE)
	tweenButton(pcAttackButton, PRESS_SCALE)

	isAttackHolding = true
	emitInputAction(context, "FireballPressed")
end

local function releaseAttack(context: any)
	if not isAttackHolding then
		tweenButton(mobileAttackButton, RELEASE_SCALE)
		tweenButton(pcAttackButton, RELEASE_SCALE)
		return
	end

	isAttackHolding = false
	tweenButton(mobileAttackButton, RELEASE_SCALE)
	tweenButton(pcAttackButton, RELEASE_SCALE)
	emitInputAction(context, "FireballReleased")
end

local function getInputScreenPosition(input: InputObject): Vector2
	return Vector2.new(input.Position.X, input.Position.Y)
end

local function isActionInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1
end

local function isScreenPositionInsideButton(button: GuiButton?, screenPosition: Vector2): boolean
	if button == nil or not button.Visible then
		return false
	end

	local absolutePosition = button.AbsolutePosition
	local absoluteSize = button.AbsoluteSize
	return screenPosition.X >= absolutePosition.X
		and screenPosition.X <= absolutePosition.X + absoluteSize.X
		and screenPosition.Y >= absolutePosition.Y
		and screenPosition.Y <= absolutePosition.Y + absoluteSize.Y
end

local function getMobileActionButtonAtPosition(screenPosition: Vector2): GuiButton?
	if not isMobile() then
		return nil
	end

	if mobileAbilities == nil or not mobileAbilities.Visible then
		return nil
	end

	if isScreenPositionInsideButton(mobileAttackButton, screenPosition) then
		return mobileAttackButton
	end
	if isScreenPositionInsideButton(mobileAbilityButton, screenPosition) then
		return mobileAbilityButton
	end
	if isScreenPositionInsideButton(jumpButton, screenPosition) then
		return jumpButton
	end

	return nil
end

local function requestExtraAbility(context: any)
	if not isRoundRunning() then
		return
	end

	tweenButton(mobileAbilityButton, PRESS_SCALE)
	tweenButton(pcAbilityButton, PRESS_SCALE)

	task.delay(0.1, function()
		tweenButton(mobileAbilityButton, RELEASE_SCALE)
		tweenButton(pcAbilityButton, RELEASE_SCALE)
	end)

	emitInputAction(context, "AbilityPressed")
end

local function bindDeviceInputFeedback(context: any)
	local inputController = context.Controllers.InputController
	if inputController == nil or inputController.ConnectAction == nil or inputController.ActionNames == nil then
		return
	end

	local actionNames = inputController.ActionNames
	table.insert(
		connections,
		inputController:ConnectAction(actionNames.AbilityPressed, function(inputSource)
			if inputSource == "CustomAbilityButton" then
				return
			end

			tweenButton(mobileAbilityButton, PRESS_SCALE)
			tweenButton(pcAbilityButton, PRESS_SCALE)
			task.delay(0.1, function()
				tweenButton(mobileAbilityButton, RELEASE_SCALE)
				tweenButton(pcAbilityButton, RELEASE_SCALE)
			end)
		end)
	)

	table.insert(
		connections,
		inputController:ConnectAction(actionNames.FireballPressed, function(inputSource)
			if inputSource == "CustomAbilityButton" then
				return
			end

			tweenButton(mobileAttackButton, PRESS_SCALE)
			tweenButton(pcAttackButton, PRESS_SCALE)
		end)
	)

	table.insert(
		connections,
		inputController:ConnectAction(actionNames.FireballReleased, function(inputSource)
			if inputSource == "CustomAbilityButton" then
				return
			end

			tweenButton(mobileAttackButton, RELEASE_SCALE)
			tweenButton(pcAttackButton, RELEASE_SCALE)
		end)
	)
end

local function requestJump(context: any)
	tweenButton(jumpButton, PRESS_SCALE)

	task.delay(0.1, function()
		tweenButton(jumpButton, RELEASE_SCALE)
	end)

	local combatController = context.Controllers.CombatController
	if combatController ~= nil and combatController.RequestJump ~= nil then
		combatController:RequestJump()
		return
	end

	local character = localPlayer.Character
	if character == nil then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		humanoid.Jump = true
	end
end

local function handleMobileActionBegan(context: any, input: InputObject)
	if not isActionInput(input) then
		return
	end

	local button = getMobileActionButtonAtPosition(getInputScreenPosition(input))
	if button == nil then
		return
	end

	activeMobileActionByInput[input] = button

	if mobileAttackButton ~= nil and button == mobileAttackButton then
		pressAttack(context)
	elseif mobileAbilityButton ~= nil and button == mobileAbilityButton then
		requestExtraAbility(context)
	elseif jumpButton ~= nil and button == jumpButton then
		requestJump(context)
	end
end

local function handleMobileActionEnded(context: any, input: InputObject)
	local button = activeMobileActionByInput[input]
	if button == nil then
		return
	end

	activeMobileActionByInput[input] = nil

	if mobileAttackButton ~= nil and button == mobileAttackButton then
		releaseAttack(context)
	elseif
		(mobileAbilityButton ~= nil and button == mobileAbilityButton) or (jumpButton ~= nil and button == jumpButton)
	then
		tweenButton(button, RELEASE_SCALE)
	end
end

local function bindMobileActionInput(context: any)
	table.insert(
		connections,
		UserInputService.InputBegan:Connect(function(input: InputObject)
			handleMobileActionBegan(context, input)
		end)
	)

	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input: InputObject)
			handleMobileActionEnded(context, input)
		end)
	)
end

local function bindClickButton(button: GuiButton?, callback: () -> ())
	if button == nil then
		return
	end

	table.insert(connections, button.Activated:Connect(callback))

	table.insert(
		connections,
		button.InputBegan:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				tweenButton(button, PRESS_SCALE)
			end
		end)
	)

	table.insert(
		connections,
		button.InputEnded:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				tweenButton(button, RELEASE_SCALE)
			end
		end)
	)

	table.insert(
		connections,
		button.MouseLeave:Connect(function()
			tweenButton(button, RELEASE_SCALE)
		end)
	)
end

local function bindHoldButton(button: GuiButton?, onPressed: () -> (), onReleased: () -> ())
	if button == nil then
		return
	end

	if button:IsA("TextButton") or button:IsA("ImageButton") then
		table.insert(
			connections,
			button.MouseButton1Down:Connect(function()
				onPressed()
			end)
		)

		table.insert(
			connections,
			button.MouseButton1Up:Connect(function()
				onReleased()
			end)
		)
	end

	table.insert(
		connections,
		button.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch then
				onPressed()
			end
		end)
	)

	table.insert(
		connections,
		button.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch then
				onReleased()
			end
		end)
	)

	table.insert(
		connections,
		button.MouseLeave:Connect(function()
			onReleased()
		end)
	)
end

function CombatControlHUDController:Init(context)
	if self._didInit then
		return
	end
	self._didInit = true
	self._context = context
	self._localPlayer = localPlayer
	self._connections = connections
end

function CombatControlHUDController:GetReferences()
	mobileAbilities = getReferenceByTag("MOBILE_ABILITIES") :: GuiObject?
	pcAbilities = getReferenceByTag("PC_ABILITIES") :: GuiObject?

	if mobileAbilities == nil then
		warn("[CombatControlHUDController] MOBILE_ABILITIES not found")
		return
	end

	if pcAbilities == nil then
		warn("[CombatControlHUDController] PC_ABILITIES not found")
	end

	preventGuiResetOnSpawn(mobileAbilities)
	preventGuiResetOnSpawn(pcAbilities)

	local foundMobileAttack = mobileAbilities:FindFirstChild("ATTACK", true)
	local foundMobileAbility = mobileAbilities:FindFirstChild("ABILITY", true)
	local foundJump = mobileAbilities:FindFirstChild("JUMP", true)

	if foundMobileAttack ~= nil and foundMobileAttack:IsA("GuiButton") then
		mobileAttackButton = foundMobileAttack
	else
		warn("[CombatControlHUDController] MOBILE_ABILITIES.ATTACK not found or not GuiButton")
	end

	if foundMobileAbility ~= nil and foundMobileAbility:IsA("GuiButton") then
		mobileAbilityButton = foundMobileAbility
	else
		warn("[CombatControlHUDController] MOBILE_ABILITIES.ABILITY not found or not GuiButton")
	end

	if foundJump ~= nil and foundJump:IsA("GuiButton") then
		jumpButton = foundJump
	else
		warn("[CombatControlHUDController] MOBILE_ABILITIES.JUMP not found or not GuiButton")
	end

	if pcAbilities ~= nil then
		local foundPcAttack = pcAbilities:FindFirstChild("ATTACK", true)
		local foundPcAbility = pcAbilities:FindFirstChild("ABILITY", true)

		if foundPcAttack ~= nil and foundPcAttack:IsA("GuiButton") then
			pcAttackButton = foundPcAttack
		else
			warn("[CombatControlHUDController] PC_ABILITIES.ATTACK not found or not GuiButton")
		end

		if foundPcAbility ~= nil and foundPcAbility:IsA("GuiButton") then
			pcAbilityButton = foundPcAbility
		else
			warn("[CombatControlHUDController] PC_ABILITIES.ABILITY not found or not GuiButton")
		end
	end
end

function CombatControlHUDController:BuildUI()
	if didBuildUI then
		refreshLayout()
		return
	end

	didBuildUI = true
	self:GetReferences()

	refreshLayout()

	bindHoldButton(pcAttackButton, function()
		pressAttack(self._context)
	end, function()
		releaseAttack(self._context)
	end)

	bindClickButton(pcAbilityButton, function()
		requestExtraAbility(self._context)
	end)

	bindMobileActionInput(self._context)
	bindDeviceInputFeedback(self._context)
	table.insert(
		connections,
		ClientEvents.Connect(ClientEvents.Names.AbilityCooldownReady, function()
			playExtraAbilityReadyFeedback()
		end)
	)

	table.insert(
		connections,
		Shared:GetAttributeChangedSignal("MatchState"):Connect(function()
			if not isRoundRunning() then
				releaseAttack(self._context)
			end
			refreshLayout()
		end)
	)

	table.insert(connections, UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(refreshLayout))

	table.insert(
		connections,
		localPlayer.CharacterAdded:Connect(function()
			isAttackHolding = false
			activeMobileActionByInput = {}
			task.defer(function()
				if defaultJumpButtonHiddenConnection ~= nil then
					defaultJumpButtonHiddenConnection:Disconnect()
					defaultJumpButtonHiddenConnection = nil
				end
				self:GetReferences()
				refreshLayout()
			end)
		end)
	)
end

function CombatControlHUDController:StartCooldown(abilityName: string, cooldownSeconds: number)
	cooldownEndsAtByName[abilityName] = Workspace:GetServerTimeNow() + cooldownSeconds
end

function CombatControlHUDController:ShowCooldownNotice(_abilityName: string, _secondsRemaining: number)
	return
end

function CombatControlHUDController:Update()
	refreshLayout()
	updateExtraAbilityDisplay()

	updateButtonCooldownVisual(mobileAbilityButton, AbilityConfig.ExtraSlotCooldownName)
	updateButtonCooldownVisual(pcAbilityButton, AbilityConfig.ExtraSlotCooldownName)
	updateButtonCooldownVisual(mobileAttackButton, "Fireball")
	updateButtonCooldownVisual(pcAttackButton, "Fireball")
end

function CombatControlHUDController:Start()
	if self._didStart then
		return
	end

	self._didStart = true
	self:BuildUI()

	table.insert(
		connections,
		RunService.RenderStepped:Connect(function()
			self:Update()
		end)
	)
end

return CombatControlHUDController
