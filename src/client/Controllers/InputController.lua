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
local beatOrbRemote: RemoteEvent? = nil
local lastBeatOrbRequest = 0

local ACTION_DROP = "PulseForgeDropBeatOrb"
local ACTION_DROP_SPACE = "PulseForgeDropBeatOrbSpace"
local ACTION_PRESET = "PulseForgeCyclePreset"
local ACTION_MIC = "PulseForgeTryMic"
local ACTION_DEMO = "PulseForgeDemoMode"

local function getRemote(): RemoteEvent?
	if beatOrbRemote ~= nil then
		return beatOrbRemote
	end

	local remotesFolder = ReplicatedStorage:WaitForChild(Constants.REMOTES_FOLDER_NAME, 10)
	if remotesFolder == nil then
		return nil
	end

	local remote = remotesFolder:WaitForChild(RemoteNames.BeatOrbRequested, 10)
	if remote ~= nil and remote:IsA("RemoteEvent") then
		beatOrbRemote = remote
		return remote
	end

	return nil
end

local function currentEnergy(): number
	local frame = context.AudioInputController:GetFrame()
	return math.clamp(math.max(frame.rms, frame.peak, frame.bass) * 1.1, 0, 1)
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
	beatOrbRemote = getRemote()

	local function handleDrop(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject): Enum.ContextActionResult
		if inputState == Enum.UserInputState.Begin then
			self:RequestBeatOrb()
		end

		return Enum.ContextActionResult.Sink
	end

	local function handleSpace(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject): Enum.ContextActionResult
		if inputState == Enum.UserInputState.Begin then
			self:RequestBeatOrb()
		end

		return Enum.ContextActionResult.Pass
	end

	local function handlePreset(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject): Enum.ContextActionResult
		if inputState == Enum.UserInputState.Begin then
			context.VisualizerController:CyclePreset()
			local text = `Preset: {context.VisualizerController:GetPreset()}`
			context.UIController:SetStatus(text)
			context.EffectsController:PlayToast(text)
		end

		return Enum.ContextActionResult.Sink
	end

	local function handleMic(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject): Enum.ContextActionResult
		if inputState == Enum.UserInputState.Begin then
			context.AudioInputController:SetMode("Mic")
			local text = context.AudioInputController:GetStatus()
			context.UIController:SetStatus(text)
			context.EffectsController:PlayToast(text)
		end

		return Enum.ContextActionResult.Sink
	end

	local function handleDemo(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject): Enum.ContextActionResult
		if inputState == Enum.UserInputState.Begin then
			context.AudioInputController:SetMode("Demo")
			context.UIController:SetStatus("Demo mode active")
			context.EffectsController:PlayToast("Demo mode active")
		end

		return Enum.ContextActionResult.Sink
	end

	ContextActionService:BindAction(ACTION_DROP, handleDrop, false, Enum.KeyCode.E)
	ContextActionService:BindAction(ACTION_DROP_SPACE, handleSpace, false, Enum.KeyCode.Space)
	ContextActionService:BindAction(ACTION_PRESET, handlePreset, false, Enum.KeyCode.B)
	ContextActionService:BindAction(ACTION_MIC, handleMic, false, Enum.KeyCode.M)
	ContextActionService:BindAction(ACTION_DEMO, handleDemo, false, Enum.KeyCode.N)

	maid:Give(function()
		ContextActionService:UnbindAction(ACTION_DROP)
		ContextActionService:UnbindAction(ACTION_DROP_SPACE)
		ContextActionService:UnbindAction(ACTION_PRESET)
		ContextActionService:UnbindAction(ACTION_MIC)
		ContextActionService:UnbindAction(ACTION_DEMO)
	end)
end

function InputController:RequestBeatOrb()
	local now = os.clock()
	if now - lastBeatOrbRequest < Constants.BEAT_ORB_COOLDOWN then
		context.UIController:SetStatus("Beat orb limited")
		context.EffectsController:PlayToast("Beat orb limited")
		return
	end

	local remote = getRemote()
	if remote == nil then
		context.UIController:SetStatus("Beat orb remote unavailable")
		context.EffectsController:PlayToast("Beat orb remote unavailable")
		return
	end

	lastBeatOrbRequest = now
	local energy = math.clamp(NumberUtil.sanitizeFiniteNumber(currentEnergy(), 0), 0, 1)
	local ok = pcall(function()
		remote:FireServer({
			energy = energy,
		})
	end)

	if ok then
		context.UIController:SetStatus("Beat orb dropped")
		context.EffectsController:PulseBeat(math.max(energy, 0.35))
		context.EffectsController:PlayToast("Beat orb dropped")
	else
		context.UIController:SetStatus("Beat orb request failed")
		context.EffectsController:PlayToast("Beat orb request failed")
	end
end

function InputController:Destroy()
	maid:Cleanup()
end

return InputController
