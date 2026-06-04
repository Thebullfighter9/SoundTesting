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
local overlay: Frame? = nil
local toastLabel: TextLabel? = nil
local burstEmitter: ParticleEmitter? = nil
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
	local gui = InstanceUtil.create("ScreenGui", {
		Name = "PulseForgeEffects",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
	}, playerGui) :: ScreenGui
	maid:Give(gui)

	overlay = InstanceUtil.create("Frame", {
		Name = "BeatFlash",
		BackgroundColor3 = Color3.fromRGB(0, 242, 255),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	}, gui) :: Frame

	toastLabel = InstanceUtil.create("TextLabel", {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(5, 8, 18),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Position = UDim2.new(0.5, 0, 0, 20),
		Size = UDim2.fromOffset(460, 42),
		Text = "",
		TextColor3 = Color3.fromRGB(230, 252, 255),
		TextScaled = true,
		TextTransparency = 1,
		Visible = false,
		ZIndex = 2,
	}, gui) :: TextLabel

	InstanceUtil.create("UICorner", {
		CornerRadius = UDim.new(0, 8),
	}, toastLabel)

	InstanceUtil.create("UIStroke", {
		Color = Color3.fromRGB(0, 242, 255),
		Thickness = 1,
		Transparency = 0.35,
	}, toastLabel)

	InstanceUtil.create("UITextSizeConstraint", {
		MaxTextSize = 18,
		MinTextSize = 10,
	}, toastLabel)
end

local function buildWorldEmitter()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end

	local folder = InstanceUtil.create("Folder", {
		Name = "PulseForgeEffectParts",
	}, camera) :: Folder
	maid:Give(folder)

	local part = InstanceUtil.create("Part", {
		Name = "BeatBurstPart",
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CFrame = CFrame.new(0, 5, 0),
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
	}, folder) :: BasePart

	local attachment = InstanceUtil.create("Attachment", {
		Name = "BurstAttachment",
	}, part) :: Attachment

	burstEmitter = InstanceUtil.create("ParticleEmitter", {
		Name = "BeatSparks",
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 64, 188)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 242, 255)),
		}),
		LightEmission = 0.8,
		Lifetime = NumberRange.new(0.25, 0.5),
		Rate = 0,
		Speed = NumberRange.new(12, 28),
		SpreadAngle = Vector2.new(360, 360),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(1, 0),
		}),
	}, attachment) :: ParticleEmitter
end

local function updateCamera(deltaTime: number)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end

	if pulse < 0.01 then
		baseFov = NumberUtil.expSmoothing(baseFov, camera.FieldOfView, deltaTime, 2)
	end

	local targetFov = baseFov + pulse * 7
	camera.FieldOfView = NumberUtil.expSmoothing(camera.FieldOfView, targetFov, deltaTime, 12)

	local shake = math.clamp(pulse * 0.12, 0, 0.16)
	if shake > 0.005 then
		local now = os.clock()
		camera.CFrame = camera.CFrame * CFrame.new(math.sin(now * 61) * shake, math.cos(now * 47) * shake, 0)
	end
end

local function updateGui(deltaTime: number)
	local flash = overlay
	if flash ~= nil then
		flash.BackgroundTransparency = 1 - math.clamp(pulse * 0.22, 0, 0.22)
		flash.BackgroundColor3 = Color3.fromHSV((os.clock() * 0.08) % 1, 0.75, 1)
	end

	local toast = toastLabel
	if toast ~= nil then
		local now = os.clock()
		if now < toastUntil then
			toast.Visible = true
			toast.TextTransparency = 0
			toast.BackgroundTransparency = 0.1
		elseif toast.Visible then
			toast.TextTransparency = NumberUtil.expSmoothing(toast.TextTransparency, 1, deltaTime, 8)
			toast.BackgroundTransparency = NumberUtil.expSmoothing(toast.BackgroundTransparency, 1, deltaTime, 8)
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
		pulse = NumberUtil.expSmoothing(pulse, 0, deltaTime, 7)
		updateCamera(deltaTime)
		updateGui(deltaTime)
	end))
end

function EffectsController:PlayToast(text: string)
	local toast = toastLabel
	if toast ~= nil then
		toast.Text = text
	end
	toastUntil = os.clock() + 2.1
end

function EffectsController:PulseBeat(strength: number)
	local cleanStrength = math.clamp(NumberUtil.sanitizeFiniteNumber(strength, 0), 0, 1)
	pulse = math.max(pulse, cleanStrength)

	local emitter = burstEmitter
	if emitter ~= nil then
		emitter:Emit(math.clamp(math.floor(6 + cleanStrength * 24), 4, 30))
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
