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

type FieldPulsePayload = {
	intensity: any?,
}

local FieldPulseService = {}

local initialized = false
local started = false
local context: any = nil
local maid = Maid.new()
local limiter = RateLimiter.new(1, 1 / Constants.FIELD_PULSE_COOLDOWN)
local activePulses: { [Player]: { BasePart } } = {}
local pulseSerial = 0

local function getPulseFolder(): Folder?
	local field = Workspace:FindFirstChild(Constants.FIELD_FOLDER_NAME)
	if field == nil then
		return nil
	end

	local folder = field:FindFirstChild("PulseMasses")
	if folder ~= nil and folder:IsA("Folder") then
		return folder
	end

	return nil
end

local function prunePlayerPulses(player: Player): { BasePart }
	local current = activePulses[player]
	if current == nil then
		current = {}
		activePulses[player] = current
	end

	local writeIndex = 1
	for _, pulse in ipairs(current) do
		if pulse.Parent ~= nil then
			current[writeIndex] = pulse
			writeIndex += 1
		end
	end

	for index = writeIndex, #current do
		current[index] = nil
	end

	return current
end

local function sanitizeIntensity(payload: any): number?
	if payload == nil then
		return 0.5
	end

	if typeof(payload) ~= "table" then
		return nil
	end

	local data = payload :: FieldPulsePayload
	local intensity = NumberUtil.sanitizeFiniteNumber(data.intensity, 0.5)
	return math.clamp(intensity, 0, Constants.MAX_PULSE_INTENSITY)
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

local function cleanupPulse(player: Player, pulse: BasePart)
	if pulse.Parent ~= nil then
		pulse:Destroy()
	end

	local current = activePulses[player]
	if current == nil then
		return
	end

	for index, activePulse in ipairs(current) do
		if activePulse == pulse then
			table.remove(current, index)
			break
		end
	end
end

local function spawnPulseMass(player: Player, root: BasePart, intensity: number)
	local pulseFolder = getPulseFolder()
	if pulseFolder == nil then
		return
	end

	local playerPulses = prunePlayerPulses(player)
	if #playerPulses >= Constants.MAX_PULSES_PER_PLAYER then
		return
	end

	pulseSerial += 1

	local look = root.CFrame.LookVector
	local diameter = 1.15 + intensity * 1.7
	local spawnPosition = root.Position + look * 4.25 + Vector3.new(0, 3.2 + intensity * 1.4, 0)

	local pulse = Instance.new("Part")
	pulse.Name = `ResonancePulse_{player.UserId}_{pulseSerial}`
	pulse.Shape = Enum.PartType.Ball
	pulse.Size = Vector3.new(diameter, diameter, diameter)
	pulse.CFrame = CFrame.new(spawnPosition)
	pulse.Material = Enum.Material.Glass
	pulse.Color = Color3.fromRGB(174, 210, 215)
	pulse.Transparency = 0.18
	pulse.Reflectance = 0.08
	pulse.CanCollide = true
	pulse.CanTouch = true
	pulse.CanQuery = true
	pulse.Anchored = false
	pulse.TopSurface = Enum.SurfaceType.Smooth
	pulse.BottomSurface = Enum.SurfaceType.Smooth
	pulse.CustomPhysicalProperties = PhysicalProperties.new(0.9, 0.38, 0.62, 1, 1)
	pulse.Parent = pulseFolder

	pcall(function()
		pulse:SetNetworkOwner(nil)
	end)

	pulse.AssemblyLinearVelocity = look * (18 + intensity * 17) + Vector3.new(0, 16 + intensity * 14, 0)
	pulse.AssemblyAngularVelocity = Vector3.new(0, 2 + intensity * 5, 0)

	table.insert(playerPulses, pulse)

	local cleanupThread = task.spawn(function()
		task.wait(Constants.FIELD_PULSE_LIFETIME)
		cleanupPulse(player, pulse)
	end)
	maid:Give(cleanupThread)
end

local function handleFieldPulseRequested(player: Player, payload: any)
	if player.Parent ~= Players then
		return
	end

	local intensity = sanitizeIntensity(payload)
	if intensity == nil then
		return
	end

	local root = getRootPart(player)
	if root == nil then
		return
	end

	if not limiter:Check(player) then
		return
	end

	spawnPulseMass(player, root, intensity)
end

function FieldPulseService:Init(nextContext: any?)
	if initialized then
		return
	end

	context = nextContext
	initialized = true
end

function FieldPulseService:Start()
	if started then
		return
	end

	assert(context ~= nil and context.RemoteService ~= nil, "FieldPulseService requires RemoteService")

	local remote = context.RemoteService:GetRemote(RemoteNames.FieldPulseRequested)
	maid:Give(remote.OnServerEvent:Connect(handleFieldPulseRequested))
	maid:Give(Players.PlayerRemoving:Connect(function(player: Player)
		limiter:Clear(player)
		local current = activePulses[player]
		if current ~= nil then
			for _, pulse in ipairs(current) do
				if pulse.Parent ~= nil then
					pulse:Destroy()
				end
			end
		end
		activePulses[player] = nil
	end))

	started = true
end

function FieldPulseService:Destroy()
	maid:Cleanup()
	for player, current in pairs(activePulses) do
		for _, pulse in ipairs(current) do
			if pulse.Parent ~= nil then
				pulse:Destroy()
			end
		end
		activePulses[player] = nil
	end
end

return FieldPulseService
