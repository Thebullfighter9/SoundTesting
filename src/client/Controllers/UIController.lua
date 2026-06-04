--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require((Shared:WaitForChild("Constants") :: ModuleScript))
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
local panel: Frame? = nil
local statusLabel: TextLabel? = nil
local modeReadout: TextLabel? = nil
local rmsReadout: TextLabel? = nil
local peakReadout: TextLabel? = nil
local beatReadout: TextLabel? = nil
local styleReadout: TextLabel? = nil
local assetBox: TextBox? = nil
local panelStroke: UIStroke? = nil
local hidden = false
local glow = 0
local lastReadoutUpdate = 0
local palette = Constants.PALETTE

local function textConstraint(parent: Instance, minSize: number, maxSize: number)
	InstanceUtil.create("UITextSizeConstraint", {
		MinTextSize = minSize,
		MaxTextSize = maxSize,
	}, parent)
end

local function createLabel(parent: Instance, name: string, text: string, height: number, color: Color3): TextLabel
	local label = InstanceUtil.create("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Size = UDim2.new(1, 0, 0, height),
		Text = text,
		TextColor3 = color,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent) :: TextLabel
	textConstraint(label, 8, height)
	return label
end

local function createButton(parent: Instance, text: string, activated: () -> ()): TextButton
	local button = InstanceUtil.create("TextButton", {
		Name = string.gsub(text, "%s+", "") .. "Button",
		AutoButtonColor = true,
		BackgroundColor3 = Color3.fromRGB(24, 27, 28),
		Font = Enum.Font.Gotham,
		Size = UDim2.new(1, 0, 0, 24),
		Text = text,
		TextColor3 = palette.SoftWhite,
		TextScaled = true,
	}, parent) :: TextButton

	InstanceUtil.create("UICorner", {
		CornerRadius = UDim.new(0, 4),
	}, button)

	InstanceUtil.create("UIStroke", {
		Color = palette.Cyan,
		Thickness = 1,
		Transparency = 0.72,
	}, button)

	textConstraint(button, 8, 12)
	maid:Give(button.Activated:Connect(activated))
	return button
end

local function createRow(parent: Instance, name: string, columns: number): Frame
	local row = InstanceUtil.create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 24),
	}, parent) :: Frame

	InstanceUtil.create("UIGridLayout", {
		CellPadding = UDim2.fromOffset(5, 0),
		CellSize = UDim2.new(1 / columns, -math.ceil(5 * (columns - 1) / columns), 1, 0),
		FillDirection = Enum.FillDirection.Horizontal,
		FillDirectionMaxCells = columns,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)

	return row
end

local function setText(label: TextLabel?, text: string)
	if label ~= nil then
		label.Text = text
	end
end

local function updateReadouts()
	local audio = context.AudioController
	local resonance = context.ResonanceController
	local frame = audio:GetFrame()

	setText(modeReadout, `Mode {audio:GetMode()}`)
	setText(rmsReadout, string.format("RMS %.2f", frame.rms))
	setText(peakReadout, string.format("Peak %.2f", frame.peak))
	setText(beatReadout, `Beat {if frame.beat then "yes" else "no"}`)
	setText(styleReadout, `Style {resonance:GetStyle()}`)
	setText(statusLabel, audio:GetStatus())
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

	local viewportWidth = if workspace.CurrentCamera ~= nil then workspace.CurrentCamera.ViewportSize.X else 1280
	local panelWidth = if viewportWidth < 700
		then 230
		else math.min(Constants.UI_PANEL_WIDTH, math.floor(viewportWidth * math.min(Constants.UI_PANEL_MAX_WIDTH_SCALE, 0.18)))
	panel = InstanceUtil.create("Frame", {
		Name = "ControlPanel",
		AutomaticSize = Enum.AutomaticSize.Y,
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = Color3.fromRGB(12, 14, 15),
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 14, 1, -14),
		Size = UDim2.fromOffset(panelWidth, 0),
	}, gui) :: Frame

	InstanceUtil.create("UICorner", {
		CornerRadius = UDim.new(0, 6),
	}, panel)

	panelStroke = InstanceUtil.create("UIStroke", {
		Color = palette.Cyan,
		Thickness = 1,
		Transparency = 0.62,
	}, panel) :: UIStroke

	InstanceUtil.create("UIPadding", {
		PaddingBottom = UDim.new(0, 9),
		PaddingLeft = UDim.new(0, 9),
		PaddingRight = UDim.new(0, 9),
		PaddingTop = UDim.new(0, 9),
	}, panel)

	InstanceUtil.create("UIListLayout", {
		Padding = UDim.new(0, 5),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, panel)

	createLabel(panel, "Title", "Resonance Field", 20, palette.SoftWhite)
	statusLabel = createLabel(panel, "Status", "Demo signal active", 18, palette.Cyan)

	local modeRow = createRow(panel, "ModeRow", 3)
	createButton(modeRow, "Demo", function()
		context.AudioController:SetMode("Demo")
		UIController:SetStatus("Demo signal active")
	end)
	createButton(modeRow, "Asset", function()
		context.AudioController:SetMode("Asset")
		UIController:SetStatus(context.AudioController:GetStatus())
	end)
	createButton(modeRow, "Mic", function()
		context.AudioController:SetMode("Mic")
		UIController:SetStatus(context.AudioController:GetStatus())
	end)

	assetBox = InstanceUtil.create("TextBox", {
		Name = "AssetIdBox",
		BackgroundColor3 = Color3.fromRGB(18, 20, 21),
		ClearTextOnFocus = false,
		Font = Enum.Font.Gotham,
		PlaceholderText = "audio asset id",
		Size = UDim2.new(1, 0, 0, 24),
		Text = "",
		TextColor3 = palette.SoftWhite,
		TextScaled = true,
	}, panel) :: TextBox
	textConstraint(assetBox, 8, 12)
	InstanceUtil.create("UICorner", {
		CornerRadius = UDim.new(0, 4),
	}, assetBox)

	local assetRow = createRow(panel, "AssetRow", 2)
	createButton(assetRow, "Play", function()
		UIController:PlayAsset()
	end)
	createButton(assetRow, "Stop", function()
		context.AudioController:Stop()
		UIController:SetStatus("Demo signal active")
	end)

	local styleRow = createRow(panel, "StyleRow", 2)
	createButton(styleRow, "Style", function()
		context.ResonanceController:CycleStyle()
		UIController:SetStatus(`Style {context.ResonanceController:GetStyle()}`)
	end)
	createButton(styleRow, "Marble", function()
		context.InputController:RequestMarble()
	end)

	local sensitivityRow = createRow(panel, "SensitivityRow", 2)
	createButton(sensitivityRow, "Sens -", function()
		local audio = context.AudioController
		audio:SetSensitivity(audio:GetSensitivity() - 0.12)
	end)
	createButton(sensitivityRow, "Sens +", function()
		local audio = context.AudioController
		audio:SetSensitivity(audio:GetSensitivity() + 0.12)
	end)

	local intensityRow = createRow(panel, "IntensityRow", 2)
	createButton(intensityRow, "Int -", function()
		local resonance = context.ResonanceController
		resonance:SetIntensity(resonance:GetIntensity() - 0.12)
	end)
	createButton(intensityRow, "Int +", function()
		local resonance = context.ResonanceController
		resonance:SetIntensity(resonance:GetIntensity() + 0.12)
	end)

	modeReadout = createLabel(panel, "ModeReadout", "Mode Demo", 15, Color3.fromRGB(158, 170, 168))
	rmsReadout = createLabel(panel, "RmsReadout", "RMS 0.00", 15, Color3.fromRGB(158, 170, 168))
	peakReadout = createLabel(panel, "PeakReadout", "Peak 0.00", 15, Color3.fromRGB(158, 170, 168))
	beatReadout = createLabel(panel, "BeatReadout", "Beat no", 15, Color3.fromRGB(158, 170, 168))
	styleReadout = createLabel(panel, "StyleReadout", "Style Field", 15, Color3.fromRGB(158, 170, 168))
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

	local disconnect = context.AudioController:OnFrameChanged(function()
		local now = os.clock()
		if now - lastReadoutUpdate < 0.12 then
			return
		end

		lastReadoutUpdate = now
		updateReadouts()
	end)
	maid:Give(disconnect)

	maid:Give(RunService.Heartbeat:Connect(function(deltaTime: number)
		glow = NumberUtil.expSmooth(glow, 0, deltaTime, 6)
		local stroke = panelStroke
		if stroke ~= nil then
			stroke.Transparency = 0.64 - math.clamp(glow * 0.18, 0, 0.18)
		end
	end))
end

function UIController:SetStatus(text: string)
	setText(statusLabel, text)
	context.AudioController:SetStatus(text)
end

function UIController:PlayAsset()
	local box = assetBox
	context.AudioController:PlayAsset(if box ~= nil then box.Text else "")
	UIController:SetStatus(context.AudioController:GetStatus())
end

function UIController:FocusAssetBox()
	local box = assetBox
	if box ~= nil then
		box:CaptureFocus()
	end
end

function UIController:ToggleVisible()
	hidden = not hidden
	local gui = screenGui
	if gui ~= nil then
		gui.Enabled = not hidden
	end
end

function UIController:PulseGlow(strength: number)
	glow = math.max(glow, math.clamp(NumberUtil.sanitizeFiniteNumber(strength, 0), 0, 1))
end

function UIController:Destroy()
	maid:Cleanup()
	screenGui = nil
	panel = nil
end

return UIController
