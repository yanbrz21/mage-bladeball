--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService('CollectionService')

local SpinUIController = {
	Name = "SpinUIController",
}

local coinsText
local gemsText
local spinGemsButton
local spinCoinsButton

function SpinUIController:Init(context)
	if self._didInit then
		return
	end

	self._didInit = true
	self._context = context
	self._localPlayer = Players.LocalPlayer
	self._connections = {}

	self._screenGui = nil
	self._mainFrame = nil
	self._mainScale = nil
	self._spinButton = nil
	self._spinIcon = nil
end

local function getReferenceByTag(id: string): Instance?
	local items = CollectionService:GetTagged(id)

	if #items < 1 then
		warn(`No item with the same ID/tag: {id}`)
		return nil
	end

	if #items > 1 then
		warn(`More than one item with the same ID/tag: {id}`)
	end

	return items[1]
end

function SpinUIController:GetReferences()
	coinsText = getReferenceByTag("SPIN_COINS")
    gemsText = getReferenceByTag('SPIN_GEMS')
    spinCoinsButton = getReferenceByTag('SPIN_OPEN_COINS')
	spinGemsButton = getReferenceByTag('SPIN_GEMS_BUTTON')
end

function SpinUIController:Enable()
	self:GetReferences()
end

function SpinUIController:Start()
	if self._didStart then
		return
	end

	self._didStart = true
end

return SpinUIController