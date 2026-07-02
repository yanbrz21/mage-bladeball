--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local DrawConfig = require(Config:WaitForChild("DrawConfig"))
local Parabellum = ReplicatedStorage:WaitForChild("Parabellum")
local DrawCatalogUtils = require(Parabellum:WaitForChild("DrawCatalogUtils"))
local DrawHighlightPreviewRenderers = require(Parabellum:WaitForChild("DrawHighlightPreviewRenderers"))
local DrawHighlightPreviewRuntime = require(Parabellum:WaitForChild("DrawHighlightPreviewRuntime"))
local InventoryItemVisuals = require(Parabellum:WaitForChild("InventoryItemVisuals"))

local DrawWorldHighlightPreviewManager = {}

local PREVIEW_PARENT_FOLDER_NAME = "DrawStandHighlightPreviewWorlds"
local PREVIEW_ANCHOR_OFFSET = Vector3.new(0, 8, 0)
local PREVIEW_WORLD_SCALE = 1
local DEFAULT_CYCLE_SECONDS = 20
local INITIAL_READY_TIMEOUT_SECONDS = 8

local localPlayer = Players.LocalPlayer

export type StandConfig = {
	modelName: string,
	drawId: string,
	worldName: string,
}

type HighlightVisualEntry = DrawCatalogUtils.HighlightVisualEntry

type Slot = {
	config: StandConfig,
	model: Model,
	runtime: any,
	entries: { HighlightVisualEntry },
	index: number,
	token: number,
	running: boolean,
}

type Manager = {
	Start: (self: Manager) -> (),
	Pause: (self: Manager) -> (),
	Resume: (self: Manager) -> (),
	Destroy: (self: Manager) -> (),
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

local function resolveHighlightEntries(drawId: string): { HighlightVisualEntry }
	local drawConfig = DrawCatalogUtils.GetDrawConfig(DrawConfig, drawId)
	if drawConfig == nil then
		warn(`[DrawController] draw stand preview has invalid draw id: {drawId}`)
		return {}
	end

	return DrawCatalogUtils.GetHighlightDrawEntries(InventoryItemVisuals, drawConfig)
end

local function renderSlot(slot: Slot)
	local entries = slot.entries
	if #entries <= 0 then
		slot.runtime.Clear()
		return
	end

	local entry = entries[slot.index]
	if entry == nil then
		slot.index = 1
		entry = entries[slot.index]
	end

	slot.runtime.Clear()
	slot.runtime.SetWorldAnchor(slot.model, PREVIEW_ANCHOR_OFFSET)
	DrawHighlightPreviewRenderers.Render(entry.Category, entry.ItemId, slot.runtime)
end

local function waitForInitialPreviewReadiness()
	local startedAt = os.clock()

	while Workspace.CurrentCamera == nil and os.clock() - startedAt < INITIAL_READY_TIMEOUT_SECONDS do
		task.wait()
	end

	local character = localPlayer.Character
	while character == nil and os.clock() - startedAt < INITIAL_READY_TIMEOUT_SECONDS do
		task.wait()
		character = localPlayer.Character
	end

	while
		character ~= nil
		and character:FindFirstChild("HumanoidRootPart") == nil
		and os.clock() - startedAt < INITIAL_READY_TIMEOUT_SECONDS
	do
		task.wait()
	end

	RunService.RenderStepped:Wait()
	RunService.RenderStepped:Wait()
end

local function startSlotLoop(slot: Slot, cycleSeconds: number)
	slot.token += 1
	local token = slot.token
	slot.running = true

	task.spawn(function()
		waitForInitialPreviewReadiness()
		if not slot.running or slot.token ~= token then
			return
		end

		renderSlot(slot)

		while slot.running and slot.token == token do
			task.wait(cycleSeconds)
			if not slot.running or slot.token ~= token then
				return
			end

			slot.index = (slot.index % math.max(#slot.entries, 1)) + 1
			renderSlot(slot)
		end
	end)
end

local function stopSlot(slot: Slot)
	slot.token += 1
	slot.running = false
	slot.runtime.Clear()
end

function DrawWorldHighlightPreviewManager.new(configs: { StandConfig }, cycleSeconds: number?): Manager
	local slots = {} :: { Slot }

	for _, config in configs do
		local model = findDrawModel(config.modelName)
		if model == nil then
			warn(`[DrawController] draw stand preview model not found: {config.modelName}`)
			continue
		end

		local entries = resolveHighlightEntries(config.drawId)
		local runtime = DrawHighlightPreviewRuntime.new({
			worldName = config.worldName,
			parentFolderName = PREVIEW_PARENT_FOLDER_NAME,
			useScreenAnchor = false,
			useWorldOcclusion = false,
			useDimPlane = false,
			worldScale = PREVIEW_WORLD_SCALE,
		})

		runtime.SetWorldAnchor(model, PREVIEW_ANCHOR_OFFSET)
		table.insert(slots, {
			config = config,
			model = model,
			runtime = runtime,
			entries = entries,
			index = 1,
			token = 0,
			running = false,
		})
	end

	local manager = {} :: any
	local running = false
	local paused = false
	local interval = cycleSeconds or DEFAULT_CYCLE_SECONDS

	function manager:Start()
		if running then
			return
		end

		running = true
		paused = false
		for _, slot in slots do
			startSlotLoop(slot, interval)
		end
	end

	function manager:Pause()
		if paused then
			return
		end

		paused = true
		for _, slot in slots do
			stopSlot(slot)
		end
	end

	function manager:Resume()
		if not running or not paused then
			return
		end

		paused = false
		for _, slot in slots do
			startSlotLoop(slot, interval)
		end
	end

	function manager:Destroy()
		running = false
		paused = true
		for _, slot in slots do
			stopSlot(slot)
		end
		table.clear(slots)
	end

	return manager :: Manager
end

return DrawWorldHighlightPreviewManager
