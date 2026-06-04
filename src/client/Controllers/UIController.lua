--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

local COLORS = {
	panel = Color3.fromRGB(16, 18, 19),
	panelSoft = Color3.fromRGB(26, 29, 30),
	line = Color3.fromRGB(92, 122, 122),
	text = Color3.fromRGB(211, 222, 220),
	muted = Color3.fromRGB(148, 164, 162),
	accent = Color3.fromRGB(115, 178, 180),
}

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
	textConstraint(label, 9, height)
	return label
end

local function createButton(parent: Instance, text: string, activated: () -> ()): TextButton
	local button = InstanceUtil.create("TextButton", {
		Name = string.gsub(text, "%s+", "") .. "Button",
		AutoButtonColor = true,
		BackgroundColor3 = COLORS.panelSoft,
		Font = Enum.Font.Gotham,
		Size = UDim2.new(1, 0, 0, 30),
		Text = text,
		TextColor3 = COLORS.text,
		TextScaled = true,
	}, parent) :: TextButton

	InstanceUtil.create("UICorner", {
		CornerRadius = UDim.new(0, 5),
	}, button)

	InstanceUtil.create("UIStroke", {
		Color = COLORS.line,
		Thickness = 1,
		Transparency = 0.55,
	}, button)

	textConstraint(button, 9, 13)
	maid:Give(button.Activated:Connect(activated))
	return button
end

local function createRow(parent: Instance, name: string, columns: number, height: number): Frame
	local row = InstanceUtil.create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height),
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
	return createLabel(parent, name, text, 21, Enum.Font.Gotham, COLORS.muted)
end

local function buildUi()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("ResonanceGui")
	if existing ~= nil then
		existing:Destroy()
	end

	local gui = InstanceUtil.create("ScreenGui", {
		Name = "ResonanceGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10,
	}, playerGui) :: ScreenGui
	screenGui = gui
	maid:Give(gui)

	local panel = InstanceUtil.create("Frame", {
		Name = "InstrumentPanel",
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = COLORS.panel,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(18, 18),
		Size = UDim2.fromOffset(318, 0),
	}, gui) :: Frame

	InstanceUtil.create("UISizeConstraint", {
		MaxSize = Vector2.new(360, 820),
		MinSize = Vector2.new(270, 0),
	}, panel)

	InstanceUtil.create("UICorner", {
		CornerRadius = UDim.new(0, 6),
	}, panel)

	panelStroke = InstanceUtil.create("UIStroke", {
		Color = COLORS.line,
		Thickness = 1,
		Transparency = 0.35,
	}, panel) :: UIStroke

	InstanceUtil.create("UIPadding", {
		PaddingBottom = UDim.new(0, 12),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
		PaddingTop = UDim.new(0, 12),
	}, panel)

	InstanceUtil.create("UIListLayout", {
		Padding = UDim.new(0, 7),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, panel)

	createLabel(panel, "Title", "Resonance Field", 26, Enum.Font.GothamMedium, COLORS.text)
	statusLabel = createLabel(panel, "Status", "Demo pulse active", 24, Enum.Font.Gotham, COLORS.accent)

	local modeRow = createRow(panel, "ModeRow", 3, 30)
	createButton(modeRow, "Demo", function()
		context.AudioInputController:SetMode("Demo")
		UIController:SetStatus("Demo pulse active")
		context.EffectsController:PlayToast("Demo pulse active")
	end)
	createButton(modeRow, "Asset", function()
		UIController:SetStatus("Enter an audio asset id")
		context.EffectsController:PlayToast("Enter an audio asset id")
	end)
	createButton(modeRow, "Mic", function()
		context.AudioInputController:SetMode("Mic")
		local text = context.AudioInputController:GetStatus()
		UIController:SetStatus(text)
		context.EffectsController:PlayToast(text)
	end)

	local assetBox = InstanceUtil.create("TextBox", {
		Name = "AssetIdBox",
		BackgroundColor3 = Color3.fromRGB(12, 14, 15),
		ClearTextOnFocus = false,
		Font = Enum.Font.Gotham,
		PlaceholderText = "audio asset id",
		Size = UDim2.new(1, 0, 0, 30),
		Text = "",
		TextColor3 = COLORS.text,
		TextScaled = true,
	}, panel) :: TextBox
	InstanceUtil.create("UICorner", {
		CornerRadius = UDim.new(0, 5),
	}, assetBox)
	InstanceUtil.create("UIStroke", {
		Color = COLORS.line,
		Thickness = 1,
		Transparency = 0.58,
	}, assetBox)
	textConstraint(assetBox, 9, 13)

	local assetRow = createRow(panel, "AssetControls", 2, 30)
	createButton(assetRow, "Analyze", function()
		context.AudioInputController:PlayAsset(assetBox.Text)
		local text = context.AudioInputController:GetStatus()
		UIController:SetStatus(text)
		context.EffectsController:PlayToast(text)
	end)
	createButton(assetRow, "Reset", function()
		context.AudioInputController:Stop()
		UIController:SetStatus("Demo pulse active")
		context.EffectsController:PlayToast("Demo pulse active")
	end)

	createButton(panel, "Preset", function()
		context.VisualizerController:CyclePreset()
		local text = `Preset: {context.VisualizerController:GetPreset()}`
		UIController:SetStatus(text)
		context.EffectsController:PlayToast(text)
	end)

	local sensitivityRow = createRow(panel, "SensitivityRow", 2, 30)
	createButton(sensitivityRow, "Sensitivity -", function()
		local audio = context.AudioInputController
		audio:SetSensitivity(audio:GetSensitivity() - 0.12)
	end)
	createButton(sensitivityRow, "Sensitivity +", function()
		local audio = context.AudioInputController
		audio:SetSensitivity(audio:GetSensitivity() + 0.12)
	end)

	local intensityRow = createRow(panel, "IntensityRow", 2, 30)
	createButton(intensityRow, "Intensity -", function()
		local visualizer = context.VisualizerController
		visualizer:SetIntensity(visualizer:GetIntensity() - 0.12)
	end)
	createButton(intensityRow, "Intensity +", function()
		local visualizer = context.VisualizerController
		visualizer:SetIntensity(visualizer:GetIntensity() + 0.12)
	end)

	createButton(panel, "Send Pulse", function()
		context.InputController:RequestFieldPulse()
	end)

	rmsReadout = createReadout(panel, "RmsReadout", "RMS 0.00")
	peakReadout = createReadout(panel, "PeakReadout", "Peak 0.00")
	beatReadout = createReadout(panel, "BeatReadout", "Pulse no")
	presetReadout = createReadout(panel, "PresetReadout", "Preset: Field")
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
	setText(beatReadout, `Pulse {if frame.beat then "yes" else "no"}`)
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
		if now - lastReadoutUpdate < 0.1 then
			return
		end

		lastReadoutUpdate = now
		updateReadouts()
	end)
	maid:Give(disconnect)

	maid:Give(RunService.Heartbeat:Connect(function(deltaTime: number)
		glowPulse = NumberUtil.expSmoothing(glowPulse, 0, deltaTime, 6)
		local stroke = panelStroke
		if stroke ~= nil then
			stroke.Thickness = 1 + glowPulse
			stroke.Transparency = 0.38 - math.clamp(glowPulse * 0.16, 0, 0.16)
			stroke.Color = Color3.fromRGB(92 + math.floor(glowPulse * 32), 122 + math.floor(glowPulse * 42), 122 + math.floor(glowPulse * 42))
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
