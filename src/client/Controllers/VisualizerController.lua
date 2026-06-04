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
local visualFolder: Folder? = nil
local anchors: { BasePart } = {}
local bars: { BasePart } = {}
local ringParts: { BasePart } = {}
local orbitParts: { BasePart } = {}
local beamParts: { BasePart } = {}
local speakerCones: { BasePart } = {}
local burstEmitter: ParticleEmitter? = nil
local preset: VisualizerPreset = "Bars"
local intensity = Constants.DEFAULT_INTENSITY
local lastBurstTime = 0

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
	local existing = camera:FindFirstChild("PulseForgeClientVisuals")
	if existing ~= nil then
		existing:Destroy()
	end

	local folder = InstanceUtil.create("Folder", {
		Name = "PulseForgeClientVisuals",
	}, camera) :: Folder

	visualFolder = folder
	maid:Give(folder)
	return folder
end

local function refreshAnchors()
	anchors = {}

	local lab = Workspace:FindFirstChild(Constants.LAB_FOLDER_NAME)
	if lab == nil then
		return
	end

	local anchorFolder = lab:FindFirstChild("VisualizerAnchors")
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
	local alpha = (index - 1) / Constants.VISUALIZER_BAND_COUNT
	local angle = alpha * math.pi * 2
	return Vector3.new(math.cos(angle) * 38, 1.45, math.sin(angle) * 38)
end

local function getAnchorPosition(index: number): Vector3
	local anchor = anchors[index]
	if anchor ~= nil and anchor.Parent ~= nil then
		return anchor.Position
	end

	return fallbackAnchorPosition(index)
end

local function createBasePart(parent: Instance, name: string, props: { [string]: any }): BasePart
	props.Name = name
	props.Anchored = true
	props.CanCollide = false
	props.CanTouch = false
	props.CanQuery = false
	props.TopSurface = Enum.SurfaceType.Smooth
	props.BottomSurface = Enum.SurfaceType.Smooth

	return InstanceUtil.create("Part", props, parent) :: BasePart
end

local function createVisuals()
	local folder = getOrCreateFolder()

	for index = 1, Constants.VISUALIZER_BAND_COUNT do
		local part = createBasePart(folder, `BandBar_{string.format("%02d", index)}`, {
			CFrame = CFrame.new(getAnchorPosition(index)),
			Size = Vector3.new(1.05, 1, 1.05),
			Color = Color3.fromHSV(index / Constants.VISUALIZER_BAND_COUNT, 0.82, 1),
			Material = Enum.Material.Neon,
			Transparency = 0.08,
		})
		table.insert(bars, part)
	end

	for index = 1, 48 do
		local alpha = (index - 1) / 48
		local angle = alpha * math.pi * 2
		local radius = 22
		local part = createBasePart(folder, `WaveRing_{string.format("%02d", index)}`, {
			CFrame = CFrame.new(math.cos(angle) * radius, 3.2, math.sin(angle) * radius) * CFrame.Angles(0, -angle, 0),
			Size = Vector3.new(3.2, 0.22, 0.38),
			Color = Color3.fromHSV(alpha, 0.88, 1),
			Material = Enum.Material.Neon,
			Transparency = 0.22,
		})
		table.insert(ringParts, part)
	end

	for index = 1, 12 do
		local alpha = (index - 1) / 12
		local part = createBasePart(folder, `OrbitNode_{string.format("%02d", index)}`, {
			CFrame = CFrame.new(math.cos(alpha * math.pi * 2) * 12, 8, math.sin(alpha * math.pi * 2) * 12),
			Size = Vector3.new(1.2, 1.2, 1.2),
			Shape = Enum.PartType.Ball,
			Color = Color3.fromHSV(alpha, 0.8, 1),
			Material = Enum.Material.Neon,
			Transparency = 0.18,
		})
		table.insert(orbitParts, part)
	end

	for index = 1, 24 do
		local alpha = (index - 1) / 24
		local part = createBasePart(folder, `RingBeam_{string.format("%02d", index)}`, {
			CFrame = CFrame.new(0, 3, 0),
			Size = Vector3.new(0.16, 0.16, 5),
			Color = Color3.fromHSV(alpha, 0.75, 1),
			Material = Enum.Material.Neon,
			Transparency = 0.62,
		})
		table.insert(beamParts, part)
	end

	for side = -1, 1, 2 do
		for level = 1, 3 do
			local part = createBasePart(folder, `LocalSpeakerCone_{side}_{level}`, {
				CFrame = CFrame.new(side * 32, 3.5 + level * 3.1, 8.2) * CFrame.Angles(math.rad(90), 0, 0),
				Size = Vector3.new(3.6, 0.25, 3.6),
				Shape = Enum.PartType.Cylinder,
				Color = if side < 0 then Color3.fromRGB(0, 242, 255) else Color3.fromRGB(255, 64, 188),
				Material = Enum.Material.Neon,
				Transparency = 0.32,
			})
			table.insert(speakerCones, part)
		end
	end

	local burstPart = createBasePart(folder, "BeatBurstEmitterPart", {
		CFrame = CFrame.new(0, 4, 0),
		Size = Vector3.new(1, 1, 1),
		Color = Color3.new(1, 1, 1),
		Transparency = 1,
	})

	local attachment = InstanceUtil.create("Attachment", {
		Name = "BurstAttachment",
	}, burstPart) :: Attachment

	burstEmitter = InstanceUtil.create("ParticleEmitter", {
		Name = "BeatBurst",
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 242, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 64, 188)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
		}),
		LightEmission = 0.7,
		Lifetime = NumberRange.new(0.35, 0.65),
		Rate = 0,
		Speed = NumberRange.new(18, 34),
		SpreadAngle = Vector2.new(360, 55),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, attachment) :: ParticleEmitter
end

local function presetScale(): number
	if preset == "Calm" then
		return 0.55
	elseif preset == "Chaos" then
		return 1.45
	elseif preset == "Physics" then
		return 1.25
	elseif preset == "Ring" then
		return 1.1
	elseif preset == "Orbit" then
		return 1.05
	end

	return 1
end

local function updateBeam(part: BasePart, a: Vector3, b: Vector3, color: Color3, transparency: number)
	local mid = (a + b) * 0.5
	local distance = (a - b).Magnitude
	part.Size = Vector3.new(0.12, 0.12, math.max(0.1, distance))
	part.CFrame = CFrame.lookAt(mid, b)
	part.Color = color
	part.Transparency = transparency
end

local function updateVisuals(frame: AudioFrame, deltaTime: number)
	if #anchors == 0 then
		refreshAnchors()
	end

	local now = frame.time
	local scale = presetScale()
	local energy = math.clamp((frame.rms * 0.75 + frame.peak * 0.35 + frame.bass * 0.25) * intensity * scale, 0, 1)
	local maxHeight = if preset == "Calm" then 15 else 28
	local barWidth = if preset == "Chaos" then 1.45 else 1.05

	for index, bar in ipairs(bars) do
		local band = frame.bands[index] or 0
		local anchorPosition = getAnchorPosition(index)
		local height = 1 + band * maxHeight * intensity * scale
		bar.Size = Vector3.new(barWidth, height, barWidth)
		bar.CFrame = CFrame.new(anchorPosition + Vector3.new(0, height * 0.5, 0))
		bar.Color = Color3.fromHSV((index / #bars + now * 0.035) % 1, if preset == "Calm" then 0.42 else 0.86, 0.75 + energy * 0.25)
		bar.Transparency = if preset == "Ring" then 0.28 else 0.08
	end

	for index, part in ipairs(ringParts) do
		local alpha = (index - 1) / #ringParts
		local bandIndex = ((index - 1) % Constants.VISUALIZER_BAND_COUNT) + 1
		local band = frame.bands[bandIndex] or 0
		local radius = 21 + band * 7 * intensity * scale
		local angle = alpha * math.pi * 2 + now * (if preset == "Calm" then 0.08 else 0.22)
		local y = 3.1 + math.sin(now * 2 + alpha * math.pi * 2) * energy * 1.4
		part.CFrame = CFrame.new(math.cos(angle) * radius, y, math.sin(angle) * radius) * CFrame.Angles(0, -angle, 0)
		part.Size = Vector3.new(2.5 + band * 3, 0.2 + band * 0.5, 0.34)
		part.Color = Color3.fromHSV((alpha + now * 0.025) % 1, 0.84, 0.7 + energy * 0.3)
		part.Transparency = if preset == "Bars" then 0.55 else 0.16
	end

	for index, part in ipairs(orbitParts) do
		local alpha = (index - 1) / #orbitParts
		local speed = if preset == "Calm" then 0.25 else 0.72
		local radius = 9 + index * 0.7 + energy * 7
		local angle = alpha * math.pi * 2 + now * speed
		local y = 7 + math.sin(now * 1.6 + index) * (1.5 + energy * 5)
		local size = 0.8 + energy * 2.2 + (frame.bands[((index - 1) % Constants.VISUALIZER_BAND_COUNT) + 1] or 0)
		part.CFrame = CFrame.new(math.cos(angle) * radius, y, math.sin(angle) * radius)
		part.Size = Vector3.new(size, size, size)
		part.Transparency = if preset == "Orbit" or preset == "Chaos" then 0.08 else 0.45
	end

	for index, cone in ipairs(speakerCones) do
		local pulse = energy + (frame.bands[((index - 1) % Constants.VISUALIZER_BAND_COUNT) + 1] or 0) * 0.45
		local size = 3.2 + pulse * 1.9
		cone.Size = Vector3.new(size, 0.22 + pulse * 0.24, size)
		cone.Transparency = 0.38 - math.clamp(pulse * 0.2, 0, 0.2)
	end

	for index, part in ipairs(beamParts) do
		local aIndex = ((index - 1) % Constants.VISUALIZER_BAND_COUNT) + 1
		local bIndex = ((index + 7) % Constants.VISUALIZER_BAND_COUNT) + 1
		local a = getAnchorPosition(aIndex) + Vector3.new(0, 5 + energy * 4, 0)
		local b = getAnchorPosition(bIndex) + Vector3.new(0, 5 + energy * 4, 0)
		updateBeam(part, a, b, Color3.fromHSV((index / #beamParts + now * 0.04) % 1, 0.75, 1), if preset == "Chaos" then 0.22 else 0.62)
	end

	if frame.beat and now - lastBurstTime > 0.08 then
		lastBurstTime = now
		local emitter = burstEmitter
		if emitter ~= nil then
			emitter:Emit(math.clamp(math.floor(12 + energy * 42), 8, 52))
		end
	end

	if deltaTime > 0.25 then
		refreshAnchors()
	end
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
	createVisuals()

	maid:Give(getRenderSignal():Connect(function(deltaTime: number)
		local audio = context.AudioInputController
		local frame = audio:GetFrame()
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
	intensity = math.clamp(cleanValue, 0.25, 3)
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
