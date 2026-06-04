--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require((Shared:WaitForChild("Constants") :: ModuleScript))
local Types = require((Shared:WaitForChild("Types") :: ModuleScript))
local Util = Shared:WaitForChild("Util")
local InstanceUtil = require((Util:WaitForChild("InstanceUtil") :: ModuleScript))
local Maid = require((Util:WaitForChild("Maid") :: ModuleScript))
local NumberUtil = require((Util:WaitForChild("NumberUtil") :: ModuleScript))

type AudioFrame = Types.AudioFrame
type AudioMode = Types.AudioMode
type BandArray = Types.BandArray

local AudioInputController = {}

local initialized = false
local started = false
local maid = Maid.new()
local audioMaid = Maid.new()
local callbacks: { (AudioFrame) -> () } = {}

local mode: AudioMode = "Demo"
local status = "Demo mode active"
local sensitivity = Constants.DEFAULT_SENSITIVITY
local demoTime = 0
local rollingEnergy = 0.12
local lastBeatTime = 0
local assetAnalyzer: AudioAnalyzer? = nil
local micAnalyzer: AudioAnalyzer? = nil
local classicSound: Sound? = nil

local smoothedBands: BandArray = table.create(Constants.VISUALIZER_BAND_COUNT, 0)
local currentFrame: AudioFrame = {
	rms = 0,
	peak = 0,
	bass = 0,
	beat = false,
	bands = smoothedBands,
	time = 0,
}

local function makeBands(value: number): BandArray
	local bands = table.create(Constants.VISUALIZER_BAND_COUNT, value)
	return bands
end

local function getRenderSignal(): RBXScriptSignal
	local preRender = (RunService :: any).PreRender
	if typeof(preRender) == "RBXScriptSignal" then
		return preRender :: RBXScriptSignal
	end

	return RunService.RenderStepped
end

local function notifyFrameChanged()
	for _, callback in ipairs(callbacks) do
		callback(currentFrame)
	end
end

local function setStatus(nextStatus: string)
	status = nextStatus
end

local function readNumberProperty(instance: any, propertyName: string, fallback: number): number
	local ok, value = pcall(function()
		return instance[propertyName]
	end)

	if not ok then
		return fallback
	end

	return NumberUtil.sanitizeFiniteNumber(value, fallback)
end

local function createAudioFolder(): Folder
	audioMaid:Cleanup()

	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local folder = InstanceUtil.create("Folder", {
		Name = "PulseForgeAudio",
	}, playerGui) :: Folder

	audioMaid:Give(folder)
	return folder
end

local function stopAudioGraph()
	audioMaid:Cleanup()
	assetAnalyzer = nil
	micAnalyzer = nil
	classicSound = nil
end

local function sanitizeAssetId(assetIdText: string): string?
	local compact = string.gsub(assetIdText, "%s+", "")
	if compact == "" or #compact > 18 then
		return nil
	end

	if string.match(compact, "^%d+$") == nil then
		return nil
	end

	local numericId = tonumber(compact)
	if numericId == nil or numericId <= 0 then
		return nil
	end

	return compact
end

local function setAudioPlayerContent(audioPlayer: AudioPlayer, assetId: string): boolean
	local numericAssetId = tonumber(assetId)
	local uri = `rbxassetid://{assetId}`

	local okContent = pcall(function()
		if numericAssetId == nil then
			error("invalid asset id")
		end

		(audioPlayer :: any).AudioContent = (Content :: any).fromAssetId(numericAssetId)
	end)
	if okContent then
		return true
	end

	local okUri = pcall(function()
		(audioPlayer :: any).AudioContent = (Content :: any).fromUri(uri)
	end)
	if okUri then
		return true
	end

	local okAsset = pcall(function()
		(audioPlayer :: any).Asset = uri
	end)
	if okAsset then
		return true
	end

	return pcall(function()
		(audioPlayer :: any).AssetId = uri
	end)
end

local function createWire(parent: Instance, source: Instance, target: Instance): Wire
	return InstanceUtil.create("Wire", {
		Name = `{source.Name}_To_{target.Name}`,
		SourceInstance = source,
		SourceName = "Output",
		TargetInstance = target,
		TargetName = "Input",
	}, parent) :: Wire
end

local function buildBandsFromSpectrum(spectrum: { any }, rms: number, peak: number): BandArray
	if #spectrum == 0 then
		return makeBands(math.max(rms, peak * 0.75))
	end

	local bands = table.create(Constants.VISUALIZER_BAND_COUNT, 0)
	local sourceCount = #spectrum

	for bandIndex = 1, Constants.VISUALIZER_BAND_COUNT do
		local startIndex = math.max(1, math.floor((bandIndex - 1) / Constants.VISUALIZER_BAND_COUNT * sourceCount) + 1)
		local endIndex = math.max(startIndex, math.floor(bandIndex / Constants.VISUALIZER_BAND_COUNT * sourceCount))
		local total = 0
		local samples = 0

		for spectrumIndex = startIndex, endIndex do
			local value = NumberUtil.sanitizeFiniteNumber(spectrum[spectrumIndex], 0)
			if value < 0 then
				value = math.abs(value)
			end
			if value > 1 then
				value = value / 100
			end
			total += math.clamp(value, 0, 1)
			samples += 1
		end

		local average = if samples > 0 then total / samples else 0
		bands[bandIndex] = math.clamp(average * sensitivity, 0, 1)
	end

	return bands
end

local function synthesizeBandsFromEnergy(rms: number, peak: number, timeNow: number): BandArray
	local bands = table.create(Constants.VISUALIZER_BAND_COUNT, 0)
	local energy = math.clamp(math.max(rms, peak * 0.8) * sensitivity, 0, 1)

	for index = 1, Constants.VISUALIZER_BAND_COUNT do
		local bandAlpha = (index - 1) / Constants.VISUALIZER_BAND_COUNT
		local wave = (math.sin(timeNow * 4 + bandAlpha * math.pi * 6) + 1) * 0.5
		local shaped = energy * (0.45 + wave * 0.55) * (1 - bandAlpha * 0.28)
		bands[index] = math.clamp(shaped, 0, 1)
	end

	return bands
end

local function readAnalyzerFrame(analyzer: AudioAnalyzer, deltaTime: number)
	local rms = math.clamp(readNumberProperty(analyzer, "RmsLevel", 0) * sensitivity, 0, 1)
	local peak = math.clamp(readNumberProperty(analyzer, "PeakLevel", rms) * sensitivity, 0, 1)
	local spectrum: { any } = {}

	local okSpectrum, spectrumValues = pcall(function()
		return analyzer:GetSpectrum()
	end)

	if okSpectrum and typeof(spectrumValues) == "table" then
		spectrum = spectrumValues :: { any }
	end

	local bands = if #spectrum > 0
		then buildBandsFromSpectrum(spectrum, rms, peak)
		else synthesizeBandsFromEnergy(rms, peak, os.clock())

	local bassTotal = 0
	for index = 1, math.min(6, #bands) do
		bassTotal += bands[index]
	end

	local bass = bassTotal / 6
	local rawPeak = math.max(peak, bass)
	local rawRms = math.max(rms, bass * 0.6)

	AudioInputController:_ApplyRawFrame(bands, rawRms, rawPeak, bass, deltaTime)
end

local function readClassicSoundFrame(sound: Sound, deltaTime: number)
	local loudness = math.clamp(readNumberProperty(sound, "PlaybackLoudness", 0) / 1000 * sensitivity, 0, 1)
	local peak = math.clamp(loudness * 1.25, 0, 1)
	local bands = synthesizeBandsFromEnergy(loudness, peak, os.clock())
	local bass = math.clamp((bands[1] + bands[2] + bands[3] + bands[4]) / 4, 0, 1)

	AudioInputController:_ApplyRawFrame(bands, loudness, peak, bass, deltaTime)
end

local function scheduleAssetReadinessCheck(readReady: () -> boolean)
	local thread = task.spawn(function()
		for _ = 1, 4 do
			task.wait(0.75)
			if mode ~= "Asset" then
				return
			end

			if readReady() or currentFrame.peak > 0.03 then
				return
			end
		end

		if mode == "Asset" then
			stopAudioGraph()
			mode = "Demo"
			setStatus("Asset unavailable - using demo pulse")
		end
	end)

	audioMaid:Give(thread)
end

local function tryModularAsset(assetId: string): boolean
	local folder = createAudioFolder()

	local ok = pcall(function()
		local audioPlayer = Instance.new("AudioPlayer")
		audioPlayer.Name = "AssetAudioPlayer"
		audioPlayer.Looping = true
		audioPlayer.Volume = 0.65
		(audioPlayer :: any).AutoLoad = true
		assert(setAudioPlayerContent(audioPlayer, assetId), "AudioPlayer content property unavailable")
		audioPlayer.Parent = folder

		local analyzer = Instance.new("AudioAnalyzer")
		analyzer.Name = "AssetAudioAnalyzer"
		pcall(function()
			analyzer.SpectrumEnabled = true
		end)
		analyzer.Parent = folder

		local output = Instance.new("AudioDeviceOutput")
		output.Name = "LocalAudioOutput"
		pcall(function()
			output.Player = LocalPlayer
		end)
		output.Parent = folder

		createWire(folder, audioPlayer, analyzer)
		createWire(folder, audioPlayer, output)

		assetAnalyzer = analyzer
		audioPlayer:Play()

		scheduleAssetReadinessCheck(function(): boolean
			local readyOk, ready = pcall(function()
				return audioPlayer.IsReady
			end)

			return readyOk and ready == true
		end)
	end)

	if not ok then
		audioMaid:Cleanup()
		assetAnalyzer = nil
		return false
	end

	return true
end

local function tryClassicSound(assetId: string): boolean
	local folder = createAudioFolder()

	local ok = pcall(function()
		local sound = Instance.new("Sound")
		sound.Name = "ClassicAssetSound"
		sound.SoundId = `rbxassetid://{assetId}`
		sound.Looped = true
		sound.Volume = 0.65
		sound.Parent = folder
		sound:Play()
		classicSound = sound

		scheduleAssetReadinessCheck(function(): boolean
			return sound.IsLoaded
		end)
	end)

	if not ok then
		audioMaid:Cleanup()
		classicSound = nil
		return false
	end

	return true
end

local function tryMicInput(): boolean
	local folder = createAudioFolder()

	local ok = pcall(function()
		local input = Instance.new("AudioDeviceInput")
		input.Name = "LocalMicInput"
		input.Player = LocalPlayer
		input.Muted = false
		input.Volume = 1
		input.Parent = folder

		local analyzer = Instance.new("AudioAnalyzer")
		analyzer.Name = "MicAudioAnalyzer"
		pcall(function()
			analyzer.SpectrumEnabled = true
		end)
		analyzer.Parent = folder

		createWire(folder, input, analyzer)
		micAnalyzer = analyzer
	end)

	if not ok then
		audioMaid:Cleanup()
		micAnalyzer = nil
		return false
	end

	local thread = task.spawn(function()
		task.wait(2.5)
		if mode == "Mic" and currentFrame.peak <= 0.01 and currentFrame.rms <= 0.01 then
			stopAudioGraph()
			mode = "Demo"
			setStatus("Mic unavailable - using demo pulse")
		end
	end)
	audioMaid:Give(thread)

	return true
end

function AudioInputController:_ApplyRawFrame(rawBands: BandArray, rawRms: number, rawPeak: number, rawBass: number, deltaTime: number)
	local now = os.clock()
	local attack = if rawPeak > currentFrame.peak then 20 else 7
	local release = if rawRms > currentFrame.rms then 18 else 5

	for index = 1, Constants.VISUALIZER_BAND_COUNT do
		local target = math.clamp(rawBands[index] or 0, 0, 1)
		local current = smoothedBands[index] or 0
		local speed = if target > current then attack else release
		smoothedBands[index] = NumberUtil.expSmoothing(current, target, deltaTime, speed)
	end

	local rms = NumberUtil.expSmoothing(currentFrame.rms, math.clamp(rawRms, 0, 1), deltaTime, release)
	local peak = NumberUtil.expSmoothing(currentFrame.peak, math.clamp(rawPeak, 0, 1), deltaTime, attack)
	local bass = NumberUtil.expSmoothing(currentFrame.bass, math.clamp(rawBass, 0, 1), deltaTime, attack)

	rollingEnergy = NumberUtil.expSmoothing(rollingEnergy, rms, deltaTime, 1.6)

	local beatThreshold = math.max(0.22, rollingEnergy + 0.16)
	local beatCooldown = 0.21
	local beat = false
	if (peak > beatThreshold or bass > beatThreshold + 0.08) and now - lastBeatTime >= beatCooldown then
		beat = true
		lastBeatTime = now
	end

	currentFrame = {
		rms = rms,
		peak = peak,
		bass = bass,
		beat = beat,
		bands = smoothedBands,
		time = now,
	}

	notifyFrameChanged()
end

function AudioInputController:_GenerateDemoFrame(deltaTime: number)
	demoTime += deltaTime

	local t = demoTime
	local bands = table.create(Constants.VISUALIZER_BAND_COUNT, 0)
	local beatWave = (math.sin(t * math.pi * 2 * 1.35) + 1) * 0.5
	local bassPulse = math.clamp((beatWave - 0.68) / 0.32, 0, 1)
	local basePulse = (math.sin(t * math.pi * 2 * 0.42) + 1) * 0.5

	for index = 1, Constants.VISUALIZER_BAND_COUNT do
		local bandAlpha = (index - 1) / Constants.VISUALIZER_BAND_COUNT
		local noise = (math.noise(t * 0.9, bandAlpha * 4.5, 0.25) + 1) * 0.5
		local ripple = (math.sin(t * 5.5 + bandAlpha * math.pi * 7.5) + 1) * 0.5
		local bassWeight = math.max(0, 1 - bandAlpha * 2.5)
		local trebleSpark = ripple * noise * bandAlpha * 0.42
		local value = 0.08 + basePulse * 0.2 + bassPulse * bassWeight * 0.75 + trebleSpark
		bands[index] = math.clamp(value * sensitivity, 0, 1)
	end

	local rms = math.clamp(0.15 + basePulse * 0.22 + bassPulse * 0.5, 0, 1)
	local peak = math.clamp(rms + bassPulse * 0.28 + bands[Constants.VISUALIZER_BAND_COUNT] * 0.12, 0, 1)
	local bass = math.clamp((bands[1] + bands[2] + bands[3] + bands[4]) / 4, 0, 1)

	self:_ApplyRawFrame(bands, rms, peak, bass, deltaTime)
end

function AudioInputController:Init(_context: any)
	if initialized then
		return
	end

	initialized = true
end

function AudioInputController:Start()
	if started then
		return
	end

	started = true
	mode = "Demo"
	setStatus("Demo mode active")

	maid:Give(getRenderSignal():Connect(function(deltaTime: number)
		if mode == "Demo" then
			self:_GenerateDemoFrame(deltaTime)
		elseif mode == "Asset" then
			if assetAnalyzer ~= nil then
				readAnalyzerFrame(assetAnalyzer, deltaTime)
			elseif classicSound ~= nil then
				readClassicSoundFrame(classicSound, deltaTime)
			else
				self:_GenerateDemoFrame(deltaTime)
			end
		elseif mode == "Mic" then
			if micAnalyzer ~= nil then
				readAnalyzerFrame(micAnalyzer, deltaTime)
			else
				self:_GenerateDemoFrame(deltaTime)
			end
		end
	end))
end

function AudioInputController:SetMode(nextMode: AudioMode)
	if nextMode == "Demo" then
		stopAudioGraph()
		mode = "Demo"
		setStatus("Demo mode active")
	elseif nextMode == "Asset" then
		setStatus("Paste an asset ID, then press Play Asset")
	elseif nextMode == "Mic" then
		stopAudioGraph()
		setStatus("Trying mic input...")
		if tryMicInput() then
			mode = "Mic"
			setStatus("Mic mode active")
		else
			mode = "Demo"
			setStatus("Mic unavailable - using demo pulse")
		end
	end
end

function AudioInputController:PlayAsset(assetIdText: string)
	local assetId = sanitizeAssetId(assetIdText)
	if assetId == nil then
		stopAudioGraph()
		mode = "Demo"
		setStatus("Invalid asset ID")
		return
	end

	setStatus("Trying asset audio...")

	if tryModularAsset(assetId) or tryClassicSound(assetId) then
		mode = "Asset"
		setStatus("Asset loaded")
	else
		stopAudioGraph()
		mode = "Demo"
		setStatus("Asset unavailable - using demo pulse")
	end
end

function AudioInputController:Stop()
	stopAudioGraph()
	mode = "Demo"
	setStatus("Demo mode active")
end

function AudioInputController:SetSensitivity(value: number)
	local cleanValue = NumberUtil.sanitizeFiniteNumber(value, Constants.DEFAULT_SENSITIVITY)
	sensitivity = math.clamp(cleanValue, 0.25, 3)
end

function AudioInputController:GetSensitivity(): number
	return sensitivity
end

function AudioInputController:GetFrame(): AudioFrame
	return currentFrame
end

function AudioInputController:GetMode(): AudioMode
	return mode
end

function AudioInputController:GetStatus(): string
	return status
end

function AudioInputController:SetStatus(nextStatus: string)
	setStatus(nextStatus)
end

function AudioInputController:OnFrameChanged(callback: (AudioFrame) -> ()): () -> ()
	table.insert(callbacks, callback)
	local connected = true

	return function()
		if not connected then
			return
		end

		connected = false
		for index, registered in ipairs(callbacks) do
			if registered == callback then
				table.remove(callbacks, index)
				break
			end
		end
	end
end

function AudioInputController:Destroy()
	maid:Cleanup()
	audioMaid:Cleanup()
end

return AudioInputController
