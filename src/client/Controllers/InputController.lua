--!strict

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require((Shared:WaitForChild("Constants") :: ModuleScript))
local Network = Shared:WaitForChild("Network")
local RemoteNames = require((Network:WaitForChild("RemoteNames") :: ModuleScript))
local Util = Shared:WaitForChild("Util")
local Maid = require((Util:WaitForChild("Maid") :: ModuleScript))
local NumberUtil = require((Util:WaitForChild("NumberUtil") :: ModuleScript))

local InputController = {}

local initialized = false
local started = false
local context: any = nil
local maid = Maid.new()
local marbleRemote: RemoteEvent? = nil
local lastMarbleRequest = 0

local ACTION_TOGGLE_UI = "ResonanceToggleUi"
local ACTION_DEMO = "ResonanceDemoMode"
local ACTION_MIC = "ResonanceMicMode"
local ACTION_ASSET = "ResonanceAssetMode"
local ACTION_STYLE = "ResonanceCycleStyle"
local ACTION_STYLE_GRID = "ResonanceStyleGrid"
local ACTION_STYLE_ROW = "ResonanceStyleRow"
local ACTION_STYLE_CIRCLE = "ResonanceStyleCircle"
local ACTION_STYLE_ALL = "ResonanceStyleAll"
local ACTION_STYLE_MINIMAL = "ResonanceStyleMinimal"
local ACTION_MARBLE = "ResonanceDropMarble"
local ACTION_CAMERA = "ResonanceResetCamera"

local function getRemote(): RemoteEvent?
	if marbleRemote ~= nil then
		return marbleRemote
	end

	local remotesFolder = ReplicatedStorage:WaitForChild(Constants.REMOTES_FOLDER_NAME, 10)
	if remotesFolder == nil then
		return nil
	end

	local remote = remotesFolder:WaitForChild(RemoteNames.MarbleRequested, 10)
	if remote ~= nil and remote:IsA("RemoteEvent") then
		marbleRemote = remote
		return remote
	end

	return nil
end

local function currentEnergy(): number
	local frame = context.AudioController:GetFrame()
	return math.clamp(math.max(frame.peak, frame.bass, frame.rms) * 1.05, 0, 1)
end

function InputController:Init(nextContext: any)
	if initialized then
		return
	end

	context = nextContext
	initialized = true
end

function InputController:Start()
	if started then
		return
	end

	started = true
	marbleRemote = getRemote()

	local function bind(actionName: string, keyCode: Enum.KeyCode, handler: () -> (), result: Enum.ContextActionResult?)
		ContextActionService:BindAction(actionName, function(_name: string, inputState: Enum.UserInputState, inputObject: InputObject): Enum.ContextActionResult
			if inputState == Enum.UserInputState.Begin and inputObject.UserInputState == Enum.UserInputState.Begin then
				handler()
			end

			return result or Enum.ContextActionResult.Sink
		end, false, keyCode)
	end

	bind(ACTION_TOGGLE_UI, Enum.KeyCode.H, function()
		context.UIController:ToggleVisible()
	end)
	bind(ACTION_DEMO, Enum.KeyCode.D, function()
		context.AudioController:SetMode("Demo")
		context.UIController:SetStatus("Demo signal active")
	end)
	bind(ACTION_MIC, Enum.KeyCode.M, function()
		context.AudioController:SetMode("Mic")
		context.UIController:SetStatus(context.AudioController:GetStatus())
	end)
	bind(ACTION_ASSET, Enum.KeyCode.A, function()
		context.UIController:PlayAsset()
	end)
	bind(ACTION_STYLE, Enum.KeyCode.V, function()
		context.ResonanceController:CycleStyle()
		context.UIController:SetStatus(`Visualizer: {context.ResonanceController:GetStyle()}`)
	end)
	bind(ACTION_STYLE_GRID, Enum.KeyCode.One, function()
		context.ResonanceController:SetStyle("Grid")
		context.UIController:SetStatus("Visualizer: Grid")
	end)
	bind(ACTION_STYLE_ROW, Enum.KeyCode.Two, function()
		context.ResonanceController:SetStyle("Row")
		context.UIController:SetStatus("Visualizer: Row")
	end)
	bind(ACTION_STYLE_CIRCLE, Enum.KeyCode.Three, function()
		context.ResonanceController:SetStyle("Circle")
		context.UIController:SetStatus("Visualizer: Circle")
	end)
	bind(ACTION_STYLE_ALL, Enum.KeyCode.Four, function()
		context.ResonanceController:SetStyle("All")
		context.UIController:SetStatus("Visualizer: All")
	end)
	bind(ACTION_STYLE_MINIMAL, Enum.KeyCode.Five, function()
		context.ResonanceController:SetStyle("Minimal")
		context.UIController:SetStatus("Visualizer: Minimal")
	end)
	bind(ACTION_MARBLE, Enum.KeyCode.E, function()
		self:RequestMarble()
	end)
	bind(ACTION_CAMERA, Enum.KeyCode.R, function()
		context.CameraController:Reset()
		context.UIController:SetStatus("Camera reset")
	end)

	maid:Give(function()
		ContextActionService:UnbindAction(ACTION_TOGGLE_UI)
		ContextActionService:UnbindAction(ACTION_DEMO)
		ContextActionService:UnbindAction(ACTION_MIC)
		ContextActionService:UnbindAction(ACTION_ASSET)
		ContextActionService:UnbindAction(ACTION_STYLE)
		ContextActionService:UnbindAction(ACTION_STYLE_GRID)
		ContextActionService:UnbindAction(ACTION_STYLE_ROW)
		ContextActionService:UnbindAction(ACTION_STYLE_CIRCLE)
		ContextActionService:UnbindAction(ACTION_STYLE_ALL)
		ContextActionService:UnbindAction(ACTION_STYLE_MINIMAL)
		ContextActionService:UnbindAction(ACTION_MARBLE)
		ContextActionService:UnbindAction(ACTION_CAMERA)
	end)
end

function InputController:RequestMarble()
	local now = os.clock()
	if now - lastMarbleRequest < Constants.MARBLE_COOLDOWN then
		context.UIController:SetStatus("Marble limited")
		return
	end

	local remote = getRemote()
	if remote == nil then
		context.UIController:SetStatus("Marble remote unavailable")
		return
	end

	lastMarbleRequest = now
	local energy = math.clamp(NumberUtil.sanitizeFiniteNumber(currentEnergy(), 0), 0, 1)
	local ok = pcall(function()
		remote:FireServer({
			energy = energy,
		})
	end)

	if ok then
		context.UIController:SetStatus("Marble dropped")
		context.UIController:PulseGlow(math.max(energy, 0.25))
	else
		context.UIController:SetStatus("Marble request failed")
	end
end

function InputController:Destroy()
	maid:Cleanup()
end

return InputController
