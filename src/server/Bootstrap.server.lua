--!strict

local ServicesFolder = script.Parent:WaitForChild("Services")

local RemoteService = require((ServicesFolder:WaitForChild("RemoteService") :: ModuleScript))
local LabWorldService = require((ServicesFolder:WaitForChild("LabWorldService") :: ModuleScript))
local FieldPulseService = require((ServicesFolder:WaitForChild("FieldPulseService") :: ModuleScript))

local services = {
	RemoteService,
	LabWorldService,
	FieldPulseService,
}

local context = {
	RemoteService = RemoteService,
	LabWorldService = LabWorldService,
	FieldPulseService = FieldPulseService,
}

for _, service in ipairs(services) do
	service:Init(context)
end

for _, service in ipairs(services) do
	service:Start()
end
