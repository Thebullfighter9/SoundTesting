--!strict

local ServicesFolder = script.Parent:WaitForChild("Services")

local RemoteService = require((ServicesFolder:WaitForChild("RemoteService") :: ModuleScript))
local GalleryService = require((ServicesFolder:WaitForChild("GalleryService") :: ModuleScript))
local MarbleService = require((ServicesFolder:WaitForChild("MarbleService") :: ModuleScript))

local services = {
	RemoteService,
	GalleryService,
	MarbleService,
}

local context = {
	RemoteService = RemoteService,
	GalleryService = GalleryService,
	MarbleService = MarbleService,
}

for _, service in ipairs(services) do
	service:Init(context)
end

for _, service in ipairs(services) do
	service:Start()
end
