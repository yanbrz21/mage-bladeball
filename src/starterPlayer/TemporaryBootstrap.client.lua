--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

local parabellumFolder = ReplicatedStorage:WaitForChild("Parabellum")

local CONTROLLER_NAMES = table.freeze({
	"DrawController",
	"InventoryController",
})

type Controller = {
	Name: string?,
	Init: ((self: any, context: ClientBootContext) -> ())?,
	Start: ((self: any) -> ())?,
	Destroy: ((self: any) -> ())?,
}

export type ClientBootContext = {
	LocalPlayer: Player,
	ReplicatedStorage: ReplicatedStorage,
	Parabellum: Instance,
	Controllers: { [string]: Controller },
}

local context: ClientBootContext = {
	LocalPlayer = localPlayer,
	ReplicatedStorage = ReplicatedStorage,
	Parabellum = parabellumFolder,
	Controllers = {},
}

local orderedControllers: { Controller } = {}

local function requireController(controllerName: string): Controller
	local module = parabellumFolder:FindFirstChild(controllerName)

	if module == nil then
		error(`[ParabellumClientBootstrap] missing controller: {controllerName}`)
	end

	if not module:IsA("ModuleScript") then
		error(`[ParabellumClientBootstrap] {controllerName} is not a ModuleScript`)
	end

	local controller = require(module) :: Controller

	if type(controller) ~= "table" then
		error(`[ParabellumClientBootstrap] {controllerName} must return a table`)
	end

	if controller.Name == nil then
		controller.Name = controllerName
	end

	return controller
end

warn("[ParabellumClientBootstrap] booting")

for _, controllerName in CONTROLLER_NAMES do
	local controller = requireController(controllerName)

	table.insert(orderedControllers, controller)

	if controller.Name ~= nil then
		context.Controllers[controller.Name] = controller
	end
end

for _, controller in orderedControllers do
	if controller.Init ~= nil then
		local ok, err = pcall(function()
			controller:Init(context)
		end)

		if not ok then
			warn(`[ParabellumClientBootstrap] init failed for {controller.Name or "unknown"}: {err}`)
		end
	end
end

for _, controller in orderedControllers do
	if controller.Start ~= nil then
		local ok, err = pcall(function()
			controller:Start()
		end)

		if not ok then
			warn(`[ParabellumClientBootstrap] start failed for {controller.Name or "unknown"}: {err}`)
		end
	end
end

warn("[ParabellumClientBootstrap] started")