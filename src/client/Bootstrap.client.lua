--!strict

local ControllersFolder = script.Parent:WaitForChild("Controllers")

local AudioController = require((ControllersFolder:WaitForChild("AudioController") :: ModuleScript))
local ResonanceController = require((ControllersFolder:WaitForChild("ResonanceController") :: ModuleScript))
local CameraController = require((ControllersFolder:WaitForChild("CameraController") :: ModuleScript))
local UIController = require((ControllersFolder:WaitForChild("UIController") :: ModuleScript))

local controllers = {
	AudioController,
	ResonanceController,
	CameraController,
	UIController,
}

local context = {
	AudioController = AudioController,
	ResonanceController = ResonanceController,
	CameraController = CameraController,
	UIController = UIController,
}

for _, controller in ipairs(controllers) do
	controller:Init(context)
end

for _, controller in ipairs(controllers) do
	controller:Start()
end
