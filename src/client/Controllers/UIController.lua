--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require((Shared:WaitForChild("Constants") :: ModuleScript))
local Network = Shared:WaitForChild("Network")
local RemoteNames = require((Network:WaitForChild("RemoteNames") :: ModuleScript))
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
local dock: Frame? = nil
local dockStroke: UIStroke? = nil
local statusLabel: TextLabel? = nil
local tuningLabel: TextLabel? = nil
local assetBox: TextBox? = nil
local marbleRemote: RemoteEvent? = nil
local lastMarbleRequest = 0
local lastReadoutUpdate = 0
local statusOverride = ""
local statusOverrideUntil = 0
local activeAudioButton = "PlayBase"
local glow = 0

local palette = Constants.PALETTE
local visualButtons: { [string]: TextButton } = {}
local audioButtons: { [string]: TextButton } = {}
local buttonStrokes: { [TextButton]: UIStroke } = {}
local selectedButtons: { [TextButton]: boolean } = {}
local focusedButtons: { [TextButton]: boolean } = {}
local hoveredButtons: { [TextButton]: boolean } = {}

local function textConstraint(parent: Instance, minSize: number, maxSize: number)
	InstanceUtil.create("UITextSizeConstraint", {
		MinTextSize = minSize,
		MaxTextSize = maxSize,
	}, parent)
end

local function buttonName(text: string): string
	local compact = string.gsub(text, "%W+", "")
	if compact == "" then
		return "Button"
	end

	return compact .. "Button"
end

local function setText(label: TextLabel?, text: string)
	if label ~= nil then
		label.Text = text
	end
end

local function getMarbleRemote(): RemoteEvent?
	if marbleRemote ~= nil and marbleRemote.Parent ~= nil then
		return marbleRemote
	end

	local remotesFolder = ReplicatedStorage:FindFirstChild(Constants.REMOTES_FOLDER_NAME)
	if remotesFolder == nil then
		remotesFolder = ReplicatedStorage:WaitForChild(Constants.REMOTES_FOLDER_NAME, 5)
	end
	if remotesFolder == nil then
		return nil
	end

	local remote = remotesFolder:FindFirstChild(RemoteNames.MarbleRequested)
	if remote == nil then
		remote = remotesFolder:WaitForChild(RemoteNames.MarbleRequested, 5)
	end
	if remote ~= nil and remote:IsA("RemoteEvent") then
		marbleRemote = remote
		return remote
	end

	return nil
end

local function updateButtonVisual(button: TextButton)
	local selected = selectedButtons[button] == true
	local focused = focusedButtons[button] == true
	local hovered = hoveredButtons[button] == true
	local stroke = buttonStrokes[button]

	if selected then
		button.BackgroundColor3 = palette.Cyan:Lerp(palette.Charcoal, 0.55)
		button.TextColor3 = palette.SoftWhite
	elseif hovered or focused then
		button.BackgroundColor3 = Color3.fromRGB(32, 36, 37)
		button.TextColor3 = palette.SoftWhite
	else
		button.BackgroundColor3 = Color3.fromRGB(22, 25, 26)
		button.TextColor3 = Color3.fromRGB(202, 211, 208)
	end

	if stroke ~= nil then
		stroke.Color = if selected or focused then palette.Cyan else Color3.fromRGB(86, 96, 96)
		stroke.Transparency = if selected then 0.18 elseif focused then 0.28 elseif hovered then 0.48 else 0.68
		stroke.Thickness = if selected or focused then 1.4 else 1
	end
end

local function setButtonSelected(button: TextButton?, selected: boolean)
	if button == nil then
		return
	end

	selectedButtons[button] = selected
	updateButtonVisual(button)
end

local function createLabel(parent: Instance, name: string, text: string, height: number, color: Color3, font: Enum.Font): TextLabel
	local label = InstanceUtil.create("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Font = font,
		Size = UDim2.new(1, 0, 0, height),
		Text = text,
		TextColor3 = color,
		TextScaled = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, parent) :: TextLabel
	textConstraint(label, 9, height)
	return label
end

local function createButton(parent: Instance, text: string, activated: () -> ()): TextButton
	local button = InstanceUtil.create("TextButton", {
		Name = buttonName(text),
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(22, 25, 26),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Selectable = true,
		Size = UDim2.new(1, 0, 0, 30),
		Text = text,
		TextColor3 = Color3.fromRGB(202, 211, 208),
		TextScaled = true,
	}, parent) :: TextButton

	InstanceUtil.create("UICorner", {
		CornerRadius = UDim.new(0, 5),
	}, button)

	local stroke = InstanceUtil.create("UIStroke", {
		Color = Color3.fromRGB(86, 96, 96),
		Thickness = 1,
		Transparency = 0.68,
	}, button) :: UIStroke
	buttonStrokes[button] = stroke

	textConstraint(button, 9, 13)
	maid:Give(button.Activated:Connect(activated))
	maid:Give(button.SelectionGained:Connect(function()
		focusedButtons[button] = true
		updateButtonVisual(button)
	end))
	maid:Give(button.SelectionLost:Connect(function()
		focusedButtons[button] = nil
		updateButtonVisual(button)
	end))
	maid:Give(button.MouseEnter:Connect(function()
		hoveredButtons[button] = true
		updateButtonVisual(button)
	end))
	maid:Give(button.MouseLeave:Connect(function()
		hoveredButtons[button] = nil
		updateButtonVisual(button)
	end))

	return button
end

local function createRow(parent: Instance, name: string, columns: number, height: number): Frame
	local row = InstanceUtil.create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, height),
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

local function showStatus(text: string, seconds: number?)
	statusOverride = text
	statusOverrideUntil = os.clock() + (seconds or 1.8)
	setText(statusLabel, text)
end

local function clearStatusOverride()
	statusOverride = ""
	statusOverrideUntil = 0
end

local function currentEnergy(): number
	local audio = context.AudioController
	local frame = audio:GetFrame()
	return math.clamp(math.max(frame.peak, frame.bass, frame.rms) * 1.05, 0, 1)
end

local function requestMarble()
	local now = os.clock()
	if now - lastMarbleRequest < Constants.MARBLE_COOLDOWN then
		showStatus("Marble limited")
		return
	end

	local remote = getMarbleRemote()
	if remote == nil then
		showStatus("Marble unavailable")
		return
	end

	lastMarbleRequest = now
	local energy = math.clamp(NumberUtil.sanitizeFiniteNumber(currentEnergy(), 0), 0, 1)
	local ok = pcall(function()
		remote:FireServer({
			energy = energy,
		})
	end)

	if ok then
		glow = math.max(glow, math.max(energy, 0.25))
		showStatus("Marble dropped")
	else
		showStatus("Marble request failed")
	end
end

local function updateSelections()
	local audio = context.AudioController
	local resonance = context.ResonanceController
	local audioMode = audio:GetMode()
	local visualStyle = resonance:GetStyle()

	for name, button in pairs(audioButtons) do
		local selected = false
		if audioMode == "Demo" then
			selected = name == "Demo"
		elseif audioMode == "Mic" then
			selected = name == "Mic"
		elseif audioMode == "Asset" then
			selected = name == activeAudioButton
		end
		setButtonSelected(button, selected)
	end

	for name, button in pairs(visualButtons) do
		setButtonSelected(button, name == visualStyle)
	end
end

local function updateReadouts()
	local audio = context.AudioController
	local resonance = context.ResonanceController
	local statusText = audio:GetStatus()

	if statusOverride ~= "" and os.clock() < statusOverrideUntil then
		statusText = statusOverride
	elseif statusOverride ~= "" then
		clearStatusOverride()
	end

	setText(statusLabel, statusText)
	if statusLabel ~= nil then
		local lower = string.lower(statusText)
		statusLabel.TextColor3 = if string.find(lower, "unavailable") or string.find(lower, "invalid") or string.find(lower, "limited")
			then palette.Amber
			else palette.Cyan
	end

	setText(
		tuningLabel,
		string.format(
			"%s  Sens %.2f  Int %.2f",
			resonance:GetStyle(),
			audio:GetSensitivity(),
			resonance:GetIntensity()
		)
	)
	updateSelections()
end

local function buildUi()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local existingArrayWave = playerGui:FindFirstChild("ArrayWaveGui")
	if existingArrayWave ~= nil then
		existingArrayWave:Destroy()
	end

	local gui = InstanceUtil.create("ScreenGui", {
		Name = "ArrayWaveGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10,
	}, playerGui) :: ScreenGui
	screenGui = gui
	maid:Give(gui)

	local viewportWidth = if workspace.CurrentCamera ~= nil then workspace.CurrentCamera.ViewportSize.X else 1280
	local dockWidth = if viewportWidth < 700 then 282 else 320
	local scale = if viewportWidth < 700 then 0.92 else 1
	dock = InstanceUtil.create("Frame", {
		Name = "ControlDock",
		AutomaticSize = Enum.AutomaticSize.Y,
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = Color3.fromRGB(12, 14, 15),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 14, 1, -14),
		Size = UDim2.fromOffset(dockWidth, 0),
	}, gui) :: Frame

	InstanceUtil.create("UICorner", {
		CornerRadius = UDim.new(0, 8),
	}, dock)

	dockStroke = InstanceUtil.create("UIStroke", {
		Color = palette.Cyan,
		Thickness = 1,
		Transparency = 0.58,
	}, dock) :: UIStroke

	InstanceUtil.create("UIScale", {
		Scale = scale,
	}, dock)

	InstanceUtil.create("UIPadding", {
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 10),
	}, dock)

	InstanceUtil.create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, dock)

	createLabel(dock, "Title", "ArrayWave", 18, palette.SoftWhite, Enum.Font.GothamMedium)
	statusLabel = createLabel(dock, "Status", "Base song: " .. Constants.DEFAULT_AUDIO_ASSET_ID, 16, palette.Cyan, Enum.Font.Gotham)

	local baseRow = createRow(dock, "BaseRow", 3, 30)
	audioButtons.PlayBase = createButton(baseRow, "Play Base", function()
		activeAudioButton = "PlayBase"
		context.AudioController:PlayBaseSong()
		clearStatusOverride()
		updateReadouts()
	end)
	audioButtons.Demo = createButton(baseRow, "Demo", function()
		activeAudioButton = "Demo"
		context.AudioController:SetMode("Demo")
		clearStatusOverride()
		updateReadouts()
	end)
	audioButtons.Mic = createButton(baseRow, "Mic", function()
		activeAudioButton = "Mic"
		context.AudioController:SetMode("Mic")
		clearStatusOverride()
		updateReadouts()
	end)

	assetBox = InstanceUtil.create("TextBox", {
		Name = "AssetIdBox",
		BackgroundColor3 = Color3.fromRGB(18, 21, 22),
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Enum.Font.Gotham,
		PlaceholderText = "audio asset id",
		Selectable = true,
		Size = UDim2.new(1, 0, 0, 30),
		Text = Constants.DEFAULT_AUDIO_ASSET_ID,
		TextColor3 = palette.SoftWhite,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, dock) :: TextBox
	textConstraint(assetBox, 10, 14)
	InstanceUtil.create("UICorner", {
		CornerRadius = UDim.new(0, 5),
	}, assetBox)
	InstanceUtil.create("UIStroke", {
		Color = Color3.fromRGB(86, 96, 96),
		Thickness = 1,
		Transparency = 0.64,
	}, assetBox)
	InstanceUtil.create("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
	}, assetBox)

	local assetRow = createRow(dock, "AssetRow", 2, 30)
	audioButtons.PlayAsset = createButton(assetRow, "Play Asset", function()
		activeAudioButton = "PlayAsset"
		local box = assetBox
		context.AudioController:PlayAsset(if box ~= nil then box.Text else "")
		clearStatusOverride()
		updateReadouts()
	end)
	createButton(assetRow, "Stop", function()
		activeAudioButton = "Demo"
		context.AudioController:Stop()
		clearStatusOverride()
		updateReadouts()
	end)

	local visualRowA = createRow(dock, "VisualizerRowA", 3, 30)
	for _, styleName in ipairs({ "Grid", "Row", "Circle" }) do
		local capturedStyle = styleName
		visualButtons[capturedStyle] = createButton(visualRowA, capturedStyle, function()
			context.ResonanceController:SetStyle(capturedStyle)
			updateReadouts()
		end)
	end

	local visualRowB = createRow(dock, "VisualizerRowB", 2, 30)
	for _, styleName in ipairs({ "All", "Minimal" }) do
		local capturedStyle = styleName
		visualButtons[capturedStyle] = createButton(visualRowB, capturedStyle, function()
			context.ResonanceController:SetStyle(capturedStyle)
			updateReadouts()
		end)
	end

	local tuneRowA = createRow(dock, "TuneRowA", 2, 30)
	createButton(tuneRowA, "Sens -", function()
		local audio = context.AudioController
		audio:SetSensitivity(audio:GetSensitivity() - 0.12)
		updateReadouts()
	end)
	createButton(tuneRowA, "Sens +", function()
		local audio = context.AudioController
		audio:SetSensitivity(audio:GetSensitivity() + 0.12)
		updateReadouts()
	end)

	local tuneRowB = createRow(dock, "TuneRowB", 2, 30)
	createButton(tuneRowB, "Int -", function()
		local resonance = context.ResonanceController
		resonance:SetIntensity(resonance:GetIntensity() - 0.12)
		updateReadouts()
	end)
	createButton(tuneRowB, "Int +", function()
		local resonance = context.ResonanceController
		resonance:SetIntensity(resonance:GetIntensity() + 0.12)
		updateReadouts()
	end)

	local actionColumns = if getMarbleRemote() ~= nil then 2 else 1
	local actionRow = createRow(dock, "ActionRow", actionColumns, 30)
	createButton(actionRow, "Pulse Test", function()
		context.ResonanceController:TriggerPulse(0.85)
		glow = math.max(glow, 0.6)
		showStatus("Pulse test")
	end)
	if actionColumns == 2 then
		createButton(actionRow, "Drop Marble", requestMarble)
	end

	tuningLabel = createLabel(dock, "Tuning", "Grid  Sens 1.00  Int 1.00", 15, Color3.fromRGB(158, 170, 168), Enum.Font.Gotham)
	updateReadouts()
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
		local stroke = dockStroke
		if stroke ~= nil then
			stroke.Transparency = 0.58 - math.clamp(glow * 0.2, 0, 0.2)
		end
	end))
end

function UIController:SetStatus(text: string)
	showStatus(text)
end

function UIController:PlayAsset()
	activeAudioButton = "PlayAsset"
	local box = assetBox
	context.AudioController:PlayAsset(if box ~= nil then box.Text else "")
	clearStatusOverride()
	updateReadouts()
end

function UIController:PulseGlow(strength: number)
	glow = math.max(glow, math.clamp(NumberUtil.sanitizeFiniteNumber(strength, 0), 0, 1))
end

function UIController:Destroy()
	maid:Cleanup()
	screenGui = nil
	dock = nil
	statusLabel = nil
	tuningLabel = nil
	assetBox = nil
end

return UIController
