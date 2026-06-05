--!strict

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local MIN_LOADING_TIME = 2
local MAX_LOADING_TIME = 8

local palette = table.freeze({
	Background = Color3.fromRGB(5, 7, 10),
	Surface = Color3.fromRGB(12, 16, 22),
	SurfaceRaised = Color3.fromRGB(18, 24, 32),
	Text = Color3.fromRGB(235, 242, 248),
	TextMuted = Color3.fromRGB(136, 150, 162),
	Cyan = Color3.fromRGB(80, 220, 255),
	CyanSoft = Color3.fromRGB(118, 232, 255),
	Stroke = Color3.fromRGB(58, 75, 88),
})

local statusMessages = table.freeze({
	"Preparing audio graph",
	"Building visual arrays",
	"Tuning beat detector",
})

local function createCorner(radius: number, parent: Instance): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function createTextLabel(name: string, text: string, size: number, color: Color3, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.Text = text
	label.TextColor3 = color
	label.TextSize = size
	label.TextWrapped = false
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	return label
end

ReplicatedFirst:RemoveDefaultLoadingScreen()

local playerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ArrayWaveLoadingGui"
screenGui.DisplayOrder = 10000
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local background = Instance.new("Frame")
background.Name = "Background"
background.BackgroundColor3 = palette.Background
background.BorderSizePixel = 0
background.Size = UDim2.fromScale(1, 1)
background.ZIndex = 1
background.Parent = screenGui

local content = Instance.new("CanvasGroup")
content.Name = "Content"
content.AnchorPoint = Vector2.new(0.5, 0.5)
content.BackgroundColor3 = palette.Surface
content.BackgroundTransparency = 0.08
content.BorderSizePixel = 0
content.GroupTransparency = 1
content.Position = UDim2.fromScale(0.5, 0.5)
content.Size = UDim2.fromOffset(340, 230)
content.ZIndex = 2
createCorner(14, content)

local contentStroke = Instance.new("UIStroke")
contentStroke.Color = palette.Stroke
contentStroke.Thickness = 1
contentStroke.Transparency = 0.18
contentStroke.Parent = content

local padding = Instance.new("UIPadding")
padding.PaddingBottom = UDim.new(0, 28)
padding.PaddingLeft = UDim.new(0, 30)
padding.PaddingRight = UDim.new(0, 30)
padding.PaddingTop = UDim.new(0, 30)
padding.Parent = content

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, 12)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Parent = content

local title = createTextLabel("Title", "ArrayWave", 28, palette.Text, content)
title.LayoutOrder = 1
title.Size = UDim2.new(1, 0, 0, 34)

local titleConstraint = Instance.new("UITextSizeConstraint")
titleConstraint.MaxTextSize = 28
titleConstraint.MinTextSize = 18
titleConstraint.Parent = title

local subtitle = createTextLabel("Subtitle", "Audio-reactive field", 13, palette.TextMuted, content)
subtitle.Font = Enum.Font.Gotham
subtitle.LayoutOrder = 2
subtitle.Size = UDim2.new(1, 0, 0, 18)

local waveFrame = Instance.new("Frame")
waveFrame.Name = "Wave"
waveFrame.BackgroundTransparency = 1
waveFrame.LayoutOrder = 3
waveFrame.Size = UDim2.new(1, 0, 0, 52)
waveFrame.Parent = content

local waveLayout = Instance.new("UIListLayout")
waveLayout.FillDirection = Enum.FillDirection.Horizontal
waveLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
waveLayout.Padding = UDim.new(0, 7)
waveLayout.SortOrder = Enum.SortOrder.LayoutOrder
waveLayout.VerticalAlignment = Enum.VerticalAlignment.Center
waveLayout.Parent = waveFrame

local bars = table.create(13)
for index = 1, 13 do
	local bar = Instance.new("Frame")
	bar.Name = `Bar{index}`
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.BackgroundColor3 = if index % 2 == 0 then palette.Cyan else palette.CyanSoft
	bar.BackgroundTransparency = 0.28
	bar.BorderSizePixel = 0
	bar.LayoutOrder = index
	bar.Size = UDim2.fromOffset(7, 12)
	bar.Parent = waveFrame
	createCorner(4, bar)
	bars[index] = bar
end

local statusLabel = createTextLabel("Status", statusMessages[1], 13, palette.TextMuted, content)
statusLabel.Font = Enum.Font.Gotham
statusLabel.LayoutOrder = 4
statusLabel.Size = UDim2.new(1, 0, 0, 20)

content.Parent = background
screenGui.Parent = playerGui

local fadeIn = TweenService:Create(content, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
	GroupTransparency = 0,
})
fadeIn:Play()

local ready = LocalPlayer:GetAttribute("ArrayWaveClientReady") == true
local startedAt = os.clock()
local lastStatusIndex = 1
local nextStatusAt = startedAt + 1.35

local readyConnection = LocalPlayer:GetAttributeChangedSignal("ArrayWaveClientReady"):Connect(function()
	ready = LocalPlayer:GetAttribute("ArrayWaveClientReady") == true
end)

local renderConnection = RunService.RenderStepped:Connect(function()
	local now = os.clock()
	local elapsed = now - startedAt

	for index, bar in ipairs(bars) do
		local wave = (math.sin(elapsed * 4.6 + index * 0.66) + 1) * 0.5
		local accent = math.clamp(wave ^ 1.8, 0, 1)
		bar.Size = UDim2.fromOffset(7, 11 + accent * 28)
		bar.BackgroundTransparency = 0.42 - accent * 0.28
	end

	if now >= nextStatusAt and not ready then
		lastStatusIndex = (lastStatusIndex % #statusMessages) + 1
		nextStatusAt = now + 1.25
		statusLabel.TextTransparency = 1
		statusLabel.Text = statusMessages[lastStatusIndex]
		TweenService:Create(statusLabel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 0,
		}):Play()
	end
end)

while true do
	local elapsed = os.clock() - startedAt
	if (ready and elapsed >= MIN_LOADING_TIME) or elapsed >= MAX_LOADING_TIME then
		break
	end

	task.wait(0.05)
end

statusLabel.Text = "Ready"
task.wait(0.18)

local fadeOutContent = TweenService:Create(content, TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
	GroupTransparency = 1,
})
local fadeOutBackground = TweenService:Create(background, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
	BackgroundTransparency = 1,
})
fadeOutContent:Play()
fadeOutBackground:Play()
fadeOutBackground.Completed:Wait()

renderConnection:Disconnect()
readyConnection:Disconnect()
screenGui:Destroy()
