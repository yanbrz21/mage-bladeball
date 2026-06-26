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
local Network = Shared:WaitForChild("Network")

local AbilityConfig = require(Config:WaitForChild("AbilityConfig"))
local MatchConfig = require(Config:WaitForChild("MatchConfig"))
local Remotes = require(Network:WaitForChild("Remotes"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local AbilityController = { Name = "AbilityController" }

local mobileAbilities: GuiObject?
local pcAbilities: GuiObject?

local mobileAttackButton: GuiButton?
local mobileAbilityButton: GuiButton?
local jumpButton: GuiButton?
local pcAttackButton: GuiButton?
local pcAbilityButton: GuiButton?

local requestUseAbilityRemote: RemoteEvent?
local connections: { RBXScriptConnection } = {}
local didBuildUI = false
local isAttackHolding = false

local cooldownEndsAtByName: { [string]: number } = {}
local buttonScales: { [GuiButton]: UIScale } = {}
local activeTweens: { [GuiButton]: Tween } = {}

local PRESS_SCALE = 0.9
local RELEASE_SCALE = 1
local PRESS_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

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

	warn(`[AbilityController] no tagged player gui item found: {tag}`)
	return nil
end

local function isMobile(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function setGuiVisible(instance: Instance?, visible: boolean)
	if instance == nil then return end
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
	if button == nil then return end
	button.Active = enabled
	button.Interactable = enabled
	button.AutoButtonColor = enabled
end

local function getButtonScale(button: GuiButton): UIScale
	local existing = buttonScales[button]
	if existing ~= nil then return existing end

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
	if button == nil then return end

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

local function getMatchState(): string
	local value = Shared:GetAttribute("MatchState")
	if typeof(value) == "string" then return value end
	return MatchConfig.MatchStates.WaitingForPlayers
end

local function isRoundRunning(): boolean
	return getMatchState() == MatchConfig.MatchStates.RoundRunning
end

local function getMoveDirection(): Vector3
	local character = localPlayer.Character
	if character == nil then return Vector3.zero end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then return Vector3.zero end

	return humanoid.MoveDirection
end

local function getCameraLookVector(): Vector3
	local camera = Workspace.CurrentCamera
	if camera == nil then return Vector3.zAxis end
	return camera.CFrame.LookVector
end

local function getRootPosition(): Vector3?
	local character = localPlayer.Character
	if character == nil then return nil end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root.Position
	end

	return nil
end

local function getHudCooldown(abilityName: string): number
	local context = AbilityController._context
	if context == nil then return 0 end

	local hudController = context.Controllers.HUDController
	if hudController == nil then return 0 end

	local hudState = hudController:GetState()
	local cooldown = hudState.cooldowns[abilityName]

	if typeof(cooldown) ~= "number" then return 0 end
	return math.max(0, cooldown)
end

local function getSecondsRemaining(abilityName: string): number
	local hudCooldown = getHudCooldown(abilityName)
	if hudCooldown > 0 then return hudCooldown end

	local endsAt = cooldownEndsAtByName[abilityName]
	if endsAt == nil then return 0 end

	return math.max(0, endsAt - Workspace:GetServerTimeNow())
end

local function hideOldMobileControls()
	local oldGui = playerGui:FindFirstChild("SwordnWizardMobileControls")
	if oldGui ~= nil then oldGui:Destroy() end

	local legacyGui = playerGui:FindFirstChild("SwordnWizardTouchControls")
	if legacyGui ~= nil then legacyGui:Destroy() end
end

local function refreshLayout()
	hideOldMobileControls()

	local mobile = isMobile()
	local roundRunning = isRoundRunning()

	setGuiVisible(mobileAbilities, mobile)
	setGuiVisible(pcAbilities, not mobile)

	setButtonVisible(jumpButton, mobile)
	setButtonVisible(mobileAttackButton, mobile and roundRunning)
	setButtonVisible(mobileAbilityButton, mobile and roundRunning)

	setButtonVisible(pcAttackButton, not mobile)
	setButtonVisible(pcAbilityButton, not mobile)

	if not roundRunning then
		isAttackHolding = false
		tweenButton(mobileAttackButton, RELEASE_SCALE)
		tweenButton(pcAttackButton, RELEASE_SCALE)
	end
end

local function updateButtonCooldownVisual(button: GuiButton?, abilityName: string)
	if button == nil then return end

	local secondsRemaining = getSecondsRemaining(abilityName)
	local isReady = secondsRemaining <= 0.05

	setButtonEnabled(button, isReady)

	local cooldownLabel = button:FindFirstChild("COOLDOWN", true)
	if cooldownLabel ~= nil and cooldownLabel:IsA("TextLabel") then
		cooldownLabel.Visible = not isReady
		cooldownLabel.Text = if isReady then "" else string.format("%.1f", secondsRemaining)
	end
end

local function emitInputAction(context: any, actionName: string)
	local inputController = context.Controllers.InputController
	if inputController == nil then return end
	inputController:EmitAction(actionName, "CustomAbilityButton")
end

local function pressAttack(context: any)
	if isAttackHolding then return end
	if not isRoundRunning() then return end
	if getSecondsRemaining("Fireball") > 0.05 then return end

	isAttackHolding = true
	tweenButton(mobileAttackButton, PRESS_SCALE)
	tweenButton(pcAttackButton, PRESS_SCALE)
	emitInputAction(context, "FireballPressed")
end

local function releaseAttack(context: any)
	if not isAttackHolding then return end

	isAttackHolding = false
	tweenButton(mobileAttackButton, RELEASE_SCALE)
	tweenButton(pcAttackButton, RELEASE_SCALE)
	emitInputAction(context, "FireballReleased")
end

local function requestExtraAbility()
	if requestUseAbilityRemote == nil then return end
	if not isRoundRunning() then return end
	if getSecondsRemaining(AbilityConfig.ExtraSlotCooldownName) > 0.05 then return end

	tweenButton(mobileAbilityButton, PRESS_SCALE)
	tweenButton(pcAbilityButton, PRESS_SCALE)

	task.delay(0.1, function()
		tweenButton(mobileAbilityButton, RELEASE_SCALE)
		tweenButton(pcAbilityButton, RELEASE_SCALE)
	end)

	requestUseAbilityRemote:FireServer({
		moveDirection = getMoveDirection(),
		cameraLookVector = getCameraLookVector(),
		startPosition = getRootPosition(),
	})
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
	if character == nil then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		humanoid.Jump = true
	end
end

local function bindClickButton(button: GuiButton?, callback: () -> ())
	if button == nil then return end

	if button:IsA("TextButton") or button:IsA("ImageButton") then
		table.insert(connections, button.MouseButton1Down:Connect(function()
			tweenButton(button, PRESS_SCALE)
		end))

		table.insert(connections, button.MouseButton1Up:Connect(function()
			tweenButton(button, RELEASE_SCALE)
			callback()
		end))
	end

	table.insert(connections, button.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			tweenButton(button, PRESS_SCALE)
		end
	end))

	table.insert(connections, button.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			tweenButton(button, RELEASE_SCALE)
			callback()
		end
	end))

	table.insert(connections, button.MouseLeave:Connect(function()
		tweenButton(button, RELEASE_SCALE)
	end))
end

local function bindHoldButton(button: GuiButton?, onPressed: () -> (), onReleased: () -> ())
	if button == nil then return end

	if button:IsA("TextButton") or button:IsA("ImageButton") then
		table.insert(connections, button.MouseButton1Down:Connect(function()
			onPressed()
		end))

		table.insert(connections, button.MouseButton1Up:Connect(function()
			onReleased()
		end))
	end

	table.insert(connections, button.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			onPressed()
		end
	end))

	table.insert(connections, button.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			onReleased()
		end
	end))

	table.insert(connections, button.MouseLeave:Connect(function()
		onReleased()
	end))
end

function AbilityController:Init(context)
	if self._didInit then return end
	self._didInit = true
	self._context = context
	self._localPlayer = localPlayer
	self._connections = connections
end

function AbilityController:GetReferences()
	mobileAbilities = getReferenceByTag("MOBILE_ABILITIES") :: GuiObject?
	pcAbilities = getReferenceByTag("PC_ABILITIES") :: GuiObject?

	if mobileAbilities == nil then
		warn("[AbilityController] MOBILE_ABILITIES not found")
		return
	end

	if pcAbilities == nil then
		warn("[AbilityController] PC_ABILITIES not found")
	end

	local foundMobileAttack = mobileAbilities:FindFirstChild("ATTACK", true)
	local foundMobileAbility = mobileAbilities:FindFirstChild("ABILITY", true)
	local foundJump = mobileAbilities:FindFirstChild("JUMP", true)

	if foundMobileAttack ~= nil and foundMobileAttack:IsA("GuiButton") then
		mobileAttackButton = foundMobileAttack
	else
		warn("[AbilityController] MOBILE_ABILITIES.ATTACK not found or not GuiButton")
	end

	if foundMobileAbility ~= nil and foundMobileAbility:IsA("GuiButton") then
		mobileAbilityButton = foundMobileAbility
	else
		warn("[AbilityController] MOBILE_ABILITIES.ABILITY not found or not GuiButton")
	end

	if foundJump ~= nil and foundJump:IsA("GuiButton") then
		jumpButton = foundJump
	else
		warn("[AbilityController] MOBILE_ABILITIES.JUMP not found or not GuiButton")
	end

	if pcAbilities ~= nil then
		local foundPcAttack = pcAbilities:FindFirstChild("ATTACK", true)
		local foundPcAbility = pcAbilities:FindFirstChild("ABILITY", true)

		if foundPcAttack ~= nil and foundPcAttack:IsA("GuiButton") then
			pcAttackButton = foundPcAttack
		else
			warn("[AbilityController] PC_ABILITIES.ATTACK not found or not GuiButton")
		end

		if foundPcAbility ~= nil and foundPcAbility:IsA("GuiButton") then
			pcAbilityButton = foundPcAbility
		else
			warn("[AbilityController] PC_ABILITIES.ABILITY not found or not GuiButton")
		end
	end
end

function AbilityController:BuildUI()
	if didBuildUI then
		refreshLayout()
		return
	end

	didBuildUI = true
	self:GetReferences()

	requestUseAbilityRemote = Remotes.GetClientToServer(Network, Remotes.ClientToServer.RequestUseAbility)

	refreshLayout()

	bindHoldButton(mobileAttackButton, function()
		pressAttack(self._context)
	end, function()
		releaseAttack(self._context)
	end)

	bindHoldButton(pcAttackButton, function()
		pressAttack(self._context)
	end, function()
		releaseAttack(self._context)
	end)

	bindClickButton(mobileAbilityButton, function()
		requestExtraAbility()
	end)

	bindClickButton(pcAbilityButton, function()
		requestExtraAbility()
	end)

	bindClickButton(jumpButton, function()
		requestJump(self._context)
	end)

	table.insert(connections, Shared:GetAttributeChangedSignal("MatchState"):Connect(function()
		if not isRoundRunning() then
			releaseAttack(self._context)
		end
		refreshLayout()
	end))

	table.insert(connections, UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(refreshLayout))
	table.insert(connections, UserInputService:GetPropertyChangedSignal("KeyboardEnabled"):Connect(refreshLayout))

	table.insert(connections, localPlayer.CharacterAdded:Connect(function()
		isAttackHolding = false
		task.defer(refreshLayout)
	end))

	table.insert(connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.LeftShift then
			requestExtraAbility()
		end
	end))
end

function AbilityController:StartCooldown(abilityName: string, cooldownSeconds: number)
	cooldownEndsAtByName[abilityName] = Workspace:GetServerTimeNow() + cooldownSeconds
end

function AbilityController:GetEquippedAbilityConfig()
	local abilityId = localPlayer:GetAttribute("EquippedAbility")

	if typeof(abilityId) ~= "string" or abilityId == "" then
		abilityId = AbilityConfig.DefaultAbilityId
	end

	local abilityData = AbilityConfig.GetAbility(abilityId)
	if abilityData == nil then
		abilityData = AbilityConfig.GetAbility(AbilityConfig.DefaultAbilityId)
	end

	return abilityData
end

function AbilityController:Update()
	refreshLayout()

	updateButtonCooldownVisual(mobileAbilityButton, AbilityConfig.ExtraSlotCooldownName)
	updateButtonCooldownVisual(pcAbilityButton, AbilityConfig.ExtraSlotCooldownName)
	updateButtonCooldownVisual(mobileAttackButton, "Fireball")
	updateButtonCooldownVisual(pcAttackButton, "Fireball")
end

function AbilityController:Start()
	if self._didStart then return end

	self._didStart = true
	self:BuildUI()

	table.insert(connections, RunService.RenderStepped:Connect(function()
		self:Update()
	end))
end

return AbilityController