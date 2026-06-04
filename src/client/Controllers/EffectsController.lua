--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = Shared:WaitForChild("Util")
local InstanceUtil = require((Util:WaitForChild("InstanceUtil") :: ModuleScript))
local Maid = require((Util:WaitForChild("Maid") :: ModuleScript))
local NumberUtil = require((Util:WaitForChild("NumberUtil") :: ModuleScript))

local EffectsController = {}

local initialized = false
local started = false
local context: any = nil
local maid = Maid.new()
local toastLabel: TextLabel? = nil
local focusLine: Frame? = nil
local pulseEmitter: ParticleEmitter? = nil
local pulse = 0
local toastUntil = 0
local baseFov = 70

local function getRenderSignal(): RBXScriptSignal
	local preRender = (RunService :: any).PreRender
	if typeof(preRender) == "RBXScriptSignal" then
		return preRender :: RBXScriptSignal
	end

	return RunService.RenderStepped
end

local function buildGui()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("ResonanceEffects")
	if existing ~= nil then
		existing:Destroy()
	end

	local gui = InstanceUtil.create("ScreenGui", {
		Name = "ResonanceEffects",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 4,
	}, playerGui) :: ScreenGui
	maid:Give(gui)

	focusLine = InstanceUtil.create("Frame", {
		Name = "FocusLine",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Color3.fromRGB(142, 190, 188),
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.new(0.28, 0, 0, 1),
		ZIndex = 1,
	}, gui) :: Frame

	toastLabel = InstanceUtil.create("TextLabel", {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(18, 21, 22),
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		Font = Enum.Font.Gotham,
		Position = UDim2.new(0.5, 0, 0, 18),
		Size = UDim2.fromOffset(360, 34),
		Text = "",
		TextColor3 = Color3.fromRGB(202, 218, 216),
		TextScaled = true,
		TextTransparency = 1,
		Visible = false,
		ZIndex = 2,
	}, gui) :: TextLabel

	InstanceUtil.create("UICorner", {
		CornerRadius = UDim.new(0, 6),
	}, toastLabel)

	InstanceUtil.create("UIStroke", {
		Color = Color3.fromRGB(94, 124, 124),
		Thickness = 1,
		Transparency = 0.55,
	}, toastLabel)

	InstanceUtil.create("UITextSizeConstraint", {
		MaxTextSize = 14,
		MinTextSize = 9,
	}, toastLabel)
end

local function buildWorldEmitter()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end

	local folder = InstanceUtil.create("Folder", {
		Name = "ResonanceEffectParts",
	}, camera) :: Folder
	maid:Give(folder)

	local part = InstanceUtil.create("Part", {
		Name = "PulseMistPart",
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CFrame = CFrame.new(0, 2.2, 0),
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
	}, folder) :: BasePart

	local attachment = InstanceUtil.create("Attachment", {
		Name = "PulseMistAttachment",
	}, part) :: Attachment

	pulseEmitter = InstanceUtil.create("ParticleEmitter", {
		Name = "PulseMist",
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(190, 210, 205)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(92, 178, 184)),
		}),
		LightEmission = 0.18,
		Lifetime = NumberRange.new(0.7, 1.1),
		Rate = 0,
		Speed = NumberRange.new(4, 9),
		SpreadAngle = Vector2.new(360, 18),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.14),
			NumberSequenceKeypoint.new(0.45, 0.34),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.34),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, attachment) :: ParticleEmitter
end

local function updateCamera(deltaTime: number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end

	if pulse < 0.02 then
		baseFov = NumberUtil.expSmoothing(baseFov, camera.FieldOfView, deltaTime, 1.5)
	end

	local targetFov = baseFov + pulse * 2.4
	camera.FieldOfView = NumberUtil.expSmoothing(camera.FieldOfView, targetFov, deltaTime, 7)
end

local function updateGui(deltaTime: number)
	local line = focusLine
	if line ~= nil then
		line.BackgroundTransparency = 0.84 - math.clamp(pulse * 0.18, 0, 0.18)
		line.Size = UDim2.new(0.28 + pulse * 0.16, 0, 0, 1)
	end

	local toast = toastLabel
	if toast ~= nil then
		local now = os.clock()
		if now < toastUntil then
			toast.Visible = true
			toast.TextTransparency = 0
			toast.BackgroundTransparency = 0.18
		elseif toast.Visible then
			toast.TextTransparency = NumberUtil.expSmoothing(toast.TextTransparency, 1, deltaTime, 7)
			toast.BackgroundTransparency = NumberUtil.expSmoothing(toast.BackgroundTransparency, 1, deltaTime, 7)
			if toast.TextTransparency > 0.96 then
				toast.Visible = false
			end
		end
	end
end

function EffectsController:Init(nextContext: any)
	if initialized then
		return
	end

	context = nextContext
	initialized = true
end

function EffectsController:Start()
	if started then
		return
	end

	started = true
	buildGui()
	buildWorldEmitter()

	local disconnect = context.AudioInputController:OnFrameChanged(function(frame)
		if frame.beat then
			self:PulseBeat(math.max(frame.peak, frame.bass))
		end
	end)
	maid:Give(disconnect)

	maid:Give(getRenderSignal():Connect(function(deltaTime: number)
		pulse = NumberUtil.expSmoothing(pulse, 0, deltaTime, 5.5)
		updateCamera(deltaTime)
		updateGui(deltaTime)
	end))
end

function EffectsController:PlayToast(text: string)
	local toast = toastLabel
	if toast ~= nil then
		toast.Text = text
	end
	toastUntil = os.clock() + 1.8
end

function EffectsController:PulseBeat(strength: number)
	local cleanStrength = math.clamp(NumberUtil.sanitizeFiniteNumber(strength, 0), 0, 1)
	pulse = math.max(pulse, cleanStrength)

	local emitter = pulseEmitter
	if emitter ~= nil then
		emitter:Emit(math.clamp(math.floor(3 + cleanStrength * 10), 3, 13))
	end

	local ui = context.UIController
	if ui ~= nil and typeof(ui.PulseGlow) == "function" then
		ui:PulseGlow(cleanStrength)
	end
end

function EffectsController:Destroy()
	maid:Cleanup()
end

return EffectsController
