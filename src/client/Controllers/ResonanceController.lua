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
	centerWeight: number,
	edgeWeight: number,
}

type RowBar = {
	part: BasePart,
	peakPart: BasePart,
	index: number,
	basePosition: Vector3,
	peakHeight: number,
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

type AccentLight = {
	part: BasePart,
	light: PointLight,
	angle: number,
	radius: number,
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
local accentLights: { AccentLight } = {}
local style: VisualStyle = Constants.DEFAULT_VISUAL_STYLE :: VisualStyle
local intensity = Constants.DEFAULT_INTENSITY
local warnedMissingGallery = false
local lastBeatTime = 0
local shockwaveCursor = 1
local pulseAge = 10
local pulseStrength = 0

local rootFolder: Folder? = nil
local gridFolder: Folder? = nil
local rowFolder: Folder? = nil
local circleFolder: Folder? = nil
local shockwaveFolder: Folder? = nil
local accentFolder: Folder? = nil

local palette = Constants.PALETTE
local fallbackCenter = Vector3.new(0, 3, 0)
local visualCenter = fallbackCenter
local audioBandCount = Constants.AUDIO_BAND_COUNT or Constants.VISUAL_BAND_COUNT

local SAFE_FRAME: AudioFrame = {
	rms = 0.2,
	peak = 0.32,
	bass = 0.24,
	lowMid = 0.18,
	mid = 0.14,
	high = 0.08,
	air = 0.04,
	beat = false,
	beatStrength = 0,
	transient = 0,
	spectralFlux = 0,
	centroid = 0.35,
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

local function clamp01(value: any): number
	return math.clamp(NumberUtil.sanitizeFiniteNumber(value, 0), 0, 1)
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
	accentFolder = createFolder(root, "AccentLights")
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
		elseif descendant:IsA("PointLight") then
			local baseBrightness = descendant:GetAttribute("BaseBrightness")
			if typeof(baseBrightness) ~= "number" then
				baseBrightness = descendant.Brightness
			end
			descendant.Brightness = if visible then baseBrightness else 0
		end
	end
end

local function updateVisibility()
	local showGrid = style == "Grid" or style == "All" or style == "Minimal"
	local showRow = style == "Row" or style == "All"
	local showCircle = style == "Circle" or style == "All" or style == "Minimal"
	local showShock = style == "Grid" or style == "Circle" or style == "All" or style == "Minimal"
	local showAccent = style == "Grid" or style == "Row" or style == "Circle" or style == "All"

	setFolderVisible(gridFolder, showGrid)
	setFolderVisible(rowFolder, showRow)
	setFolderVisible(circleFolder, showCircle)
	setFolderVisible(shockwaveFolder, showShock)
	setFolderVisible(accentFolder, showAccent)
end

local function createGrid(center: Vector3)
	local folder = assert(gridFolder, "Grid folder missing")
	local gridSize = Constants.GRID_SIZE
	local spacing = Constants.GRID_SPACING
	local origin = (gridSize - 1) * spacing * -0.5
	local gridCenter = (gridSize + 1) * 0.5

	for row = 1, gridSize do
		for column = 1, gridSize do
			local x = origin + (column - 1) * spacing
			local z = origin + (row - 1) * spacing
			local localPosition = Vector3.new(x, 0, z)
			local basePosition = center + Vector3.new(x, 0, z)
			local normalizedDistance = math.sqrt((row - gridCenter) ^ 2 + (column - gridCenter) ^ 2) / gridCenter
			local centerWeight = math.clamp(1 - normalizedDistance, 0, 1)
			local tile = createVisualPart(folder, `Grid_{row}_{column}`, {
				CFrame = CFrame.new(basePosition),
				Size = Vector3.new(0.78, 0.12, 0.78),
				Color = palette.Text:Lerp(palette.Cyan, 0.12),
				Material = Enum.Material.Neon,
				Transparency = 0.12,
			})
			tile:SetAttribute("BaseTransparency", 0.12)

			table.insert(gridTiles, {
				part = tile,
				row = row,
				column = column,
				basePosition = basePosition,
				radius = localPosition.Magnitude,
				angle = math.atan2(z, x),
				centerWeight = centerWeight,
				edgeWeight = 1 - centerWeight,
			})
		end
	end
end

local function createRowBars(center: Vector3)
	local folder = assert(rowFolder, "Row folder missing")
	local accents = assert(accentFolder, "Accent folder missing")
	local peakFolder = createFolder(accents, "RowPeakCaps")
	local count = Constants.ROW_BAR_COUNT
	local spacing = 0.5
	local origin = (count - 1) * spacing * -0.5
	local rowBase = center + Vector3.new(0, 0.15, 17.2)

	for index = 1, count do
		local position = rowBase + Vector3.new(origin + (index - 1) * spacing, 0, 0)
		local bar = createVisualPart(folder, `RowBar_{index}`, {
			CFrame = CFrame.new(position + Vector3.new(0, 0.42, 0)),
			Size = Vector3.new(0.3, 0.84, 0.54),
			Color = palette.Text:Lerp(palette.Cyan, 0.26),
			Material = Enum.Material.Neon,
			Transparency = 0.1,
		})
		bar:SetAttribute("BaseTransparency", 0.1)

		local peakPart = createVisualPart(peakFolder, `PeakCap_{index}`, {
			CFrame = CFrame.new(position + Vector3.new(0, 1.1, 0)),
			Size = Vector3.new(0.32, 0.08, 0.58),
			Color = palette.CyanSoft,
			Material = Enum.Material.Neon,
			Transparency = 0.22,
		})
		peakPart:SetAttribute("BaseTransparency", 0.22)

		table.insert(rowBars, {
			part = bar,
			peakPart = peakPart,
			index = index,
			basePosition = position,
			peakHeight = 0.8,
		})
	end
end

local function createRadialCircle(center: Vector3)
	local folder = assert(circleFolder, "Circle folder missing")
	local count = Constants.CIRCLE_BAR_COUNT
	local radius = 12.4

	for index = 1, count do
		local alpha = (index - 1) / count
		local angle = alpha * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local position = center + direction * radius + Vector3.new(0, 2.55, 0)
		local bar = createVisualPart(folder, `CircleBar_{index}`, {
			CFrame = CFrame.lookAt(position, position + direction),
			Size = Vector3.new(0.14, 0.4, 1.28),
			Color = palette.Text:Lerp(palette.Cyan, 0.34),
			Material = Enum.Material.Neon,
			Transparency = 0.14,
		})
		bar:SetAttribute("BaseTransparency", 0.14)

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
			local position = center + direction * 6 + Vector3.new(0, 2.2, 0)
			local segment = createVisualPart(ringFolder, `Segment_{segmentIndex}`, {
				CFrame = CFrame.lookAt(position, position + direction),
				Size = Vector3.new(0.09, 0.06, 0.96),
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

local function createAccentLights(center: Vector3)
	local folder = assert(accentFolder, "Accent folder missing")
	local glintFolder = createFolder(folder, "Glints")
	for index = 1, Constants.ACCENT_LIGHT_COUNT do
		local alpha = (index - 1) / Constants.ACCENT_LIGHT_COUNT
		local angle = alpha * math.pi * 2
		local radius = 8 + (index % 3) * 3.5
		local position = center + Vector3.new(math.cos(angle) * radius, 2.2, math.sin(angle) * radius)
		local part = createVisualPart(glintFolder, `Accent_{index}`, {
			CFrame = CFrame.new(position),
			Size = Vector3.new(0.18, 0.18, 0.18),
			Shape = Enum.PartType.Ball,
			Color = palette.CyanSoft,
			Material = Enum.Material.Neon,
			Transparency = 0.78,
		})
		part:SetAttribute("BaseTransparency", 0.78)
		local light = InstanceUtil.create("PointLight", {
			Name = "Glow",
			Brightness = 0.2,
			Color = palette.CyanSoft,
			Range = 7,
			Shadows = false,
		}, part) :: PointLight
		light:SetAttribute("BaseBrightness", 0.2)

		table.insert(accentLights, {
			part = part,
			light = light,
			angle = angle,
			radius = radius,
		})
	end
end

local function synthesizeBands(frame: AudioFrame): { number }
	local bands = table.create(audioBandCount, 0)
	local timeNow = if frame.time > 0 then frame.time else os.clock()
	local energy = math.clamp(math.max(frame.rms, frame.peak * 0.85, 0.22), 0, 1)

	for index = 1, audioBandCount do
		local alpha = (index - 1) / audioBandCount
		local wave = (math.sin(timeNow * 3.8 + alpha * math.pi * 5.5) + 1) * 0.5
		local shimmer = (math.sin(timeNow * 12 + alpha * math.pi * 22) + 1) * 0.5
		local bassShape = math.max(0, 1 - alpha * 3) * frame.bass
		bands[index] = math.clamp(energy * (0.22 + wave * 0.28 + shimmer * alpha * 0.12) + bassShape * 0.48, 0, 1)
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
		for index = 1, math.min(#bands, audioBandCount) do
			if NumberUtil.sanitizeFiniteNumber(bands[index], 0) > 0.01 then
				hasUsefulBand = true
				break
			end
		end
	end

	local cleanFrame: AudioFrame = {
		rms = clamp01(audioFrame.rms),
		peak = clamp01(audioFrame.peak),
		bass = clamp01(audioFrame.bass),
		lowMid = clamp01(audioFrame.lowMid),
		mid = clamp01(audioFrame.mid),
		high = clamp01(audioFrame.high),
		air = clamp01(audioFrame.air),
		beat = audioFrame.beat == true,
		beatStrength = clamp01(audioFrame.beatStrength),
		transient = clamp01(audioFrame.transient),
		spectralFlux = clamp01(audioFrame.spectralFlux),
		centroid = clamp01(audioFrame.centroid),
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
	local count = math.max(1, #bands)
	local value = bands[((index - 1) % count) + 1]
	return clamp01(value)
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
	ring.strength = math.clamp(strength, 0.18, 1)
	ring.active = true
	pulseAge = 0
	pulseStrength = math.max(pulseStrength, ring.strength)
end

local function updateGrid(frame: AudioFrame, energy: number)
	local timeNow = frame.time
	local minimal = style == "Minimal"
	local visible = style == "Grid" or style == "All" or style == "Minimal"
	local pulse = math.clamp(1 - pulseAge / 0.45, 0, 1) * pulseStrength
	local centroidEdge = math.clamp(frame.centroid, 0, 1)

	for index, tile in ipairs(gridTiles) do
		local band = getBand(frame, index + tile.row * 5 + tile.column * 2)
		local dome = frame.bass * tile.centerWeight * (3.4 + pulse * 2.8)
		local diagonal = (math.sin(timeNow * 5.1 + (tile.row + tile.column) * 0.34) + 1) * 0.5 * frame.lowMid * 2.2
		local midRipple = (math.sin(timeNow * 4.2 - tile.radius * 0.56 + tile.angle * 1.4) + 1) * 0.5 * frame.mid * 1.8
		local beatRipple = math.max(0, 1 - math.abs(tile.radius - pulseAge * 46) / 4.2) * pulse * 4.2
		local highShimmer = (math.sin(timeNow * 18 + tile.angle * 7 + index) + 1) * 0.5 * frame.high * tile.edgeWeight * (0.7 + centroidEdge)
		local lift = (band * (1.8 + centroidEdge) + dome + diagonal + midRipple + beatRipple + highShimmer) * intensity
		if minimal then
			lift *= 0.32
		end

		local height = math.clamp(0.14 + band * 0.32 + frame.transient * 0.16 + highShimmer * 0.12, 0.12, 0.72)
		local brightness = math.clamp(band * 0.3 + frame.high * tile.edgeWeight * 0.28 + pulse * tile.centerWeight * 0.22 + frame.air * tile.edgeWeight * 0.18, 0, if minimal then 0.22 else 0.74)
		local transparency = if minimal then 0.48 else math.clamp(0.16 - brightness * 0.1, 0.06, 0.2)

		tile.part.Size = Vector3.new(0.78, height, 0.78)
		tile.part.CFrame = CFrame.new(tile.basePosition + Vector3.new(0, lift + height * 0.5, 0))
		tile.part.Color = palette.Text:Lerp(palette.CyanSoft, brightness)
		tile.part.Transparency = if visible then transparency else 1
		tile.part:SetAttribute("BaseTransparency", transparency)
	end
end

local function updateRow(frame: AudioFrame, _energy: number, deltaTime: number)
	local visible = style == "Row" or style == "All"
	for _, rowBar in ipairs(rowBars) do
		local alpha = (rowBar.index - 1) / math.max(1, Constants.ROW_BAR_COUNT - 1)
		local band = getBand(frame, math.floor(alpha * audioBandCount) + 1)
		local leftWeight = math.max(0, 1 - alpha * 2.8)
		local centerWeight = math.max(0, 1 - math.abs(alpha - 0.44) * 3)
		local rightWeight = alpha ^ 1.6
		local body = frame.bass * leftWeight * 3.5 + frame.lowMid * centerWeight * 3 + frame.mid * 2.4 + frame.high * rightWeight * 2.2
		local variation = (math.sin(frame.time * 4.5 + alpha * math.pi * 7) + 1) * 0.5 * frame.mid
		local height = math.clamp(0.55 + (band * 8.2 + body + variation + frame.peak * 1.1) * intensity, 0.55, 13.5)

		rowBar.peakHeight = math.max(height + 0.28, rowBar.peakHeight - deltaTime * (4.2 + frame.spectralFlux * 5))
		rowBar.part.Size = Vector3.new(0.3, height, 0.54)
		rowBar.part.CFrame = CFrame.new(rowBar.basePosition + Vector3.new(0, height * 0.5, 0))
		rowBar.part.Color = palette.Text:Lerp(palette.Cyan, math.clamp(band * 0.44 + frame.mid * 0.18 + rightWeight * frame.high * 0.2, 0, 0.72))
		rowBar.part.Transparency = if visible then 0.1 else 1
		rowBar.part:SetAttribute("BaseTransparency", 0.1)

		rowBar.peakPart.CFrame = CFrame.new(rowBar.basePosition + Vector3.new(0, rowBar.peakHeight, 0))
		rowBar.peakPart.Transparency = if visible then math.clamp(0.22 - frame.spectralFlux * 0.08, 0.1, 0.34) else 1
		rowBar.peakPart:SetAttribute("BaseTransparency", rowBar.peakPart.Transparency)
	end
end

local function updateCircle(frame: AudioFrame, energy: number)
	local visible = style == "Circle" or style == "All" or style == "Minimal"
	local pulse = math.clamp(1 - pulseAge / 0.45, 0, 1) * pulseStrength
	local bassRadius = frame.bass * 1.8 + pulse * 1.2
	local centroidPush = frame.centroid * 1.4

	for _, circleBar in ipairs(circleBars) do
		local alpha = (circleBar.index - 1) / math.max(1, Constants.CIRCLE_BAR_COUNT - 1)
		local band = getBand(frame, math.floor(alpha * audioBandCount) + 1)
		local phase = (math.sin(frame.time * 5.4 + circleBar.angle * 6) + 1) * 0.5
		local highTip = (frame.high * 0.8 + frame.air * 0.65) * (0.5 + phase * 0.5)
		local extension = math.clamp((band * 4.8 + frame.mid * 2 + highTip * 2.4 + energy * 1.2) * intensity, 0.35, 8.2)
		local radius = circleBar.baseRadius + bassRadius + centroidPush + extension * 0.5
		local yLift = 2.52 + frame.lowMid * 0.8 + pulse * 0.45
		local position = visualCenter + Vector3.new(0, yLift, 0) + circleBar.direction * radius

		circleBar.part.Size = Vector3.new(0.14, 0.38 + highTip * 0.42, 1.05 + extension)
		circleBar.part.CFrame = CFrame.lookAt(position, position + circleBar.direction)
		circleBar.part.Color = palette.Text:Lerp(palette.CyanSoft, math.clamp(band * 0.4 + highTip * 0.3 + pulse * 0.16, 0, 0.76))
		local transparency = if style == "Minimal" then 0.48 else math.clamp(0.16 - highTip * 0.08, 0.07, 0.2)
		circleBar.part.Transparency = if visible then transparency else 1
		circleBar.part:SetAttribute("BaseTransparency", transparency)
	end
end

local function updateShockwaves(deltaTime: number)
	local visible = style == "Grid" or style == "Circle" or style == "All" or style == "Minimal"
	for _, ring in ipairs(shockwaves) do
		if ring.active then
			ring.age += deltaTime / 0.52
			if ring.age >= 1 then
				ring.active = false
				for _, segment in ipairs(ring.segments) do
					segment.Transparency = 1
					segment:SetAttribute("BaseTransparency", 1)
				end
			else
				local alpha = 1 - ring.age
				local radius = 6 + ring.age * 28
				local visibleScale = if style == "Minimal" then 0.2 else 0.5
				local transparency = math.clamp(1 - alpha * ring.strength * visibleScale, 0.42, 1)
				for index, segment in ipairs(ring.segments) do
					local segmentAlpha = (index - 1) / #ring.segments
					local angle = segmentAlpha * math.pi * 2
					local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
					local position = visualCenter + Vector3.new(0, 2.25 + alpha * 0.9, 0) + direction * radius
					segment.CFrame = CFrame.lookAt(position, position + direction)
					segment.Size = Vector3.new(0.1, 0.07, 0.92 + alpha * 1.45)
					segment.Transparency = if visible then transparency else 1
					segment:SetAttribute("BaseTransparency", transparency)
				end
			end
		end
	end
end

local function updateAccentLights(frame: AudioFrame)
	local visible = style == "Grid" or style == "Row" or style == "Circle" or style == "All"
	for index, accent in ipairs(accentLights) do
		local phase = (math.sin(frame.time * (1.5 + index * 0.07) + accent.angle * 3) + 1) * 0.5
		local airGlow = (frame.air * 0.7 + frame.high * 0.34 + frame.spectralFlux * 0.22) * phase
		local position = visualCenter
			+ Vector3.new(
				math.cos(accent.angle + frame.time * 0.04) * accent.radius,
				2.2 + phase * 0.8 + frame.bass * 0.5,
				math.sin(accent.angle + frame.time * 0.04) * accent.radius
			)
		accent.part.CFrame = CFrame.new(position)
		accent.part.Transparency = if visible then math.clamp(0.86 - airGlow * 0.34, 0.48, 0.92) else 1
		accent.part:SetAttribute("BaseTransparency", accent.part.Transparency)
		accent.light.Brightness = if visible then math.clamp(0.08 + airGlow * 0.75, 0.05, 0.85) else 0
		accent.light:SetAttribute("BaseBrightness", accent.light.Brightness)
	end
end

local function updateVisuals(deltaTime: number)
	local frame = getSafeFrame()
	local cleanDelta = math.clamp(NumberUtil.sanitizeFiniteNumber(deltaTime, 1 / 60), 1 / 240, 0.2)
	local energy = math.clamp((frame.rms * 0.42 + frame.peak * 0.22 + frame.bass * 0.22 + frame.mid * 0.16 + frame.high * 0.12) * intensity, 0, 1)
	pulseAge += cleanDelta
	pulseStrength = NumberUtil.expSmooth(pulseStrength, 0, cleanDelta, 4.5)

	if frame.beat and frame.time - lastBeatTime > 0.08 then
		lastBeatTime = frame.time
		activateShockwave(math.max(frame.beatStrength, frame.bass * 0.65, frame.spectralFlux * 0.8, 0.32))
	elseif frame.spectralFlux > 0.5 and frame.transient > 0.18 and frame.time - lastBeatTime > 0.22 then
		lastBeatTime = frame.time
		activateShockwave(math.max(frame.spectralFlux, frame.transient, 0.25))
	end

	updateGrid(frame, energy)
	updateRow(frame, energy, cleanDelta)
	updateCircle(frame, energy)
	updateShockwaves(cleanDelta)
	updateAccentLights(frame)

	local camera = context and context.CameraController
	if camera ~= nil and typeof(camera.Update) == "function" then
		camera:Update(cleanDelta, frame, style)
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
	createAccentLights(center)
	createRowBars(center)
	createRadialCircle(center)
	createShockwaves(center)
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
	activateShockwave(math.clamp(NumberUtil.sanitizeFiniteNumber(strength, 0.85), 0.1, 1))
end

function ResonanceController:TriggerPulseTest()
	self:TriggerPulse(0.85)
end

function ResonanceController:GetCurrentVisualStats(): { [string]: number }
	return {
		GridArray = #gridTiles,
		RowBars = #rowBars,
		RadialCircle = #circleBars,
		Shockwaves = #shockwaves,
		AccentLights = #accentLights,
	}
end

function ResonanceController:GetDebugCounts(): { [string]: number }
	return self:GetCurrentVisualStats()
end

function ResonanceController:Destroy()
	maid:Cleanup()
end

return ResonanceController
