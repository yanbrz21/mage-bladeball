--!strict

local DrawHighlightPreviewRenderers = require(script.Parent:WaitForChild("DrawHighlightPreviewRenderers"))
local DrawHighlightPreviewWorld = require(script.Parent:WaitForChild("DrawHighlightPreviewWorld"))

local DrawHighlightPreview = {}

function DrawHighlightPreview.Clear()
	DrawHighlightPreviewRenderers.Clear()
	DrawHighlightPreviewWorld.Clear()
end

function DrawHighlightPreview.ResolveReferences(screen: Instance?)
	DrawHighlightPreviewWorld.ResolveReferences(screen)
end

function DrawHighlightPreview.Render(category: string, itemId: string)
	DrawHighlightPreview.Clear()
	DrawHighlightPreviewRenderers.Render(category, itemId)
end

return DrawHighlightPreview
