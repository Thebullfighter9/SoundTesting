--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require((Shared:WaitForChild("Constants") :: ModuleScript))
local Network = Shared:WaitForChild("Network")
local RemoteNames = require((Network:WaitForChild("RemoteNames") :: ModuleScript))
local Util = Shared:WaitForChild("Util")
local InstanceUtil = require((Util:WaitForChild("InstanceUtil") :: ModuleScript))

local RemoteService = {}

local remotesFolder: Folder? = nil
local remotes: { [string]: RemoteEvent } = {}
local initialized = false

local function isKnownRemote(name: string): boolean
	for _, remoteName in pairs(RemoteNames :: { [string]: string }) do
		if remoteName == name then
			return true
		end
	end

	return false
end

local function getOrCreateRemote(folder: Folder, name: string): RemoteEvent
	local existing = folder:FindFirstChild(name)
	if existing ~= nil then
		if existing:IsA("RemoteEvent") then
			return existing
		end

		existing:Destroy()
	end

	return InstanceUtil.create("RemoteEvent", {
		Name = name,
	}, folder) :: RemoteEvent
end

function RemoteService:Init(_context: any?)
	if initialized then
		return
	end

	local existing = ReplicatedStorage:FindFirstChild(Constants.REMOTES_FOLDER_NAME)
	if existing ~= nil and not existing:IsA("Folder") then
		existing:Destroy()
		existing = nil
	end

	local folder = existing :: Folder?
	if folder == nil then
		folder = InstanceUtil.create("Folder", {
			Name = Constants.REMOTES_FOLDER_NAME,
		}, ReplicatedStorage) :: Folder
	end

	remotesFolder = folder

	for _, remoteName in pairs(RemoteNames :: { [string]: string }) do
		remotes[remoteName] = getOrCreateRemote(folder, remoteName)
	end

	initialized = true
end

function RemoteService:Start() end

function RemoteService:GetRemote(name: string): RemoteEvent
	assert(initialized, "RemoteService must be initialized before GetRemote")
	assert(isKnownRemote(name), `Unknown remote: {name}`)

	local remote = remotes[name]
	if remote ~= nil then
		return remote
	end

	local folder = remotesFolder
	assert(folder ~= nil, "Remotes folder is missing")

	local found = folder:FindFirstChild(name)
	assert(found ~= nil and found:IsA("RemoteEvent"), `Remote is missing: {name}`)

	remote = found :: RemoteEvent
	remotes[name] = remote
	return remote
end

return RemoteService
