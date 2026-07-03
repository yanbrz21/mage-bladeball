--!strict

local DrawHighlightPreviewRuntime = require(script.Parent:WaitForChild("DrawHighlightPreviewRuntime"))

local DrawHighlightPreviewWorld = {}

local defaultRuntime = DrawHighlightPreviewRuntime.new({
	worldName = "HighlightPreviewWorld",
	useScreenAnchor = true,
	useWorldOcclusion = true,
	useDimPlane = true,
})

export type LayoutOptions = {
	distance: number?,
	offset: Vector3?,
	screenOffset: Vector2?,
	rotation: CFrame?,
	orbitSpeed: number?,
}

function DrawHighlightPreviewWorld.GetDefaultRuntime()
	return defaultRuntime
end

function DrawHighlightPreviewWorld.Clear()
	defaultRuntime.Clear()
end

function DrawHighlightPreviewWorld.ResolveReferences(screen: Instance?)
	defaultRuntime.ResolveReferences(screen)
end

function DrawHighlightPreviewWorld.Begin(layoutOptions: LayoutOptions): boolean
	return defaultRuntime.Begin(layoutOptions)
end

function DrawHighlightPreviewWorld.GetWorld(): Folder?
	return defaultRuntime.GetWorld()
end

function DrawHighlightPreviewWorld.CloneResource(
	source: Instance,
	name: string,
	localCFrame: CFrame,
	scale: number?,
	playParticles: boolean?
): Instance?
	return defaultRuntime.CloneResource(source, name, localCFrame, scale, playParticles)
end

function DrawHighlightPreviewWorld.CreateAnchor(name: string, localCFrame: CFrame): BasePart?
	return defaultRuntime.CreateAnchor(name, localCFrame)
end

function DrawHighlightPreviewWorld.PlayParticlePlaybackLoop(root: Instance, minimumCycleSeconds: number)
	defaultRuntime.PlayParticlePlaybackLoop(root, minimumCycleSeconds)
end

function DrawHighlightPreviewWorld.PlayParticlePlaybackOnce(root: Instance): number
	return defaultRuntime.PlayParticlePlaybackOnce(root)
end

function DrawHighlightPreviewWorld.SetItemLocalCFrame(instance: Instance, localCFrame: CFrame)
	defaultRuntime.SetItemLocalCFrame(instance, localCFrame)
end

function DrawHighlightPreviewWorld.TransformLocalDirectionToWorld(localDirection: Vector3): Vector3
	return defaultRuntime.TransformLocalDirectionToWorld(localDirection)
end

function DrawHighlightPreviewWorld.FlushLayout()
	defaultRuntime.FlushLayout()
end

return DrawHighlightPreviewWorld
