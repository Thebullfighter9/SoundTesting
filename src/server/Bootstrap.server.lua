--!strict

local ServicesFolder = script.Parent:WaitForChild("Services")

local RemoteService = require((ServicesFolder:WaitForChild("RemoteService") :: ModuleScript))
local LabWorldService = require((ServicesFolder:WaitForChild("LabWorldService") :: ModuleScript))
local BeatOrbService = require((ServicesFolder:WaitForChild("BeatOrbService") :: ModuleScript))

local services = {
	RemoteService,
	LabWorldService,
	BeatOrbService,
}

local context = {
	RemoteService = RemoteService,
	LabWorldService = LabWorldService,
	BeatOrbService = BeatOrbService,
}

for _, service in ipairs(services) do
	service:Init(context)
end

for _, service in ipairs(services) do
	service:Start()
end
