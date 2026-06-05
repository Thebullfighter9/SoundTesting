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
type AnalyzerTruthMode = Types.AnalyzerTruthMode
type AudioDiagnostics = Types.AudioDiagnostics
type VisualStats = Types.VisualStats
type VisualStyle = Types.VisualStyle

type FrequencyCharacter = {
	lowWeight: number,
	bodyWeight: number,
	presenceWeight: number,
	shimmerWeight: number,
	edgeFocus: number,
	centerFocus: number,
	beatAccent: number,
	fluxAccent: number,
}

type BandMotionState = {
	part: BasePart,
	cap: BasePart?,
	index: number,
	basePosition: Vector3,
	bandIndex: number,
	secondaryBandIndex: number,
	frequencyBias: number,
	phase: number,
	attack: number,
	release: number,
	stiffness: number,
	damping: number,
	current: number,
	velocity: number,
	peakHold: number,
	peakVelocity: number,
	glow: number,
	target: number,
}

type GridTileState = {
	part: BasePart,
	basePosition: Vector3,
	xIndex: number,
	zIndex: number,
	normalizedX: number,
	normalizedZ: number,
	radius: number,
	normalizedRadius: number,
	angle: number,
	bandIndex: number,
	secondaryBandIndex: number,
	motionBias: number,
	phase: number,
	currentY: number,
	velocityY: number,
	currentHeight: number,
	glow: number,
	ripple: number,
	lastTarget: number,
}

type ShockwaveRing = {
	folder: Folder,
	segments: { BasePart },
	age: number,
	strength: number,
	active: boolean,
}

type PersistentWaveRing = {
	segments: { BasePart },
	radius: number,
	phase: number,
}

type AccentLight = {
	part: BasePart,
	light: PointLight,
	angle: number,
	radius: number,
	burst: number,
}

type LightSpray = {
	part: BasePart,
	active: boolean,
	position: Vector3,
	velocity: Vector3,
	life: number,
	maxLife: number,
	size: number,
	spin: number,
	colorWeight: number,
}

type GridRipple = {
	age: number,
	strength: number,
	active: boolean,
	speed: number,
	width: number,
}

local ResonanceController = {}

local initialized = false
local started = false
local context: any = nil
local maid = Maid.new()
local random = Random.new()
local gridTiles: { GridTileState } = {}
local rowBars: { BandMotionState } = {}
local circleBars: { BandMotionState } = {}
local shockwaves: { ShockwaveRing } = {}
local persistentWaveRings: { PersistentWaveRing } = {}
local accentLights: { AccentLight } = {}
local lightSprays: { LightSpray } = {}
local gridRipples: { GridRipple } = table.create(Constants.GRID_RIPPLE_POOL_SIZE)
local style: VisualStyle = Constants.DEFAULT_VISUAL_STYLE :: VisualStyle
local motion = Constants.DEFAULT_MOTION
local sprayAmount = Constants.DEFAULT_SPRAY_AMOUNT
local smoothness = Constants.DEFAULT_SMOOTHNESS
local warnedMissingGallery = false
local lastBeatTime = 0
local shockwaveCursor = 1
local sprayCursor = 1
local rippleCursor = 1
local pulseAge = 10
local pulseStrength = 0
local maxRecentGridJump = 0
local lastBeatStrength = 0
local activeSprayCount = 0
local activeShockwaveCount = 0
local activeRippleCount = 0
local attributeAccumulator = 0
local rowHeightVariance = 0
local rowMaxHeight = 0
local rowActiveCaps = 0
local rowSpectrumCorrelation = -1
local gridHeightVariance = 0
local circleLengthVariance = 0
local circleActiveWaves = 0

local rootFolder: Folder? = nil
local gridFolder: Folder? = nil
local rowFolder: Folder? = nil
local circleFolder: Folder? = nil
local shockwaveFolder: Folder? = nil
local accentFolder: Folder? = nil
local sprayFolder: Folder? = nil

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
	visualEnergy = 0.25,
	bands = {},
	time = 0,
	audioMode = "Demo",
	analyzerTruthMode = "Demo",
	usingRealSpectrum = false,
	spectrumBinCount = 0,
	spectrumVariance = 0,
	loudness = 0.25,
	fallbackReason = "Audio controller unavailable",
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

local function lerp(a: number, b: number, alpha: number): number
	return a + (b - a) * math.clamp(alpha, 0, 1)
end

local function springStep(
	current: number,
	velocity: number,
	target: number,
	stiffness: number,
	damping: number,
	deltaTime: number
): (number, number)
	local stiffnessScale = lerp(1.18, 0.74, smoothness)
	local dampingScale = lerp(0.86, 1.24, smoothness)
	local acceleration = (target - current) * stiffness * stiffnessScale - velocity * damping * dampingScale
	velocity += acceleration * deltaTime
	current += velocity * deltaTime
	return current, velocity
end

local function getBandInterpolated(frame: AudioFrame, normalizedIndex: number): number
	local bands = frame.bands
	local count = #bands
	if count <= 0 then
		return 0
	end

	local cleanIndex = math.clamp(NumberUtil.sanitizeFiniteNumber(normalizedIndex, 0), 0, 1)
	local position = cleanIndex * (count - 1) + 1
	local lowerIndex = math.clamp(math.floor(position), 1, count)
	local upperIndex = math.clamp(lowerIndex + 1, 1, count)
	local alpha = position - lowerIndex
	local lower = clamp01(bands[lowerIndex] or 0)
	local upper = clamp01(bands[upperIndex] or lower)
	return lower + (upper - lower) * alpha
end

local function computeVariance(sum: number, sumSquares: number, count: number): number
	if count <= 0 then
		return 0
	end

	local mean = sum / count
	return math.max(0, sumSquares / count - mean * mean)
end

local function computeFrequencyCharacter(frame: AudioFrame): FrequencyCharacter
	local centroid = clamp01(frame.centroid)
	local beatAccent = clamp01(math.max(frame.beatStrength, frame.bass * 0.3 + frame.transient * 0.6))
	local fluxAccent = clamp01(math.max(frame.spectralFlux, frame.transient * 0.8))
	local lowWeight = clamp01(frame.bass * 0.72 + frame.lowMid * 0.32)
	local bodyWeight = clamp01(frame.lowMid * 0.52 + frame.mid * 0.54)
	local presenceWeight = clamp01(frame.mid * 0.58 + frame.high * 0.38)
	local shimmerWeight = clamp01(frame.high * 0.58 + frame.air * 0.64)

	return {
		lowWeight = lowWeight,
		bodyWeight = bodyWeight,
		presenceWeight = presenceWeight,
		shimmerWeight = shimmerWeight,
		edgeFocus = clamp01(0.32 + centroid * 0.82 + shimmerWeight * 0.2),
		centerFocus = clamp01(1.05 - centroid * 0.56 + lowWeight * 0.22),
		beatAccent = beatAccent,
		fluxAccent = fluxAccent,
	}
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
	sprayFolder = createFolder(root, "LightSprays")
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
	setFolderVisible(sprayFolder, true)
end

local function createGrid(center: Vector3)
	local folder = assert(gridFolder, "Grid folder missing")
	local gridSize = Constants.GRID_SIZE
	local spacing = Constants.GRID_SPACING
	local tileWidth = Constants.GRID_TILE_WIDTH
	local origin = (gridSize - 1) * spacing * -0.5
	local halfIndex = (gridSize - 1) * 0.5
	local maxRadius = math.max(1, math.sqrt(2) * halfIndex * spacing)

	for row = 1, gridSize do
		for column = 1, gridSize do
			local x = origin + (column - 1) * spacing
			local z = origin + (row - 1) * spacing
			local localPosition = Vector3.new(x, 0, z)
			local basePosition = center + Vector3.new(x, 0, z)
			local normalizedX = (column - 1 - halfIndex) / math.max(1, halfIndex)
			local normalizedZ = (row - 1 - halfIndex) / math.max(1, halfIndex)
			local normalizedRadius = math.clamp(localPosition.Magnitude / maxRadius, 0, 1)
			local angle = math.atan2(z, x)
			local angleBand = (math.sin(angle * 2.0) + 1) * 0.045
			local bandIndex = math.clamp(normalizedRadius ^ 1.34 * 0.88 + angleBand, 0, 1)
			local secondaryBandIndex = math.clamp(bandIndex * 0.62 + 0.18 + math.cos(angle * 3) * 0.05, 0, 1)
			local motionBias = 0.88 + ((math.noise(row * 0.37, column * 0.41, 0.2) + 1) * 0.5) * 0.28
			local tile = createVisualPart(folder, `Grid_{row}_{column}`, {
				CFrame = CFrame.new(basePosition + Vector3.new(0, Constants.GRID_MIN_HEIGHT * 0.5, 0)),
				Size = Vector3.new(tileWidth, Constants.GRID_MIN_HEIGHT, tileWidth),
				Color = palette.Text:Lerp(palette.Cyan, 0.14),
				Material = Enum.Material.Neon,
				Transparency = 0.1,
			})
			tile:SetAttribute("BaseTransparency", 0.1)

			table.insert(gridTiles, {
				part = tile,
				basePosition = basePosition,
				xIndex = column,
				zIndex = row,
				normalizedX = normalizedX,
				normalizedZ = normalizedZ,
				radius = localPosition.Magnitude,
				normalizedRadius = normalizedRadius,
				angle = angle,
				bandIndex = bandIndex,
				secondaryBandIndex = secondaryBandIndex,
				motionBias = motionBias,
				phase = row * 0.47 + column * 0.31 + angle,
				currentY = 0,
				velocityY = 0,
				currentHeight = Constants.GRID_MIN_HEIGHT,
				glow = 0,
				ripple = 0,
				lastTarget = 0,
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
		local alpha = (index - 1) / math.max(1, count - 1)
		local bandIndex = alpha ^ 1.48
		local secondaryBandIndex = math.clamp(bandIndex * 1.76 + 0.04 + math.sin(alpha * math.pi * 2) * 0.025, 0, 1)
		local position = rowBase + Vector3.new(origin + (index - 1) * spacing, 0, 0)
		local bar = createVisualPart(folder, `RowBar_{index}`, {
			CFrame = CFrame.new(position + Vector3.new(0, Constants.ROW_MIN_HEIGHT * 0.5, 0)),
			Size = Vector3.new(0.32, Constants.ROW_MIN_HEIGHT, 0.56),
			Color = palette.Text:Lerp(palette.Cyan, 0.28),
			Material = Enum.Material.Neon,
			Transparency = 0.08,
		})
		bar:SetAttribute("BaseTransparency", 0.08)

		local peakPart = createVisualPart(peakFolder, `PeakCap_{index}`, {
			CFrame = CFrame.new(position + Vector3.new(0, 0.55, 0)),
			Size = Vector3.new(0.34, 0.08, 0.6),
			Color = palette.CyanSoft,
			Material = Enum.Material.Neon,
			Transparency = 0.18,
		})
		peakPart:SetAttribute("BaseTransparency", 0.18)

		table.insert(rowBars, {
			part = bar,
			cap = peakPart,
			index = index,
			basePosition = position,
			bandIndex = bandIndex,
			secondaryBandIndex = secondaryBandIndex,
			frequencyBias = alpha,
			phase = alpha * math.pi * 5.5 + random:NextNumber(-0.12, 0.12),
			attack = lerp(8.5, 20.5, alpha),
			release = lerp(2.8, 7.2, alpha),
			stiffness = lerp(Constants.ROW_SPRING_STIFFNESS_LOW, Constants.ROW_SPRING_STIFFNESS_HIGH, alpha),
			damping = lerp(Constants.ROW_DAMPING_LOW, Constants.ROW_DAMPING_HIGH, alpha),
			current = Constants.ROW_MIN_HEIGHT,
			velocity = 0,
			peakHold = Constants.ROW_MIN_HEIGHT + 0.34,
			peakVelocity = 0,
			glow = 0,
			target = Constants.ROW_MIN_HEIGHT,
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
		local bandIndex = math.clamp((alpha + math.sin(angle * 3) * 0.018 + 0.035) % 1, 0, 1)
		local secondaryBandIndex = math.clamp((bandIndex * 1.42 + 0.18) % 1, 0, 1)
		local position = center + direction * radius + Vector3.new(0, 2.55, 0)
		local bar = createVisualPart(folder, `CircleBar_{index}`, {
			CFrame = CFrame.lookAt(position, position + direction),
			Size = Vector3.new(0.14, 0.38, 1.05 + Constants.CIRCLE_MIN_LENGTH),
			Color = palette.Text:Lerp(palette.Cyan, 0.34),
			Material = Enum.Material.Neon,
			Transparency = 0.12,
		})
		bar:SetAttribute("BaseTransparency", 0.12)

		table.insert(circleBars, {
			part = bar,
			cap = nil,
			index = index,
			basePosition = center + direction * radius,
			bandIndex = bandIndex,
			secondaryBandIndex = secondaryBandIndex,
			frequencyBias = alpha,
			phase = angle + random:NextNumber(-0.08, 0.08),
			attack = lerp(13, 24, alpha),
			release = lerp(4.5, 8.5, alpha),
			stiffness = lerp(22, 42, alpha),
			damping = lerp(8, 12, alpha),
			current = Constants.CIRCLE_MIN_LENGTH,
			velocity = 0,
			peakHold = Constants.CIRCLE_MIN_LENGTH,
			peakVelocity = 0,
			glow = 0,
			target = Constants.CIRCLE_MIN_LENGTH,
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
				Size = Vector3.new(0.11, 0.07, 1.1),
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

local function createPersistentWaveRings(center: Vector3)
	local folder = assert(shockwaveFolder, "Shockwave folder missing")
	local ringRoot = createFolder(folder, "CircleWaveRings")

	for ringIndex = 1, Constants.CIRCLE_WAVE_RING_COUNT do
		local segments: { BasePart } = {}
		local radius = 9.5 + ringIndex * 2.75
		local ringFolder = createFolder(ringRoot, `WaveRing_{ringIndex}`)
		for segmentIndex = 1, Constants.SHOCKWAVE_SEGMENT_COUNT do
			local alpha = (segmentIndex - 1) / Constants.SHOCKWAVE_SEGMENT_COUNT
			local angle = alpha * math.pi * 2
			local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local position = center + direction * radius + Vector3.new(0, 2.2, 0)
			local segment = createVisualPart(ringFolder, `Wave_{segmentIndex}`, {
				CFrame = CFrame.lookAt(position, position + direction),
				Size = Vector3.new(0.055, 0.04, 0.9),
				Color = palette.CyanSoft,
				Material = Enum.Material.Neon,
				Transparency = 0.88,
			})
			segment:SetAttribute("BaseTransparency", 0.88)
			table.insert(segments, segment)
		end

		table.insert(persistentWaveRings, {
			segments = segments,
			radius = radius,
			phase = ringIndex * math.pi * 0.42,
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
			Size = Vector3.new(0.22, 0.22, 0.22),
			Shape = Enum.PartType.Ball,
			Color = palette.CyanSoft,
			Material = Enum.Material.Neon,
			Transparency = 0.72,
		})
		part:SetAttribute("BaseTransparency", 0.72)
		local light = InstanceUtil.create("PointLight", {
			Name = "Glow",
			Brightness = 0.35,
			Color = palette.CyanSoft,
			Range = 8,
			Shadows = false,
		}, part) :: PointLight
		light:SetAttribute("BaseBrightness", 0.35)

		table.insert(accentLights, {
			part = part,
			light = light,
			angle = angle,
			radius = radius,
			burst = 0,
		})
	end
end

local function createLightSprays(center: Vector3)
	local folder = assert(sprayFolder, "Light spray folder missing")
	for index = 1, Constants.LIGHT_SPRAY_POOL_SIZE do
		local spray = createVisualPart(folder, `LightSpray_{index}`, {
			CFrame = CFrame.new(center),
			Size = Vector3.new(0.08, 0.08, 1),
			Color = palette.CyanSoft,
			Material = Enum.Material.Neon,
			Transparency = 1,
		})
		spray:SetAttribute("BaseTransparency", 1)

		table.insert(lightSprays, {
			part = spray,
			active = false,
			position = center,
			velocity = Vector3.zero,
			life = 1,
			maxLife = 1,
			size = 1,
			spin = 0,
			colorWeight = 0,
		})
	end
end

local function initializeGridRipples()
	table.clear(gridRipples)
	for _ = 1, Constants.GRID_RIPPLE_POOL_SIZE do
		table.insert(gridRipples, {
			age = 2,
			strength = 0,
			active = false,
			speed = 32,
			width = 3.2,
		})
	end
end

local function synthesizeBands(frame: AudioFrame): { number }
	local bands = table.create(audioBandCount, 0)
	local timeNow = if frame.time > 0 then frame.time else os.clock()
	local energy = math.clamp(math.max(frame.rms, frame.peak * 0.85, frame.visualEnergy, 0.24), 0, 1)

	for index = 1, audioBandCount do
		local alpha = (index - 1) / math.max(1, audioBandCount - 1)
		local wave = (math.sin(timeNow * 3.4 + alpha * math.pi * 5.5) + 1) * 0.5
		local shimmer = (math.sin(timeNow * 11.5 + alpha * math.pi * 20.5) + 1) * 0.5
		local bassShape = math.max(0, 1 - alpha * 3.2) * frame.bass
		local midShape = math.max(0, 1 - math.abs(alpha - 0.48) * 3.2) * frame.mid
		bands[index] = math.clamp(energy * (0.18 + wave * 0.26 + shimmer * alpha * 0.12) + bassShape * 0.52 + midShape * 0.22, 0, 1)
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
	local hasBandTable = false
	if typeof(bands) == "table" then
		hasBandTable = #bands > 0
	end

	local visualEnergy = clamp01(audioFrame.visualEnergy or math.max(audioFrame.rms, audioFrame.peak))
	local truthMode: AnalyzerTruthMode = audioFrame.analyzerTruthMode
	if truthMode ~= "Spectrum" and truthMode ~= "LoudnessOnly" and truthMode ~= "Demo" and truthMode ~= "Silent" then
		truthMode = "Demo"
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
		visualEnergy = visualEnergy,
		bands = if hasBandTable then bands else {},
		time = NumberUtil.sanitizeFiniteNumber(audioFrame.time, os.clock()),
		audioMode = audioFrame.audioMode,
		analyzerTruthMode = truthMode,
		usingRealSpectrum = audioFrame.usingRealSpectrum == true,
		spectrumBinCount = math.max(0, NumberUtil.sanitizeFiniteNumber(audioFrame.spectrumBinCount, 0)),
		spectrumVariance = math.max(0, NumberUtil.sanitizeFiniteNumber(audioFrame.spectrumVariance, 0)),
		loudness = clamp01(audioFrame.loudness),
		fallbackReason = audioFrame.fallbackReason,
	}

	if not hasBandTable and cleanFrame.analyzerTruthMode == "Demo" then
		cleanFrame.bands = synthesizeBands(cleanFrame)
	elseif not hasBandTable then
		cleanFrame.bands = {}
	end

	return cleanFrame
end

local function getAudioDiagnostics(frame: AudioFrame): AudioDiagnostics
	local audio = context and context.AudioController
	if audio ~= nil and typeof(audio.GetDiagnostics) == "function" then
		local ok, diagnostics = pcall(function()
			return audio:GetDiagnostics()
		end)
		if ok and typeof(diagnostics) == "table" then
			return diagnostics :: AudioDiagnostics
		end
	end

	return {
		audioMode = frame.audioMode,
		analyzerTruthMode = frame.analyzerTruthMode,
		assetId = nil,
		usingRealSpectrum = frame.usingRealSpectrum,
		spectrumBinCount = frame.spectrumBinCount,
		spectrumVariance = frame.spectrumVariance,
		loudness = frame.loudness,
		rms = frame.rms,
		peak = frame.peak,
		fallbackReason = frame.fallbackReason,
	}
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
	ring.strength = math.clamp(strength, 0.22, 1)
	ring.active = true
end

local function activateGridRipple(strength: number)
	if #gridRipples == 0 then
		return
	end

	local ripple = gridRipples[rippleCursor]
	rippleCursor += 1
	if rippleCursor > #gridRipples then
		rippleCursor = 1
	end

	ripple.age = 0
	ripple.strength = math.clamp(strength, 0.18, 1)
	ripple.active = true
	ripple.speed = 26 + strength * 16
	ripple.width = 2.4 + strength * 2.1
end

local function activateAccentBurst(strength: number)
	for _, accent in ipairs(accentLights) do
		accent.burst = math.max(accent.burst, strength)
	end
end

local function getSprayStart(): Vector3
	local choice = random:NextInteger(1, if style == "All" then 3 else 1)
	if style == "Row" or choice == 2 then
		local rowBar = rowBars[random:NextInteger(1, math.max(1, #rowBars))]
		if rowBar ~= nil then
			return rowBar.basePosition + Vector3.new(0, math.max(rowBar.current, rowBar.peakHold), 0)
		end
	elseif style == "Circle" or choice == 3 then
		local angle = random:NextNumber(0, math.pi * 2)
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		return visualCenter + direction * random:NextNumber(12.5, 17.2) + Vector3.new(0, random:NextNumber(2.4, 4.2), 0)
	end

	local side = random:NextInteger(1, 4)
	local half = Constants.GRID_SPACING * (Constants.GRID_SIZE - 1) * 0.5
	local offsetX = random:NextNumber(-half, half)
	local offsetZ = random:NextNumber(-half, half)
	if side == 1 then
		offsetX = half
	elseif side == 2 then
		offsetX = -half
	elseif side == 3 then
		offsetZ = half
	else
		offsetZ = -half
	end

	return visualCenter + Vector3.new(offsetX, random:NextNumber(1.3, 3.5), offsetZ)
end

local function activateSprays(strength: number, fullBurst: boolean)
	if #lightSprays == 0 then
		return
	end
	if sprayAmount <= 0 and not fullBurst then
		return
	end

	local styleScale = 1
	if style == "All" then
		styleScale = Constants.ALL_MODE_SPRAY_MULTIPLIER + 0.42
	elseif style == "Minimal" then
		styleScale = Constants.MINIMAL_MODE_SPRAY_MULTIPLIER
	elseif style == "Row" then
		styleScale = 0.78
	elseif style == "Circle" then
		styleScale = 0.9
	end

	local lowCount = if fullBurst then 24 else if strength >= 0.72 then 12 else 4
	local highCount = if fullBurst then 42 else if strength >= 0.72 then 24 else 14
	local effectiveSpray = if fullBurst then math.max(0.9, sprayAmount) else 0.65 + sprayAmount * 0.55
	local requestedCount = math.floor(lerp(lowCount, highCount, strength) * effectiveSpray * styleScale)
	local count = math.clamp(requestedCount, if style == "Minimal" then 0 else lowCount, math.min(highCount, Constants.LIGHT_SPRAY_POOL_SIZE))
	if count <= 0 then
		return
	end

	for _ = 1, count do
		local spray = lightSprays[sprayCursor]
		sprayCursor += 1
		if sprayCursor > #lightSprays then
			sprayCursor = 1
		end

		local start = getSprayStart()
		local outward = start - visualCenter
		local direction = Vector3.new(outward.X, 0, outward.Z)
		if direction.Magnitude < 0.001 then
			local angle = random:NextNumber(0, math.pi * 2)
			direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		else
			direction = direction.Unit
		end
		local tangent = Vector3.new(-direction.Z, 0, direction.X)
		local upward = random:NextNumber(4.8, 8.4) * (0.78 + strength * 0.34)
		local radialSpeed = random:NextNumber(7.5, 15) * (0.68 + strength * 0.44)
		local sideSpeed = random:NextNumber(-1.8, 1.8)

		spray.active = true
		spray.position = start
		spray.velocity = direction * radialSpeed + tangent * sideSpeed + Vector3.new(0, upward, 0)
		spray.life = 0
		spray.maxLife = random:NextNumber(0.22, 0.58)
		spray.size = random:NextNumber(0.46, 0.95) * (0.82 + strength * 0.25)
		spray.spin = random:NextNumber(-1.1, 1.1)
		spray.colorWeight = random:NextNumber(0, 1)
	end
end

local function activatePulse(strength: number, fullSprayBurst: boolean?)
	local cleanStrength = math.clamp(NumberUtil.sanitizeFiniteNumber(strength, 0.85), 0.1, 1)
	pulseAge = 0
	pulseStrength = math.max(pulseStrength, cleanStrength)
	lastBeatStrength = cleanStrength

	activateShockwave(cleanStrength)
	activateGridRipple(cleanStrength)
	activateSprays(cleanStrength, fullSprayBurst == true)
	activateAccentBurst(cleanStrength)

	for _, tile in ipairs(gridTiles) do
		local centerImpulse = Constants.GRID_BEAT_IMPULSE * (0.16 + (1 - tile.normalizedRadius) ^ 1.45 * 0.92)
		local radialMatch = math.max(0, 1 - math.abs(tile.radius - 5.5) / 7) * 1.8
		tile.velocityY += (centerImpulse + radialMatch) * cleanStrength * motion * tile.motionBias
		tile.ripple = math.max(tile.ripple, cleanStrength)
		tile.glow = math.max(tile.glow, cleanStrength)
	end
end

local function updateGridRipples(deltaTime: number)
	activeRippleCount = 0
	for _, ripple in ipairs(gridRipples) do
		if ripple.active then
			ripple.age += deltaTime
			if ripple.age > 1.15 then
				ripple.active = false
			else
				activeRippleCount += 1
			end
		end
	end
end

local function getGridRippleValue(tile: GridTileState): number
	local value = 0
	for _, ripple in ipairs(gridRipples) do
		if ripple.active then
			local waveRadius = ripple.age * ripple.speed
			local fade = math.clamp(1 - ripple.age / 1.15, 0, 1)
			local distanceMatch = math.max(0, 1 - math.abs(tile.radius - waveRadius) / ripple.width)
			value += distanceMatch ^ 2 * ripple.strength * fade
		end
	end
	return math.clamp(value, 0, 1.4)
end

local function updateGrid(
	frame: AudioFrame,
	character: FrequencyCharacter,
	energy: number,
	deltaTime: number,
	diagnostics: AudioDiagnostics
): number
	local timeNow = frame.time
	local minimal = style == "Minimal"
	local visible = style == "Grid" or style == "All" or style == "Minimal"
	local maxJump = 0
	local sum = 0
	local sumSquares = 0
	local truthMode = diagnostics.analyzerTruthMode
	local proceduralScale = if truthMode == "Spectrum" then 0.16 elseif truthMode == "LoudnessOnly" then 0.45 elseif truthMode == "Silent" then 0 else 1
	local bandScale = if truthMode == "Spectrum" then 1.18 elseif truthMode == "LoudnessOnly" then 0.78 elseif truthMode == "Silent" then 0 else 1

	for _, tile in ipairs(gridTiles) do
		local directBand = getBandInterpolated(frame, tile.bandIndex)
		local secondaryBand = getBandInterpolated(frame, tile.secondaryBandIndex)
		local centerWeight = (1 - tile.normalizedRadius) ^ 1.75
		local middleWeight = math.max(0, 1 - math.abs(tile.normalizedRadius - 0.48) * 2.4)
		local edgeWeight = tile.normalizedRadius ^ 1.7
		local bassDome = frame.bass ^ 1.2 * centerWeight * character.centerFocus * Constants.GRID_CENTER_BASS_GAIN
		local diagonalPhase = (tile.normalizedX + tile.normalizedZ) * 4.4 + tile.phase
		local diagonal = ((math.sin(timeNow * 2.65 + diagonalPhase) + 1) * 0.5)
			* character.bodyWeight
			* Constants.GRID_WAVE_GAIN
			* middleWeight
			* proceduralScale
		local bandWave = (directBand * 0.76 + secondaryBand * 0.24) ^ 0.72 * (1.0 + middleWeight * 0.65) * 2.85 * bandScale
		local midSculpt = ((math.sin(timeNow * 2.1 - tile.radius * 0.48 + tile.angle * 1.8) + 1) * 0.5)
			* character.presenceWeight
			* middleWeight
			* 2.15
			* proceduralScale
		local ripple = getGridRippleValue(tile)
		local beatRipple = ripple * (2.4 + character.beatAccent * 2.1) * (0.58 + centerWeight * 0.42)
		local shimmerPhase = math.sin(timeNow * 12.5 + tile.angle * 5.5 + tile.radius * 0.66 + tile.phase)
		local edgeShimmer = (shimmerPhase + 1) * 0.5
			* character.shimmerWeight
			* edgeWeight
			* character.edgeFocus
			* Constants.GRID_EDGE_HIGH_GAIN
			* proceduralScale
		local visibleFloor = if truthMode == "Silent" then 0 else Constants.MIN_VISIBLE_ENERGY * (0.28 + energy * 0.55)
		local targetY = visibleFloor + bassDome + diagonal + bandWave + midSculpt + beatRipple + edgeShimmer
		targetY *= motion * tile.motionBias
		if minimal then
			targetY *= 0.32
		end
		targetY = math.clamp(targetY, 0, Constants.GRID_MAX_JUMP)

		tile.lastTarget = targetY
		tile.ripple = NumberUtil.expSmooth(tile.ripple, ripple, deltaTime, 8)
		tile.glow = NumberUtil.expSmooth(tile.glow, math.max(edgeShimmer * 0.32, ripple * 0.65, directBand * 0.24), deltaTime, 7.5)
		tile.currentY, tile.velocityY = springStep(
			tile.currentY,
			tile.velocityY,
			targetY,
			Constants.GRID_SPRING_STIFFNESS,
			Constants.GRID_SPRING_DAMPING,
			deltaTime
		)
		tile.currentY = math.clamp(tile.currentY, -0.22, Constants.GRID_MAX_JUMP + 2.2)
		maxJump = math.max(maxJump, tile.currentY)

		local targetHeight = Constants.GRID_MIN_HEIGHT
			+ bandWave * 0.9
			+ tile.currentY * 0.82
			+ character.fluxAccent * (0.45 + edgeWeight * 0.8)
			+ tile.ripple * (0.42 + centerWeight * 1.4)
			+ edgeShimmer * 0.72
		targetHeight *= if minimal then 0.46 else 1
		targetHeight = math.clamp(targetHeight, Constants.GRID_MIN_HEIGHT, Constants.GRID_MAX_HEIGHT)
		tile.currentHeight = NumberUtil.expSmooth(tile.currentHeight, targetHeight, deltaTime, lerp(12, 21, 1 - smoothness))

		local normalizedHeight = math.clamp(tile.currentY / math.max(1, Constants.GRID_MAX_JUMP), 0, 1)
		sum += normalizedHeight
		sumSquares += normalizedHeight * normalizedHeight

		local brightness = math.clamp(directBand * 0.28 + tile.glow * 0.48 + frame.air * edgeWeight * 0.18, 0, if minimal then 0.3 else 0.82)
		local transparency = if minimal then 0.48 else math.clamp(0.13 - brightness * 0.08, 0.035, 0.18)
		local width = Constants.GRID_TILE_WIDTH + math.clamp(tile.glow * 0.08 + directBand * 0.05, 0, 0.13)

		tile.part.Size = Vector3.new(width, tile.currentHeight, width)
		tile.part.CFrame = CFrame.new(tile.part.Position:Lerp(tile.basePosition + Vector3.new(0, tile.currentY + tile.currentHeight * 0.5, 0), 0.82))
		tile.part.Color = palette.Text:Lerp(palette.CyanSoft, brightness)
		tile.part.Transparency = if visible then transparency else 1
		tile.part:SetAttribute("BaseTransparency", transparency)
	end

	gridHeightVariance = computeVariance(sum, sumSquares, #gridTiles)
	return maxJump
end

local function updateRow(
	frame: AudioFrame,
	character: FrequencyCharacter,
	energy: number,
	deltaTime: number,
	diagnostics: AudioDiagnostics
)
	local visible = style == "Row" or style == "All"
	local sum = 0
	local sumSquares = 0
	local correlationSamples = 0
	local directSum = 0
	local targetSum = 0
	local directSquares = 0
	local targetSquares = 0
	local directTarget = 0
	local truthMode = diagnostics.analyzerTruthMode
	rowMaxHeight = 0
	rowActiveCaps = 0

	for _, rowBar in ipairs(rowBars) do
		local alpha = rowBar.frequencyBias
		local direct = getBandInterpolated(frame, rowBar.bandIndex)
		local neighborOffset = if truthMode == "Spectrum" then 0.006 else math.sin(rowBar.phase + frame.time * 0.2) * 0.014
		local neighbor = getBandInterpolated(frame, math.clamp(rowBar.bandIndex + neighborOffset, 0, 1))
		local harmonic = getBandInterpolated(frame, rowBar.secondaryBandIndex)
		local lowWeight = math.max(0, 1 - alpha * 3.2)
		local bodyWeight = math.max(0, 1 - math.abs(alpha - 0.28) * 3.4)
		local presenceWeight = math.max(0, 1 - math.abs(alpha - 0.55) * 2.8)
		local shimmerWeight = alpha ^ 1.55
		local accent = character.fluxAccent * (0.08 + shimmerWeight * 0.1) + character.beatAccent * lowWeight * 0.12
		local power = 0

		if truthMode == "Spectrum" then
			local region = frame.bass * lowWeight * 0.08
				+ frame.lowMid * bodyWeight * 0.05
				+ frame.mid * presenceWeight * 0.05
				+ frame.high * shimmerWeight * 0.04
			power = math.clamp(direct * 0.84 + neighbor * 0.08 + harmonic * 0.04 + region + accent * 0.45, 0, 1.35)
		elseif truthMode == "LoudnessOnly" then
			local loudness = math.clamp(math.max(diagnostics.loudness, frame.rms, frame.peak * 0.72, frame.visualEnergy * 0.78), 0, 1)
			local centerWeight = 1 - math.abs(alpha - 0.5) * 2
			local amplitudeWave = (math.sin(frame.time * 2.4 + alpha * math.pi * 2.0 + rowBar.phase * 0.18) + 1) * 0.5
			local silhouette = 0.2 + centerWeight * 0.58 + amplitudeWave * 0.14
			direct = loudness * silhouette
			power = math.clamp(direct + character.beatAccent * (0.04 + centerWeight * 0.1), 0, 1.2)
		elseif truthMode == "Silent" then
			direct = 0
			power = 0
			accent = 0
		else
			local phaseWave = (math.sin(frame.time * 3.2 - alpha * math.pi * 3.2 + rowBar.phase) + 1) * 0.5
			local waveLag = phaseWave * character.bodyWeight * 0.22
			local region = frame.bass * lowWeight * 0.46
				+ frame.lowMid * bodyWeight * 0.36
				+ frame.mid * presenceWeight * 0.42
				+ frame.high * shimmerWeight * 0.28
			accent = character.fluxAccent * (0.12 + shimmerWeight * 0.18) + character.beatAccent * lowWeight * 0.2
			power = math.clamp(direct * 0.62 + neighbor * 0.16 + harmonic * 0.13 + region + waveLag + accent + energy * 0.05, 0, 1.4)
		end

		local curved = 1 - math.exp(-power * Constants.ROW_HEIGHT_CURVE)
		local heightTarget = Constants.ROW_MIN_HEIGHT + curved * (Constants.ROW_MAX_HEIGHT - Constants.ROW_MIN_HEIGHT) * 0.82 * motion
		heightTarget = math.clamp(heightTarget, Constants.ROW_MIN_HEIGHT, Constants.ROW_MAX_HEIGHT)
		if truthMode == "Spectrum" then
			local normalizedTarget = math.clamp((heightTarget - Constants.ROW_MIN_HEIGHT) / math.max(0.001, Constants.ROW_MAX_HEIGHT - Constants.ROW_MIN_HEIGHT), 0, 1)
			directSum += direct
			targetSum += normalizedTarget
			directSquares += direct * direct
			targetSquares += normalizedTarget * normalizedTarget
			directTarget += direct * normalizedTarget
			correlationSamples += 1
		end

		local targetSpeed = if heightTarget > rowBar.target then rowBar.attack else rowBar.release
		rowBar.target = NumberUtil.expSmooth(rowBar.target, heightTarget, deltaTime, targetSpeed)
		rowBar.current, rowBar.velocity = springStep(rowBar.current, rowBar.velocity, rowBar.target, rowBar.stiffness, rowBar.damping, deltaTime)
		rowBar.current = math.clamp(rowBar.current, Constants.ROW_MIN_HEIGHT, Constants.ROW_MAX_HEIGHT + 0.5)
		rowMaxHeight = math.max(rowMaxHeight, rowBar.current)

		local peakTarget = rowBar.current + 0.38 + character.fluxAccent * (0.22 + alpha * 0.3)
		if peakTarget > rowBar.peakHold then
			rowBar.peakHold = peakTarget
			rowBar.peakVelocity = math.max(rowBar.peakVelocity, character.fluxAccent * 1.8 + character.beatAccent * 0.9)
		else
			local decay = lerp(Constants.ROW_PEAK_DECAY_LOW, Constants.ROW_PEAK_DECAY_HIGH, alpha)
			rowBar.peakVelocity = NumberUtil.expSmooth(rowBar.peakVelocity, 0, deltaTime, decay * 0.65)
			rowBar.peakHold -= deltaTime * (decay * (0.62 + rowBar.peakVelocity * 0.4))
		end
		rowBar.peakHold = math.clamp(rowBar.peakHold, Constants.ROW_MIN_HEIGHT + 0.2, Constants.ROW_MAX_HEIGHT + 1.1)
		if rowBar.peakHold > rowBar.current + 0.62 then
			rowActiveCaps += 1
		end

		rowBar.glow = NumberUtil.expSmooth(rowBar.glow, math.clamp(power * 0.55 + accent * 0.6, 0, 1), deltaTime, 8)
		local width = 0.31 + rowBar.glow * 0.08 + character.fluxAccent * 0.025
		local depth = 0.54 + rowBar.glow * 0.1
		rowBar.part.Size = Vector3.new(width, rowBar.current, depth)
		rowBar.part.CFrame = CFrame.new(rowBar.basePosition + Vector3.new(0, rowBar.current * 0.5, 0))
		rowBar.part.Color = palette.Text:Lerp(palette.Cyan, math.clamp(power * 0.42 + rowBar.glow * 0.28 + shimmerWeight * frame.high * 0.18, 0, 0.82))
		rowBar.part.Transparency = if visible then math.clamp(0.1 - rowBar.glow * 0.045, 0.045, 0.16) else 1
		rowBar.part:SetAttribute("BaseTransparency", rowBar.part.Transparency)

		local cap = rowBar.cap
		if cap ~= nil then
			cap.Size = Vector3.new(width + 0.05, 0.075, depth + 0.04)
			cap.CFrame = CFrame.new(rowBar.basePosition + Vector3.new(0, rowBar.peakHold, 0))
			cap.Color = palette.CyanSoft:Lerp(palette.Text, math.clamp(character.fluxAccent * 0.22, 0, 0.32))
			cap.Transparency = if visible then math.clamp(0.24 - rowBar.glow * 0.12 - character.fluxAccent * 0.06, 0.08, 0.34) else 1
			cap:SetAttribute("BaseTransparency", cap.Transparency)
		end

		local normalizedHeight = math.clamp(rowBar.current / Constants.ROW_MAX_HEIGHT, 0, 1)
		sum += normalizedHeight
		sumSquares += normalizedHeight * normalizedHeight
	end

	rowHeightVariance = computeVariance(sum, sumSquares, #rowBars)
	if truthMode == "Spectrum" and correlationSamples > 2 then
		local sampleCount = correlationSamples
		local covariance = directTarget - directSum * targetSum / sampleCount
		local directVariance = directSquares - directSum * directSum / sampleCount
		local targetVariance = targetSquares - targetSum * targetSum / sampleCount
		local denominator = math.sqrt(math.max(0, directVariance) * math.max(0, targetVariance))
		rowSpectrumCorrelation = if denominator > 0.000001 then math.clamp(covariance / denominator, -1, 1) else 0
	else
		rowSpectrumCorrelation = -1
	end
end

local function updateCircle(
	frame: AudioFrame,
	character: FrequencyCharacter,
	energy: number,
	deltaTime: number,
	diagnostics: AudioDiagnostics
)
	local visible = style == "Circle" or style == "All" or style == "Minimal"
	local minimal = style == "Minimal"
	local sum = 0
	local sumSquares = 0
	local pulse = math.clamp(1 - pulseAge / 0.58, 0, 1) * pulseStrength
	local bassRadius = frame.bass * 2.4 + pulse * 1.7
	local centroidPush = frame.centroid * 1.45
	local truthMode = diagnostics.analyzerTruthMode
	local proceduralScale = if truthMode == "Spectrum" then 0.18 elseif truthMode == "LoudnessOnly" then 0.52 elseif truthMode == "Silent" then 0 else 1
	local bandScale = if truthMode == "Spectrum" then 1.16 elseif truthMode == "LoudnessOnly" then 0.82 elseif truthMode == "Silent" then 0 else 1

	for _, circleBar in ipairs(circleBars) do
		local alpha = circleBar.frequencyBias
		local angle = alpha * math.pi * 2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local direct = getBandInterpolated(frame, circleBar.bandIndex)
		local neighbor = getBandInterpolated(frame, math.clamp(circleBar.bandIndex + 0.025, 0, 1))
		local harmonic = getBandInterpolated(frame, circleBar.secondaryBandIndex)
		local traveling = (math.sin(frame.time * (3.2 + Constants.CIRCLE_TRAVEL_SPEED) + circleBar.phase * 2.2) + 1) * 0.5
		local beatPhase = math.max(0, math.sin(pulseAge * 10 - circleBar.phase * 1.4)) * pulse
		local centroidInfluence = lerp(character.centerFocus * 0.28, character.edgeFocus * 0.44, alpha) * proceduralScale
		local highTip = (frame.high * 0.72 + frame.air * 0.58) * (0.36 + traveling * 0.64 * proceduralScale)
		local power = math.clamp(
			(direct * 0.64 + neighbor * 0.14 + harmonic * 0.08) * bandScale
				+ frame.mid * 0.22 * proceduralScale
				+ highTip * 0.34
				+ centroidInfluence
				+ beatPhase * 0.32
				+ energy * 0.04,
			0,
			1.45
		)
		local curved = 1 - math.exp(-power * 1.72)
		local target = math.clamp((Constants.CIRCLE_MIN_LENGTH + curved * (Constants.CIRCLE_MAX_LENGTH - 0.4)) * motion, Constants.CIRCLE_MIN_LENGTH, Constants.CIRCLE_MAX_LENGTH)
		if minimal then
			target *= 0.54
		end

		local targetSpeed = if target > circleBar.target then circleBar.attack else circleBar.release
		circleBar.target = NumberUtil.expSmooth(circleBar.target, target, deltaTime, targetSpeed)
		circleBar.current, circleBar.velocity = springStep(circleBar.current, circleBar.velocity, circleBar.target, circleBar.stiffness, circleBar.damping, deltaTime)
		circleBar.current = math.clamp(circleBar.current, Constants.CIRCLE_MIN_LENGTH, Constants.CIRCLE_MAX_LENGTH + 0.4)
		circleBar.glow = NumberUtil.expSmooth(circleBar.glow, math.clamp(highTip * 0.72 + beatPhase * 0.5 + direct * 0.2, 0, 1), deltaTime, 9)

		local radius = 12.4 + bassRadius + centroidPush + circleBar.current * 0.44
		local yLift = 2.52 + frame.lowMid * 0.86 + pulse * 0.52 + traveling * frame.mid * 0.2 * proceduralScale
		local position = visualCenter + Vector3.new(0, yLift, 0) + direction * radius
		local tipWidth = 0.14 + highTip * 0.08
		circleBar.part.Size = Vector3.new(tipWidth, 0.36 + highTip * 0.34, 1.0 + circleBar.current)
		circleBar.part.CFrame = CFrame.lookAt(position, position + direction)
		circleBar.part.Color = palette.Text:Lerp(palette.CyanSoft, math.clamp(power * 0.38 + circleBar.glow * 0.34, 0, 0.82))
		local transparency = if minimal then 0.5 else math.clamp(0.14 - circleBar.glow * 0.08, 0.05, 0.18)
		circleBar.part.Transparency = if visible then transparency else 1
		circleBar.part:SetAttribute("BaseTransparency", transparency)

		local normalizedLength = math.clamp(circleBar.current / Constants.CIRCLE_MAX_LENGTH, 0, 1)
		sum += normalizedLength
		sumSquares += normalizedLength * normalizedLength
	end

	circleLengthVariance = computeVariance(sum, sumSquares, #circleBars)
end

local function updatePersistentWaveRings(frame: AudioFrame, character: FrequencyCharacter)
	local visible = style == "Circle" or style == "All" or style == "Minimal"
	local pulse = math.clamp(1 - pulseAge / 0.7, 0, 1) * pulseStrength
	for ringIndex, ring in ipairs(persistentWaveRings) do
		local radius = ring.radius + frame.bass * (0.8 + ringIndex * 0.24) + pulse * (1.2 + ringIndex * 0.2)
		local ringGlow = math.clamp(0.1 + frame.mid * 0.16 + character.shimmerWeight * 0.22 + pulse * 0.28, 0, 0.72)
		for segmentIndex, segment in ipairs(ring.segments) do
			local alpha = (segmentIndex - 1) / #ring.segments
			local angle = alpha * math.pi * 2
			local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local phase = (math.sin(frame.time * (1.4 + ringIndex * 0.17) + angle * 3.2 + ring.phase) + 1) * 0.5
			local waveRadius = radius + phase * (0.28 + frame.lowMid * 0.7)
			local position = visualCenter + Vector3.new(0, 2.22 + ringIndex * 0.11 + phase * frame.mid * 0.22, 0) + direction * waveRadius
			segment.CFrame = CFrame.lookAt(position, position + direction)
			segment.Size = Vector3.new(0.055, 0.04, 0.82 + phase * 0.45 + frame.high * 0.42)
			local transparency = math.clamp(0.9 - ringGlow * 0.28 - phase * 0.04, 0.62, 0.96)
			segment.Transparency = if visible then transparency else 1
			segment:SetAttribute("BaseTransparency", transparency)
		end
	end
end

local function updateShockwaves(deltaTime: number)
	activeShockwaveCount = 0
	local visible = style == "Grid" or style == "Circle" or style == "All" or style == "Minimal"
	for _, ring in ipairs(shockwaves) do
		if ring.active then
			activeShockwaveCount += 1
			ring.age += deltaTime / 0.72
			if ring.age >= 1 then
				ring.active = false
				for _, segment in ipairs(ring.segments) do
					segment.Transparency = 1
					segment:SetAttribute("BaseTransparency", 1)
				end
			else
				local alpha = 1 - ring.age
				local radius = 3.5 + ring.age * 35
				local visibleScale = if style == "Minimal" then 0.24 else 0.66
				local transparency = math.clamp(1 - alpha * ring.strength * visibleScale, 0.32, 1)
				for index, segment in ipairs(ring.segments) do
					local segmentAlpha = (index - 1) / #ring.segments
					local angle = segmentAlpha * math.pi * 2
					local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
					local position = visualCenter + Vector3.new(0, 2.35 + alpha * 0.85, 0) + direction * radius
					segment.CFrame = CFrame.lookAt(position, position + direction)
					segment.Size = Vector3.new(0.1, 0.07, 1.06 + alpha * 1.85)
					segment.Transparency = if visible then transparency else 1
					segment:SetAttribute("BaseTransparency", transparency)
				end
			end
		end
	end

	circleActiveWaves = activeShockwaveCount + #persistentWaveRings
end

local function updateLightSprays(deltaTime: number)
	activeSprayCount = 0
	for _, spray in ipairs(lightSprays) do
		if spray.active then
			spray.life += deltaTime
			if spray.life >= spray.maxLife then
				spray.active = false
				spray.part.Transparency = 1
				spray.part:SetAttribute("BaseTransparency", 1)
			else
				activeSprayCount += 1
				local ageAlpha = spray.life / spray.maxLife
				local fade = 1 - ageAlpha
				spray.velocity += Vector3.new(0, -8.5 * deltaTime, 0)
				spray.position += spray.velocity * deltaTime
				local velocityDirection = if spray.velocity.Magnitude > 0.001 then spray.velocity.Unit else Vector3.yAxis
				local length = (0.42 + spray.velocity.Magnitude * 0.022) * spray.size
				local transparency = math.clamp(1 - fade * (0.72 + spray.colorWeight * 0.08), 0.12, 1)
				local color = palette.Cyan:Lerp(palette.Text, 0.32 + spray.colorWeight * 0.46)

				spray.part.Size = Vector3.new(0.04 * spray.size, 0.04 * spray.size, length)
				spray.part.CFrame = CFrame.lookAt(spray.position, spray.position + velocityDirection) * CFrame.Angles(0, 0, spray.spin * spray.life)
				spray.part.Color = color
				spray.part.Transparency = transparency
				spray.part:SetAttribute("BaseTransparency", transparency)
			end
		end
	end
end

local function updateAccentLights(frame: AudioFrame, character: FrequencyCharacter, deltaTime: number)
	local visible = style == "Grid" or style == "Row" or style == "Circle" or style == "All"
	for index, accent in ipairs(accentLights) do
		accent.burst = NumberUtil.expSmooth(accent.burst, 0, deltaTime, 7)
		local phase = (math.sin(frame.time * (1.35 + index * 0.055) + accent.angle * 3) + 1) * 0.5
		local airGlow = (character.shimmerWeight * 0.68 + character.fluxAccent * 0.2) * phase
		local burst = accent.burst
		local position = visualCenter
			+ Vector3.new(
				math.cos(accent.angle + frame.time * 0.035) * accent.radius,
				2.15 + phase * 0.7 + frame.bass * 0.5 + burst * 0.42,
				math.sin(accent.angle + frame.time * 0.035) * accent.radius
			)
		accent.part.CFrame = CFrame.new(position)
		accent.part.Transparency = if visible then math.clamp(0.82 - airGlow * 0.3 - burst * 0.22, 0.34, 0.92) else 1
		accent.part:SetAttribute("BaseTransparency", accent.part.Transparency)
		accent.light.Brightness = if visible then math.clamp(0.08 + airGlow * 0.78 + burst * 1.8, 0.04, 2.0) else 0
		accent.light.Range = math.clamp(6.5 + burst * 8, 5.5, 15)
		accent.light:SetAttribute("BaseBrightness", accent.light.Brightness)
	end
end

local function updateAttributes(deltaTime: number, diagnostics: AudioDiagnostics)
	attributeAccumulator += deltaTime
	if attributeAccumulator < 0.25 then
		return
	end

	attributeAccumulator = 0
	local root = rootFolder
	if root == nil then
		return
	end

	root:SetAttribute("GridParts", #gridTiles)
	root:SetAttribute("RowBars", #rowBars)
	root:SetAttribute("CircleBars", #circleBars)
	root:SetAttribute("RowHeightVariance", rowHeightVariance)
	root:SetAttribute("RowMaxHeight", rowMaxHeight)
	root:SetAttribute("RowActiveCaps", rowActiveCaps)
	root:SetAttribute("RowSpectrumCorrelation", rowSpectrumCorrelation)
	root:SetAttribute("GridHeightVariance", gridHeightVariance)
	root:SetAttribute("GridMaxJump", maxRecentGridJump)
	root:SetAttribute("GridRippleCount", activeRippleCount)
	root:SetAttribute("CircleLengthVariance", circleLengthVariance)
	root:SetAttribute("CircleActiveWaves", circleActiveWaves)
	root:SetAttribute("ActiveSprays", activeSprayCount)
	root:SetAttribute("ActiveShockwaves", activeShockwaveCount)
	root:SetAttribute("MaxRecentGridJump", maxRecentGridJump)
	root:SetAttribute("LastBeatStrength", lastBeatStrength)
	root:SetAttribute("AnalyzerTruthMode", diagnostics.analyzerTruthMode)
	root:SetAttribute("UsingRealSpectrum", diagnostics.usingRealSpectrum)
	root:SetAttribute("SpectrumBinCount", diagnostics.spectrumBinCount)
	root:SetAttribute("SpectrumVariance", diagnostics.spectrumVariance)
	root:SetAttribute("CurrentAssetId", diagnostics.assetId)
	root:SetAttribute("AudioFallbackReason", diagnostics.fallbackReason)
end

local function updateVisuals(deltaTime: number)
	local frame = getSafeFrame()
	local diagnostics = getAudioDiagnostics(frame)
	local cleanDelta = math.clamp(NumberUtil.sanitizeFiniteNumber(deltaTime, 1 / 60), 1 / 240, 0.2)
	local character = computeFrequencyCharacter(frame)
	local energy = math.clamp((frame.visualEnergy * 0.38 + frame.rms * 0.18 + frame.peak * 0.16 + frame.bass * 0.2 + frame.mid * 0.12 + frame.high * 0.1) * motion, 0, 1)
	pulseAge += cleanDelta
	pulseStrength = NumberUtil.expSmooth(pulseStrength, 0, cleanDelta, 4.6)
	maxRecentGridJump = NumberUtil.expSmooth(maxRecentGridJump, 0, cleanDelta, 0.85)

	if frame.beat and frame.time - lastBeatTime > 0.08 then
		lastBeatTime = frame.time
		activatePulse(math.max(frame.beatStrength, frame.bass * 0.7, frame.spectralFlux * 0.82, 0.35), false)
	elseif frame.spectralFlux > 0.42 and frame.transient > 0.14 and frame.time - lastBeatTime > 0.22 then
		lastBeatTime = frame.time
		activatePulse(math.max(frame.spectralFlux * 0.8, frame.transient, 0.28), false)
	end

	updateGridRipples(cleanDelta)
	local gridJump = updateGrid(frame, character, energy, cleanDelta, diagnostics)
	maxRecentGridJump = math.max(maxRecentGridJump, gridJump)
	updateRow(frame, character, energy, cleanDelta, diagnostics)
	updateCircle(frame, character, energy, cleanDelta, diagnostics)
	updatePersistentWaveRings(frame, character)
	updateShockwaves(cleanDelta)
	updateLightSprays(cleanDelta)
	updateAccentLights(frame, character, cleanDelta)
	updateAttributes(cleanDelta, diagnostics)

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
	initializeGridRipples()
	createGrid(center)
	createAccentLights(center)
	createRowBars(center)
	createRadialCircle(center)
	createShockwaves(center)
	createPersistentWaveRings(center)
	createLightSprays(center)
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

function ResonanceController:SetMotion(value: number)
	motion = math.clamp(NumberUtil.sanitizeFiniteNumber(value, Constants.DEFAULT_MOTION), 0.25, 3.25)
end

function ResonanceController:GetMotion(): number
	return motion
end

function ResonanceController:SetIntensity(value: number)
	self:SetMotion(value)
end

function ResonanceController:GetIntensity(): number
	return motion
end

function ResonanceController:SetSprayAmount(value: number)
	sprayAmount = math.clamp(NumberUtil.sanitizeFiniteNumber(value, Constants.DEFAULT_SPRAY_AMOUNT), 0, 2.5)
end

function ResonanceController:GetSprayAmount(): number
	return sprayAmount
end

function ResonanceController:SetSmoothness(value: number)
	smoothness = math.clamp(NumberUtil.sanitizeFiniteNumber(value, Constants.DEFAULT_SMOOTHNESS), 0.25, 0.92)
end

function ResonanceController:GetSmoothness(): number
	return smoothness
end

function ResonanceController:GetStyle(): VisualStyle
	return style
end

function ResonanceController:TriggerPulse(strength: number)
	activatePulse(math.clamp(NumberUtil.sanitizeFiniteNumber(strength, 0.85), 0.1, 1), true)
end

function ResonanceController:TriggerPulseTest()
	self:TriggerPulse(1)
end

function ResonanceController:GetCurrentVisualStats(): VisualStats & { [string]: any }
	local frame = getSafeFrame()
	local diagnostics = getAudioDiagnostics(frame)
	return {
		gridParts = #gridTiles,
		rowBars = #rowBars,
		circleBars = #circleBars,
		rowHeightVariance = rowHeightVariance,
		circleLengthVariance = circleLengthVariance,
		gridHeightVariance = gridHeightVariance,
		rowActiveCaps = rowActiveCaps,
		rowSpectrumCorrelation = rowSpectrumCorrelation,
		activeSprays = activeSprayCount,
		activeShockwaves = activeShockwaveCount,
		maxRecentGridJump = maxRecentGridJump,
		lastBeatStrength = lastBeatStrength,
		analyzerTruthMode = diagnostics.analyzerTruthMode,
		usingRealSpectrum = diagnostics.usingRealSpectrum,
		spectrumBinCount = diagnostics.spectrumBinCount,
		spectrumVariance = diagnostics.spectrumVariance,
		AnalyzerTruthMode = diagnostics.analyzerTruthMode,
		UsingRealSpectrum = diagnostics.usingRealSpectrum,
		SpectrumBinCount = diagnostics.spectrumBinCount,
		SpectrumVariance = diagnostics.spectrumVariance,
		RowSpectrumCorrelation = rowSpectrumCorrelation,
		RowMaxHeight = rowMaxHeight,
		GridRippleCount = activeRippleCount,
		CircleActiveWaves = circleActiveWaves,
		GridArray = #gridTiles,
		RowBars = #rowBars,
		RadialCircle = #circleBars,
		Shockwaves = #shockwaves,
		AccentLights = #accentLights,
	}
end

function ResonanceController:GetDebugCounts(): { [string]: any }
	return self:GetCurrentVisualStats()
end

function ResonanceController:Destroy()
	maid:Cleanup()
end

return ResonanceController
