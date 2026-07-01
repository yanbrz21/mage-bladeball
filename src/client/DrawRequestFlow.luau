--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Parabellum = ReplicatedStorage:WaitForChild("Parabellum")
local DrawCatalogUtils = require(Parabellum:WaitForChild("DrawCatalogUtils"))

local DrawRequestFlow = {}

export type Params = {
	count: number,
	currentDrawId: string,
	localPlayer: Player,
	requestSkinDrawRemote: RemoteEvent,
	rollSequence: any,
	resolveDraw: (drawId: string) -> DrawCatalogUtils.ResolvedDraw?,
	findRobuxDrawProduct: (drawId: string, count: number) -> DrawCatalogUtils.RobuxDrawProduct?,
	readBalance: () -> (),
	getBalance: () -> number,
	setCurrentCount: (count: number) -> (),
	updateDrawPrices: () -> (),
}

local function requestCoinDraw(params: Params, drawConfig: any, count: number)
	params.readBalance()

	if type(drawConfig.Cost) ~= "number" or drawConfig.Cost <= 0 then
		warn(`[DrawController] coin draw {params.currentDrawId} has invalid Cost`)
		return
	end

	local cost = drawConfig.Cost * count
	local currentBalance = params.getBalance()
	if currentBalance < cost then
		warn(`[DrawController] not enough coins. need {math.max(0, cost - currentBalance)} more coins`)
		return
	end

	params.setCurrentCount(count)
	params.rollSequence:BeginWaiting(true)

	params.requestSkinDrawRemote:FireServer({
		drawId = params.currentDrawId,
		count = count,
	})
end

local function requestRobuxDraw(params: Params, count: number)
	local product = params.findRobuxDrawProduct(params.currentDrawId, count)
	if product == nil then
		warn(`[DrawController] no Robux product configured for draw {params.currentDrawId} x{count}`)
		return
	end

	if product.productId <= 0 then
		warn(
			`[DrawController] Robux product {product.productKey} for draw {params.currentDrawId} has no ProductId configured`
		)
		return
	end

	params.setCurrentCount(count)
	params.rollSequence:BeginWaiting(false)

	local purchaseFinishedConnection: RBXScriptConnection?
	purchaseFinishedConnection = MarketplaceService.PromptProductPurchaseFinished:Connect(
		function(userId: number, productId: number, wasPurchased: boolean)
			if userId ~= params.localPlayer.UserId or productId ~= product.productId then
				return
			end

			if purchaseFinishedConnection ~= nil then
				purchaseFinishedConnection:Disconnect()
				purchaseFinishedConnection = nil
			end

			if not wasPurchased then
				params.rollSequence:ResetToChoose(false)
				params.updateDrawPrices()
			end
		end
	)

	local ok, err =
		pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, params.localPlayer, product.productId)
	if not ok then
		if purchaseFinishedConnection ~= nil then
			purchaseFinishedConnection:Disconnect()
			purchaseFinishedConnection = nil
		end

		params.rollSequence:ResetAfterEmptyResult()
		warn(`[DrawController] failed to prompt Robux product {product.productKey}: {tostring(err)}`)
	end
end

function DrawRequestFlow.Request(params: Params)
	if params.rollSequence:IsBusy() then
		return
	end

	local resolvedDraw = params.resolveDraw(params.currentDrawId)
	if resolvedDraw == nil then
		return
	end

	if resolvedDraw.kind == DrawCatalogUtils.DRAW_KIND_ROBUX then
		requestRobuxDraw(params, params.count)
		return
	end

	requestCoinDraw(params, resolvedDraw.config, params.count)
end

return DrawRequestFlow
