--!strict

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require((Shared:WaitForChild("Constants") :: ModuleScript))
local Util = Shared:WaitForChild("Util")
local InstanceUtil = require((Util:WaitForChild("InstanceUtil") :: ModuleScript))

local LabWorldService = {}

local initialized = false
local started = false
local fieldFolder: Folder? = nil

local PALETTE = {
	charcoal = Color3.fromRGB(18, 20, 22),
	graphite = Color3.fromRGB(34, 38, 40),
	stone = Color3.fromRGB(68, 72, 72),
	mist = Color3.fromRGB(172, 198, 198),
	softCyan = Color3.fromRGB(92, 178, 184),
	warm = Color3.fromRGB(210, 198, 170),
}

local function safeSet(instance: Instance, propertyName: string, value: any)
	pcall(function()
		(instance :: any)[propertyName] = value
	end)
end

local function tag(instance: Instance, tagName: string)
	CollectionService:AddTag(instance, tagName)
end

local function createPart(parent: Instance, name: string, props: { [string]: any }): BasePart
	props.Name = name
	props.Anchored = if props.Anchored == nil then true else props.Anchored
	props.TopSurface = Enum.SurfaceType.Smooth
	props.BottomSurface = Enum.SurfaceType.Smooth

	return InstanceUtil.create("Part", props, parent) :: BasePart
end

local function createCylinder(parent: Instance, name: string, cframe: CFrame, size: Vector3, color: Color3, material: Enum.Material): BasePart
	return createPart(parent, name, {
		CFrame = cframe * CFrame.Angles(0, 0, math.rad(90)),
		Size = size,
		Color = color,
		Material = material,
		Shape = Enum.PartType.Cylinder,
		CanCollide = true,
		CanTouch = true,
		CanQuery = true,
	})
end

local function clearPreviousWorld()
	for _, folderName in ipairs({ Constants.FIELD_FOLDER_NAME }) do
		local existing = Workspace:FindFirstChild(folderName)
		if existing ~= nil then
			existing:Destroy()
		end
	end

	for _, effectName in ipairs({
		"ResonanceBloom",
		"ResonanceColor",
		"ResonanceAtmosphere",
	}) do
		local effect = Lighting:FindFirstChild(effectName)
		if effect ~= nil then
			effect:Destroy()
		end
	end
end

local function configureLighting()
	InstanceUtil.create("BloomEffect", {
		Name = "ResonanceBloom",
		Intensity = 0.28,
		Size = 18,
		Threshold = 1.1,
	}, Lighting)

	InstanceUtil.create("ColorCorrectionEffect", {
		Name = "ResonanceColor",
		Brightness = -0.02,
		Contrast = 0.08,
		Saturation = -0.08,
		TintColor = Color3.fromRGB(232, 238, 232),
	}, Lighting)

	local ok, atmosphere = pcall(function()
		return Instance.new("Atmosphere")
	end)

	if ok and atmosphere ~= nil then
		atmosphere.Name = "ResonanceAtmosphere"
		safeSet(atmosphere, "Density", 0.22)
		safeSet(atmosphere, "Color", Color3.fromRGB(182, 194, 190))
		safeSet(atmosphere, "Decay", Color3.fromRGB(42, 50, 54))
		atmosphere.Parent = Lighting
	end

	safeSet(Lighting, "Ambient", Color3.fromRGB(76, 82, 82))
	safeSet(Lighting, "OutdoorAmbient", Color3.fromRGB(28, 31, 34))
	safeSet(Lighting, "Brightness", 1.35)
	safeSet(Lighting, "ClockTime", 18.25)
end

local function buildGround(staticFolder: Folder)
	local floor = createPart(staticFolder, "GalleryFloor", {
		CFrame = CFrame.new(0, -0.05, 0),
		Size = Vector3.new(96, 0.25, 96),
		Color = PALETTE.charcoal,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
		CanTouch = true,
		CanQuery = true,
	})
	tag(floor, "ResonanceStage")

	local plinth = createCylinder(
		staticFolder,
		"ListeningPlinth",
		CFrame.new(0, 0.35, 0),
		Vector3.new(0.8, 34, 34),
		PALETTE.graphite,
		Enum.Material.Metal
	)
	tag(plinth, "ResonanceStage")

	local inner = createCylinder(
		staticFolder,
		"FieldSurface",
		CFrame.new(0, 0.86, 0),
		Vector3.new(0.2, 24, 24),
		Color3.fromRGB(24, 28, 29),
		Enum.Material.SmoothPlastic
	)
	inner.CanCollide = false
	inner.CanTouch = false
	tag(inner, "ResonanceStage")

	for index = 1, 4 do
		local angle = (index - 1) * math.pi * 0.5 + math.pi * 0.25
		local radius = 38
		local marker = createPart(staticFolder, `BoundaryMarker_{index}`, {
			CFrame = CFrame.new(math.cos(angle) * radius, 1.45, math.sin(angle) * radius) * CFrame.Angles(0, -angle, 0),
			Size = Vector3.new(12, 0.32, 0.42),
			Color = PALETTE.stone,
			Material = Enum.Material.Metal,
			CanCollide = false,
			CanTouch = false,
			CanQuery = true,
		})
		marker.Transparency = 0.18
	end
end

local function buildSpawn(spawnFolder: Folder)
	local spawnLocation = InstanceUtil.create("SpawnLocation", {
		Name = "ResonanceSpawn",
		Anchored = true,
		CanCollide = true,
		CanTouch = true,
		CanQuery = true,
		Neutral = true,
		Duration = 0,
		CFrame = CFrame.new(0, 1.35, -22),
		Size = Vector3.new(8, 0.8, 8),
		Color = PALETTE.stone,
		Material = Enum.Material.Metal,
		Transparency = 0.15,
	}, spawnFolder) :: SpawnLocation

	tag(spawnLocation, "ResonanceStage")
end

local function buildAnchors(anchorFolder: Folder)
	local count = Constants.FIELD_BAND_COUNT
	local radius = 18

	for index = 1, count do
		local alpha = (index - 1) / count
		local angle = alpha * math.pi * 2
		local position = Vector3.new(math.cos(angle) * radius, 1.05, math.sin(angle) * radius)
		local anchor = createPart(anchorFolder, `FieldAnchor_{string.format("%02d", index)}`, {
			CFrame = CFrame.new(position),
			Size = Vector3.new(0.34, 0.34, 0.34),
			Color = PALETTE.mist,
			Material = Enum.Material.Glass,
			CanCollide = false,
			CanTouch = false,
			CanQuery = true,
			Transparency = 0.25,
		})
		tag(anchor, "ResonanceAnchor")
	end
end

local function buildReferenceRings(staticFolder: Folder)
	for ringIndex, radius in ipairs({ 10, 18, 27 }) do
		local segments = 36
		for index = 1, segments do
			local alpha = (index - 1) / segments
			local angle = alpha * math.pi * 2
			local segment = createPart(staticFolder, `ReferenceRing_{ringIndex}_{string.format("%02d", index)}`, {
				CFrame = CFrame.new(math.cos(angle) * radius, 1.02 + ringIndex * 0.04, math.sin(angle) * radius)
					* CFrame.Angles(0, -angle, 0),
				Size = Vector3.new(2.6, 0.08, 0.08),
				Color = if ringIndex == 2 then PALETTE.softCyan else PALETTE.stone,
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				CanTouch = false,
				CanQuery = true,
				Transparency = if ringIndex == 2 then 0.22 else 0.42,
			})
			tag(segment, "ResonanceGuide")
		end
	end
end

local function buildLabel(staticFolder: Folder)
	local labelPart = createPart(staticFolder, "WorldLabelAnchor", {
		CFrame = CFrame.new(0, 6.5, -30),
		Size = Vector3.new(1, 1, 1),
		Color = PALETTE.mist,
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
	})

	local billboard = InstanceUtil.create("BillboardGui", {
		Name = "ResonanceLabel",
		Adornee = labelPart,
		AlwaysOnTop = true,
		LightInfluence = 0.15,
		Size = UDim2.fromOffset(360, 54),
		StudsOffset = Vector3.new(0, 0, 0),
	}, labelPart) :: BillboardGui

	local textLabel = InstanceUtil.create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "Resonance Field",
		TextColor3 = PALETTE.mist,
		TextScaled = true,
		TextStrokeTransparency = 0.7,
		Size = UDim2.fromScale(1, 1),
	}, billboard) :: TextLabel

	InstanceUtil.create("UITextSizeConstraint", {
		MaxTextSize = 28,
		MinTextSize = 12,
	}, textLabel)
end

function LabWorldService:Init(_context: any?)
	if initialized then
		return
	end

	initialized = true
end

function LabWorldService:Start()
	if started then
		return
	end

	started = true
	clearPreviousWorld()

	local root = InstanceUtil.create("Folder", {
		Name = Constants.FIELD_FOLDER_NAME,
	}, Workspace) :: Folder

	local staticFolder = InstanceUtil.create("Folder", {
		Name = "Static",
	}, root) :: Folder

	local anchorFolder = InstanceUtil.create("Folder", {
		Name = "FieldAnchors",
	}, root) :: Folder

	local pulseFolder = InstanceUtil.create("Folder", {
		Name = "PulseMasses",
	}, root) :: Folder
	tag(pulseFolder, "ResonancePulseContainer")

	local spawnFolder = InstanceUtil.create("Folder", {
		Name = "Spawn",
	}, root) :: Folder

	buildGround(staticFolder)
	buildSpawn(spawnFolder)
	buildAnchors(anchorFolder)
	buildReferenceRings(staticFolder)
	buildLabel(staticFolder)
	configureLighting()

	fieldFolder = root
end

function LabWorldService:GetFieldFolder(): Folder?
	return fieldFolder
end

return LabWorldService
