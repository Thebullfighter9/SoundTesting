--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require((Shared:WaitForChild("Constants") :: ModuleScript))
local Types = require((Shared:WaitForChild("Types") :: ModuleScript))
local Network = Shared:WaitForChild("Network")
local RemoteNames = require((Network:WaitForChild("RemoteNames") :: ModuleScript))
local Util = Shared:WaitForChild("Util")
local Maid = require((Util:WaitForChild("Maid") :: ModuleScript))
local NumberUtil = require((Util:WaitForChild("NumberUtil") :: ModuleScript))

type CameraMode = Types.CameraMode
type VisualStyle = Types.VisualStyle

local UIController = {}

local initialized = false
local started = false
local context: any = nil
local maid = Maid.new()
local screenGui: ScreenGui? = nil
local nowPlayingPill: Frame? = nil
local bottomDock: Frame? = nil
local collapsedControls: Frame? = nil
local tuneDrawer: Frame? = nil
local tuneButton: TextButton? = nil
local currentModeButton: TextButton? = nil
local compactCameraButton: TextButton? = nil
local pillStroke: UIStroke? = nil
local dockStroke: UIStroke? = nil
local songIdStroke: UIStroke? = nil
local statusLabel: TextLabel? = nil
local songIdBox: TextBox? = nil
local sensValueLabel: TextLabel? = nil
local motionValueLabel: TextLabel? = nil
local sprayValueLabel: TextLabel? = nil
local marbleRemote: RemoteEvent? = nil
local dropMarbleButton: TextButton? = nil
local lastMarbleRequest = 0
local lastReadoutUpdate = 0
local statusOverride = ""
local statusOverrideUntil = 0
local activeAudioButton = "PlayBase"
local glow = 0
local songHighlight = 1
local songHighlightUntil = 0
local songIdFocused = false
local isTuneOpen = Constants.UI_TUNE_DEFAULT_OPEN

local palette = Constants.PALETTE
local analyzerBars: { Frame } = {}
local visualButtons: { [string]: TextButton } = {}
local audioButtons: { [string]: TextButton } = {}
local cameraButtons: { [string]: TextButton } = {}
local buttonStrokes: { [TextButton]: UIStroke } = {}
local selectedButtons: { [TextButton]: boolean } = {}
local focusedButtons: { [TextButton]: boolean } = {}
local hoveredButtons: { [TextButton]: boolean } = {}

local CAMERA_MODES: { CameraMode } = { "Auto", "Still", "Wide", "Close" }

local function expectChild(parent: Instance, name: string, className: string): Instance
	local child = parent:WaitForChild(name, 8)
	assert(child ~= nil, `ArrayWaveGui missing {name}`)
	assert(child.ClassName == className, `ArrayWaveGui {name} must be {className}`)
	return child
end

local function findButton(parent: Instance, name: string): TextButton
	return expectChild(parent, name, "TextButton") :: TextButton
end

local function setText(label: any, text: string)
	if label ~= nil then
		label.Text = text
	end
end

local function getStroke(button: TextButton): UIStroke?
	return button:FindFirstChildOfClass("UIStroke")
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
		button.BackgroundColor3 = palette.Cyan:Lerp(palette.SurfaceRaised, 0.58)
		button.BackgroundTransparency = 0.06
		button.TextColor3 = palette.Text
	elseif focused or hovered then
		button.BackgroundColor3 = palette.SurfaceRaised:Lerp(palette.Cyan, 0.08)
		button.BackgroundTransparency = 0.08
		button.TextColor3 = palette.Text
	else
		button.BackgroundColor3 = palette.SurfaceRaised
		button.BackgroundTransparency = 0.18
		button.TextColor3 = palette.TextMuted:Lerp(palette.Text, 0.38)
	end

	if stroke ~= nil then
		stroke.Color = if selected or focused then palette.Cyan else palette.Stroke
		stroke.Transparency = if selected then 0.12 elseif focused then 0.22 elseif hovered then 0.44 else 0.7
		stroke.Thickness = if selected or focused then 1.25 else 1
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

local function selectSongText()
	local box = songIdBox
	if box == nil then
		return
	end

	pcall(function()
		box.SelectionStart = 1
		box.CursorPosition = #box.Text + 1
	end)
end

local function currentEnergy(): number
	local audio = context.AudioController
	local frame = audio:GetFrame()
	return math.clamp(math.max(frame.peak, frame.bass, frame.rms, frame.beatStrength, frame.visualEnergy), 0, 1)
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
		showStatus("Marble")
	else
		showStatus("Marble failed")
	end
end

local function playAssetFromBox()
	activeAudioButton = "PlayAsset"
	local box = songIdBox
	context.AudioController:PlayAsset(if box ~= nil then box.Text else "")
	clearStatusOverride()
end

local function setTuneOpen(open: boolean)
	isTuneOpen = open
	local dock = bottomDock
	local drawer = tuneDrawer
	if dock == nil or drawer == nil then
		return
	end

	if open then
		drawer.Visible = true
	end

	local targetHeight = if open then Constants.UI_TUNE_DOCK_HEIGHT else Constants.UI_COLLAPSED_DOCK_HEIGHT
	local targetSize = UDim2.new(dock.Size.X.Scale, dock.Size.X.Offset, 0, targetHeight)
	TweenService:Create(dock, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = targetSize,
	}):Play()

	if not open then
		task.delay(0.19, function()
			if not isTuneOpen and drawer.Parent ~= nil then
				drawer.Visible = false
			end
		end)
	end

	local button = tuneButton
	if button ~= nil then
		button.Text = if open then "Hide" else "Tune"
		setButtonSelected(button, open)
	end
end

local function toggleTune()
	setTuneOpen(not isTuneOpen)
end

local function updateAnalyzerBars()
	local drawer = tuneDrawer
	if drawer ~= nil and not drawer.Visible then
		return
	end

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
		local heightScale = math.clamp(0.1 + value * 0.9, 0.1, 1)
		bar.Size = UDim2.new(1, 0, heightScale, 0)
		bar.BackgroundTransparency = math.clamp(0.42 - value * 0.18, 0.12, 0.5)
		bar.BackgroundColor3 = palette.Cyan:Lerp(palette.CyanSoft, math.clamp(frame.centroid * 0.45 + value * 0.2, 0, 0.62))
	end
end

local function cycleVisualStyle()
	local resonance = context.ResonanceController
	local currentStyle = resonance:GetStyle()
	local styles = Constants.VISUAL_STYLES :: { string }
	local nextIndex = 1
	for index, styleName in ipairs(styles) do
		if styleName == currentStyle then
			nextIndex = if index >= #styles then 1 else index + 1
			break
		end
	end

	resonance:SetStyle(styles[nextIndex] :: VisualStyle)
end

local function cycleCameraMode()
	local camera = context.CameraController
	local currentMode = camera:GetMode()
	local nextIndex = 1
	for index, cameraMode in ipairs(CAMERA_MODES) do
		if cameraMode == currentMode then
			nextIndex = if index >= #CAMERA_MODES then 1 else index + 1
			break
		end
	end

	camera:SetMode(CAMERA_MODES[nextIndex])
end

local function updateCameraMode(nextMode: CameraMode)
	context.CameraController:SetMode(nextMode)
end

local function updateSelections()
	local audio = context.AudioController
	local resonance = context.ResonanceController
	local camera = context.CameraController
	local audioMode = audio:GetMode()
	local visualStyle = resonance:GetStyle()
	local cameraMode = camera:GetMode()

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

	for name, button in pairs(cameraButtons) do
		setButtonSelected(button, name == cameraMode)
	end

	setButtonSelected(tuneButton, isTuneOpen)
	setText(currentModeButton, visualStyle)
	setText(compactCameraButton, cameraMode)
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
			else palette.CyanSoft
	end

	setText(sensValueLabel, string.format("%.2f", audio:GetSensitivity()))
	setText(motionValueLabel, string.format("%.2f", resonance:GetMotion()))
	setText(sprayValueLabel, string.format("%.2f", resonance:GetSprayAmount()))
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

local function bindStaticUi()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local gui = expectChild(playerGui, "ArrayWaveGui", "ScreenGui") :: ScreenGui
	local pill = expectChild(gui, "NowPlayingPill", "Frame") :: Frame
	local dockFrame = expectChild(gui, "BottomControlDock", "Frame") :: Frame
	local collapsed = expectChild(dockFrame, "CollapsedControls", "Frame") :: Frame
	local drawer = expectChild(dockFrame, "TuneDrawer", "Frame") :: Frame

	screenGui = gui
	nowPlayingPill = pill
	bottomDock = dockFrame
	collapsedControls = collapsed
	tuneDrawer = drawer
	pillStroke = pill:FindFirstChildOfClass("UIStroke")
	dockStroke = dockFrame:FindFirstChildOfClass("UIStroke")
	statusLabel = expectChild(pill, "StatusLabel", "TextLabel") :: TextLabel
	songIdBox = expectChild(pill, "SongIdBox", "TextBox") :: TextBox
	songIdStroke = songIdBox:FindFirstChildOfClass("UIStroke")

	gui.Enabled = true
	gui.ResetOnSpawn = false
	songIdBox.Text = Constants.DEFAULT_AUDIO_ASSET_ID
	songHighlight = 1
	songHighlightUntil = os.clock() + 3.25

	local compactPlayBase = findButton(collapsed, "CompactPlayBaseButton")
	currentModeButton = findButton(collapsed, "CurrentModeButton")
	tuneButton = findButton(collapsed, "TuneButton")
	compactCameraButton = findButton(collapsed, "CompactCameraButton")

	local sourceRow = expectChild(drawer, "SourceRow", "Frame")
	audioButtons.PlayBase = findButton(sourceRow, "PlayBaseButton")
	audioButtons.Demo = findButton(sourceRow, "DemoButton")
	audioButtons.Mic = findButton(sourceRow, "MicButton")
	audioButtons.PlayAsset = findButton(sourceRow, "PlayAssetButton")
	local stopButton = findButton(sourceRow, "StopButton")

	local visualModeRow = expectChild(drawer, "VisualModeRow", "Frame")
	visualButtons.Grid = findButton(visualModeRow, "GridButton")
	visualButtons.Row = findButton(visualModeRow, "RowButton")
	visualButtons.Circle = findButton(visualModeRow, "CircleButton")
	visualButtons.All = findButton(visualModeRow, "AllButton")
	visualButtons.Minimal = findButton(visualModeRow, "MinimalButton")

	local feelRow = expectChild(drawer, "FeelRow", "Frame")
	local sensMinus = findButton(feelRow, "SensMinusButton")
	sensValueLabel = expectChild(feelRow, "SensValueLabel", "TextLabel") :: TextLabel
	local sensPlus = findButton(feelRow, "SensPlusButton")
	local motionMinus = findButton(feelRow, "MotionMinusButton")
	motionValueLabel = expectChild(feelRow, "MotionValueLabel", "TextLabel") :: TextLabel
	local motionPlus = findButton(feelRow, "MotionPlusButton")
	local sprayMinus = findButton(feelRow, "SprayMinusButton")
	sprayValueLabel = expectChild(feelRow, "SprayValueLabel", "TextLabel") :: TextLabel
	local sprayPlus = findButton(feelRow, "SprayPlusButton")

	local cameraActionRow = expectChild(drawer, "CameraActionRow", "Frame")
	cameraButtons.Auto = findButton(cameraActionRow, "CameraAutoButton")
	cameraButtons.Still = findButton(cameraActionRow, "CameraStillButton")
	cameraButtons.Wide = findButton(cameraActionRow, "CameraWideButton")
	cameraButtons.Close = findButton(cameraActionRow, "CameraCloseButton")
	local pulseTest = findButton(cameraActionRow, "PulseTestButton")
	dropMarbleButton = findButton(cameraActionRow, "DropMarbleButton")
	dropMarbleButton.Visible = getMarbleRemote() ~= nil

	local analyzerFrame = expectChild(drawer, "AnalyzerStrip", "Frame") :: Frame
	collectAnalyzerBars(analyzerFrame)

	maid:Give(songIdBox.Focused:Connect(function()
		songIdFocused = true
		songHighlight = 1
		songHighlightUntil = os.clock() + 2.2
		selectSongText()
	end))
	maid:Give(songIdBox.FocusLost:Connect(function(submitted: boolean)
		songIdFocused = false
		if submitted then
			playAssetFromBox()
			updateReadouts()
		end
	end))

	local function playBase()
		activeAudioButton = "PlayBase"
		context.AudioController:PlayBaseSong()
		clearStatusOverride()
		updateReadouts()
	end

	bindButton(compactPlayBase, playBase)
	bindButton(audioButtons.PlayBase, playBase)
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
		playAssetFromBox()
		updateReadouts()
	end)
	bindButton(stopButton, function()
		activeAudioButton = "Demo"
		context.AudioController:Stop()
		clearStatusOverride()
		updateReadouts()
	end)

	bindButton(currentModeButton :: TextButton, function()
		cycleVisualStyle()
		updateReadouts()
	end)
	for styleName, button in pairs(visualButtons) do
		local capturedStyle = styleName
		bindButton(button, function()
			context.ResonanceController:SetStyle(capturedStyle)
			updateReadouts()
		end)
	end

	bindButton(tuneButton :: TextButton, toggleTune)
	bindButton(compactCameraButton :: TextButton, function()
		cycleCameraMode()
		updateReadouts()
	end)
	for cameraMode, button in pairs(cameraButtons) do
		local capturedMode = cameraMode :: CameraMode
		bindButton(button, function()
			updateCameraMode(capturedMode)
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
	bindButton(motionMinus, function()
		local resonance = context.ResonanceController
		resonance:SetMotion(resonance:GetMotion() - 0.12)
		updateReadouts()
	end)
	bindButton(motionPlus, function()
		local resonance = context.ResonanceController
		resonance:SetMotion(resonance:GetMotion() + 0.12)
		updateReadouts()
	end)
	bindButton(sprayMinus, function()
		local resonance = context.ResonanceController
		resonance:SetSprayAmount(resonance:GetSprayAmount() - 0.15)
		updateReadouts()
	end)
	bindButton(sprayPlus, function()
		local resonance = context.ResonanceController
		resonance:SetSprayAmount(resonance:GetSprayAmount() + 0.15)
		updateReadouts()
	end)
	bindButton(pulseTest, function()
		context.ResonanceController:TriggerPulse(1)
		glow = math.max(glow, 0.9)
		songHighlight = math.max(songHighlight, 0.45)
		showStatus("Pulse")
	end)
	if dropMarbleButton ~= nil then
		bindButton(dropMarbleButton, requestMarble)
	end

	setTuneOpen(Constants.UI_TUNE_DEFAULT_OPEN)
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
		local highlightPulse = if os.clock() < songHighlightUntil then (math.sin(os.clock() * 5.2) + 1) * 0.18 + 0.38 else 0
		local targetHighlight = if songIdFocused then 1 else highlightPulse
		songHighlight = NumberUtil.expSmooth(songHighlight, targetHighlight, deltaTime, 6)

		local topStroke = pillStroke
		if topStroke ~= nil then
			topStroke.Transparency = 0.68 - math.clamp(songHighlight * 0.22, 0, 0.22)
		end

		local idStroke = songIdStroke
		if idStroke ~= nil then
			idStroke.Color = palette.CyanSoft
			idStroke.Transparency = 0.72 - math.clamp(songHighlight * 0.48, 0, 0.48)
			idStroke.Thickness = 1 + songHighlight * 0.55
		end

		local stroke = dockStroke
		if stroke ~= nil then
			stroke.Transparency = 0.64 - math.clamp(glow * 0.22, 0, 0.22)
		end
	end))
end

function UIController:SetTuneOpen(open: boolean)
	setTuneOpen(open)
end

function UIController:ToggleTune()
	toggleTune()
end

function UIController:UpdateCameraMode(nextMode: CameraMode)
	updateCameraMode(nextMode)
	updateReadouts()
end

function UIController:SetStatus(text: string)
	showStatus(text)
end

function UIController:PlayAsset()
	playAssetFromBox()
	updateReadouts()
end

function UIController:PulseGlow(strength: number)
	glow = math.max(glow, math.clamp(NumberUtil.sanitizeFiniteNumber(strength, 0), 0, 1))
end

function UIController:Destroy()
	maid:Cleanup()
	screenGui = nil
	nowPlayingPill = nil
	bottomDock = nil
	collapsedControls = nil
	tuneDrawer = nil
	statusLabel = nil
	songIdBox = nil
	dropMarbleButton = nil
end

return UIController
