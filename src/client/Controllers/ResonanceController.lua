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
	currentY: number,
	velocityY: number,
	currentHeight: number,
	glow: number,
	ripple: number,
	lastTarget: number,
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

local ResonanceController = {}

local initialized = false
local started = false
local context: any = nil
local maid = Maid.new()
local random = Random.new()
local gridTiles: { GridTile } = {}
local rowBars: { RowBar } = {}
local circleBars: { CircleBar } = {}
local shockwaves: { ShockwaveRing } = {}
local accentLights: { AccentLight } = {}
local lightSprays: { LightSpray } = {}
local style: VisualStyle = Constants.DEFAULT_VISUAL_STYLE :: VisualStyle
local motion = Constants.DEFAULT_MOTION
local sprayAmount = Constants.DEFAULT_SPRAY_AMOUNT
local warnedMissingGallery = false
local lastBeatTime = 0
local shockwaveCursor = 1
local sprayCursor = 1
local pulseAge = 10
local pulseStrength = 0
local maxRecentGridJump = 0
local lastBeatStrength = 0
local activeSprayCount = 0
local activeShockwaveCount = 0
local attributeAccumulator = 0

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
				CFrame = CFrame.new(basePosition + Vector3.new(0, Constants.GRID_MIN_HEIGHT * 0.5, 0)),
				Size = Vector3.new(tileWidth, Constants.GRID_MIN_HEIGHT, tileWidth),
				Color = palette.Text:Lerp(palette.Cyan, 0.14),
				Material = Enum.Material.Neon,
				Transparency = 0.1,
			})
			tile:SetAttribute("BaseTransparency", 0.1)

			table.insert(gridTiles, {
				part = tile,
				row = row,
				column = column,
				basePosition = basePosition,
				radius = localPosition.Magnitude,
				angle = math.atan2(z, x),
				centerWeight = centerWeight,
				edgeWeight = 1 - centerWeight,
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
			peakPart = peakPart,
			index = index,
			basePosition = position,
			peakHeight = Constants.ROW_MIN_HEIGHT,
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
			Size = Vector3.new(0.14, 0.38, 1.05 + Constants.CIRCLE_MIN_LENGTH),
			Color = palette.Text:Lerp(palette.Cyan, 0.34),
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

local function synthesizeBands(frame: AudioFrame): { number }
	local bands = table.create(audioBandCount, 0)
	local timeNow = if frame.time > 0 then frame.time else os.clock()
	local energy = math.clamp(math.max(frame.rms, frame.peak * 0.85, frame.visualEnergy, 0.24), 0, 1)

	for index = 1, audioBandCount do
		local alpha = (index - 1) / audioBandCount
		local wave = (math.sin(timeNow * 3.8 + alpha * math.pi * 5.5) + 1) * 0.5
		local shimmer = (math.sin(timeNow * 12 + alpha * math.pi * 22) + 1) * 0.5
		local bassShape = math.max(0, 1 - alpha * 3) * frame.bass
		bands[index] = math.clamp(energy * (0.24 + wave * 0.32 + shimmer * alpha * 0.16) + bassShape * 0.52, 0, 1)
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

	local visualEnergy = clamp01(audioFrame.visualEnergy or math.max(audioFrame.rms, audioFrame.peak))
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
	ring.strength = math.clamp(strength, 0.22, 1)
	ring.active = true
end

local function activateAccentBurst(strength: number)
	for _, accent in ipairs(accentLights) do
		accent.burst = math.max(accent.burst, strength)
	end
end

local function activateSprays(strength: number)
	if #lightSprays == 0 then
		return
	end
	if sprayAmount <= 0 then
		return
	end

	local minimalScale = if style == "Minimal" then 0.35 else 1
	local requestedCount = math.floor((12 + strength * 36) * sprayAmount * minimalScale)
	local count = math.clamp(requestedCount, 4, Constants.LIGHT_SPRAY_POOL_SIZE)
	for _ = 1, count do
		local spray = lightSprays[sprayCursor]
		sprayCursor += 1
		if sprayCursor > #lightSprays then
			sprayCursor = 1
		end

		local angle = random:NextNumber(0, math.pi * 2)
		local radius = random:NextNumber(0.8, 5.4 + strength * 5.5)
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local upward = random:NextNumber(8.5, 15.5) * (0.75 + strength * 0.6)
		local radialSpeed = random:NextNumber(15, 31) * (0.55 + strength * 0.8)
		local start = visualCenter + direction * radius + Vector3.new(0, random:NextNumber(2.1, 4.2), 0)

		spray.active = true
		spray.position = start
		spray.velocity = direction * radialSpeed + Vector3.new(0, upward, 0)
		spray.life = 0
		spray.maxLife = random:NextNumber(0.35, 0.85)
		spray.size = random:NextNumber(0.72, 1.55) * (0.7 + strength * 0.5)
		spray.spin = random:NextNumber(-3.5, 3.5)
		spray.colorWeight = random:NextNumber(0, 1)
	end
end

local function activatePulse(strength: number)
	local cleanStrength = math.clamp(NumberUtil.sanitizeFiniteNumber(strength, 0.85), 0.1, 1)
	pulseAge = 0
	pulseStrength = math.max(pulseStrength, cleanStrength)
	lastBeatStrength = cleanStrength

	activateShockwave(cleanStrength)
	activateSprays(cleanStrength)
	activateAccentBurst(cleanStrength)

	for _, tile in ipairs(gridTiles) do
		local centerImpulse = Constants.GRID_BEAT_IMPULSE * (0.24 + tile.centerWeight * 1.08)
		local radialImpulse = math.max(0, 1 - math.abs(tile.radius - 5.5) / 7) * 2.2
		tile.velocityY += (centerImpulse + radialImpulse) * cleanStrength * motion
		tile.ripple = math.max(tile.ripple, cleanStrength)
		tile.glow = math.max(tile.glow, cleanStrength)
	end
end

local function updateGrid(frame: AudioFrame, energy: number, deltaTime: number): number
	local timeNow = frame.time
	local minimal = style == "Minimal"
	local visible = style == "Grid" or style == "All" or style == "Minimal"
	local pulse = math.clamp(1 - pulseAge / 0.45, 0, 1) * pulseStrength
	local centroidEdge = math.clamp(frame.centroid, 0, 1)
	local maxJump = 0

	for index, tile in ipairs(gridTiles) do
		local band = getBand(frame, index + tile.row * 5 + tile.column * 2)
		local centerFocus = 1 - centroidEdge * 0.35
		local edgeFocus = 0.45 + centroidEdge * 1.15
		local dome = frame.bass ^ 1.25 * tile.centerWeight * centerFocus * (Constants.GRID_MAX_JUMP * 0.72)
		local diagonal = (math.sin(timeNow * 5.8 + (tile.row + tile.column) * 0.34) + 1) * 0.5 * frame.lowMid * 2.4
		local midRipple = (math.sin(timeNow * 4.6 - tile.radius * 0.62 + tile.angle * 1.6) + 1) * 0.5 * frame.mid * 2.2
		local beatRipple = math.max(0, 1 - math.abs(tile.radius - pulseAge * 45) / 4.4) * pulse * 4.8
		local highShimmer = (math.sin(timeNow * 22 + tile.angle * 7 + index) + 1) * 0.5 * (frame.high + frame.air * 0.65) * tile.edgeWeight * edgeFocus
		local visibleFloor = Constants.MIN_VISIBLE_ENERGY * (0.7 + energy * 0.7)
		local beatLift = math.max(frame.beatStrength, frame.transient * 1.35) * tile.centerWeight * Constants.GRID_BEAT_IMPULSE * 1.15
		local targetY = visibleFloor + band ^ 0.9 * 2.25 + dome + diagonal + midRipple + beatRipple + beatLift + highShimmer
		targetY *= motion
		if minimal then
			targetY *= 0.34
		end
		targetY = math.clamp(targetY, 0, Constants.GRID_MAX_JUMP)

		tile.lastTarget = targetY
		tile.ripple = NumberUtil.expSmooth(tile.ripple, 0, deltaTime, 5.2)
		tile.glow = NumberUtil.expSmooth(tile.glow, math.max(highShimmer, pulse * tile.centerWeight), deltaTime, 8)

		local acceleration = (targetY - tile.currentY) * Constants.GRID_SPRING_STIFFNESS - tile.velocityY * Constants.GRID_SPRING_DAMPING
		tile.velocityY += acceleration * deltaTime
		tile.currentY = math.clamp(tile.currentY + tile.velocityY * deltaTime, -0.24, Constants.GRID_MAX_JUMP + 2.2)
		maxJump = math.max(maxJump, tile.currentY)

		local targetHeight = Constants.GRID_MIN_HEIGHT
			+ band ^ 0.72 * 3.6
			+ tile.currentY * 0.95
			+ frame.transient * 2.2
			+ tile.ripple * tile.centerWeight * 2.4
			+ highShimmer * 0.9
		targetHeight *= if minimal then 0.45 else motion
		targetHeight = math.clamp(targetHeight, Constants.GRID_MIN_HEIGHT, Constants.GRID_MAX_HEIGHT)
		tile.currentHeight = NumberUtil.expSmooth(tile.currentHeight, targetHeight, deltaTime, 18)

		local brightness = math.clamp(band * 0.34 + tile.glow * 0.48 + frame.air * tile.edgeWeight * 0.24, 0, if minimal then 0.32 else 0.88)
		local transparency = if minimal then 0.46 else math.clamp(0.13 - brightness * 0.08, 0.035, 0.17)
		local width = Constants.GRID_TILE_WIDTH + math.clamp(tile.glow * 0.1 + band * 0.06, 0, 0.16)

		tile.part.Size = Vector3.new(width, tile.currentHeight, width)
		tile.part.CFrame = CFrame.new(tile.basePosition + Vector3.new(0, tile.currentY + tile.currentHeight * 0.5, 0))
		tile.part.Color = palette.Text:Lerp(palette.CyanSoft, brightness)
		tile.part.Transparency = if visible then transparency else 1
		tile.part:SetAttribute("BaseTransparency", transparency)
	end

	return maxJump
end

local function updateRow(frame: AudioFrame, energy: number, deltaTime: number)
	local visible = style == "Row" or style == "All"
	for _, rowBar in ipairs(rowBars) do
		local alpha = (rowBar.index - 1) / math.max(1, Constants.ROW_BAR_COUNT - 1)
		local band = getBand(frame, math.floor(alpha * audioBandCount) + 1)
		local leftWeight = math.max(0, 1 - alpha * 2.8)
		local centerWeight = math.max(0, 1 - math.abs(alpha - 0.44) * 3)
		local rightWeight = alpha ^ 1.6
		local body = frame.bass * leftWeight * 5.2 + frame.lowMid * centerWeight * 4.2 + frame.mid * 3.8 + frame.high * rightWeight * 3.1
		local variation = (math.sin(frame.time * 5.2 + alpha * math.pi * 7) + 1) * 0.5 * frame.mid * 2
		local globalPulse = math.max(frame.beatStrength, pulseStrength * math.clamp(1 - pulseAge / 0.34, 0, 1)) * 2.8
		local height = math.clamp(Constants.ROW_MIN_HEIGHT + (band ^ 0.74 * 12.8 + body + variation + energy * 2.2 + globalPulse) * motion, Constants.ROW_MIN_HEIGHT, Constants.ROW_MAX_HEIGHT)

		rowBar.peakHeight = math.max(height + 0.34, rowBar.peakHeight - deltaTime * (5.8 + frame.spectralFlux * 8))
		rowBar.peakHeight = math.clamp(rowBar.peakHeight, Constants.ROW_MIN_HEIGHT, Constants.ROW_MAX_HEIGHT + 0.8)
		rowBar.part.Size = Vector3.new(0.32 + frame.lowMid * 0.08, height, 0.56)
		rowBar.part.CFrame = CFrame.new(rowBar.basePosition + Vector3.new(0, height * 0.5, 0))
		rowBar.part.Color = palette.Text:Lerp(palette.Cyan, math.clamp(band * 0.5 + frame.mid * 0.22 + rightWeight * frame.high * 0.28, 0, 0.82))
		rowBar.part.Transparency = if visible then 0.08 else 1
		rowBar.part:SetAttribute("BaseTransparency", 0.08)

		rowBar.peakPart.CFrame = CFrame.new(rowBar.basePosition + Vector3.new(0, rowBar.peakHeight, 0))
		rowBar.peakPart.Transparency = if visible then math.clamp(0.18 - frame.spectralFlux * 0.08, 0.08, 0.3) else 1
		rowBar.peakPart:SetAttribute("BaseTransparency", rowBar.peakPart.Transparency)
	end
end

local function updateCircle(frame: AudioFrame, energy: number)
	local visible = style == "Circle" or style == "All" or style == "Minimal"
	local pulse = math.clamp(1 - pulseAge / 0.45, 0, 1) * pulseStrength
	local bassRadius = frame.bass * 2.8 + pulse * 2.2
	local centroidPush = frame.centroid * 1.8

	for _, circleBar in ipairs(circleBars) do
		local alpha = (circleBar.index - 1) / math.max(1, Constants.CIRCLE_BAR_COUNT - 1)
		local band = getBand(frame, math.floor(alpha * audioBandCount) + 1)
		local phase = (math.sin(frame.time * 6.4 + circleBar.angle * 7.5) + 1) * 0.5
		local highTip = (frame.high * 0.95 + frame.air * 0.72) * (0.5 + phase * 0.5)
		local extension = math.clamp((Constants.CIRCLE_MIN_LENGTH + band ^ 0.72 * 5.8 + frame.mid * 2.7 + highTip * 3.1 + energy * 1.6 + pulse * 2.2) * motion, Constants.CIRCLE_MIN_LENGTH, Constants.CIRCLE_MAX_LENGTH)
		local radius = circleBar.baseRadius + bassRadius + centroidPush + extension * 0.45
		local yLift = 2.52 + frame.lowMid * 1.1 + pulse * 0.68
		local position = visualCenter + Vector3.new(0, yLift, 0) + circleBar.direction * radius

		circleBar.part.Size = Vector3.new(0.14, 0.38 + highTip * 0.5, 1.05 + extension)
		circleBar.part.CFrame = CFrame.lookAt(position, position + circleBar.direction)
		circleBar.part.Color = palette.Text:Lerp(palette.CyanSoft, math.clamp(band * 0.44 + highTip * 0.34 + pulse * 0.22, 0, 0.84))
		local transparency = if style == "Minimal" then 0.5 else math.clamp(0.14 - highTip * 0.09, 0.05, 0.18)
		circleBar.part.Transparency = if visible then transparency else 1
		circleBar.part:SetAttribute("BaseTransparency", transparency)
	end
end

local function updateShockwaves(deltaTime: number)
	activeShockwaveCount = 0
	local visible = style == "Grid" or style == "Circle" or style == "All" or style == "Minimal"
	for _, ring in ipairs(shockwaves) do
		if ring.active then
			activeShockwaveCount += 1
			ring.age += deltaTime / 0.62
			if ring.age >= 1 then
				ring.active = false
				for _, segment in ipairs(ring.segments) do
					segment.Transparency = 1
					segment:SetAttribute("BaseTransparency", 1)
				end
			else
				local alpha = 1 - ring.age
				local radius = 3.5 + ring.age * 35
				local visibleScale = if style == "Minimal" then 0.28 else 0.72
				local transparency = math.clamp(1 - alpha * ring.strength * visibleScale, 0.28, 1)
				for index, segment in ipairs(ring.segments) do
					local segmentAlpha = (index - 1) / #ring.segments
					local angle = segmentAlpha * math.pi * 2
					local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
					local position = visualCenter + Vector3.new(0, 2.35 + alpha * 1.05, 0) + direction * radius
					segment.CFrame = CFrame.lookAt(position, position + direction)
					segment.Size = Vector3.new(0.11, 0.08, 1.12 + alpha * 2.1)
					segment.Transparency = if visible then transparency else 1
					segment:SetAttribute("BaseTransparency", transparency)
				end
			end
		end
	end
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
				spray.velocity += Vector3.new(0, -14 * deltaTime, 0)
				spray.position += spray.velocity * deltaTime
				local velocityDirection = if spray.velocity.Magnitude > 0.001 then spray.velocity.Unit else Vector3.yAxis
				local length = (0.7 + spray.velocity.Magnitude * 0.032) * spray.size
				local transparency = math.clamp(1 - fade * (0.78 + spray.colorWeight * 0.1), 0.08, 1)
				local color = palette.Cyan:Lerp(palette.Text, 0.28 + spray.colorWeight * 0.48)

				spray.part.Size = Vector3.new(0.055 * spray.size, 0.055 * spray.size, length)
				spray.part.CFrame = CFrame.lookAt(spray.position, spray.position + velocityDirection) * CFrame.Angles(0, 0, spray.spin * spray.life)
				spray.part.Color = color
				spray.part.Transparency = transparency
				spray.part:SetAttribute("BaseTransparency", transparency)
			end
		end
	end
end

local function updateAccentLights(frame: AudioFrame, deltaTime: number)
	local visible = style == "Grid" or style == "Row" or style == "Circle" or style == "All"
	for index, accent in ipairs(accentLights) do
		accent.burst = NumberUtil.expSmooth(accent.burst, 0, deltaTime, 7)
		local phase = (math.sin(frame.time * (1.5 + index * 0.07) + accent.angle * 3) + 1) * 0.5
		local airGlow = (frame.air * 0.72 + frame.high * 0.38 + frame.spectralFlux * 0.24) * phase
		local burst = accent.burst
		local position = visualCenter
			+ Vector3.new(
				math.cos(accent.angle + frame.time * 0.04) * accent.radius,
				2.2 + phase * 0.8 + frame.bass * 0.6 + burst * 0.5,
				math.sin(accent.angle + frame.time * 0.04) * accent.radius
			)
		accent.part.CFrame = CFrame.new(position)
		accent.part.Transparency = if visible then math.clamp(0.8 - airGlow * 0.34 - burst * 0.24, 0.32, 0.9) else 1
		accent.part:SetAttribute("BaseTransparency", accent.part.Transparency)
		accent.light.Brightness = if visible then math.clamp(0.1 + airGlow * 0.85 + burst * 2.1, 0.05, 2.3) else 0
		accent.light.Range = math.clamp(7 + burst * 10, 6, 18)
		accent.light:SetAttribute("BaseBrightness", accent.light.Brightness)
	end
end

local function updateAttributes(deltaTime: number)
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
	root:SetAttribute("ActiveSprays", activeSprayCount)
	root:SetAttribute("ActiveShockwaves", activeShockwaveCount)
	root:SetAttribute("MaxRecentGridJump", maxRecentGridJump)
	root:SetAttribute("LastBeatStrength", lastBeatStrength)
end

local function updateVisuals(deltaTime: number)
	local frame = getSafeFrame()
	local cleanDelta = math.clamp(NumberUtil.sanitizeFiniteNumber(deltaTime, 1 / 60), 1 / 240, 0.2)
	local energy = math.clamp((frame.visualEnergy * 0.44 + frame.rms * 0.2 + frame.peak * 0.18 + frame.bass * 0.2 + frame.mid * 0.12 + frame.high * 0.1) * motion, 0, 1)
	pulseAge += cleanDelta
	pulseStrength = NumberUtil.expSmooth(pulseStrength, 0, cleanDelta, 4.8)
	maxRecentGridJump = NumberUtil.expSmooth(maxRecentGridJump, 0, cleanDelta, 0.85)

	if frame.beat and frame.time - lastBeatTime > 0.08 then
		lastBeatTime = frame.time
		activatePulse(math.max(frame.beatStrength, frame.bass * 0.72, frame.spectralFlux * 0.9, 0.38))
	elseif frame.spectralFlux > 0.42 and frame.transient > 0.14 and frame.time - lastBeatTime > 0.22 then
		lastBeatTime = frame.time
		activatePulse(math.max(frame.spectralFlux * 0.85, frame.transient, 0.28))
	end

	local gridJump = updateGrid(frame, energy, cleanDelta)
	maxRecentGridJump = math.max(maxRecentGridJump, gridJump)
	updateRow(frame, energy, cleanDelta)
	updateCircle(frame, energy)
	updateShockwaves(cleanDelta)
	updateLightSprays(cleanDelta)
	updateAccentLights(frame, cleanDelta)
	updateAttributes(cleanDelta)

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

function ResonanceController:GetStyle(): VisualStyle
	return style
end

function ResonanceController:TriggerPulse(strength: number)
	activatePulse(math.clamp(NumberUtil.sanitizeFiniteNumber(strength, 0.85), 0.1, 1))
end

function ResonanceController:TriggerPulseTest()
	self:TriggerPulse(1)
end

function ResonanceController:GetCurrentVisualStats(): { [string]: number }
	return {
		gridParts = #gridTiles,
		rowBars = #rowBars,
		circleBars = #circleBars,
		activeSprays = activeSprayCount,
		activeShockwaves = activeShockwaveCount,
		maxRecentGridJump = maxRecentGridJump,
		lastBeatStrength = lastBeatStrength,
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
