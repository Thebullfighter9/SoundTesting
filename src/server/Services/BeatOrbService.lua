--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require((Shared:WaitForChild("Constants") :: ModuleScript))
local Network = Shared:WaitForChild("Network")
local RemoteNames = require((Network:WaitForChild("RemoteNames") :: ModuleScript))
local Util = Shared:WaitForChild("Util")
local Maid = require((Util:WaitForChild("Maid") :: ModuleScript))
local NumberUtil = require((Util:WaitForChild("NumberUtil") :: ModuleScript))
local RateLimiter = require((Util:WaitForChild("RateLimiter") :: ModuleScript))

type BeatOrbPayload = {
	energy: any?,
}

local BeatOrbService = {}

local initialized = false
local started = false
local context: any = nil
local maid = Maid.new()
local limiter = RateLimiter.new(1, 1 / Constants.BEAT_ORB_COOLDOWN)
local activeOrbs: { [Player]: { BasePart } } = {}
local orbSerial = 0

local function getOrbFolder(): Folder?
	local lab = Workspace:FindFirstChild(Constants.LAB_FOLDER_NAME)
	if lab == nil then
		return nil
	end

	local folder = lab:FindFirstChild("PhysicsOrbs")
	if folder ~= nil and folder:IsA("Folder") then
		return folder
	end

	return nil
end

local function prunePlayerOrbs(player: Player): { BasePart }
	local current = activeOrbs[player]
	if current == nil then
		current = {}
		activeOrbs[player] = current
	end

	local writeIndex = 1
	for _, orb in ipairs(current) do
		if orb.Parent ~= nil then
			current[writeIndex] = orb
			writeIndex += 1
		end
	end

	for index = writeIndex, #current do
		current[index] = nil
	end

	return current
end

local function sanitizeEnergy(payload: any): number?
	if payload == nil then
		return 0.45
	end

	if typeof(payload) ~= "table" then
		return nil
	end

	local data = payload :: BeatOrbPayload
	local energy = NumberUtil.sanitizeFiniteNumber(data.energy, 0.45)
	return math.clamp(energy, 0, Constants.MAX_ORB_ENERGY)
end

local function getRootPart(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root
	end

	return nil
end

local function cleanupOrb(player: Player, orb: BasePart)
	if orb.Parent ~= nil then
		orb:Destroy()
	end

	local current = activeOrbs[player]
	if current == nil then
		return
	end

	for index, activeOrb in ipairs(current) do
		if activeOrb == orb then
			table.remove(current, index)
			break
		end
	end
end

local function spawnBeatOrb(player: Player, root: BasePart, energy: number)
	local orbFolder = getOrbFolder()
	if orbFolder == nil then
		return
	end

	local playerOrbs = prunePlayerOrbs(player)
	if #playerOrbs >= Constants.MAX_ORBS_PER_PLAYER then
		return
	end

	orbSerial += 1

	local diameter = 2.1 + energy * 2.2
	local look = root.CFrame.LookVector
	local spawnPosition = root.Position + look * 6 + Vector3.new(0, 4 + energy * 1.5, 0)
	local hue = (player.UserId % 360) / 360

	local orb = Instance.new("Part")
	orb.Name = `BeatOrb_{player.UserId}_{orbSerial}`
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(diameter, diameter, diameter)
	orb.CFrame = CFrame.new(spawnPosition)
	orb.Material = Enum.Material.Neon
	orb.Color = Color3.fromHSV(hue, 0.72, 1)
	orb.CanCollide = true
	orb.CanTouch = true
	orb.CanQuery = true
	orb.Anchored = false
	orb.TopSurface = Enum.SurfaceType.Smooth
	orb.BottomSurface = Enum.SurfaceType.Smooth
	orb.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.25, 0.78, 1, 1)
	orb.Parent = orbFolder

	pcall(function()
		orb:SetNetworkOwner(nil)
	end)

	orb.AssemblyLinearVelocity = look * (36 + energy * 30) + Vector3.new(0, 34 + energy * 24, 0)
	orb.AssemblyAngularVelocity = Vector3.new(0, 5 + energy * 8, 0)

	table.insert(playerOrbs, orb)

	local cleanupThread = task.spawn(function()
		task.wait(Constants.BEAT_ORB_LIFETIME)
		cleanupOrb(player, orb)
	end)
	maid:Give(cleanupThread)
end

local function handleBeatOrbRequested(player: Player, payload: any)
	if player.Parent ~= Players then
		return
	end

	local energy = sanitizeEnergy(payload)
	if energy == nil then
		return
	end

	local root = getRootPart(player)
	if root == nil then
		return
	end

	if not limiter:Check(player) then
		return
	end

	spawnBeatOrb(player, root, energy)
end

function BeatOrbService:Init(nextContext: any?)
	if initialized then
		return
	end

	context = nextContext
	initialized = true
end

function BeatOrbService:Start()
	if started then
		return
	end

	assert(context ~= nil and context.RemoteService ~= nil, "BeatOrbService requires RemoteService")

	local remote = context.RemoteService:GetRemote(RemoteNames.BeatOrbRequested)
	maid:Give(remote.OnServerEvent:Connect(handleBeatOrbRequested))
	maid:Give(Players.PlayerRemoving:Connect(function(player: Player)
		limiter:Clear(player)
		local current = activeOrbs[player]
		if current ~= nil then
			for _, orb in ipairs(current) do
				if orb.Parent ~= nil then
					orb:Destroy()
				end
			end
		end
		activeOrbs[player] = nil
	end))

	started = true
end

function BeatOrbService:Destroy()
	maid:Cleanup()
	for player, current in pairs(activeOrbs) do
		for _, orb in ipairs(current) do
			if orb.Parent ~= nil then
				orb:Destroy()
			end
		end
		activeOrbs[player] = nil
	end
end

return BeatOrbService
