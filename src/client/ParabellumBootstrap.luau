--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local parabellumFolder = ReplicatedStorage:WaitForChild("Parabellum")

local CONTROLLER_NAMES = table.freeze({
	"DrawController",
	"InventoryController",
	"QuestController",
<<<<<<< Updated upstream
	"CombatControlHUDController",
=======
	"AbilityController"
>>>>>>> Stashed changes
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

type ParentBootContext = {
	Controllers: { [string]: any },
}

local ParabellumBootstrap = {
	Name = "ParabellumBootstrap",
	_didInit = false,
	_didStart = false,
	_context = nil :: ClientBootContext?,
	_orderedControllers = {} :: { Controller },
}

local function requireController(controllerName: string): Controller
	local module = parabellumFolder:FindFirstChild(controllerName)

	if module == nil then
		error(`[ParabellumBootstrap] missing controller: {controllerName}`)
	end

	if not module:IsA("ModuleScript") then
		error(`[ParabellumBootstrap] {controllerName} is not a ModuleScript`)
	end

	local controller = require(module) :: Controller

	if type(controller) ~= "table" then
		error(`[ParabellumBootstrap] {controllerName} must return a table`)
	end

	if controller.Name == nil then
		controller.Name = controllerName
	end

	return controller
end

function ParabellumBootstrap:Init(parentContext: ParentBootContext)
	if self._didInit then
		return
	end

	self._didInit = true

	local context: ClientBootContext = {
		LocalPlayer = localPlayer,
		ReplicatedStorage = ReplicatedStorage,
		Parabellum = parabellumFolder,
		Controllers = parentContext.Controllers,
	}

	self._context = context

	for _, controllerName in CONTROLLER_NAMES do
		local controller = requireController(controllerName)
		table.insert(self._orderedControllers, controller)

		if controller.Name ~= nil then
			parentContext.Controllers[controller.Name] = controller
		end
	end

	for _, controller in self._orderedControllers do
		local init = controller.Init
		if init ~= nil then
			local ok, err = pcall(function()
				init(controller, context)
			end)

			if not ok then
				warn(`[ParabellumBootstrap] init failed for {controller.Name or "unknown"}: {err}`)
			end
		end
	end
end

function ParabellumBootstrap:Start()
	if self._didStart then
		return
	end

	self._didStart = true

	for _, controller in self._orderedControllers do
		local start = controller.Start
		if start ~= nil then
			local ok, err = pcall(function()
				start(controller)
			end)

			if not ok then
				warn(`[ParabellumBootstrap] start failed for {controller.Name or "unknown"}: {err}`)
			end
		end
	end
end

return ParabellumBootstrap
