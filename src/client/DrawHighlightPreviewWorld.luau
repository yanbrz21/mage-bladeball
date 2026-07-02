--!strict

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DrawHighlightPreviewWorld = {}

local PREVIEW_WORLD_NAME = "HighlightPreviewWorld"
local DIM_PLANE_NAME = "HighlightPreviewDimPlane"
local DEFAULT_PREVIEW_DISTANCE = 6
local DIM_PLANE_EXTRA_DISTANCE = 2.4
local DIM_PLANE_TRANSPARENCY = 0.2
local DEFAULT_EMIT_COUNT = 12

export type LayoutOptions = {
	distance: number?,
	offset: Vector3?,
	screenOffset: Vector2?,
	rotation: CFrame?,
	orbitSpeed: number?,
}

type PreviewItem = {
	instance: Instance,
	localCFrame: CFrame,
}

local previewRoot: Frame?
local previewWorld: Folder?
local dimPlane: Part?
local previewItems: { PreviewItem } = {}
local previewConnections: { RBXScriptConnection } = {}
local hiddenParts: { [BasePart]: number } = {}
local disabledEffects: { [Instance]: boolean } = {}
local previewGeneration = 0
local activeLayoutOptions: LayoutOptions?
local activeOrbitAngle = 0

local function disconnectConnections()
	for _, connection in previewConnections do
		connection:Disconnect()
	end

	table.clear(previewConnections)
end

local function getCurrentCamera(): Camera?
	return Workspace.CurrentCamera
end

local function isPreviewDescendant(instance: Instance): boolean
	local camera = getCurrentCamera()
	if camera == nil then
		return false
	end

	return instance == camera or instance:IsDescendantOf(camera)
end

local function hidePart(part: BasePart)
	if isPreviewDescendant(part) or hiddenParts[part] ~= nil then
		return
	end

	hiddenParts[part] = part.LocalTransparencyModifier
	part.LocalTransparencyModifier = 1
end

local function disableWorldEffect(effect: Instance)
	if isPreviewDescendant(effect) or disabledEffects[effect] ~= nil then
		return
	end

	local effectObject = effect :: any
	disabledEffects[effect] = effectObject.Enabled
	effectObject.Enabled = false
end

local function applyWorldOcclusion(instance: Instance)
	if instance:IsA("BasePart") then
		hidePart(instance)
	elseif instance:IsA("ParticleEmitter") or instance:IsA("Beam") or instance:IsA("Trail") then
		disableWorldEffect(instance)
	end
end

local function restoreWorldOcclusion()
	for part, localTransparencyModifier in hiddenParts do
		if part.Parent ~= nil then
			part.LocalTransparencyModifier = localTransparencyModifier
		end
	end

	for effect, enabled in disabledEffects do
		if effect.Parent ~= nil then
			(effect :: any).Enabled = enabled
		end
	end

	table.clear(hiddenParts)
	table.clear(disabledEffects)
end

local function startWorldOcclusion()
	for _, descendant in Workspace:GetDescendants() do
		applyWorldOcclusion(descendant)
	end

	table.insert(
		previewConnections,
		Workspace.DescendantAdded:Connect(function(descendant: Instance)
			applyWorldOcclusion(descendant)
		end)
	)
end

local function collectParts(root: Instance): { BasePart }
	local parts = {} :: { BasePart }

	if root:IsA("BasePart") then
		table.insert(parts, root)
	end

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	return parts
end

local function getPivot(root: Instance): CFrame
	if root:IsA("Model") then
		local cframe = root:GetBoundingBox()
		return cframe
	end

	if root:IsA("BasePart") then
		return root.CFrame
	end

	local parts = collectParts(root)
	if #parts <= 0 then
		return CFrame.new()
	end

	local total = Vector3.zero
	for _, part in parts do
		total += part.Position
	end

	return CFrame.new(total / #parts)
end

local function pivotInstance(root: Instance, targetCFrame: CFrame)
	if root:IsA("Model") then
		root:PivotTo(targetCFrame)
		return
	end

	if root:IsA("BasePart") then
		root.CFrame = targetCFrame
		return
	end

	local currentPivot = getPivot(root)
	local delta = targetCFrame * currentPivot:Inverse()
	for _, part in collectParts(root) do
		part.CFrame = delta * part.CFrame
	end
end

local function scaleInstance(root: Instance, scale: number?)
	if scale == nil or math.abs(scale - 1) < 0.001 then
		return
	end

	if root:IsA("Model") then
		root:ScaleTo(root:GetScale() * scale)
	elseif root:IsA("BasePart") then
		root.Size *= scale
	end
end

local function setEffectEnabled(target: Instance, enabled: boolean)
	local effect = target :: any
	effect.Enabled = enabled
end

local function prepareDescendant(target: Instance, enableEffects: boolean)
	if target:IsA("BasePart") then
		target.Anchored = true
		target.CanCollide = false
		target.CanTouch = false
		target.CanQuery = false
		target.CastShadow = false
		target.Massless = true
	elseif
		enableEffects
		and (target:IsA("ParticleEmitter") or target:IsA("Beam") or target:IsA("Trail") or target:IsA("Light"))
	then
		setEffectEnabled(target, true)
	end
end

local function prepareInstance(root: Instance, enableEffects: boolean)
	prepareDescendant(root, enableEffects)

	for _, descendant in root:GetDescendants() do
		prepareDescendant(descendant, enableEffects)
	end
end

local function readNumberAttribute(instance: Instance, attributeName: string): number?
	local value = instance:GetAttribute(attributeName)
	return if type(value) == "number" then value else nil
end

local function playParticleEmitterFromAttributes(
	emitter: ParticleEmitter,
	generation: number,
	enableZeroDurationEmitters: boolean
): number
	local emitCountAttribute = readNumberAttribute(emitter, "EmitCount")
	local emitCount = if emitCountAttribute ~= nil
		then math.max(0, math.floor(emitCountAttribute))
		else DEFAULT_EMIT_COUNT
	local emitDelay = math.max(0, readNumberAttribute(emitter, "EmitDelay") or 0)
	local emitDuration = math.max(0, readNumberAttribute(emitter, "EmitDuration") or 0)

	if emitDuration > 0 then
		emitter.Enabled = false
	elseif enableZeroDurationEmitters then
		emitter.Enabled = true
	end

	local function playNow()
		if generation ~= previewGeneration or emitter.Parent == nil then
			return
		end

		if emitCount > 0 then
			emitter:Emit(emitCount)
		end

		if emitDuration > 0 then
			emitter.Enabled = true
			task.delay(emitDuration, function()
				if generation == previewGeneration and emitter:IsDescendantOf(game) then
					emitter.Enabled = false
				end
			end)
		end
	end

	if emitDelay > 0 then
		task.delay(emitDelay, playNow)
	else
		playNow()
	end

	return emitDelay + emitDuration + emitter.Lifetime.Max
end

local function playParticlePlayback(root: Instance, generation: number, enableZeroDurationEmitters: boolean): number
	local latestEndTime = 0
	for _, descendant in root:GetDescendants() do
		if not descendant:IsA("ParticleEmitter") then
			continue
		end

		local emitter = descendant :: ParticleEmitter
		latestEndTime =
			math.max(latestEndTime, playParticleEmitterFromAttributes(emitter, generation, enableZeroDurationEmitters))
	end

	return latestEndTime
end

local function scheduleParticlePlayback(root: Instance)
	playParticlePlayback(root, previewGeneration, true)
end

local function addPreviewItem(instance: Instance, localCFrame: CFrame)
	table.insert(previewItems, {
		instance = instance,
		localCFrame = localCFrame,
	})
end

local function getPreviewBaseCFrame(
	camera: Camera,
	layoutOptions: LayoutOptions,
	orbitAngle: number,
	distance: number
): CFrame
	local root = previewRoot
	if root == nil then
		return camera.CFrame * CFrame.new(0, 0, -distance)
	end

	local absolutePosition = root.AbsolutePosition
	local absoluteSize = root.AbsoluteSize
	local screenOffset = layoutOptions.screenOffset or Vector2.zero
	local centerX = absolutePosition.X + absoluteSize.X * (0.5 + screenOffset.X)
	local centerY = absolutePosition.Y + absoluteSize.Y * (0.5 + screenOffset.Y)
	local ray = camera:ViewportPointToRay(centerX, centerY)
	local offset = layoutOptions.offset or Vector3.zero
	local position = ray.Origin + ray.Direction * distance
	local base = CFrame.lookAt(position, ray.Origin) * CFrame.new(offset)
	local rotation = layoutOptions.rotation or CFrame.identity

	return base * CFrame.Angles(0, orbitAngle, 0) * rotation
end

local function updateDimPlane(camera: Camera, distance: number)
	local plane = dimPlane
	if plane == nil then
		return
	end

	local viewportSize = camera.ViewportSize
	local aspect = if viewportSize.Y > 0 then viewportSize.X / viewportSize.Y else 1
	local height = 2 * math.tan(math.rad(camera.FieldOfView) * 0.5) * distance
	local width = height * aspect

	plane.Size = Vector3.new(width, height, 0.05)
	plane.CFrame = camera.CFrame * CFrame.new(0, 0, -distance)
end

local function applyLayoutNow(layoutOptions: LayoutOptions, orbitAngle: number)
	local camera = getCurrentCamera()
	if camera == nil then
		return
	end

	local distance = layoutOptions.distance or DEFAULT_PREVIEW_DISTANCE
	updateDimPlane(camera, distance + DIM_PLANE_EXTRA_DISTANCE)

	local baseCFrame = getPreviewBaseCFrame(camera, layoutOptions, orbitAngle, distance)
	for _, item in previewItems do
		if item.instance.Parent ~= nil then
			pivotInstance(item.instance, baseCFrame * item.localCFrame)
		end
	end
end

local function startLayoutLoop(layoutOptions: LayoutOptions)
	local orbitAngle = 0
	activeLayoutOptions = layoutOptions
	activeOrbitAngle = orbitAngle

	table.insert(
		previewConnections,
		RunService.RenderStepped:Connect(function(deltaTime: number)
			if layoutOptions.orbitSpeed ~= nil then
				orbitAngle += deltaTime * layoutOptions.orbitSpeed
			end

			activeOrbitAngle = orbitAngle
			applyLayoutNow(layoutOptions, orbitAngle)
		end)
	)
end

local function ensurePreviewWorld(): boolean
	local camera = getCurrentCamera()
	if camera == nil then
		warn("[DrawController] missing CurrentCamera; skipping highlight 3D preview")
		return false
	end

	local existing = camera:FindFirstChild(PREVIEW_WORLD_NAME)
	if existing ~= nil then
		existing:Destroy()
	end

	local world = Instance.new("Folder")
	world.Name = PREVIEW_WORLD_NAME
	world.Parent = camera
	previewWorld = world

	local plane = Instance.new("Part")
	plane.Name = DIM_PLANE_NAME
	plane.Anchored = true
	plane.CanCollide = false
	plane.CanTouch = false
	plane.CanQuery = false
	plane.CastShadow = false
	plane.Color = Color3.new(0, 0, 0)
	plane.Material = Enum.Material.SmoothPlastic
	plane.Transparency = DIM_PLANE_TRANSPARENCY
	plane.Parent = world
	dimPlane = plane

	return true
end

function DrawHighlightPreviewWorld.Clear()
	previewGeneration += 1
	disconnectConnections()
	restoreWorldOcclusion()
	table.clear(previewItems)
	activeLayoutOptions = nil
	activeOrbitAngle = 0

	if previewWorld ~= nil then
		previewWorld:Destroy()
		previewWorld = nil
	end

	local camera = getCurrentCamera()
	local currentCameraWorld = if camera ~= nil then camera:FindFirstChild(PREVIEW_WORLD_NAME) else nil
	if currentCameraWorld ~= nil then
		currentCameraWorld:Destroy()
	end

	dimPlane = nil
end

function DrawHighlightPreviewWorld.ResolveReferences(screen: Instance?)
	previewRoot = nil

	if screen == nil then
		DrawHighlightPreviewWorld.Clear()
		return
	end

	local bg = screen:FindFirstChild("Bg")
	local canvas = if bg ~= nil then bg:FindFirstChild("Canvas") else nil
	local preview = if canvas ~= nil then canvas:FindFirstChild("Preview") else nil
	if preview == nil or not preview:IsA("Frame") then
		warn("[DrawController] missing Lottery.Bg.Canvas.Preview for highlight preview")
		DrawHighlightPreviewWorld.Clear()
		return
	end

	previewRoot = preview
end

function DrawHighlightPreviewWorld.Begin(layoutOptions: LayoutOptions): boolean
	if previewRoot == nil or not ensurePreviewWorld() then
		return false
	end

	startWorldOcclusion()
	startLayoutLoop(layoutOptions)
	return true
end

function DrawHighlightPreviewWorld.GetWorld(): Folder?
	return previewWorld
end

function DrawHighlightPreviewWorld.CloneResource(
	source: Instance,
	name: string,
	localCFrame: CFrame,
	scale: number?,
	playParticles: boolean?
): Instance?
	if previewWorld == nil then
		return nil
	end

	local clone = source:Clone()
	clone.Name = name
	local shouldPlayParticles = if playParticles == nil then true else playParticles
	prepareInstance(clone, shouldPlayParticles)
	scaleInstance(clone, scale)
	clone.Parent = previewWorld
	addPreviewItem(clone, localCFrame)
	if shouldPlayParticles then
		scheduleParticlePlayback(clone)
	end

	return clone
end

function DrawHighlightPreviewWorld.CreateAnchor(name: string, localCFrame: CFrame): BasePart?
	if previewWorld == nil then
		return nil
	end

	local anchor = Instance.new("Part")
	anchor.Name = name
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.Massless = true
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Parent = previewWorld
	addPreviewItem(anchor, localCFrame)
	return anchor
end

function DrawHighlightPreviewWorld.PlayParticlePlaybackLoop(root: Instance, minimumCycleSeconds: number)
	local generation = previewGeneration
	task.spawn(function()
		while generation == previewGeneration and root:IsDescendantOf(game) do
			local playbackEndTime = playParticlePlayback(root, generation, false)
			task.wait(math.max(minimumCycleSeconds, playbackEndTime))
		end
	end)
end

function DrawHighlightPreviewWorld.PlayParticlePlaybackOnce(root: Instance): number
	return playParticlePlayback(root, previewGeneration, false)
end

function DrawHighlightPreviewWorld.SetItemLocalCFrame(instance: Instance, localCFrame: CFrame)
	for _, item in previewItems do
		if item.instance == instance then
			item.localCFrame = localCFrame
			return
		end
	end
end

function DrawHighlightPreviewWorld.FlushLayout()
	local layoutOptions = activeLayoutOptions
	if layoutOptions == nil then
		return
	end

	applyLayoutNow(layoutOptions, activeOrbitAngle)
end

return DrawHighlightPreviewWorld
