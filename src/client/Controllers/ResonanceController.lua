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

type AudioFrame = Types.AudioFrame
type VisualStyle = Types.VisualStyle

type TileVisual = {
	part: BasePart,
	basePosition: Vector3,
	row: number,
	column: number,
	radius: number,
	angle: number,
}

local ResonanceController = {}

local initialized = false
local started = false
local context: any = nil
local maid = Maid.new()
local tiles: { TileVisual } = {}
local orbitPoints: { BasePart } = {}
local shockwaveSegments: { BasePart } = {}
local speakerOverlays: { BasePart } = {}
local style: VisualStyle = "Field"
local intensity = Constants.DEFAULT_INTENSITY
local shockwaveAge = 1
local shockwaveStrength = 0

local palette = Constants.PALETTE

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

local function getLocalFolder(): Folder
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

local function collectAnchorData(): { TileVisual }
	local anchorTiles: { TileVisual } = {}
	local gallery = Workspace:WaitForChild(Constants.GALLERY_FOLDER_NAME, 10)
	local anchorFolder = if gallery ~= nil then gallery:WaitForChild(Constants.ANCHORS_FOLDER_NAME, 10) else nil

	if anchorFolder ~= nil then
		local anchors = anchorFolder:GetChildren()
		table.sort(anchors, function(a: Instance, b: Instance): boolean
			return a.Name < b.Name
		end)

		for _, anchor in ipairs(anchors) do
			if anchor:IsA("BasePart") then
				local row = anchor:GetAttribute("Row")
				local column = anchor:GetAttribute("Column")
				if typeof(row) == "number" and typeof(column) == "number" then
					local position = anchor.Position
					table.insert(anchorTiles, {
						part = anchor,
						basePosition = position,
						row = row,
						column = column,
						radius = Vector3.new(position.X, 0, position.Z).Magnitude,
						angle = math.atan2(position.Z, position.X),
					})
				end
			end
		end
	end

	if #anchorTiles > 0 then
		return anchorTiles
	end

	local gridSize = Constants.FIELD_GRID_SIZE
	local spacing = 1.55
	local origin = (gridSize - 1) * spacing * -0.5
	for row = 1, gridSize do
		for column = 1, gridSize do
			local position = Vector3.new(origin + (column - 1) * spacing, 1.2, origin + (row - 1) * spacing)
			table.insert(anchorTiles, {
				part = Workspace.Terrain,
				basePosition = position,
				row = row,
				column = column,
				radius = Vector3.new(position.X, 0, position.Z).Magnitude,
				angle = math.atan2(position.Z, position.X),
			})
		end
	end

	return anchorTiles
end

local function createTiles(folder: Folder, anchorTiles: { TileVisual })
	for _, data in ipairs(anchorTiles) do
		local tile = createVisualPart(folder, `Tile_{data.row}_{data.column}`, {
			CFrame = CFrame.new(data.basePosition + Vector3.new(0, 0.06, 0)),
			Size = Vector3.new(1.18, 0.08, 1.18),
			Color = palette.Graphite:Lerp(palette.SoftWhite, 0.08),
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.05,
		})

		table.insert(tiles, {
			part = tile,
			basePosition = data.basePosition,
			row = data.row,
			column = data.column,
			radius = data.radius,
			angle = data.angle,
		})
	end
end

local function createOrbitPoints(folder: Folder)
	for index = 1, 24 do
		local alpha = (index - 1) / 24
		local angle = alpha * math.pi * 2
		local point = createVisualPart(folder, `OrbitPoint_{index}`, {
			CFrame = CFrame.new(math.cos(angle) * 18, 2.4, math.sin(angle) * 18),
			Size = Vector3.new(0.34, 0.34, 0.34),
			Shape = Enum.PartType.Ball,
			Color = palette.SoftWhite,
			Material = Enum.Material.Glass,
			Transparency = 0.42,
		})
		table.insert(orbitPoints, point)
	end
end

local function createShockwave(folder: Folder)
	for index = 1, 48 do
		local alpha = (index - 1) / 48
		local angle = alpha * math.pi * 2
		local segment = createVisualPart(folder, `Shockwave_{index}`, {
			CFrame = CFrame.new(math.cos(angle) * 4, 1.55, math.sin(angle) * 4) * CFrame.Angles(0, -angle, 0),
			Size = Vector3.new(0.8, 0.05, 0.05),
			Color = palette.Cyan,
			Material = Enum.Material.Glass,
			Transparency = 1,
		})
		table.insert(shockwaveSegments, segment)
	end
end

local function createSpeakerOverlays(folder: Folder)
	local positions = {
		Vector3.new(-31, 3.45, -26.25),
		Vector3.new(31, 3.45, -26.25),
		Vector3.new(-31, 3.45, 23.75),
		Vector3.new(31, 3.45, 23.75),
	}

	for index, position in ipairs(positions) do
		local overlay = createVisualPart(folder, `SpeakerOverlay_{index}`, {
			CFrame = CFrame.new(position),
			Size = Vector3.new(1.6, 4.4, 0.07),
			Color = palette.Cyan,
			Material = Enum.Material.Glass,
			Transparency = 0.82,
		})
		table.insert(speakerOverlays, overlay)
	end
end

local function styleScale(): number
	if style == "Minimal" then
		return 0.38
	elseif style == "Marbles" then
		return 1.08
	elseif style == "Orbit" then
		return 0.78
	end

	return 0.9
end

local function updateTiles(frame: AudioFrame, energy: number)
	local gridCenter = (Constants.FIELD_GRID_SIZE + 1) * 0.5
	local motionScale = styleScale()
	local timeNow = frame.time

	for index, tile in ipairs(tiles) do
		local band = frame.bands[((index - 1) % Constants.VISUAL_BAND_COUNT) + 1] or 0
		local radialWave = (math.sin(timeNow * 3.1 - tile.radius * 0.55) + 1) * 0.5
		local centerDistance = math.sqrt((tile.row - gridCenter) ^ 2 + (tile.column - gridCenter) ^ 2) / gridCenter
		local centerWeight = math.clamp(1 - centerDistance * 0.7, 0.15, 1)
		local bassLift = frame.bass * centerWeight * 1.35
		local height = (band * 2.2 + radialWave * energy * 1.35 + bassLift) * intensity * motionScale
		local scale = 1 + math.clamp(band * 0.05 + energy * 0.035, 0, 0.08)
		local colorWeight = if style == "Minimal" then band * 0.12 else band * 0.32 + energy * 0.16

		tile.part.Size = Vector3.new(1.18 * scale, 0.08 + band * 0.05, 1.18 * scale)
		tile.part.CFrame = CFrame.new(tile.basePosition + Vector3.new(0, 0.05 + height, 0))
		tile.part.Color = palette.Graphite:Lerp(palette.Cyan, math.clamp(colorWeight, 0, 0.38)):Lerp(palette.SoftWhite, if style == "Minimal" then 0.04 else band * 0.12)
		tile.part.Transparency = if style == "Minimal" then 0.18 else 0.06
	end
end

local function updateOrbit(frame: AudioFrame, energy: number)
	local visible = if style == "Minimal" then 0.12 elseif style == "Field" then 0.42 else 0.82
	local radius = if style == "Orbit" then 19 + energy * 2.2 else 17.5 + energy * 0.8
	local speed = if style == "Orbit" then 0.28 else 0.1

	for index, point in ipairs(orbitPoints) do
		local alpha = (index - 1) / #orbitPoints
		local band = frame.bands[((index * 2 - 1) % Constants.VISUAL_BAND_COUNT) + 1] or 0
		local angle = alpha * math.pi * 2 + frame.time * speed
		local y = 2.35 + math.sin(frame.time * 0.9 + index) * (0.25 + energy * 0.55)
		local size = 0.24 + visible * 0.22 + band * 0.18

		point.CFrame = CFrame.new(math.cos(angle) * radius, y, math.sin(angle) * radius)
		point.Size = Vector3.new(size, size, size)
		point.Color = palette.SoftWhite:Lerp(palette.Cyan, math.clamp(band * 0.45, 0, 0.45))
		point.Transparency = 0.72 - visible * 0.35
	end
end

local function updateShockwave(frame: AudioFrame)
	if frame.beat then
		shockwaveAge = 0
		shockwaveStrength = math.clamp(math.max(frame.peak, frame.bass), 0, 1)
	end

	shockwaveAge = math.min(shockwaveAge + 0.035, 1)
	local alpha = 1 - shockwaveAge
	local radius = 5 + shockwaveAge * 23
	local transparency = 1 - alpha * shockwaveStrength * (if style == "Minimal" then 0.22 else 0.45)

	for index, segment in ipairs(shockwaveSegments) do
		local ringAlpha = (index - 1) / #shockwaveSegments
		local angle = ringAlpha * math.pi * 2
		segment.CFrame = CFrame.new(math.cos(angle) * radius, 1.5 + alpha * 0.8, math.sin(angle) * radius) * CFrame.Angles(0, -angle, 0)
		segment.Size = Vector3.new(1.3 + alpha * 1.2, 0.04, 0.05)
		segment.Transparency = math.clamp(transparency, 0.52, 1)
	end
end

local function updateSpeakers(frame: AudioFrame)
	local pulse = math.clamp((frame.bass * 0.45 + frame.peak * 0.18) * intensity, 0, 1)
	for _, overlay in ipairs(speakerOverlays) do
		overlay.Transparency = 0.86 - pulse * 0.22
		overlay.Size = Vector3.new(1.6 + pulse * 0.3, 4.4 + pulse * 0.6, 0.07)
	end
end

local function updateVisuals(deltaTime: number)
	local frame = context.AudioController:GetFrame()
	local energy = math.clamp((frame.rms * 0.72 + frame.peak * 0.25 + frame.bass * 0.2) * intensity, 0, 1)

	updateTiles(frame, energy)
	updateOrbit(frame, energy)
	updateShockwave(frame)
	updateSpeakers(frame)

	local camera = context.CameraController
	if camera ~= nil and typeof(camera.Update) == "function" then
		camera:Update(deltaTime, frame, style)
	end
end

function ResonanceController:Init(nextContext: any)
	if initialized then
		return
	end

	context = nextContext
	initialized = true
end

function ResonanceController:Start()
	if started then
		return
	end

	started = true
	local folder = getLocalFolder()
	local anchorTiles = collectAnchorData()
	createTiles(folder, anchorTiles)
	createOrbitPoints(folder)
	createShockwave(folder)
	createSpeakerOverlays(folder)

	maid:Give(getRenderSignal():Connect(updateVisuals))
end

function ResonanceController:SetStyle(nextStyle: VisualStyle)
	style = nextStyle
end

function ResonanceController:CycleStyle()
	local styles = Constants.VISUAL_STYLES :: { string }
	local currentIndex = 1
	for index, styleName in ipairs(styles) do
		if styleName == style then
			currentIndex = index
			break
		end
	end

	local nextIndex = currentIndex + 1
	if nextIndex > #styles then
		nextIndex = 1
	end

	style = styles[nextIndex] :: VisualStyle
end

function ResonanceController:SetIntensity(value: number)
	intensity = math.clamp(NumberUtil.sanitizeFiniteNumber(value, Constants.DEFAULT_INTENSITY), 0.2, 2)
end

function ResonanceController:GetIntensity(): number
	return intensity
end

function ResonanceController:GetStyle(): VisualStyle
	return style
end

function ResonanceController:Destroy()
	maid:Cleanup()
end

return ResonanceController
