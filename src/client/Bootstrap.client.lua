--!strict

local ControllersFolder = script.Parent:WaitForChild("Controllers")

local AudioController = require((ControllersFolder:WaitForChild("AudioController") :: ModuleScript))
local ResonanceController = require((ControllersFolder:WaitForChild("ResonanceController") :: ModuleScript))
local CameraController = require((ControllersFolder:WaitForChild("CameraController") :: ModuleScript))
local UIController = require((ControllersFolder:WaitForChild("UIController") :: ModuleScript))
local InputController = require((ControllersFolder:WaitForChild("InputController") :: ModuleScript))

local controllers = {
	AudioController,
	ResonanceController,
	CameraController,
	UIController,
	InputController,
}

local context = {
	AudioController = AudioController,
	ResonanceController = ResonanceController,
	CameraController = CameraController,
	UIController = UIController,
	InputController = InputController,
}

for _, controller in ipairs(controllers) do
	controller:Init(context)
end

for _, controller in ipairs(controllers) do
	controller:Start()
end
