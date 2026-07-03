--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local InstanceUtils =
	require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("CommonKit"):WaitForChild("InstanceUtils"))

local DrawWorldEntryPrompts = {}

local PROMPT_NAME = "SwordnWizardDrawPrompt"
local PROMPT_HOLD_DURATION = 0
local PROMPT_MAX_ACTIVATION_DISTANCE = 14
local DRAW_MODEL_WAIT_SECONDS = 10
local PROMPT_HOST_WAIT_SECONDS = 10

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
	return InstanceUtils.FindByPath(Workspace, "SwordnWizardLobby.Geometry")
end

local function findDrawModel(modelName: string): Model?
	local geometry = findLobbyGeometry()
	local model = if geometry ~= nil then geometry:FindFirstChild(modelName) else nil
	if model ~= nil and model:IsA("Model") then
		return model
	end

	return nil
end

local function waitForDrawModel(modelName: string): Model?
	local model = findDrawModel(modelName)
	if model ~= nil then
		return model
	end

	local found =
		InstanceUtils.WaitForPath(Workspace, DRAW_MODEL_WAIT_SECONDS, "SwordnWizardLobby", "Geometry", modelName)
	if found ~= nil and found:IsA("Model") then
		return found
	end

	return nil
end

local function findPromptHost(model: Model): BasePart?
	local beamBase = InstanceUtils.FindFirstDescendantMatching(model, function(descendant: Instance): boolean
		return descendant.Name == "BeamBase" and descendant:IsA("BasePart")
	end)
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

local function waitForPromptHost(model: Model): BasePart?
	local existing = findPromptHost(model)
	if existing ~= nil then
		return existing
	end

	local host = InstanceUtils.WaitForDescendantMatching(model, function(descendant: Instance): boolean
		return descendant:IsA("BasePart")
	end, PROMPT_HOST_WAIT_SECONDS)
	if host ~= nil and host:IsA("BasePart") then
		return host
	end

	return nil
end

local function createPromptBinding(host: BasePart, entry: EntryConfig, onOpenDraw: (string) -> ()): PromptBinding
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

	return {
		prompt = prompt,
		connection = connection,
	}
end

function DrawWorldEntryPrompts.Start(entries: { EntryConfig }, onOpenDraw: (string) -> ()): () -> ()
	local bindings = {} :: { PromptBinding }
	local isStopped = false

	for _, entry in entries do
		local entryConfig = entry
		task.spawn(function()
			local model = waitForDrawModel(entryConfig.modelName)
			if model == nil then
				warn(`[DrawController] draw stand model not found after wait: {entryConfig.modelName}`)
				return
			end

			local host = waitForPromptHost(model)
			if isStopped then
				return
			end

			if host == nil then
				warn(`[DrawController] draw stand has no prompt host after wait: {model:GetFullName()}`)
				return
			end

			table.insert(bindings, createPromptBinding(host, entryConfig, onOpenDraw))
		end)
	end

	return function()
		isStopped = true
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
