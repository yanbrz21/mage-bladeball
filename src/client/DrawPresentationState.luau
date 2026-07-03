--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local InstanceUtils =
	require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("CommonKit"):WaitForChild("InstanceUtils"))

local DrawPresentationState = {}

local CAMERA_BIND_NAME = "DrawControllerCameraLock"
local CAMERA_RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 1
local MANAGED_GUI_NAMES: { [string]: boolean } = table.freeze({
	HUD = true,
	SwordnWizardHUD = true,
	TopbarStandard = true,
	TopbarStandardClipped = true,
	TopbarCentered = true,
	TopbarCenteredClipped = true,
})
local CAMERA_OUTSIDE_DISTANCE = -34
local CAMERA_HEIGHT_OFFSET = 16
local CAMERA_TARGET_HEIGHT_OFFSET = 16
local DRAW_CAMERA_FIELD_OF_VIEW = 38

type CameraState = {
	cameraType: Enum.CameraType,
	cameraSubject: (BasePart | Humanoid)?,
	cameraCFrame: CFrame,
	fieldOfView: number,
}

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local enabledGuiStates: { [ScreenGui]: boolean } = {}
local guiConnection: RBXScriptConnection?
local savedCameraState: CameraState?
local isActive = false

local function isManagedGui(instance: Instance): boolean
	return MANAGED_GUI_NAMES[instance.Name] == true
end

local function hideManagedGui(instance: Instance)
	if not instance:IsA("ScreenGui") or not isManagedGui(instance) then
		return
	end

	if enabledGuiStates[instance] == nil then
		enabledGuiStates[instance] = instance.Enabled
	end

	instance.Enabled = false
end

local function hideManagedGuis()
	for _, descendant in playerGui:GetDescendants() do
		hideManagedGui(descendant)
	end

	for _, child in playerGui:GetChildren() do
		hideManagedGui(child)
	end

	if guiConnection == nil then
		guiConnection = playerGui.DescendantAdded:Connect(function(descendant: Instance)
			hideManagedGui(descendant)
		end)
	end
end

local function restoreManagedGuis()
	if guiConnection ~= nil then
		guiConnection:Disconnect()
		guiConnection = nil
	end

	for gui, wasEnabled in enabledGuiStates do
		if gui.Parent ~= nil then
			gui.Enabled = wasEnabled
		end
	end

	table.clear(enabledGuiStates)
end

local function findLobbySpawn(): BasePart?
	local lobbySpawn = InstanceUtils.FindByPath(Workspace, "SwordnWizardLobby.LobbySpawn")
	if lobbySpawn ~= nil and lobbySpawn:IsA("BasePart") then
		return lobbySpawn
	end

	return nil
end

local function getDrawCameraCFrame(): CFrame?
	local lobbySpawn = findLobbySpawn()
	if lobbySpawn == nil then
		return nil
	end

	local spawnCFrame = lobbySpawn.CFrame
	local spawnPosition = lobbySpawn.Position
	local cameraPosition = spawnPosition
		+ spawnCFrame.LookVector * CAMERA_OUTSIDE_DISTANCE
		+ Vector3.new(0, CAMERA_HEIGHT_OFFSET, 0)
	local targetPosition = spawnPosition - spawnCFrame.LookVector * 50 + Vector3.new(0, CAMERA_TARGET_HEIGHT_OFFSET, 0)

	return CFrame.lookAt(cameraPosition, targetPosition)
end

local function saveCameraState(camera: Camera)
	if savedCameraState ~= nil then
		return
	end

	savedCameraState = {
		cameraType = camera.CameraType,
		cameraSubject = camera.CameraSubject,
		cameraCFrame = camera.CFrame,
		fieldOfView = camera.FieldOfView,
	}
end

local function applyDrawCamera()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end

	local drawCameraCFrame = getDrawCameraCFrame()
	if drawCameraCFrame == nil then
		return
	end

	saveCameraState(camera)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = nil
	camera.FieldOfView = DRAW_CAMERA_FIELD_OF_VIEW
	camera.CFrame = drawCameraCFrame
end

local function startCameraLock()
	RunService:UnbindFromRenderStep(CAMERA_BIND_NAME)
	applyDrawCamera()
	RunService:BindToRenderStep(CAMERA_BIND_NAME, CAMERA_RENDER_PRIORITY, function()
		applyDrawCamera()
	end)
end

local function restoreCamera()
	RunService:UnbindFromRenderStep(CAMERA_BIND_NAME)

	local camera = Workspace.CurrentCamera
	local state = savedCameraState
	savedCameraState = nil

	if camera == nil or state == nil then
		return
	end

	camera.CameraType = state.cameraType
	camera.CameraSubject = state.cameraSubject
	camera.FieldOfView = state.fieldOfView
	camera.CFrame = state.cameraCFrame
end

function DrawPresentationState.Enable()
	if isActive then
		return
	end

	isActive = true
	hideManagedGuis()
	startCameraLock()
end

function DrawPresentationState.Disable()
	isActive = false
	restoreCamera()
	restoreManagedGuis()
end

function DrawPresentationState.IsActive(): boolean
	return isActive
end

return DrawPresentationState
