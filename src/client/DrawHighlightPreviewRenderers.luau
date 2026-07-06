--!strict

local DrawHighlightDeflectShieldPreviewRenderer =
	require(script.Parent:WaitForChild("DrawHighlightDeflectShieldPreviewRenderer"))
local DrawHighlightHealingZonePreviewRenderer =
	require(script.Parent:WaitForChild("DrawHighlightHealingZonePreviewRenderer"))
local DrawHighlightIceWallPreviewRenderer = require(script.Parent:WaitForChild("DrawHighlightIceWallPreviewRenderer"))
local DrawHighlightInvisibilityPreviewRenderer =
	require(script.Parent:WaitForChild("DrawHighlightInvisibilityPreviewRenderer"))
local DrawHighlightPreviewSupport = require(script.Parent:WaitForChild("DrawHighlightPreviewSupport"))
local DrawHighlightWeaponSkinPreviewRenderers =
	require(script.Parent:WaitForChild("DrawHighlightWeaponSkinPreviewRenderers"))

local DrawHighlightPreviewRenderers = {}

local CATEGORY_ABILITY = "Ability"
local CATEGORY_WEAPON_SKIN = "WeaponSkin"

local function clearRenderers()
	DrawHighlightDeflectShieldPreviewRenderer.Clear()
	DrawHighlightHealingZonePreviewRenderer.Clear()
	DrawHighlightIceWallPreviewRenderer.Clear()
	DrawHighlightInvisibilityPreviewRenderer.Clear()
	DrawHighlightWeaponSkinPreviewRenderers.Clear()
end

function DrawHighlightPreviewRenderers.Clear()
	clearRenderers()
end

function DrawHighlightPreviewRenderers.Render(category: string, itemId: string, previewRuntime: any?)
	if previewRuntime == nil then
		clearRenderers()
	end
	DrawHighlightPreviewSupport.ConfigureVFXSystem(
		require(
			game:GetService("Players").LocalPlayer
				:WaitForChild("PlayerScripts")
				:WaitForChild("ClientPackages")
				:WaitForChild("CommonKit")
				:WaitForChild("VFXSystem")
		)
	)

	if category == CATEGORY_WEAPON_SKIN then
		DrawHighlightWeaponSkinPreviewRenderers.Render(itemId, previewRuntime)
	elseif category == CATEGORY_ABILITY then
		if itemId == "ice_wall" then
			DrawHighlightIceWallPreviewRenderer.Render(previewRuntime)
		elseif itemId == "healing_zone" then
			DrawHighlightHealingZonePreviewRenderer.Render(previewRuntime)
		elseif itemId == "deflect_shield" then
			DrawHighlightDeflectShieldPreviewRenderer.Render(previewRuntime)
		elseif itemId == "invisibility" then
			DrawHighlightInvisibilityPreviewRenderer.Render(previewRuntime)
		else
			warn(`[DrawController] no highlight preview defined for ability: {itemId}`)
		end
	else
		warn(`[DrawController] unsupported highlight preview category: {category}`)
	end
end

return DrawHighlightPreviewRenderers
