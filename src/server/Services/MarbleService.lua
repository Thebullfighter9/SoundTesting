--!strict

local Debris = game:GetService("Debris")
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

type MarblePayload = {
	energy: any?,
}

local MarbleService = {}

local initialized = false
local started = false
local context: any = nil
local maid = Maid.new()
local limiter = RateLimiter.new(1, 1 / Constants.MARBLE_COOLDOWN)
local activeMarbles: { [Player]: { BasePart } } = {}
local marbleSerial = 0
local palette = Constants.PALETTE

local function getMarbleFolder(): Folder?
	local gallery = Workspace:FindFirstChild(Constants.GALLERY_FOLDER_NAME)
	if gallery == nil then
		return nil
	end

	local folder = gallery:FindFirstChild(Constants.MARBLES_FOLDER_NAME)
	if folder ~= nil and folder:IsA("Folder") then
		return folder
	end

	return nil
end

local function prunePlayerMarbles(player: Player): { BasePart }
	local current = activeMarbles[player]
	if current == nil then
		current = {}
		activeMarbles[player] = current
	end

	local writeIndex = 1
	for _, marble in ipairs(current) do
		if marble.Parent ~= nil then
			current[writeIndex] = marble
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

	local data = payload :: MarblePayload
	if data.energy == nil then
		return 0.45
	end

	local energy = NumberUtil.sanitizeFiniteNumber(data.energy, 0.45)
	return math.clamp(energy, 0, Constants.MAX_MARBLE_ENERGY)
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

local function removeFromActive(player: Player, marble: BasePart)
	local current = activeMarbles[player]
	if current == nil then
		return
	end

	for index, activeMarble in ipairs(current) do
		if activeMarble == marble then
			table.remove(current, index)
			return
		end
	end
end

local function spawnMarble(player: Player, root: BasePart, energy: number)
	local marbleFolder = getMarbleFolder()
	if marbleFolder == nil then
		return
	end

	local playerMarbles = prunePlayerMarbles(player)
	if #playerMarbles >= Constants.MAX_MARBLES_PER_PLAYER then
		return
	end

	marbleSerial += 1

	local look = root.CFrame.LookVector
	local diameter = 1.05 + energy * 1.2
	local spawnPosition = root.Position + look * 4.2 + Vector3.new(0, 2.9 + energy, 0)

	local marble = Instance.new("Part")
	marble.Name = `ResonanceMarble_{player.UserId}_{marbleSerial}`
	marble.Shape = Enum.PartType.Ball
	marble.Size = Vector3.new(diameter, diameter, diameter)
	marble.CFrame = CFrame.new(spawnPosition)
	marble.Material = Enum.Material.Glass
	marble.Color = palette.Cyan:Lerp(palette.SoftWhite, 0.45)
	marble.Transparency = 0.16
	marble.Reflectance = 0.08
	marble.CanCollide = true
	marble.CanTouch = true
	marble.CanQuery = true
	marble.Anchored = false
	marble.TopSurface = Enum.SurfaceType.Smooth
	marble.BottomSurface = Enum.SurfaceType.Smooth
	marble.CustomPhysicalProperties = PhysicalProperties.new(0.9, 0.35, 0.58, 1, 1)
	marble.Parent = marbleFolder

	pcall(function()
		marble:SetNetworkOwner(nil)
	end)

	marble.AssemblyLinearVelocity = look * (15 + energy * 18) + Vector3.new(0, 15 + energy * 11, 0)
	marble.AssemblyAngularVelocity = Vector3.new(0, 1.8 + energy * 4.5, 0)

	table.insert(playerMarbles, marble)
	Debris:AddItem(marble, Constants.MARBLE_LIFETIME)

	local cleanupThread = task.spawn(function()
		task.wait(Constants.MARBLE_LIFETIME + 0.1)
		removeFromActive(player, marble)
	end)
	maid:Give(cleanupThread)
end

local function handleMarbleRequested(player: Player, payload: any)
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

	spawnMarble(player, root, energy)
end

function MarbleService:Init(nextContext: any?)
	if initialized then
		return
	end

	context = nextContext
	initialized = true
end

function MarbleService:Start()
	if started then
		return
	end

	assert(context ~= nil and context.RemoteService ~= nil, "MarbleService requires RemoteService")

	local remote = context.RemoteService:GetRemote(RemoteNames.MarbleRequested)
	maid:Give(remote.OnServerEvent:Connect(handleMarbleRequested))
	maid:Give(Players.PlayerRemoving:Connect(function(player: Player)
		limiter:Clear(player)
		local current = activeMarbles[player]
		if current ~= nil then
			for _, marble in ipairs(current) do
				if marble.Parent ~= nil then
					marble:Destroy()
				end
			end
		end
		activeMarbles[player] = nil
	end))

	started = true
end

function MarbleService:Destroy()
	maid:Cleanup()
	for player, current in pairs(activeMarbles) do
		for _, marble in ipairs(current) do
			if marble.Parent ~= nil then
				marble:Destroy()
			end
		end
		activeMarbles[player] = nil
	end
end

return MarbleService
