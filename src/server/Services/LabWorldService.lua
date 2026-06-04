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
local labFolder: Folder? = nil

local COLORS = {
	cyan = Color3.fromRGB(0, 242, 255),
	blue = Color3.fromRGB(40, 118, 255),
	pink = Color3.fromRGB(255, 64, 188),
	purple = Color3.fromRGB(138, 80, 255),
	dark = Color3.fromRGB(9, 11, 22),
	black = Color3.fromRGB(2, 3, 8),
	white = Color3.fromRGB(230, 252, 255),
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

local function createNeonBlock(parent: Instance, name: string, cframe: CFrame, size: Vector3, color: Color3): BasePart
	return createPart(parent, name, {
		CFrame = cframe,
		Size = size,
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = true,
		CanTouch = true,
		CanQuery = true,
	})
end

local function rebuildLighting()
	for _, effectName in ipairs({ "PulseForgeBloom", "PulseForgeColor", "PulseForgeAtmosphere" }) do
		local existing = Lighting:FindFirstChild(effectName)
		if existing ~= nil then
			existing:Destroy()
		end
	end

	local bloom = InstanceUtil.create("BloomEffect", {
		Name = "PulseForgeBloom",
		Intensity = 1.2,
		Size = 24,
		Threshold = 0.85,
	}, Lighting)

	local color = InstanceUtil.create("ColorCorrectionEffect", {
		Name = "PulseForgeColor",
		Brightness = 0.03,
		Contrast = 0.18,
		Saturation = 0.18,
		TintColor = Color3.fromRGB(220, 245, 255),
	}, Lighting)

	local atmosphereOk, atmosphere = pcall(function()
		return Instance.new("Atmosphere")
	end)

	if atmosphereOk and atmosphere ~= nil then
		atmosphere.Name = "PulseForgeAtmosphere"
		safeSet(atmosphere, "Density", 0.35)
		safeSet(atmosphere, "Color", Color3.fromRGB(115, 175, 255))
		safeSet(atmosphere, "Decay", Color3.fromRGB(20, 30, 60))
		atmosphere.Parent = Lighting
	end

	safeSet(Lighting, "Ambient", Color3.fromRGB(22, 28, 55))
	safeSet(Lighting, "OutdoorAmbient", Color3.fromRGB(8, 10, 18))
	safeSet(Lighting, "Brightness", 2)
	safeSet(Lighting, "ClockTime", 0.1)

	-- Keep references live in strict mode without needing later mutation.
	if bloom == nil or color == nil then
		warn("PulseForge lighting effect creation did not complete")
	end
end

local function createStage(staticFolder: Folder)
	local floor = createPart(staticFolder, "StageFloor", {
		CFrame = CFrame.new(0, 0, 0),
		Size = Vector3.new(110, 1, 110),
		Color = COLORS.black,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = true,
		CanTouch = true,
		CanQuery = true,
	})
	tag(floor, "PulseForgeStage")

	local platform = createPart(staticFolder, "RaisedPlatform", {
		CFrame = CFrame.new(0, 1.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Size = Vector3.new(2, 34, 34),
		Color = Color3.fromRGB(13, 20, 38),
		Material = Enum.Material.Metal,
		Shape = Enum.PartType.Cylinder,
		CanCollide = true,
		CanTouch = true,
		CanQuery = true,
	})
	tag(platform, "PulseForgeStage")

	createNeonBlock(staticFolder, "EntryRailLeft", CFrame.new(-26, 2.2, -38), Vector3.new(2, 3, 26), COLORS.cyan)
	createNeonBlock(staticFolder, "EntryRailRight", CFrame.new(26, 2.2, -38), Vector3.new(2, 3, 26), COLORS.pink)
	createNeonBlock(staticFolder, "BackGlowWall", CFrame.new(0, 6, 47), Vector3.new(86, 11, 2), COLORS.blue)

	for index = 1, 4 do
		local sign = if index <= 2 then -1 else 1
		local offset = if index % 2 == 0 then 18 else 34
		local rail = createNeonBlock(
			staticFolder,
			`SideRail_{index}`,
			CFrame.new(sign * 51, 2.6, offset),
			Vector3.new(2, 3.5, 26),
			if sign < 0 then COLORS.purple else COLORS.cyan
		)
		rail.Transparency = 0.1
	end
end

local function createSpawn(spawnFolder: Folder)
	local spawnLocation = InstanceUtil.create("SpawnLocation", {
		Name = "PulseForgeSpawn",
		Anchored = true,
		CanCollide = true,
		CanTouch = true,
		CanQuery = true,
		Neutral = true,
		Duration = 0,
		CFrame = CFrame.new(0, 3, -22),
		Size = Vector3.new(12, 1, 12),
		Color = COLORS.cyan,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
	}, spawnFolder) :: SpawnLocation

	tag(spawnLocation, "PulseForgeStage")
end

local function createSpeakers(staticFolder: Folder)
	for side = -1, 1, 2 do
		local baseX = side * 32
		createPart(staticFolder, `SpeakerTower_{side}_Body`, {
			CFrame = CFrame.new(baseX, 7, 12),
			Size = Vector3.new(8, 14, 6),
			Color = Color3.fromRGB(10, 13, 25),
			Material = Enum.Material.Metal,
			CanCollide = true,
			CanTouch = true,
			CanQuery = true,
		})

		for level = 1, 3 do
			local cone = createPart(staticFolder, `SpeakerTower_{side}_Cone_{level}`, {
				CFrame = CFrame.new(baseX, 3.5 + level * 3.1, 8.65) * CFrame.Angles(math.rad(90), 0, 0),
				Size = Vector3.new(3.3, 0.35, 3.3),
				Color = if level == 2 then COLORS.pink else COLORS.cyan,
				Material = Enum.Material.Neon,
				Shape = Enum.PartType.Cylinder,
				CanCollide = false,
				CanTouch = false,
				CanQuery = true,
			})
			cone.Transparency = 0.15
		end

		local light = InstanceUtil.create("PointLight", {
			Name = `SpeakerGlow_{side}`,
			Color = if side < 0 then COLORS.cyan else COLORS.pink,
			Range = 24,
			Brightness = 2.2,
		}, staticFolder:FindFirstChild(`SpeakerTower_{side}_Body`) :: Instance)

		if light == nil then
			warn("PulseForge speaker light creation failed")
		end
	end
end

local function createAnchors(anchorFolder: Folder)
	local count = Constants.VISUALIZER_BAND_COUNT
	local radius = 38

	for index = 1, count do
		local alpha = (index - 1) / count
		local angle = alpha * math.pi * 2
		local x = math.cos(angle) * radius
		local z = math.sin(angle) * radius
		local color = Color3.fromHSV(alpha, 0.82, 1)

		local anchor = createPart(anchorFolder, `Anchor_{string.format("%02d", index)}`, {
			CFrame = CFrame.new(x, 1.45, z),
			Size = Vector3.new(1.2, 1.2, 1.2),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.1,
			CanCollide = false,
			CanTouch = false,
			CanQuery = true,
		})
		tag(anchor, "PulseForgeAnchor")
	end
end

local function createCenterRing(staticFolder: Folder)
	local segmentCount = 40
	local radius = 18

	for index = 1, segmentCount do
		local alpha = (index - 1) / segmentCount
		local angle = alpha * math.pi * 2
		local x = math.cos(angle) * radius
		local z = math.sin(angle) * radius
		local segment = createNeonBlock(
			staticFolder,
			`CenterRing_{string.format("%02d", index)}`,
			CFrame.new(x, 2.35, z) * CFrame.Angles(0, -angle, 0),
			Vector3.new(4.2, 0.35, 0.55),
			Color3.fromHSV(alpha, 0.9, 1)
		)
		segment.CanCollide = false
		segment.CanTouch = false
	end
end

local function createLabel(staticFolder: Folder)
	local labelPart = createPart(staticFolder, "WorldLabelAnchor", {
		CFrame = CFrame.new(0, 13, -31),
		Size = Vector3.new(1, 1, 1),
		Color = COLORS.white,
		Transparency = 1,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
	})

	local billboard = InstanceUtil.create("BillboardGui", {
		Name = "PulseForgeLabel",
		Adornee = labelPart,
		AlwaysOnTop = true,
		LightInfluence = 0,
		Size = UDim2.fromOffset(420, 92),
		StudsOffset = Vector3.new(0, 0, 0),
	}, labelPart) :: BillboardGui

	local textLabel = InstanceUtil.create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "PulseForge Lab",
		TextColor3 = COLORS.white,
		TextScaled = true,
		TextStrokeTransparency = 0.25,
		Size = UDim2.fromScale(1, 1),
	}, billboard) :: TextLabel

	InstanceUtil.create("UITextSizeConstraint", {
		MaxTextSize = 42,
		MinTextSize = 14,
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

	local existing = Workspace:FindFirstChild(Constants.LAB_FOLDER_NAME)
	if existing ~= nil then
		existing:Destroy()
	end

	local root = InstanceUtil.create("Folder", {
		Name = Constants.LAB_FOLDER_NAME,
	}, Workspace) :: Folder

	local staticFolder = InstanceUtil.create("Folder", {
		Name = "Static",
	}, root) :: Folder

	local anchorFolder = InstanceUtil.create("Folder", {
		Name = "VisualizerAnchors",
	}, root) :: Folder

	local orbFolder = InstanceUtil.create("Folder", {
		Name = "PhysicsOrbs",
	}, root) :: Folder
	tag(orbFolder, "PulseForgeOrbContainer")

	local spawnFolder = InstanceUtil.create("Folder", {
		Name = "Spawn",
	}, root) :: Folder

	createStage(staticFolder)
	createSpawn(spawnFolder)
	createSpeakers(staticFolder)
	createAnchors(anchorFolder)
	createCenterRing(staticFolder)
	createLabel(staticFolder)
	rebuildLighting()

	labFolder = root
end

function LabWorldService:GetLabFolder(): Folder?
	return labFolder
end

return LabWorldService
