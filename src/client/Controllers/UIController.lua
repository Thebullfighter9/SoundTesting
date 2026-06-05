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
local sourceLabel: TextLabel? = nil
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
local analyzerBars: { Frame } = {}
local visualButtons: { [string]: TextButton } = {}
local audioButtons: { [string]: TextButton } = {}
local buttonStrokes: { [TextButton]: UIStroke } = {}
local selectedButtons: { [TextButton]: boolean } = {}
local focusedButtons: { [TextButton]: boolean } = {}
local hoveredButtons: { [TextButton]: boolean } = {}
local dropMarbleButton: TextButton? = nil

local function expectChild(parent: Instance, name: string, className: string): Instance
	local child = parent:WaitForChild(name, 8)
	assert(child ~= nil, `ArrayWaveGui missing {name}`)
	assert(child.ClassName == className, `ArrayWaveGui {name} must be {className}`)
	return child
end

local function getStroke(button: TextButton): UIStroke?
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke ~= nil then
		return stroke
	end

	return nil
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
		button.BackgroundColor3 = palette.Cyan:Lerp(palette.SurfaceRaised, 0.54)
		button.BackgroundTransparency = 0.08
		button.TextColor3 = palette.Text
	elseif focused or hovered then
		button.BackgroundColor3 = palette.SurfaceRaised:Lerp(palette.Cyan, 0.08)
		button.BackgroundTransparency = 0.04
		button.TextColor3 = palette.Text
	else
		button.BackgroundColor3 = palette.SurfaceRaised
		button.BackgroundTransparency = 0.16
		button.TextColor3 = palette.TextMuted:Lerp(palette.Text, 0.38)
	end

	if stroke ~= nil then
		stroke.Color = if selected or focused then palette.Cyan else palette.Stroke
		stroke.Transparency = if selected then 0.14 elseif focused then 0.22 elseif hovered then 0.42 else 0.66
		stroke.Thickness = if selected or focused then 1.3 else 1
	end
end

local function setButtonSelected(button: TextButton?, selected: boolean)
	if button == nil then
		return
	end

	selectedButtons[button] = selected
	updateButtonVisual(button)
end

local function bindButton(button: TextButton, activated: () -> ())
	buttonStrokes[button] = getStroke(button)
	updateButtonVisual(button)

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
	return math.clamp(math.max(frame.peak, frame.bass, frame.rms, frame.beatStrength), 0, 1)
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

local function sourceText(): string
	local audio = context.AudioController
	local mode = audio:GetMode()
	if mode == "Asset" then
		if activeAudioButton == "PlayBase" then
			return `Source: {Constants.DEFAULT_AUDIO_LABEL}`
		end
		return "Source: Asset"
	elseif mode == "Mic" then
		return "Source: Mic"
	end
	return "Source: Demo"
end

local function updateAnalyzerBars()
	local audio = context.AudioController
	local frame = audio:GetFrame()
	local bands = frame.bands
	local bandTotal = math.max(1, #bands)
	local barTotal = math.max(1, #analyzerBars)

	for barIndex, bar in ipairs(analyzerBars) do
		local startIndex = math.floor((barIndex - 1) / barTotal * bandTotal) + 1
		local endIndex = math.max(startIndex, math.floor(barIndex / barTotal * bandTotal))
		local total = 0
		local samples = 0
		for bandIndex = startIndex, endIndex do
			total += math.clamp(NumberUtil.sanitizeFiniteNumber(bands[bandIndex], 0), 0, 1)
			samples += 1
		end
		local value = if samples > 0 then total / samples else 0
		local heightScale = math.clamp(0.08 + value * 0.92, 0.08, 1)
		bar.Size = UDim2.new(1, 0, heightScale, 0)
		bar.BackgroundTransparency = math.clamp(0.28 - value * 0.16 + frame.air * 0.04, 0.1, 0.42)
		bar.BackgroundColor3 = palette.Cyan:Lerp(palette.CyanSoft, math.clamp(frame.centroid * 0.45 + value * 0.22, 0, 0.62))
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
	local frame = audio:GetFrame()
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
			else palette.CyanSoft
	end

	setText(sourceLabel, sourceText())
	setText(
		tuningLabel,
		string.format(
			"%s  Sens %.2f  Int %.2f  Beat %.2f",
			resonance:GetStyle(),
			audio:GetSensitivity(),
			resonance:GetIntensity(),
			frame.beatStrength
		)
	)
	updateAnalyzerBars()
	updateSelections()
end

local function collectAnalyzerBars(analyzerFrame: Frame)
	table.clear(analyzerBars)

	for index = 1, Constants.UI_ANALYZER_BAR_COUNT do
		local holder = expectChild(analyzerFrame, `Band_{index}`, "Frame") :: Frame
		local fill = expectChild(holder, "Fill", "Frame") :: Frame
		table.insert(analyzerBars, fill)
	end
end

local function findButton(parent: Instance, name: string): TextButton
	return expectChild(parent, name, "TextButton") :: TextButton
end

local function bindStaticUi()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local gui = expectChild(playerGui, "ArrayWaveGui", "ScreenGui") :: ScreenGui
	local dockFrame = expectChild(gui, "ControlDock", "Frame") :: Frame

	screenGui = gui
	dock = dockFrame
	dockStroke = dockFrame:FindFirstChildOfClass("UIStroke")
	statusLabel = expectChild(dockFrame, "Status", "TextLabel") :: TextLabel
	sourceLabel = expectChild(dockFrame, "Source", "TextLabel") :: TextLabel
	tuningLabel = expectChild(dockFrame, "Tuning", "TextLabel") :: TextLabel
	assetBox = expectChild(dockFrame, "AssetIdBox", "TextBox") :: TextBox

	gui.Enabled = true
	gui.ResetOnSpawn = false
	assetBox.Text = Constants.DEFAULT_AUDIO_ASSET_ID

	local analyzerFrame = expectChild(dockFrame, "AnalyzerStrip", "Frame") :: Frame
	collectAnalyzerBars(analyzerFrame)

	local baseRow = expectChild(dockFrame, "BaseRow", "Frame")
	audioButtons.PlayBase = findButton(baseRow, "PlayBaseButton")
	audioButtons.Demo = findButton(baseRow, "DemoButton")
	audioButtons.Mic = findButton(baseRow, "MicButton")

	local assetRow = expectChild(dockFrame, "AssetRow", "Frame")
	audioButtons.PlayAsset = findButton(assetRow, "PlayAssetButton")
	local stopButton = findButton(assetRow, "StopButton")

	local visualRowA = expectChild(dockFrame, "VisualizerRowA", "Frame")
	visualButtons.Grid = findButton(visualRowA, "GridButton")
	visualButtons.Row = findButton(visualRowA, "RowButton")
	visualButtons.Circle = findButton(visualRowA, "CircleButton")

	local visualRowB = expectChild(dockFrame, "VisualizerRowB", "Frame")
	visualButtons.All = findButton(visualRowB, "AllButton")
	visualButtons.Minimal = findButton(visualRowB, "MinimalButton")

	local tuneRowA = expectChild(dockFrame, "TuneRowA", "Frame")
	local sensMinus = findButton(tuneRowA, "SensMinusButton")
	local sensPlus = findButton(tuneRowA, "SensPlusButton")

	local tuneRowB = expectChild(dockFrame, "TuneRowB", "Frame")
	local intMinus = findButton(tuneRowB, "IntMinusButton")
	local intPlus = findButton(tuneRowB, "IntPlusButton")

	local actionRow = expectChild(dockFrame, "ActionRow", "Frame")
	local pulseTest = findButton(actionRow, "PulseTestButton")
	local resetView = findButton(actionRow, "ResetViewButton")
	dropMarbleButton = findButton(actionRow, "DropMarbleButton")
	dropMarbleButton.Visible = getMarbleRemote() ~= nil

	bindButton(audioButtons.PlayBase, function()
		activeAudioButton = "PlayBase"
		context.AudioController:PlayBaseSong()
		clearStatusOverride()
		updateReadouts()
	end)
	bindButton(audioButtons.Demo, function()
		activeAudioButton = "Demo"
		context.AudioController:SetMode("Demo")
		clearStatusOverride()
		updateReadouts()
	end)
	bindButton(audioButtons.Mic, function()
		activeAudioButton = "Mic"
		context.AudioController:SetMode("Mic")
		clearStatusOverride()
		updateReadouts()
	end)
	bindButton(audioButtons.PlayAsset, function()
		activeAudioButton = "PlayAsset"
		local box = assetBox
		context.AudioController:PlayAsset(if box ~= nil then box.Text else "")
		clearStatusOverride()
		updateReadouts()
	end)
	bindButton(stopButton, function()
		activeAudioButton = "Demo"
		context.AudioController:Stop()
		clearStatusOverride()
		updateReadouts()
	end)

	for styleName, button in pairs(visualButtons) do
		local capturedStyle = styleName
		bindButton(button, function()
			context.ResonanceController:SetStyle(capturedStyle)
			updateReadouts()
		end)
	end

	bindButton(sensMinus, function()
		local audio = context.AudioController
		audio:SetSensitivity(audio:GetSensitivity() - 0.12)
		updateReadouts()
	end)
	bindButton(sensPlus, function()
		local audio = context.AudioController
		audio:SetSensitivity(audio:GetSensitivity() + 0.12)
		updateReadouts()
	end)
	bindButton(intMinus, function()
		local resonance = context.ResonanceController
		resonance:SetIntensity(resonance:GetIntensity() - 0.12)
		updateReadouts()
	end)
	bindButton(intPlus, function()
		local resonance = context.ResonanceController
		resonance:SetIntensity(resonance:GetIntensity() + 0.12)
		updateReadouts()
	end)
	bindButton(pulseTest, function()
		context.ResonanceController:TriggerPulse(1)
		glow = math.max(glow, 0.72)
		showStatus("Pulse test")
	end)
	bindButton(resetView, function()
		context.CameraController:Reset()
		showStatus("View reset")
	end)
	if dropMarbleButton ~= nil then
		bindButton(dropMarbleButton, requestMarble)
	end

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
	bindStaticUi()

	local disconnect = context.AudioController:OnFrameChanged(function()
		local now = os.clock()
		if now - lastReadoutUpdate < 0.055 then
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
			stroke.Transparency = 0.54 - math.clamp(glow * 0.2, 0, 0.2)
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
	sourceLabel = nil
	tuningLabel = nil
	assetBox = nil
	dropMarbleButton = nil
end

return UIController
