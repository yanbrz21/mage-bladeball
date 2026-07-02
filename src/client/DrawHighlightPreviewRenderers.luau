--!strict

local DrawHighlightDeflectShieldPreviewRenderer =
	require(script.Parent:WaitForChild("DrawHighlightDeflectShieldPreviewRenderer"))
local DrawHighlightHealingZonePreviewRenderer =
	require(script.Parent:WaitForChild("DrawHighlightAbilityPreviewRenderers"))
local DrawHighlightIceWallPreviewRenderer = require(script.Parent:WaitForChild("DrawHighlightIceWallPreviewRenderer"))
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
	DrawHighlightWeaponSkinPreviewRenderers.Clear()
end

function DrawHighlightPreviewRenderers.Clear()
	clearRenderers()
end

function DrawHighlightPreviewRenderers.Render(category: string, itemId: string)
	clearRenderers()
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
		DrawHighlightWeaponSkinPreviewRenderers.Render(itemId)
	elseif category == CATEGORY_ABILITY then
		if itemId == "ice_wall" then
			DrawHighlightIceWallPreviewRenderer.Render()
		elseif itemId == "healing_zone" then
			DrawHighlightHealingZonePreviewRenderer.Render()
		elseif itemId == "deflect_shield" then
			DrawHighlightDeflectShieldPreviewRenderer.Render()
		else
			warn(`[DrawController] no highlight preview defined for ability: {itemId}`)
		end
	else
		warn(`[DrawController] unsupported highlight preview category: {category}`)
	end
end

return DrawHighlightPreviewRenderers
