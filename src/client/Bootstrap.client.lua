--!strict

local ControllersFolder = script.Parent:WaitForChild("Controllers")

local AudioInputController = require((ControllersFolder:WaitForChild("AudioInputController") :: ModuleScript))
local VisualizerController = require((ControllersFolder:WaitForChild("VisualizerController") :: ModuleScript))
local UIController = require((ControllersFolder:WaitForChild("UIController") :: ModuleScript))
local InputController = require((ControllersFolder:WaitForChild("InputController") :: ModuleScript))
local EffectsController = require((ControllersFolder:WaitForChild("EffectsController") :: ModuleScript))

local controllers = {
	AudioInputController,
	VisualizerController,
	EffectsController,
	UIController,
	InputController,
}

local context = {
	AudioInputController = AudioInputController,
	VisualizerController = VisualizerController,
	EffectsController = EffectsController,
	UIController = UIController,
	InputController = InputController,
}

for _, controller in ipairs(controllers) do
	controller:Init(context)
end

for _, controller in ipairs(controllers) do
	controller:Start()
end
