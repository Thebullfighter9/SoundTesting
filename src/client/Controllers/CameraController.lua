--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require((Shared:WaitForChild("Constants") :: ModuleScript))
local Types = require((Shared:WaitForChild("Types") :: ModuleScript))
local Util = Shared:WaitForChild("Util")
local Maid = require((Util:WaitForChild("Maid") :: ModuleScript))
local NumberUtil = require((Util:WaitForChild("NumberUtil") :: ModuleScript))

type AudioFrame = Types.AudioFrame
type CameraMode = Types.CameraMode
type VisualStyle = Types.VisualStyle

local CameraController = {}

local initialized = false
local started = false
local maid = Maid.new()
local characterMaid = Maid.new()
local mode: CameraMode = Constants.DEFAULT_CAMERA_MODE :: CameraMode
local cameraEnabled = true
local cameraCenter = Vector3.new(0, 4, 0)
local orbitAngle = -math.pi * 0.38
local currentCFrame: CFrame? = nil
local currentFov = Constants.CAMERA_FOV_BASE
local pulse = 0
local lastBeatTime = 0
local visibilityAccumulator = 0
local galleryCenterResolved = false
local playerControls: any = nil

local VALID_MODES: { [string]: boolean } = {
	Auto = true,
	Still = true,
	Wide = true,
	Close = true,
}

local function getCamera(): Camera?
	return Workspace.CurrentCamera
end

local function getGalleryCenter(): (Vector3, boolean)
	local gallery = Workspace:FindFirstChild(Constants.GALLERY_FOLDER_NAME)
	if gallery ~= nil then
		local anchors = gallery:FindFirstChild(Constants.ANCHORS_FOLDER_NAME)
		if anchors ~= nil then
			local total = Vector3.zero
			local count = 0
			for _, child in ipairs(anchors:GetChildren()) do
				if child:IsA("BasePart") then
					total += child.Position
					count += 1
				end
			end
			if count > 0 then
				local average = total / count
				return Vector3.new(average.X, 4, average.Z), true
			end
		end
	end

	return Vector3.new(0, 4, 0), false
end

local function refreshCameraCenter()
	local center, found = getGalleryCenter()
	cameraCenter = center
	galleryCenterResolved = galleryCenterResolved or found
end

local function hideLocalDescendant(descendant: Instance)
	if descendant:IsA("BasePart") then
		descendant.LocalTransparencyModifier = 1
	elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
		pcall(function()
			(descendant :: any).Transparency = 1
		end)
	elseif descendant:IsA("Humanoid") then
		descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

local function hideCharacter(character: Model)
	characterMaid:Cleanup()

	for _, descendant in ipairs(character:GetDescendants()) do
		hideLocalDescendant(descendant)
	end

	characterMaid:Give(character.DescendantAdded:Connect(hideLocalDescendant))
end

local function refreshLocalCharacterVisibility()
	local character = LocalPlayer.Character
	if character == nil then
		return
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		hideLocalDescendant(descendant)
	end
end

local function disableLocalControls()
	task.defer(function()
		local playerScripts = LocalPlayer:WaitForChild("PlayerScripts", 8)
		if playerScripts == nil then
			return
		end

		local playerModule = playerScripts:FindFirstChild("PlayerModule")
		if playerModule == nil then
			playerModule = playerScripts:WaitForChild("PlayerModule", 8)
		end
		if playerModule == nil or not playerModule:IsA("ModuleScript") then
			return
		end

		local ok, module = pcall(require, playerModule)
		if not ok or typeof(module) ~= "table" or typeof((module :: any).GetControls) ~= "function" then
			return
		end

		local okControls, controls = pcall(function()
			return (module :: any):GetControls()
		end)
		if okControls and controls ~= nil and typeof((controls :: any).Disable) == "function" then
			playerControls = controls
			pcall(function()
				(playerControls :: any):Disable()
			end)
		end
	end)
end

local function setLocalControlsEnabled(enabled: boolean)
	local controls = playerControls
	if controls == nil then
		return
	end

	if enabled and typeof((controls :: any).Enable) == "function" then
		pcall(function()
			(controls :: any):Enable()
		end)
	elseif not enabled and typeof((controls :: any).Disable) == "function" then
		pcall(function()
			(controls :: any):Disable()
		end)
	end
end

local function getModeSettings(frame: AudioFrame): (number, number, number, number, Vector3)
	local energy = math.clamp(frame.visualEnergy, 0, 1)
	local centroid = math.clamp(frame.centroid, 0, 1)
	local target = cameraCenter + Vector3.new(0, 2.2 + frame.bass * 1.8, 0)

	if mode == "Still" then
		return -math.pi * 0.5, Constants.CAMERA_DEFAULT_DISTANCE, Constants.CAMERA_HEIGHT + 2, Constants.CAMERA_FOV_BASE, target
	elseif mode == "Wide" then
		return orbitAngle * 0.3 - math.pi * 0.7, Constants.CAMERA_WIDE_DISTANCE - energy * 3, Constants.CAMERA_HEIGHT + 9, Constants.CAMERA_FOV_BASE + 4, target
	elseif mode == "Close" then
		return orbitAngle * 0.45 - math.pi * 0.35, Constants.CAMERA_CLOSE_DISTANCE - energy * 2, Constants.CAMERA_HEIGHT - 5 + centroid * 2.4, Constants.CAMERA_FOV_BASE - 5, target + Vector3.new(0, 1.4, 0)
	end

	local sideDrift = (centroid - 0.5) * 0.24
	local distance = Constants.CAMERA_DEFAULT_DISTANCE - energy * 4
	local height = Constants.CAMERA_HEIGHT + (centroid - 0.5) * 5 + frame.lowMid * 1.4
	return orbitAngle + sideDrift, distance, height, Constants.CAMERA_FOV_BASE, target
end

local function updateCamera(deltaTime: number, frame: AudioFrame)
	if not cameraEnabled then
		return
	end

	local camera = getCamera()
	if camera == nil then
		return
	end

	if not galleryCenterResolved then
		refreshCameraCenter()
	end

	if mode == "Auto" then
		orbitAngle += Constants.CAMERA_ORBIT_SPEED * math.clamp(deltaTime, 1 / 240, 0.08) * (0.82 + frame.visualEnergy * 0.22)
	elseif mode == "Wide" then
		orbitAngle += Constants.CAMERA_ORBIT_SPEED * 0.38 * math.clamp(deltaTime, 1 / 240, 0.08)
	elseif mode == "Close" then
		orbitAngle += Constants.CAMERA_ORBIT_SPEED * 0.28 * math.clamp(deltaTime, 1 / 240, 0.08)
	end

	if frame.beat and frame.time - lastBeatTime > 0.16 then
		pulse = math.max(pulse, math.clamp(math.max(frame.beatStrength, frame.bass * 0.7, frame.visualEnergy * 0.35), 0, 1))
		lastBeatTime = frame.time
	end

	local angle, distance, height, baseFov, target = getModeSettings(frame)
	local position = cameraCenter + Vector3.new(math.cos(angle) * distance, height, math.sin(angle) * distance)
	local targetCFrame = CFrame.lookAt(position, target)
	local cframeAlpha = 1 - math.exp(-math.clamp(deltaTime, 1 / 240, 0.12) * 3.6)
	local fovTarget = baseFov + pulse * Constants.CAMERA_FOV_BEAT_GAIN

	camera.CameraType = Enum.CameraType.Scriptable
	currentCFrame = if currentCFrame == nil then targetCFrame else (currentCFrame :: CFrame):Lerp(targetCFrame, cframeAlpha)
	currentFov = NumberUtil.expSmooth(currentFov, fovTarget, deltaTime, 6)
	camera.CFrame = currentCFrame :: CFrame
	camera.FieldOfView = math.clamp(currentFov, 42, 72)

	visibilityAccumulator += deltaTime
	if visibilityAccumulator >= 0.2 then
		visibilityAccumulator = 0
		refreshLocalCharacterVisibility()
	end

	pulse = NumberUtil.expSmooth(pulse, 0, deltaTime, 5)
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
	refreshCameraCenter()
	task.delay(1, refreshCameraCenter)
	task.delay(3, refreshCameraCenter)

	local character = LocalPlayer.Character
	if character ~= nil then
		hideCharacter(character)
	end

	maid:Give(LocalPlayer.CharacterAdded:Connect(function(nextCharacter: Model)
		hideCharacter(nextCharacter)
	end))
	maid:Give(characterMaid)

	disableLocalControls()
	self:ResetView()
end

function CameraController:SetMode(nextMode: CameraMode)
	if not VALID_MODES[nextMode] then
		return
	end

	mode = nextMode
	self:ResetView()
end

function CameraController:GetMode(): CameraMode
	return mode
end

function CameraController:ResetView()
	currentCFrame = nil
	currentFov = Constants.CAMERA_FOV_BASE
	refreshCameraCenter()
	local camera = getCamera()
	if camera ~= nil and cameraEnabled then
		camera.CameraType = Enum.CameraType.Scriptable
	end
end

function CameraController:Reset()
	self:ResetView()
end

function CameraController:SetCameraEnabled(enabled: boolean)
	cameraEnabled = enabled
	local camera = getCamera()
	if camera ~= nil then
		camera.CameraType = if enabled then Enum.CameraType.Scriptable else Enum.CameraType.Custom
	end
	setLocalControlsEnabled(not enabled)
end

function CameraController:Update(deltaTime: number, frame: AudioFrame, _style: VisualStyle)
	updateCamera(deltaTime, frame)
end

function CameraController:Destroy()
	setLocalControlsEnabled(true)
	characterMaid:Cleanup()
	maid:Cleanup()
end

return CameraController
