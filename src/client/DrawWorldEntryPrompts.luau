--!strict

local Workspace = game:GetService("Workspace")

local DrawWorldEntryPrompts = {}

local PROMPT_NAME = "SwordnWizardDrawPrompt"
local PROMPT_HOLD_DURATION = 0
local PROMPT_MAX_ACTIVATION_DISTANCE = 14

export type EntryConfig = {
	modelName: string,
	drawId: string,
	actionText: string,
	objectText: string,
}

type PromptBinding = {
	prompt: ProximityPrompt,
	connection: RBXScriptConnection,
}

local function findLobbyGeometry(): Instance?
	local lobby = Workspace:FindFirstChild("SwordnWizardLobby")
	return if lobby ~= nil then lobby:FindFirstChild("Geometry") else nil
end

local function findDrawModel(modelName: string): Model?
	local geometry = findLobbyGeometry()
	local model = if geometry ~= nil then geometry:FindFirstChild(modelName) else nil
	if model ~= nil and model:IsA("Model") then
		return model
	end

	return nil
end

local function findPromptHost(model: Model): BasePart?
	local beamBase = model:FindFirstChild("BeamBase", true)
	if beamBase ~= nil and beamBase:IsA("BasePart") then
		return beamBase
	end

	if model.PrimaryPart ~= nil then
		return model.PrimaryPart
	end

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

function DrawWorldEntryPrompts.Start(entries: { EntryConfig }, onOpenDraw: (string) -> ()): () -> ()
	local bindings = {} :: { PromptBinding }

	for _, entry in entries do
		local model = findDrawModel(entry.modelName)
		if model == nil then
			warn(`[DrawController] draw stand model not found: {entry.modelName}`)
			continue
		end

		local host = findPromptHost(model)
		if host == nil then
			warn(`[DrawController] draw stand has no prompt host: {model:GetFullName()}`)
			continue
		end

		local existingPrompt = host:FindFirstChild(PROMPT_NAME)
		if existingPrompt ~= nil then
			existingPrompt:Destroy()
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = PROMPT_NAME
		prompt.ActionText = entry.actionText
		prompt.ObjectText = entry.objectText
		prompt.HoldDuration = PROMPT_HOLD_DURATION
		prompt.MaxActivationDistance = PROMPT_MAX_ACTIVATION_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.Parent = host

		local connection = prompt.Triggered:Connect(function()
			onOpenDraw(entry.drawId)
		end)

		table.insert(bindings, {
			prompt = prompt,
			connection = connection,
		})
	end

	return function()
		for _, binding in bindings do
			binding.connection:Disconnect()
			if binding.prompt.Parent ~= nil then
				binding.prompt:Destroy()
			end
		end
		table.clear(bindings)
	end
end

return DrawWorldEntryPrompts
