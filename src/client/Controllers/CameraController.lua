--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require((Shared:WaitForChild("Types") :: ModuleScript))
local Util = Shared:WaitForChild("Util")
local Maid = require((Util:WaitForChild("Maid") :: ModuleScript))
local NumberUtil = require((Util:WaitForChild("NumberUtil") :: ModuleScript))

type AudioFrame = Types.AudioFrame
type VisualStyle = Types.VisualStyle

local CameraController = {}

local initialized = false
local started = false
local maid = Maid.new()
local pulse = 0
local baseFov = 70
local lastBeatTime = 0
local framingUntil = 0
local hasReleasedFrame = true

local function getFramedCFrame(): CFrame
	return CFrame.lookAt(Vector3.new(0, 24, -44), Vector3.new(0, 4, 0))
end

local function getCamera(): Camera?
	return Workspace.CurrentCamera
end

local function frameSculpture()
	local camera = getCamera()
	if camera == nil then
		return
	end

	local character = LocalPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root ~= nil and root:IsA("BasePart") then
		root.CFrame = CFrame.lookAt(root.Position, Vector3.new(0, root.Position.Y, 0))
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = getFramedCFrame()
	camera.FieldOfView = 72
	baseFov = camera.FieldOfView
	framingUntil = os.clock() + 6
	hasReleasedFrame = false
end

function CameraController:Init(_context: any)
	if initialized then
		return
	end

	initialized = true
end

function CameraController:Start()
	if started then
		return
	end

	started = true
	task.defer(frameSculpture)

	maid:Give(LocalPlayer.CharacterAdded:Connect(function()
		task.defer(frameSculpture)
	end))
end

function CameraController:Reset()
	frameSculpture()
end

function CameraController:Update(deltaTime: number, frame: AudioFrame, style: VisualStyle)
	local camera = getCamera()
	if camera == nil then
		return
	end

	if os.clock() <= framingUntil then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = getFramedCFrame()
	elseif not hasReleasedFrame then
		camera.CameraType = Enum.CameraType.Custom
		hasReleasedFrame = true
	end

	if frame.beat and frame.time - lastBeatTime > 0.16 then
		pulse = math.max(pulse, math.clamp(math.max(frame.peak, frame.bass), 0, 1))
		lastBeatTime = frame.time
	end

	if pulse < 0.02 then
		baseFov = NumberUtil.expSmooth(baseFov, camera.FieldOfView, deltaTime, 1)
	end

	local targetFov = baseFov + pulse * 2.2
	camera.FieldOfView = NumberUtil.expSmooth(camera.FieldOfView, targetFov, deltaTime, 6)

	if style == "All" and pulse > 0.08 then
		local shake = math.clamp(pulse * 0.035, 0, 0.045)
		local timeNow = os.clock()
		camera.CFrame = camera.CFrame * CFrame.new(math.sin(timeNow * 37) * shake, math.cos(timeNow * 31) * shake, 0)
	end

	pulse = NumberUtil.expSmooth(pulse, 0, deltaTime, 5)
end

function CameraController:Destroy()
	maid:Cleanup()
end

return CameraController
