--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = Shared:WaitForChild("Util")
local InstanceUtil = require((Util:WaitForChild("InstanceUtil") :: ModuleScript))
local Maid = require((Util:WaitForChild("Maid") :: ModuleScript))
local NumberUtil = require((Util:WaitForChild("NumberUtil") :: ModuleScript))

local UIController = {}

local initialized = false
local started = false
local context: any = nil
local maid = Maid.new()
local screenGui: ScreenGui? = nil
local statusLabel: TextLabel? = nil
local modeReadout: TextLabel? = nil
local presetReadout: TextLabel? = nil
local rmsReadout: TextLabel? = nil
local peakReadout: TextLabel? = nil
local beatReadout: TextLabel? = nil
local sensitivityReadout: TextLabel? = nil
local intensityReadout: TextLabel? = nil
local panelStroke: UIStroke? = nil
local glowPulse = 0
local lastReadoutUpdate = 0

local function textConstraint(parent: Instance, minSize: number, maxSize: number)
	InstanceUtil.create("UITextSizeConstraint", {
		MinTextSize = minSize,
		MaxTextSize = maxSize,
	}, parent)
end

local function createLabel(parent: Instance, name: string, text: string, height: number, font: Enum.Font, color: Color3): TextLabel
	local label = InstanceUtil.create("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Font = font,
		Size = UDim2.new(1, 0, 0, height),
		Text = text,
		TextColor3 = color,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent) :: TextLabel
	textConstraint(label, 10, height)
	return label
end

local function createButton(parent: Instance, text: string, activated: () -> ()): TextButton
	local button = InstanceUtil.create("TextButton", {
		Name = string.gsub(text, "%s+", "") .. "Button",
		AutoButtonColor = true,
		BackgroundColor3 = Color3.fromRGB(15, 26, 46),
		Font = Enum.Font.GothamMedium,
		Size = UDim2.new(1, 0, 0, 34),
		Text = text,
		TextColor3 = Color3.fromRGB(230, 252, 255),
		TextScaled = true,
	}, parent) :: TextButton

	InstanceUtil.create("UICorner", {
		CornerRadius = UDim.new(0, 7),
	}, button)

	InstanceUtil.create("UIStroke", {
		Color = Color3.fromRGB(0, 242, 255),
		Thickness = 1,
		Transparency = 0.58,
	}, button)

	textConstraint(button, 9, 15)
	maid:Give(button.Activated:Connect(activated))
	return button
end

local function createRow(parent: Instance, name: string, columns: number): Frame
	local row = InstanceUtil.create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 34),
	}, parent) :: Frame

	InstanceUtil.create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(6, 0),
		CellSize = UDim2.new(1 / columns, -math.ceil(6 * (columns - 1) / columns), 1, 0),
		FillDirection = Enum.FillDirection.Horizontal,
		FillDirectionMaxCells = columns,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)

	return row
end

local function createReadout(parent: Instance, name: string, text: string): TextLabel
	return createLabel(parent, name, text, 24, Enum.Font.GothamMedium, Color3.fromRGB(195, 220, 235))
end

local function buildUi()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("PulseForgeGui")
	if existing ~= nil then
		existing:Destroy()
	end

	local gui = InstanceUtil.create("ScreenGui", {
		Name = "PulseForgeGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10,
	}, playerGui) :: ScreenGui
	screenGui = gui
	maid:Give(gui)

	local panel = InstanceUtil.create("Frame", {
		Name = "MainPanel",
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(6, 10, 22),
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.fromOffset(344, 0),
	}, gui) :: Frame

	InstanceUtil.create("UISizeConstraint", {
		MaxSize = Vector2.new(390, 900),
		MinSize = Vector2.new(280, 0),
	}, panel)

	InstanceUtil.create("UICorner", {
		CornerRadius = UDim.new(0, 8),
	}, panel)

	panelStroke = InstanceUtil.create("UIStroke", {
		Color = Color3.fromRGB(0, 242, 255),
		Thickness = 1,
		Transparency = 0.32,
	}, panel) :: UIStroke

	InstanceUtil.create("UIPadding", {
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 12),
	}, panel)

	InstanceUtil.create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, panel)

	createLabel(panel, "Title", "PulseForge", 34, Enum.Font.GothamBlack, Color3.fromRGB(230, 252, 255))
	statusLabel = createLabel(panel, "Status", "Demo mode active", 28, Enum.Font.GothamMedium, Color3.fromRGB(0, 242, 255))

	local modeRow = createRow(panel, "ModeRow", 3)
	createButton(modeRow, "Demo", function()
		context.AudioInputController:SetMode("Demo")
		UIController:SetStatus("Demo mode active")
		context.EffectsController:PlayToast("Demo mode active")
	end)
	createButton(modeRow, "Asset", function()
		UIController:SetStatus("Paste an asset ID, then Play Asset")
	end)
	createButton(modeRow, "Mic", function()
		context.AudioInputController:SetMode("Mic")
		UIController:SetStatus(context.AudioInputController:GetStatus())
		context.EffectsController:PlayToast(context.AudioInputController:GetStatus())
	end)

	local assetBox = InstanceUtil.create("TextBox", {
		Name = "AssetIdBox",
		BackgroundColor3 = Color3.fromRGB(9, 15, 29),
		ClearTextOnFocus = false,
		Font = Enum.Font.Gotham,
		PlaceholderText = "Audio asset ID",
		Size = UDim2.new(1, 0, 0, 34),
		Text = "",
		TextColor3 = Color3.fromRGB(230, 252, 255),
		TextScaled = true,
	}, panel) :: TextBox
	InstanceUtil.create("UICorner", {
		CornerRadius = UDim.new(0, 7),
	}, assetBox)
	InstanceUtil.create("UIStroke", {
		Color = Color3.fromRGB(75, 110, 145),
		Thickness = 1,
		Transparency = 0.25,
	}, assetBox)
	textConstraint(assetBox, 10, 15)

	local assetRow = createRow(panel, "AssetControls", 2)
	createButton(assetRow, "Play Asset", function()
		context.AudioInputController:PlayAsset(assetBox.Text)
		local nextStatus = context.AudioInputController:GetStatus()
		UIController:SetStatus(nextStatus)
		context.EffectsController:PlayToast(nextStatus)
	end)
	createButton(assetRow, "Stop", function()
		context.AudioInputController:Stop()
		UIController:SetStatus("Demo mode active")
		context.EffectsController:PlayToast("Demo mode active")
	end)

	createButton(panel, "Next Preset", function()
		context.VisualizerController:CyclePreset()
		local nextPreset = context.VisualizerController:GetPreset()
		local text = `Preset: {nextPreset}`
		UIController:SetStatus(text)
		context.EffectsController:PlayToast(text)
	end)

	local sensitivityRow = createRow(panel, "SensitivityRow", 2)
	createButton(sensitivityRow, "Sensitivity -", function()
		local audio = context.AudioInputController
		audio:SetSensitivity(audio:GetSensitivity() - 0.15)
	end)
	createButton(sensitivityRow, "Sensitivity +", function()
		local audio = context.AudioInputController
		audio:SetSensitivity(audio:GetSensitivity() + 0.15)
	end)

	local intensityRow = createRow(panel, "IntensityRow", 2)
	createButton(intensityRow, "Intensity -", function()
		local visualizer = context.VisualizerController
		visualizer:SetIntensity(visualizer:GetIntensity() - 0.15)
	end)
	createButton(intensityRow, "Intensity +", function()
		local visualizer = context.VisualizerController
		visualizer:SetIntensity(visualizer:GetIntensity() + 0.15)
	end)

	createButton(panel, "Drop Beat Orb", function()
		context.InputController:RequestBeatOrb()
	end)

	rmsReadout = createReadout(panel, "RmsReadout", "RMS 0.00")
	peakReadout = createReadout(panel, "PeakReadout", "Peak 0.00")
	beatReadout = createReadout(panel, "BeatReadout", "Beat no")
	presetReadout = createReadout(panel, "PresetReadout", "Preset: Bars")
	modeReadout = createReadout(panel, "ModeReadout", "Mode: Demo")
	sensitivityReadout = createReadout(panel, "SensitivityReadout", "Sensitivity: 1.00")
	intensityReadout = createReadout(panel, "IntensityReadout", "Intensity: 1.00")
end

local function setText(label: TextLabel?, text: string)
	if label ~= nil then
		label.Text = text
	end
end

local function updateReadouts()
	local audio = context.AudioInputController
	local visualizer = context.VisualizerController
	local frame = audio:GetFrame()

	setText(rmsReadout, string.format("RMS %.2f", frame.rms))
	setText(peakReadout, string.format("Peak %.2f", frame.peak))
	setText(beatReadout, `Beat {if frame.beat then "yes" else "no"}`)
	setText(presetReadout, `Preset: {visualizer:GetPreset()}`)
	setText(modeReadout, `Mode: {audio:GetMode()}`)
	setText(sensitivityReadout, string.format("Sensitivity: %.2f", audio:GetSensitivity()))
	setText(intensityReadout, string.format("Intensity: %.2f", visualizer:GetIntensity()))

	local label = statusLabel
	if label ~= nil then
		label.Text = audio:GetStatus()
	end
end

function UIController:Init(nextContext: any)
	if initialized then
		return
	end

	context = nextContext
	initialized = true
end

function UIController:Start()
	if started then
		return
	end

	started = true
	buildUi()

	local disconnect = context.AudioInputController:OnFrameChanged(function()
		local now = os.clock()
		if now - lastReadoutUpdate < 0.08 then
			return
		end

		lastReadoutUpdate = now
		updateReadouts()
	end)
	maid:Give(disconnect)

	maid:Give(game:GetService("RunService").Heartbeat:Connect(function(deltaTime: number)
		glowPulse = NumberUtil.expSmoothing(glowPulse, 0, deltaTime, 8)
		local stroke = panelStroke
		if stroke ~= nil then
			stroke.Thickness = 1 + glowPulse * 2
			stroke.Transparency = 0.36 - math.clamp(glowPulse * 0.24, 0, 0.24)
			stroke.Color = Color3.fromHSV((os.clock() * 0.08) % 1, 0.75, 1)
		end
	end))
end

function UIController:SetStatus(text: string)
	local label = statusLabel
	if label ~= nil then
		label.Text = text
	end
	context.AudioInputController:SetStatus(text)
end

function UIController:PulseGlow(strength: number)
	glowPulse = math.max(glowPulse, math.clamp(NumberUtil.sanitizeFiniteNumber(strength, 0), 0, 1))
end

function UIController:Destroy()
	maid:Cleanup()
	screenGui = nil
end

return UIController
