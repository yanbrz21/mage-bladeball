--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Parabellum = ReplicatedStorage:WaitForChild("Parabellum")
local DrawCatalogUtils = require(Parabellum:WaitForChild("DrawCatalogUtils"))

local DrawPricingView = {}

local COIN_PRICE_ICON = "rbxassetid://87190121549893"
local ROBUX_PRICE_ICON = "rbxassetid://138110852462666"

export type Refs = {
	spin1xButton: TextButton?,
	price1x: TextLabel?,
	coinsDrawPrice: TextLabel?,
	price1xIcon: ImageLabel?,
}

export type Params = {
	refs: Refs,
	currentDrawId: string,
	currentCount: number,
	resolvedDraw: DrawCatalogUtils.ResolvedDraw,
	findRobuxDrawProduct: (drawId: string, count: number) -> DrawCatalogUtils.RobuxDrawProduct?,
}

local function setButtonTitle(button: TextButton?, text: string)
	if button == nil then
		return
	end

	local title = button:FindFirstChild("Title", true)
	if title ~= nil and title:IsA("TextLabel") then
		title.Text = text
	else
		button.Text = text
	end
end

local function setDrawButtonEnabled(button: TextButton?, enabled: boolean)
	if button == nil then
		return
	end

	button.Active = enabled
	button.Interactable = enabled
	button.AutoButtonColor = enabled
	button.BackgroundTransparency = if enabled then 1 else 0.85
end

local function setPriceIcons(refs: Refs, image: string)
	if refs.price1xIcon ~= nil then
		refs.price1xIcon.Image = image
	end
end

local function isCoinDrawCountAllowed(drawConfig, count: number): boolean
	local allowedCounts = drawConfig.AllowedCounts
	if type(allowedCounts) ~= "table" then
		return false
	end

	for _, allowedCount in allowedCounts do
		if allowedCount == count then
			return true
		end
	end

	return false
end

local function updateRobuxDrawPrices(params: Params)
	local refs = params.refs
	setPriceIcons(refs, ROBUX_PRICE_ICON)

	local product1x = params.findRobuxDrawProduct(params.currentDrawId, 1)

	if refs.price1x ~= nil then
		refs.price1x.Text = if product1x ~= nil then tostring(product1x.robuxPrice) else "--"
	end

	if refs.coinsDrawPrice ~= nil then
		refs.coinsDrawPrice.Text = if product1x ~= nil then tostring(product1x.robuxPrice) else "--"
	end

	if refs.spin1xButton ~= nil then
		refs.spin1xButton.Visible = product1x ~= nil
		setButtonTitle(refs.spin1xButton, "Buy x1")
		setDrawButtonEnabled(refs.spin1xButton, product1x ~= nil and product1x.productId > 0)
	end
end

local function updateCoinDrawPrices(params: Params)
	local refs = params.refs
	setPriceIcons(refs, COIN_PRICE_ICON)

	local drawConfig = params.resolvedDraw.config
	local cost = drawConfig.Cost
	if type(cost) ~= "number" or cost <= 0 then
		warn(`[DrawController] coin draw {params.currentDrawId} has invalid Cost`)
		setDrawButtonEnabled(refs.spin1xButton, false)
		return
	end

	local totalCost = cost * params.currentCount

	if refs.price1x ~= nil then
		refs.price1x.Text = if isCoinDrawCountAllowed(drawConfig, 1) then tostring(cost) else "--"
	end

	if refs.coinsDrawPrice ~= nil then
		refs.coinsDrawPrice.Text = tostring(totalCost)
	end

	if refs.spin1xButton ~= nil then
		refs.spin1xButton.Visible = true
		setButtonTitle(refs.spin1xButton, "Draw x1")
		setDrawButtonEnabled(refs.spin1xButton, isCoinDrawCountAllowed(drawConfig, 1))
	end
end

function DrawPricingView.Update(params: Params)
	if params.resolvedDraw.kind == DrawCatalogUtils.DRAW_KIND_ROBUX then
		updateRobuxDrawPrices(params)
		return
	end

	updateCoinDrawPrices(params)
end

return DrawPricingView
