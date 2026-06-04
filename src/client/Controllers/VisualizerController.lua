--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require((Shared:WaitForChild("Constants") :: ModuleScript))
local Types = require((Shared:WaitForChild("Types") :: ModuleScript))
local Util = Shared:WaitForChild("Util")
local InstanceUtil = require((Util:WaitForChild("InstanceUtil") :: ModuleScript))
local Maid = require((Util:WaitForChild("Maid") :: ModuleScript))
local NumberUtil = require((Util:WaitForChild("NumberUtil") :: ModuleScript))

type VisualizerPreset = Types.VisualizerPreset
type AudioFrame = Types.AudioFrame

local VisualizerController = {}

local initialized = false
local started = false
local context: any = nil
local maid = Maid.new()
local anchors: { BasePart } = {}
local fieldPins: { BasePart } = {}
local surfaceTiles: { BasePart } = {}
local waveSegments: { BasePart } = {}
local orbitMasses: { BasePart } = {}
local preset: VisualizerPreset = "Field"
local intensity = Constants.DEFAULT_INTENSITY
local lastAnchorRefresh = 0

local PALETTE = {
	mist = Color3.fromRGB(178, 204, 203),
	cyan = Color3.fromRGB(90, 176, 181),
	warm = Color3.fromRGB(205, 194, 168),
	stone = Color3.fromRGB(74, 78, 78),
	graphite = Color3.fromRGB(28, 31, 32),
}

local function getRenderSignal(): RBXScriptSignal
	local preRender = (RunService :: any).PreRender
	if typeof(preRender) == "RBXScriptSignal" then
		return preRender :: RBXScriptSignal
	end

	return RunService.RenderStepped
end

local function getCamera(): Camera
	local camera = Workspace.CurrentCamera
	while camera == nil do
		Workspace:GetPropertyChangedSignal("CurrentCamera"):Wait()
		camera = Workspace.CurrentCamera
	end

	return camera
end

local function getOrCreateFolder(): Folder
	local camera = getCamera()
	local existing = camera:FindFirstChild("ResonanceClientVisuals")
	if existing ~= nil then
		existing:Destroy()
	end

	local folder = InstanceUtil.create("Folder", {
		Name = "ResonanceClientVisuals",
	}, camera) :: Folder
	maid:Give(folder)
	return folder
end

local function createVisualPart(parent: Instance, name: string, props: { [string]: any }): BasePart
	props.Name = name
	props.Anchored = true
	props.CanCollide = false
	props.CanTouch = false
	props.CanQuery = false
	props.TopSurface = Enum.SurfaceType.Smooth
	props.BottomSurface = Enum.SurfaceType.Smooth

	return InstanceUtil.create("Part", props, parent) :: BasePart
end

local function refreshAnchors()
	anchors = {}
	lastAnchorRefresh = os.clock()

	local field = Workspace:FindFirstChild(Constants.FIELD_FOLDER_NAME)
	if field == nil then
		return
	end

	local anchorFolder = field:FindFirstChild("FieldAnchors")
	if anchorFolder == nil then
		return
	end

	for _, child in ipairs(anchorFolder:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(anchors, child)
		end
	end

	table.sort(anchors, function(a: BasePart, b: BasePart): boolean
		return a.Name < b.Name
	end)
end

local function fallbackAnchorPosition(index: number): Vector3
	local alpha = (index - 1) / Constants.FIELD_BAND_COUNT
	local angle = alpha * math.pi * 2
	return Vector3.new(math.cos(angle) * 18, 1.05, math.sin(angle) * 18)
end

local function getAnchorPosition(index: number): Vector3
	local anchor = anchors[index]
	if anchor ~= nil and anchor.Parent ~= nil then
		return anchor.Position
	end

	return fallbackAnchorPosition(index)
end

local function blendColor(a: Color3, b: Color3, alpha: number): Color3
	local cleanAlpha = math.clamp(alpha, 0, 1)
	return Color3.new(
		a.R + (b.R - a.R) * cleanAlpha,
		a.G + (b.G - a.G) * cleanAlpha,
		a.B + (b.B - a.B) * cleanAlpha
	)
end

local function buildVisuals()
	local folder = getOrCreateFolder()

	for index = 1, Constants.FIELD_BAND_COUNT do
		local position = getAnchorPosition(index)
		local pin = createVisualPart(folder, `FieldPin_{string.format("%02d", index)}`, {
			CFrame = CFrame.new(position + Vector3.new(0, 0.42, 0)),
			Size = Vector3.new(0.28, 0.84, 0.28),
			Color = PALETTE.mist,
			Material = Enum.Material.Glass,
			Transparency = 0.14,
		})
		table.insert(fieldPins, pin)

		local tile = createVisualPart(folder, `SurfaceTile_{string.format("%02d", index)}`, {
			CFrame = CFrame.new(position.X * 0.72, 1.03, position.Z * 0.72),
			Size = Vector3.new(0.9, 0.04, 0.9),
			Color = PALETTE.graphite,
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.18,
		})
		table.insert(surfaceTiles, tile)
	end

	for index = 1, 64 do
		local alpha = (index - 1) / 64
		local angle = alpha * math.pi * 2
		local radius = 11.5
		local segment = createVisualPart(folder, `WaveSegment_{string.format("%02d", index)}`, {
			CFrame = CFrame.new(math.cos(angle) * radius, 1.45, math.sin(angle) * radius) * CFrame.Angles(0, -angle, 0),
			Size = Vector3.new(1.45, 0.08, 0.08),
			Color = PALETTE.stone,
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.38,
		})
		table.insert(waveSegments, segment)
	end

	for index = 1, 8 do
		local alpha = (index - 1) / 8
		local angle = alpha * math.pi * 2
		local mass = createVisualPart(folder, `OrbitMass_{index}`, {
			CFrame = CFrame.new(math.cos(angle) * 7.5, 3.2, math.sin(angle) * 7.5),
			Size = Vector3.new(0.72, 0.72, 0.72),
			Shape = Enum.PartType.Ball,
			Color = PALETTE.warm,
			Material = Enum.Material.Glass,
			Transparency = 0.24,
		})
		table.insert(orbitMasses, mass)
	end
end

local function presetMotionScale(): number
	if preset == "Still" then
		return 0.35
	elseif preset == "Wave" then
		return 1.05
	elseif preset == "Orbit" then
		return 0.85
	end

	return 0.75
end

local function updatePins(frame: AudioFrame, energy: number, deltaTime: number)
	local motionScale = presetMotionScale()

	for index, pin in ipairs(fieldPins) do
		local band = frame.bands[index] or 0
		local position = getAnchorPosition(index)
		local height = 0.45 + band * 4.8 * intensity * motionScale
		local width = 0.22 + math.min(band * 0.16, 0.24)
		local color = blendColor(PALETTE.mist, if index % 5 == 0 then PALETTE.warm else PALETTE.cyan, band * 0.55)

		pin.Size = Vector3.new(width, height, width)
		pin.CFrame = CFrame.new(position + Vector3.new(0, height * 0.5, 0))
		pin.Color = color
		pin.Transparency = 0.18 - math.clamp(band * 0.08, 0, 0.08)
	end

	for index, tile in ipairs(surfaceTiles) do
		local band = frame.bands[((index * 3 - 1) % Constants.FIELD_BAND_COUNT) + 1] or 0
		local position = getAnchorPosition(index)
		local inset = if preset == "Still" then 0.58 else 0.7 + band * 0.08
		local lift = 1.02 + band * 0.12 * intensity
		tile.CFrame = CFrame.new(position.X * inset, lift, position.Z * inset)
		tile.Color = blendColor(PALETTE.graphite, PALETTE.cyan, band * 0.25 + energy * 0.1)
		tile.Transparency = 0.26 - math.clamp(band * 0.08, 0, 0.08)
	end

	if deltaTime > 0.2 and os.clock() - lastAnchorRefresh > 1 then
		refreshAnchors()
	end
end

local function updateWave(frame: AudioFrame, energy: number)
	local timeNow = frame.time
	local waveBias = if preset == "Wave" then 1.25 elseif preset == "Still" then 0.45 else 0.8

	for index, segment in ipairs(waveSegments) do
		local alpha = (index - 1) / #waveSegments
		local bandIndex = ((index - 1) % Constants.FIELD_BAND_COUNT) + 1
		local band = frame.bands[bandIndex] or 0
		local angle = alpha * math.pi * 2
		local radius = 11.5 + band * 3.4 * intensity * waveBias
		local y = 1.45 + math.sin(timeNow * 1.7 + alpha * math.pi * 2) * energy * waveBias

		segment.CFrame = CFrame.new(math.cos(angle) * radius, y, math.sin(angle) * radius) * CFrame.Angles(0, -angle, 0)
		segment.Size = Vector3.new(1.2 + band * 1.8, 0.06 + band * 0.1, 0.08)
		segment.Color = blendColor(PALETTE.stone, PALETTE.mist, band * 0.35 + energy * 0.2)
		segment.Transparency = if preset == "Field" then 0.44 else 0.3
	end
end

local function updateOrbit(frame: AudioFrame, energy: number)
	local timeNow = frame.time
	local speed = if preset == "Orbit" then 0.42 else 0.16
	local radiusBase = if preset == "Orbit" then 7.5 else 5.8

	for index, mass in ipairs(orbitMasses) do
		local alpha = (index - 1) / #orbitMasses
		local band = frame.bands[((index * 5 - 1) % Constants.FIELD_BAND_COUNT) + 1] or 0
		local angle = alpha * math.pi * 2 + timeNow * speed
		local radius = radiusBase + energy * 2.2 + band * 1.4
		local y = 2.6 + math.sin(timeNow * 1.15 + index) * (0.35 + energy * 0.7)
		local size = 0.55 + band * 0.75 + energy * 0.35

		mass.CFrame = CFrame.new(math.cos(angle) * radius, y, math.sin(angle) * radius)
		mass.Size = Vector3.new(size, size, size)
		mass.Color = blendColor(PALETTE.warm, PALETTE.cyan, band * 0.28)
		mass.Transparency = if preset == "Orbit" then 0.18 else 0.38
	end
end

local function updateVisuals(frame: AudioFrame, deltaTime: number)
	if #anchors == 0 then
		refreshAnchors()
	end

	local energy = math.clamp((frame.rms * 0.7 + frame.peak * 0.25 + frame.bass * 0.2) * intensity, 0, 1)
	updatePins(frame, energy, deltaTime)
	updateWave(frame, energy)
	updateOrbit(frame, energy)
end

function VisualizerController:Init(nextContext: any)
	if initialized then
		return
	end

	context = nextContext
	initialized = true
end

function VisualizerController:Start()
	if started then
		return
	end

	started = true
	refreshAnchors()
	buildVisuals()

	maid:Give(getRenderSignal():Connect(function(deltaTime: number)
		local frame = context.AudioInputController:GetFrame()
		updateVisuals(frame, deltaTime)
	end))
end

function VisualizerController:SetPreset(nextPreset: VisualizerPreset)
	preset = nextPreset
end

function VisualizerController:CyclePreset()
	local presets = Constants.PRESETS :: { string }
	local currentIndex = 1
	for index, presetName in ipairs(presets) do
		if presetName == preset then
			currentIndex = index
			break
		end
	end

	local nextIndex = currentIndex + 1
	if nextIndex > #presets then
		nextIndex = 1
	end

	preset = presets[nextIndex] :: VisualizerPreset
end

function VisualizerController:SetIntensity(value: number)
	local cleanValue = NumberUtil.sanitizeFiniteNumber(value, Constants.DEFAULT_INTENSITY)
	intensity = math.clamp(cleanValue, 0.2, 2)
end

function VisualizerController:GetIntensity(): number
	return intensity
end

function VisualizerController:GetPreset(): VisualizerPreset
	return preset
end

function VisualizerController:Destroy()
	maid:Cleanup()
end

return VisualizerController
