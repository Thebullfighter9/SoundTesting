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

type GridTile = {
	part: BasePart,
	row: number,
	column: number,
	basePosition: Vector3,
	radius: number,
	angle: number,
}

type RowBar = {
	part: BasePart,
	index: number,
	basePosition: Vector3,
}

type CircleBar = {
	part: BasePart,
	index: number,
	direction: Vector3,
	baseRadius: number,
	angle: number,
}

type ShockwaveRing = {
	folder: Folder,
	segments: { BasePart },
	age: number,
	strength: number,
	active: boolean,
}

local ResonanceController = {}

local initialized = false
local started = false
local context: any = nil
local maid = Maid.new()
local gridTiles: { GridTile } = {}
local rowBars: { RowBar } = {}
local circleBars: { CircleBar } = {}
local shockwaves: { ShockwaveRing } = {}
local debugMarkers: { BasePart } = {}
local style: VisualStyle = Constants.DEFAULT_VISUAL_STYLE :: VisualStyle
local intensity = Constants.DEFAULT_INTENSITY
local warnedMissingGallery = false
local lastBeatTime = 0
local shockwaveCursor = 1

local rootFolder: Folder? = nil
local gridFolder: Folder? = nil
local rowFolder: Folder? = nil
local circleFolder: Folder? = nil
local shockwaveFolder: Folder? = nil
local debugFolder: Folder? = nil

local palette = Constants.PALETTE
local fallbackCenter = Vector3.new(0, 3, 0)
local visualCenter = fallbackCenter

local SAFE_FRAME: AudioFrame = {
	rms = 0.2,
	peak = 0.32,
	bass = 0.24,
	beat = false,
	bands = {},
	time = 0,
}

local function getRenderSignal(): RBXScriptSignal
	local preRender = (RunService :: any).PreRender
	if typeof(preRender) == "RBXScriptSignal" then
		return preRender :: RBXScriptSignal
	end

	return RunService.RenderStepped
end

local function createVisualPart(parent: Instance, name: string, props: { [string]: any }): BasePart
	props.Name = name
	props.Anchored = true
	props.CanCollide = false
	props.CanTouch = false
	props.CanQuery = false
	props.CastShadow = false
	props.TopSurface = Enum.SurfaceType.Smooth
	props.BottomSurface = Enum.SurfaceType.Smooth

	return InstanceUtil.create("Part", props, parent) :: BasePart
end

local function createFolder(parent: Instance, name: string): Folder
	return InstanceUtil.create("Folder", {
		Name = name,
	}, parent) :: Folder
end

local function getGalleryCenter(): Vector3
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
				return Vector3.new(average.X, fallbackCenter.Y, average.Z)
			end
		end
	end

	if not warnedMissingGallery then
		warn("ArrayWave visualizer using fallback center because ResonanceGallery anchors are missing")
		warnedMissingGallery = true
	end

	return fallbackCenter
end

local function getOrCreateRootFolder(): Folder
	local existing = Workspace:FindFirstChild(Constants.CLIENT_VISUALS_FOLDER_NAME)
	if existing ~= nil then
		existing:Destroy()
	end

	local root = createFolder(Workspace, Constants.CLIENT_VISUALS_FOLDER_NAME)
	rootFolder = root
	gridFolder = createFolder(root, "GridArray")
	rowFolder = createFolder(root, "RowBars")
	circleFolder = createFolder(root, "RadialCircle")
	shockwaveFolder = createFolder(root, "Shockwaves")
	debugFolder = createFolder(root, "DebugMarkers")
	maid:Give(root)

	return root
end

local function setFolderVisible(folder: Folder?, visible: boolean)
	if folder == nil then
		return
	end

	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local baseTransparency = descendant:GetAttribute("BaseTransparency")
			if typeof(baseTransparency) ~= "number" then
				baseTransparency = 0
			end
			descendant.Transparency = if visible then baseTransparency else 1
		end
	end
end

local function updateVisibility()
	setFolderVisible(gridFolder, style == "Grid" or style == "All" or style == "Minimal")
	setFolderVisible(rowFolder, style == "Row" or style == "All")
	setFolderVisible(circleFolder, style == "Circle" or style == "All" or style == "Minimal")
	setFolderVisible(shockwaveFolder, style == "Grid" or style == "Circle" or style == "All" or style == "Minimal")
end

local function createGrid(center: Vector3)
	local folder = assert(gridFolder, "Grid folder missing")
	local gridSize = Constants.GRID_SIZE
	local spacing = Constants.GRID_SPACING
	local origin = (gridSize - 1) * spacing * -0.5

	for row = 1, gridSize do
		for column = 1, gridSize do
			local x = origin + (column - 1) * spacing
			local z = origin + (row - 1) * spacing
			local localPosition = Vector3.new(x, 0, z)
			local basePosition = center + Vector3.new(x, 0, z)
			local tile = createVisualPart(folder, `Grid_{row}_{column}`, {
				CFrame = CFrame.new(basePosition),
				Size = Vector3.new(0.86, 0.14, 0.86),
				Color = palette.SoftWhite:Lerp(palette.Cyan, 0.16),
				Material = Enum.Material.Neon,
				Transparency = 0.08,
			})
			tile:SetAttribute("BaseTransparency", 0.08)

			table.insert(gridTiles, {
				part = tile,
				row = row,
				column = column,
				basePosition = basePosition,
				radius = localPosition.Magnitude,
				angle = math.atan2(z, x),
			})
		end
	end
end

local function createRowBars(center: Vector3)
	local folder = assert(rowFolder, "Row folder missing")
	local count = Constants.ROW_BAR_COUNT
	local spacing = 0.72
	local origin = (count - 1) * spacing * -0.5
	local rowBase = center + Vector3.new(0, 0.15, 18)

	for index = 1, count do
		local position = rowBase + Vector3.new(origin + (index - 1) * spacing, 0, 0)
		local bar = createVisualPart(folder, `RowBar_{index}`, {
			CFrame = CFrame.new(position + Vector3.new(0, 0.5, 0)),
			Size = Vector3.new(0.38, 1, 0.62),
			Color = palette.SoftWhite:Lerp(palette.Cyan, 0.3),
			Material = Enum.Material.Neon,
			Transparency = 0.1,
		})
		bar:SetAttribute("BaseTransparency", 0.1)

		table.insert(rowBars, {
			part = bar,
			index = index,
			basePosition = position,
		})
	end
end

local function createRadialCircle(center: Vector3)
	local folder = assert(circleFolder, "Circle folder missing")
	local count = Constants.CIRCLE_BAR_COUNT
	local radius = 13.5

	for index = 1, count do
		local alpha = (index - 1) / count
		local angle = alpha * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local position = center + direction * radius + Vector3.new(0, 2.4, 0)
		local bar = createVisualPart(folder, `CircleBar_{index}`, {
			CFrame = CFrame.lookAt(position, position + direction),
			Size = Vector3.new(0.18, 0.44, 1.55),
			Color = palette.SoftWhite:Lerp(palette.Cyan, 0.36),
			Material = Enum.Material.Neon,
			Transparency = 0.12,
		})
		bar:SetAttribute("BaseTransparency", 0.12)

		table.insert(circleBars, {
			part = bar,
			index = index,
			direction = direction,
			baseRadius = radius,
			angle = angle,
		})
	end
end

local function createShockwaves(center: Vector3)
	local folder = assert(shockwaveFolder, "Shockwave folder missing")

	for ringIndex = 1, Constants.SHOCKWAVE_POOL_SIZE do
		local ringFolder = createFolder(folder, `Shockwave_{ringIndex}`)
		local segments: { BasePart } = {}
		for segmentIndex = 1, Constants.SHOCKWAVE_SEGMENT_COUNT do
			local alpha = (segmentIndex - 1) / Constants.SHOCKWAVE_SEGMENT_COUNT
			local angle = alpha * math.pi * 2
			local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local position = center + direction * 6 + Vector3.new(0, 2.15, 0)
			local segment = createVisualPart(ringFolder, `Segment_{segmentIndex}`, {
				CFrame = CFrame.lookAt(position, position + direction),
				Size = Vector3.new(0.1, 0.08, 1.1),
				Color = palette.Cyan,
				Material = Enum.Material.Neon,
				Transparency = 1,
			})
			segment:SetAttribute("BaseTransparency", 1)
			table.insert(segments, segment)
		end

		table.insert(shockwaves, {
			folder = ringFolder,
			segments = segments,
			age = 1,
			strength = 0,
			active = false,
		})
	end
end

local function createDebugMarkers(center: Vector3)
	local folder = assert(debugFolder, "Debug folder missing")
	local marker = createVisualPart(folder, "Center", {
		CFrame = CFrame.new(center),
		Size = Vector3.new(0.45, 0.45, 0.45),
		Shape = Enum.PartType.Ball,
		Color = palette.Amber,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 1,
	})
	marker:SetAttribute("BaseTransparency", 1)
	table.insert(debugMarkers, marker)
end

local function synthesizeBands(frame: AudioFrame): { number }
	local bands = table.create(Constants.VISUAL_BAND_COUNT, 0)
	local timeNow = if frame.time > 0 then frame.time else os.clock()
	local energy = math.clamp(math.max(frame.rms, frame.peak * 0.85, 0.22), 0, 1)

	for index = 1, Constants.VISUAL_BAND_COUNT do
		local alpha = (index - 1) / Constants.VISUAL_BAND_COUNT
		local wave = (math.sin(timeNow * 3.8 + alpha * math.pi * 5.5) + 1) * 0.5
		local bassShape = math.max(0, 1 - alpha * 2.3) * frame.bass
		bands[index] = math.clamp(energy * (0.34 + wave * 0.42) + bassShape * 0.44, 0, 1)
	end

	return bands
end

local function getSafeFrame(): AudioFrame
	local audio = context and context.AudioController
	if audio == nil or typeof(audio.GetFrame) ~= "function" then
		SAFE_FRAME.time = os.clock()
		SAFE_FRAME.bands = synthesizeBands(SAFE_FRAME)
		return SAFE_FRAME
	end

	local ok, frame = pcall(function()
		return audio:GetFrame()
	end)
	if not ok or typeof(frame) ~= "table" then
		SAFE_FRAME.time = os.clock()
		SAFE_FRAME.bands = synthesizeBands(SAFE_FRAME)
		return SAFE_FRAME
	end

	local audioFrame = frame :: AudioFrame
	local bands = audioFrame.bands
	local hasUsefulBand = false
	if typeof(bands) == "table" then
		for index = 1, math.min(#bands, Constants.VISUAL_BAND_COUNT) do
			if NumberUtil.sanitizeFiniteNumber(bands[index], 0) > 0.01 then
				hasUsefulBand = true
				break
			end
		end
	end

	local cleanFrame: AudioFrame = {
		rms = math.clamp(NumberUtil.sanitizeFiniteNumber(audioFrame.rms, 0), 0, 1),
		peak = math.clamp(NumberUtil.sanitizeFiniteNumber(audioFrame.peak, 0), 0, 1),
		bass = math.clamp(NumberUtil.sanitizeFiniteNumber(audioFrame.bass, 0), 0, 1),
		beat = audioFrame.beat == true,
		bands = if hasUsefulBand then bands else {},
		time = NumberUtil.sanitizeFiniteNumber(audioFrame.time, os.clock()),
	}

	if not hasUsefulBand then
		cleanFrame.bands = synthesizeBands(cleanFrame)
	end

	return cleanFrame
end

local function getBand(frame: AudioFrame, index: number): number
	local bands = frame.bands
	local bandCount = math.max(1, #bands)
	local value = bands[((index - 1) % bandCount) + 1]
	return math.clamp(NumberUtil.sanitizeFiniteNumber(value, 0), 0, 1)
end

local function activateShockwave(strength: number)
	if #shockwaves == 0 then
		return
	end

	local ring = shockwaves[shockwaveCursor]
	shockwaveCursor += 1
	if shockwaveCursor > #shockwaves then
		shockwaveCursor = 1
	end

	ring.age = 0
	ring.strength = math.clamp(strength, 0.25, 1)
	ring.active = true
end

local function updateGrid(frame: AudioFrame, energy: number)
	local gridCenter = (Constants.GRID_SIZE + 1) * 0.5
	local timeNow = frame.time
	local minimal = style == "Minimal"
	local visible = style == "Grid" or style == "All" or style == "Minimal"

	for index, tile in ipairs(gridTiles) do
		local band = getBand(frame, index + tile.row * 3 + tile.column)
		local centerDistance = math.sqrt((tile.row - gridCenter) ^ 2 + (tile.column - gridCenter) ^ 2) / gridCenter
		local radialDelay = tile.radius * 0.72
		local ripple = (math.sin(timeNow * 5.2 - radialDelay + tile.angle * 0.35) + 1) * 0.5
		local bassWeight = math.clamp(1 - centerDistance * 0.75, 0.08, 1)
		local lift = (band * 3.8 + ripple * energy * 2.2 + frame.bass * bassWeight * 2.8) * intensity
		if minimal then
			lift *= 0.35
		end

		local height = math.clamp(0.18 + band * 0.28 + energy * 0.12, 0.14, 0.62)
		tile.part.Size = Vector3.new(0.86, height, 0.86)
		tile.part.CFrame = CFrame.new(tile.basePosition + Vector3.new(0, lift + height * 0.5, 0))
		tile.part.Color = palette.SoftWhite:Lerp(palette.Cyan, math.clamp(band * 0.42 + energy * 0.18, 0, if minimal then 0.16 else 0.58))
		local transparency = if minimal then 0.42 else 0.08
		tile.part.Transparency = if visible then transparency else 1
		tile.part:SetAttribute("BaseTransparency", transparency)
	end
end

local function updateRow(frame: AudioFrame, energy: number)
	local visible = style == "Row" or style == "All"
	for _, rowBar in ipairs(rowBars) do
		local leftBias = 1 - ((rowBar.index - 1) / math.max(1, Constants.ROW_BAR_COUNT - 1))
		local centerDistance = math.abs(rowBar.index - (Constants.ROW_BAR_COUNT + 1) * 0.5) / (Constants.ROW_BAR_COUNT * 0.5)
		local band = getBand(frame, rowBar.index)
		local bassBoost = frame.bass * math.max(leftBias, 1 - centerDistance) * 1.6
		local height = math.clamp(0.7 + (band * 8.5 + bassBoost * 4 + frame.peak * 1.3) * intensity, 0.7, 12)

		rowBar.part.Size = Vector3.new(0.38, height, 0.62)
		rowBar.part.CFrame = CFrame.new(rowBar.basePosition + Vector3.new(0, height * 0.5, 0))
		rowBar.part.Color = palette.SoftWhite:Lerp(palette.Cyan, math.clamp(band * 0.55 + frame.peak * 0.14, 0, 0.64))
		rowBar.part.Transparency = if visible then 0.08 else 1
		rowBar.part:SetAttribute("BaseTransparency", 0.08)
	end
end

local function updateCircle(frame: AudioFrame, energy: number)
	local visible = style == "Circle" or style == "All" or style == "Minimal"
	for _, circleBar in ipairs(circleBars) do
		local band = getBand(frame, circleBar.index * 2)
		local wave = (math.sin(frame.time * 4.5 + circleBar.angle * 5) + 1) * 0.5
		local extension = math.clamp((band * 5.2 + frame.peak * 1.2 + wave * energy * 1.5) * intensity, 0.45, 7.5)
		local yLift = 2.4 + frame.bass * 1.1
		local position = visualCenter + Vector3.new(0, yLift, 0) + circleBar.direction * (circleBar.baseRadius + extension * 0.5)

		circleBar.part.Size = Vector3.new(0.18, 0.44 + band * 0.42, 1.2 + extension)
		circleBar.part.CFrame = CFrame.lookAt(position, position + circleBar.direction)
		circleBar.part.Color = palette.SoftWhite:Lerp(palette.Cyan, math.clamp(band * 0.52 + energy * 0.18, 0, 0.68))
		local transparency = if style == "Minimal" then 0.42 else 0.12
		circleBar.part.Transparency = if visible then transparency else 1
		circleBar.part:SetAttribute("BaseTransparency", transparency)
	end
end

local function updateShockwaves(deltaTime: number)
	local visible = style == "Grid" or style == "Circle" or style == "All" or style == "Minimal"
	for _, ring in ipairs(shockwaves) do
		if ring.active then
			ring.age += deltaTime / 0.45
			if ring.age >= 1 then
				ring.active = false
				for _, segment in ipairs(ring.segments) do
					segment.Transparency = 1
					segment:SetAttribute("BaseTransparency", 1)
				end
			else
				local alpha = 1 - ring.age
				local radius = 7 + ring.age * 24
				local visibleScale = if style == "Minimal" then 0.25 else 0.55
				local transparency = math.clamp(1 - alpha * ring.strength * visibleScale, 0.38, 1)
				for index, segment in ipairs(ring.segments) do
					local segmentAlpha = (index - 1) / #ring.segments
					local angle = segmentAlpha * math.pi * 2
					local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
					local position = visualCenter + Vector3.new(0, 2.25 + alpha * 0.9, 0) + direction * radius
					segment.CFrame = CFrame.lookAt(position, position + direction)
					segment.Size = Vector3.new(0.12, 0.08, 1.05 + alpha * 1.2)
					segment.Transparency = if visible then transparency else 1
					segment:SetAttribute("BaseTransparency", transparency)
				end
			end
		end
	end
end

local function updateVisuals(deltaTime: number)
	local frame = getSafeFrame()
	local energy = math.clamp((frame.rms * 0.65 + frame.peak * 0.3 + frame.bass * 0.24) * intensity, 0, 1)

	if frame.beat and frame.time - lastBeatTime > 0.08 then
		lastBeatTime = frame.time
		activateShockwave(math.max(frame.peak, frame.bass, 0.35))
	end

	updateGrid(frame, energy)
	updateRow(frame, energy)
	updateCircle(frame, energy)
	updateShockwaves(deltaTime)

	local camera = context and context.CameraController
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
	local center = getGalleryCenter()
	visualCenter = center
	getOrCreateRootFolder()
	createGrid(center)
	createRowBars(center)
	createRadialCircle(center)
	createShockwaves(center)
	createDebugMarkers(center)
	updateVisibility()

	maid:Give(getRenderSignal():Connect(updateVisuals))
end

function ResonanceController:SetStyle(nextStyle: VisualStyle)
	style = nextStyle
	updateVisibility()
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

	self:SetStyle(styles[nextIndex] :: VisualStyle)
end

function ResonanceController:SetIntensity(value: number)
	intensity = math.clamp(NumberUtil.sanitizeFiniteNumber(value, Constants.DEFAULT_INTENSITY), 0.2, 2.5)
end

function ResonanceController:GetIntensity(): number
	return intensity
end

function ResonanceController:GetStyle(): VisualStyle
	return style
end

function ResonanceController:TriggerPulse(strength: number)
	activateShockwave(strength)
end

function ResonanceController:TriggerPulseTest()
	self:TriggerPulse(0.85)
end

function ResonanceController:GetDebugCounts(): { [string]: number }
	return {
		GridArray = #gridTiles,
		RowBars = #rowBars,
		RadialCircle = #circleBars,
		Shockwaves = #shockwaves,
		DebugMarkers = #debugMarkers,
	}
end

function ResonanceController:Destroy()
	maid:Cleanup()
end

return ResonanceController
