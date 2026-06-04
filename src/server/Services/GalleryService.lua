--!strict

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require((Shared:WaitForChild("Constants") :: ModuleScript))
local Util = Shared:WaitForChild("Util")
local InstanceUtil = require((Util:WaitForChild("InstanceUtil") :: ModuleScript))

local GalleryService = {}

local initialized = false
local started = false
local galleryFolder: Folder? = nil
local palette = Constants.PALETTE

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

local function clearExisting()
	local existing = Workspace:FindFirstChild(Constants.GALLERY_FOLDER_NAME)
	if existing ~= nil then
		existing:Destroy()
	end

	for _, effectName in ipairs({ "ResonanceBloom", "ResonanceColor", "ResonanceAtmosphere" }) do
		local existingEffect = Lighting:FindFirstChild(effectName)
		if existingEffect ~= nil then
			existingEffect:Destroy()
		end
	end
end

local function configureLighting()
	InstanceUtil.create("BloomEffect", {
		Name = "ResonanceBloom",
		Intensity = 0.18,
		Size = 16,
		Threshold = 1.15,
	}, Lighting)

	InstanceUtil.create("ColorCorrectionEffect", {
		Name = "ResonanceColor",
		Brightness = -0.03,
		Contrast = 0.1,
		Saturation = -0.12,
		TintColor = Color3.fromRGB(226, 232, 226),
	}, Lighting)

	local ok, atmosphere = pcall(function()
		return Instance.new("Atmosphere")
	end)

	if ok and atmosphere ~= nil then
		atmosphere.Name = "ResonanceAtmosphere"
		safeSet(atmosphere, "Density", 0.18)
		safeSet(atmosphere, "Color", Color3.fromRGB(174, 184, 180))
		safeSet(atmosphere, "Decay", Color3.fromRGB(38, 42, 44))
		atmosphere.Parent = Lighting
	end

	safeSet(Lighting, "Ambient", Color3.fromRGB(70, 74, 72))
	safeSet(Lighting, "OutdoorAmbient", Color3.fromRGB(18, 20, 22))
	safeSet(Lighting, "Brightness", 1.25)
	safeSet(Lighting, "ClockTime", 18.4)
end

local function buildRoom(staticFolder: Folder)
	local floor = createPart(staticFolder, "MatteFloor", {
		CFrame = CFrame.new(0, 0, 0),
		Size = Vector3.new(92, 0.35, 92),
		Color = palette.Background,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
		CanTouch = true,
		CanQuery = true,
	})
	tag(floor, "ResonanceStage")

	local backWall = createPart(staticFolder, "BackWall", {
		CFrame = CFrame.new(0, 14, 46),
		Size = Vector3.new(92, 28, 0.7),
		Color = palette.Charcoal,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
		CanTouch = true,
		CanQuery = true,
	})
	tag(backWall, "ResonanceStage")

	local leftWall = createPart(staticFolder, "LeftWall", {
		CFrame = CFrame.new(-46, 14, 0),
		Size = Vector3.new(0.7, 28, 92),
		Color = palette.Charcoal,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
		CanTouch = true,
		CanQuery = true,
	})
	tag(leftWall, "ResonanceStage")

	local rightWall = createPart(staticFolder, "RightWall", {
		CFrame = CFrame.new(46, 14, 0),
		Size = Vector3.new(0.7, 28, 92),
		Color = palette.Charcoal,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
		CanTouch = true,
		CanQuery = true,
	})
	tag(rightWall, "ResonanceStage")

	local platform = createCylinder(
		staticFolder,
		"CentralPlatform",
		CFrame.new(0, 0.55, 0),
		Vector3.new(0.75, 33, 33),
		palette.Graphite,
		Enum.Material.Metal
	)
	tag(platform, "ResonanceStage")

	local rim = createCylinder(
		staticFolder,
		"FieldRim",
		CFrame.new(0, 1.08, 0),
		Vector3.new(0.16, 35, 35),
		palette.Cyan,
		Enum.Material.Glass
	)
	rim.CanCollide = false
	rim.CanTouch = false
	rim.Transparency = 0.52
	tag(rim, "ResonanceStage")
end

local function buildSpeakers(staticFolder: Folder)
	local positions = {
		Vector3.new(-31, 3.2, -25),
		Vector3.new(31, 3.2, -25),
		Vector3.new(-31, 3.2, 25),
		Vector3.new(31, 3.2, 25),
	}

	for index, position in ipairs(positions) do
		local monolith = createPart(staticFolder, `SpeakerMonolith_{index}`, {
			CFrame = CFrame.new(position),
			Size = Vector3.new(3.2, 6.4, 2.4),
			Color = palette.Graphite,
			Material = Enum.Material.Metal,
			CanCollide = true,
			CanTouch = true,
			CanQuery = true,
		})
		tag(monolith, "ResonanceStage")

		local slit = createPart(staticFolder, `SpeakerSlit_{index}`, {
			CFrame = CFrame.new(position + Vector3.new(0, 0.25, -1.23)),
			Size = Vector3.new(1.7, 4.7, 0.08),
			Color = palette.SoftWhite,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CanTouch = false,
			CanQuery = true,
			Transparency = 0.68,
		})
		tag(slit, "ResonanceStage")
	end
end

local function buildAnchors(anchorFolder: Folder)
	local gridSize = Constants.GALLERY_ANCHOR_GRID_SIZE
	local spacing = 1.55
	local origin = (gridSize - 1) * spacing * -0.5

	for row = 1, gridSize do
		for column = 1, gridSize do
			local x = origin + (column - 1) * spacing
			local z = origin + (row - 1) * spacing
			local anchor = createPart(anchorFolder, `Anchor_{row}_{column}`, {
				CFrame = CFrame.new(x, 1.2, z),
				Size = Vector3.new(0.2, 0.2, 0.2),
				Color = palette.Cyan,
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				CanTouch = false,
				CanQuery = true,
				Transparency = 1,
			})
			anchor:SetAttribute("Row", row)
			anchor:SetAttribute("Column", column)
			tag(anchor, "ResonanceAnchor")
		end
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
		CFrame = CFrame.new(0, 1.4, -31) * CFrame.Angles(0, math.rad(180), 0),
		Size = Vector3.new(7, 0.8, 7),
		Color = palette.Graphite,
		Material = Enum.Material.Metal,
		Transparency = 0.2,
	}, spawnFolder) :: SpawnLocation
	tag(spawnLocation, "ResonanceStage")
end

function GalleryService:Init(_context: any?)
	if initialized then
		return
	end

	initialized = true
end

function GalleryService:Start()
	if started then
		return
	end

	started = true
	clearExisting()

	local root = InstanceUtil.create("Folder", {
		Name = Constants.GALLERY_FOLDER_NAME,
	}, Workspace) :: Folder

	local staticFolder = InstanceUtil.create("Folder", {
		Name = Constants.STATIC_FOLDER_NAME,
	}, root) :: Folder

	local anchorFolder = InstanceUtil.create("Folder", {
		Name = Constants.ANCHORS_FOLDER_NAME,
	}, root) :: Folder

	local marblesFolder = InstanceUtil.create("Folder", {
		Name = Constants.MARBLES_FOLDER_NAME,
	}, root) :: Folder
	tag(marblesFolder, "MarbleContainer")

	local spawnFolder = InstanceUtil.create("Folder", {
		Name = Constants.SPAWN_FOLDER_NAME,
	}, root) :: Folder

	buildRoom(staticFolder)
	buildSpeakers(staticFolder)
	buildAnchors(anchorFolder)
	buildSpawn(spawnFolder)
	configureLighting()

	galleryFolder = root
end

function GalleryService:GetGalleryFolder(): Folder?
	return galleryFolder
end

return GalleryService
