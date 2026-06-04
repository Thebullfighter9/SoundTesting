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

local AudioController = {}

local initialized = false
local started = false
local maid = Maid.new()
local audioMaid = Maid.new()
local callbacks: { (AudioFrame) -> () } = {}

local mode: AudioMode = Constants.DEFAULT_AUDIO_MODE :: AudioMode
local status = "Base song ready"
local sensitivity = Constants.DEFAULT_SENSITIVITY
local demoTime = 0
local rollingEnergy = 0.12
local lastBeatTime = 0
local audioAttemptSerial = 0
local assetAnalyzer: AudioAnalyzer? = nil
local micAnalyzer: AudioAnalyzer? = nil
local classicSound: Sound? = nil

local smoothedBands: { number } = table.create(Constants.VISUAL_BAND_COUNT, 0)
local currentFrame: AudioFrame = {
	rms = 0,
	peak = 0,
	bass = 0,
	beat = false,
	bands = smoothedBands,
	time = 0,
}

local function getRenderSignal(): RBXScriptSignal
	local preRender = (RunService :: any).PreRender
	if typeof(preRender) == "RBXScriptSignal" then
		return preRender :: RBXScriptSignal
	end

	return RunService.RenderStepped
end

local function setStatus(nextStatus: string)
	status = nextStatus
end

local function nextAudioAttempt(): number
	audioAttemptSerial += 1
	return audioAttemptSerial
end

local function isCurrentAttempt(attemptId: number): boolean
	return attemptId == audioAttemptSerial
end

local function notifyFrameChanged()
	for _, callback in ipairs(callbacks) do
		callback(currentFrame)
	end
end

local function makeBands(value: number): { number }
	return table.create(Constants.VISUAL_BAND_COUNT, value)
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

local function stopAudioGraph()
	audioMaid:Cleanup()
	assetAnalyzer = nil
	micAnalyzer = nil
	classicSound = nil
end

local function createAudioFolder(): Folder
	stopAudioGraph()

	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local folder = InstanceUtil.create("Folder", {
		Name = "ResonanceAudio",
	}, playerGui) :: Folder

	audioMaid:Give(folder)
	return folder
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

local function bandsFromSpectrum(spectrum: { any }, rms: number, peak: number): { number }
	if #spectrum == 0 then
		return makeBands(math.max(rms, peak * 0.8))
	end

	local bands = table.create(Constants.VISUAL_BAND_COUNT, 0)
	local sourceCount = #spectrum

	for bandIndex = 1, Constants.VISUAL_BAND_COUNT do
		local startIndex = math.max(1, math.floor((bandIndex - 1) / Constants.VISUAL_BAND_COUNT * sourceCount) + 1)
		local endIndex = math.max(startIndex, math.floor(bandIndex / Constants.VISUAL_BAND_COUNT * sourceCount))
		local total = 0
		local samples = 0

		for spectrumIndex = startIndex, endIndex do
			local value = NumberUtil.sanitizeFiniteNumber(spectrum[spectrumIndex], 0)
			if value < 0 then
				value = math.abs(value)
			end
			if value > 1 then
				value /= 100
			end
			total += math.clamp(value, 0, 1)
			samples += 1
		end

		bands[bandIndex] = math.clamp((if samples > 0 then total / samples else 0) * sensitivity, 0, 1)
	end

	return bands
end

local function synthesizeBands(rms: number, peak: number, timeNow: number): { number }
	local bands = table.create(Constants.VISUAL_BAND_COUNT, 0)
	local energy = math.clamp(math.max(rms, peak * 0.82) * sensitivity, 0, 1)

	for index = 1, Constants.VISUAL_BAND_COUNT do
		local alpha = (index - 1) / Constants.VISUAL_BAND_COUNT
		local wave = (math.sin(timeNow * 3.5 + alpha * math.pi * 5.5) + 1) * 0.5
		local quietShape = 0.45 + wave * 0.38 + math.max(0, 1 - alpha * 2.4) * 0.24
		bands[index] = math.clamp(energy * quietShape, 0, 1)
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

	local bands = if #spectrum > 0 then bandsFromSpectrum(spectrum, rms, peak) else synthesizeBands(rms, peak, os.clock())
	local bassTotal = 0
	for index = 1, math.min(5, #bands) do
		bassTotal += bands[index]
	end

	local bass = bassTotal / 5
	AudioController:_ApplyRawFrame(bands, math.max(rms, bass * 0.55), math.max(peak, bass), bass, deltaTime)
end

local function readClassicSoundFrame(sound: Sound, deltaTime: number)
	local loudness = math.clamp(readNumberProperty(sound, "PlaybackLoudness", 0) / 950 * sensitivity, 0, 1)
	local peak = math.clamp(loudness * 1.18, 0, 1)
	local bands = synthesizeBands(loudness, peak, os.clock())
	local bass = math.clamp((bands[1] + bands[2] + bands[3] + bands[4]) / 4, 0, 1)

	AudioController:_ApplyRawFrame(bands, loudness, peak, bass, deltaTime)
end

local function scheduleAssetReadinessCheck(readReady: () -> boolean, unavailableStatus: string, attemptId: number)
	local thread = task.spawn(function()
		for _ = 1, 4 do
			task.wait(0.75)
			if mode ~= "Asset" or not isCurrentAttempt(attemptId) then
				return
			end

			if readReady() or currentFrame.peak > 0.025 then
				return
			end
		end

		if mode == "Asset" and isCurrentAttempt(attemptId) then
			stopAudioGraph()
			mode = "Demo"
			setStatus(unavailableStatus)
		end
	end)

	audioMaid:Give(thread)
end

local function tryModularAsset(assetId: string, unavailableStatus: string, attemptId: number): boolean
	local folder = createAudioFolder()

	local ok = pcall(function()
		local audioPlayer = Instance.new("AudioPlayer")
		audioPlayer.Name = "AssetAudioPlayer"
		audioPlayer.Looping = true
		audioPlayer.Volume = 0.55
		pcall(function()
			(audioPlayer :: any).AutoLoad = true
		end)
		assert(setAudioPlayerContent(audioPlayer, assetId), "AudioPlayer content property unavailable")
		audioPlayer.Parent = folder

		local analyzer = Instance.new("AudioAnalyzer")
		analyzer.Name = "AssetAudioAnalyzer"
		pcall(function()
			analyzer.SpectrumEnabled = true
		end)
		analyzer.Parent = folder

		createWire(folder, audioPlayer, analyzer)

		local outputOk, output = pcall(function()
			return Instance.new("AudioDeviceOutput")
		end)
		if outputOk and output ~= nil then
			output.Name = "LocalAudioOutput"
			pcall(function()
				(output :: any).Player = LocalPlayer
			end)
			output.Parent = folder
			pcall(function()
				createWire(folder, audioPlayer, output)
			end)
		end

		assetAnalyzer = analyzer
		audioPlayer:Play()

		scheduleAssetReadinessCheck(function(): boolean
			local readyOk, ready = pcall(function()
				return audioPlayer.IsReady
			end)
			return readyOk and ready == true
		end, unavailableStatus, attemptId)
	end)

	if not ok then
		stopAudioGraph()
		return false
	end

	return true
end

local function tryClassicSound(assetId: string, unavailableStatus: string, attemptId: number): boolean
	local folder = createAudioFolder()

	local ok = pcall(function()
		local sound = Instance.new("Sound")
		sound.Name = "ClassicAssetSound"
		sound.SoundId = `rbxassetid://{assetId}`
		sound.Looped = true
		sound.Volume = 0.55
		sound.Parent = folder
		sound:Play()
		classicSound = sound

		scheduleAssetReadinessCheck(function(): boolean
			return sound.IsLoaded
		end, unavailableStatus, attemptId)
	end)

	if not ok then
		stopAudioGraph()
		return false
	end

	return true
end

local function playAssetWithStatus(
	assetIdText: string,
	tryingStatus: string,
	readyStatus: string,
	unavailableStatus: string,
	invalidStatus: string
): boolean
	local assetId = sanitizeAssetId(assetIdText)
	if assetId == nil then
		stopAudioGraph()
		mode = "Demo"
		setStatus(invalidStatus)
		return false
	end

	setStatus(tryingStatus)
	local attemptId = nextAudioAttempt()

	if tryModularAsset(assetId, unavailableStatus, attemptId) or tryClassicSound(assetId, unavailableStatus, attemptId) then
		mode = "Asset"
		setStatus(readyStatus)
		return true
	end

	stopAudioGraph()
	mode = "Demo"
	setStatus(unavailableStatus)
	return false
end

local function tryMicInput(attemptId: number): boolean
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
		stopAudioGraph()
		return false
	end

	local thread = task.spawn(function()
		task.wait(2.5)
		if mode == "Mic" and isCurrentAttempt(attemptId) and currentFrame.peak <= 0.01 and currentFrame.rms <= 0.01 then
			stopAudioGraph()
			mode = "Demo"
			setStatus("Mic unavailable - using demo signal")
		end
	end)
	audioMaid:Give(thread)

	return true
end

function AudioController:_ApplyRawFrame(rawBands: { number }, rawRms: number, rawPeak: number, rawBass: number, deltaTime: number)
	local now = os.clock()
	local attack = if rawPeak > currentFrame.peak then 18 else 6
	local release = if rawRms > currentFrame.rms then 15 else 4

	for index = 1, Constants.VISUAL_BAND_COUNT do
		local target = math.clamp(rawBands[index] or 0, 0, 1)
		local current = smoothedBands[index] or 0
		local speed = if target > current then attack else release
		smoothedBands[index] = NumberUtil.expSmooth(current, target, deltaTime, speed)
	end

	local rms = NumberUtil.expSmooth(currentFrame.rms, math.clamp(rawRms, 0, 1), deltaTime, release)
	local peak = NumberUtil.expSmooth(currentFrame.peak, math.clamp(rawPeak, 0, 1), deltaTime, attack)
	local bass = NumberUtil.expSmooth(currentFrame.bass, math.clamp(rawBass, 0, 1), deltaTime, attack)

	rollingEnergy = NumberUtil.expSmooth(rollingEnergy, rms, deltaTime, 1.4)

	local beat = false
	local threshold = math.max(0.2, rollingEnergy + 0.15)
	if (peak > threshold or bass > threshold + 0.08) and now - lastBeatTime > 0.22 then
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

function AudioController:_GenerateDemoFrame(deltaTime: number)
	demoTime += deltaTime

	local t = demoTime
	local bands = table.create(Constants.VISUAL_BAND_COUNT, 0)
	local kickWave = (math.sin(t * math.pi * 2 * 1.08) + 1) * 0.5
	local kick = math.clamp((kickWave - 0.72) / 0.28, 0, 1)
	local bassWave = (math.sin(t * math.pi * 2 * 0.27) + 1) * 0.5
	local breath = (math.sin(t * math.pi * 2 * 0.08) + 1) * 0.5

	for index = 1, Constants.VISUAL_BAND_COUNT do
		local alpha = (index - 1) / Constants.VISUAL_BAND_COUNT
		local noise = (math.noise(t * 0.55, alpha * 3.8, 0.1) + 1) * 0.5
		local ripple = (math.sin(t * 3.6 + alpha * math.pi * 4.2) + 1) * 0.5
		local bassWeight = math.max(0, 1 - alpha * 2.6)
		local value = 0.07 + breath * 0.1 + bassWave * 0.16 + kick * bassWeight * 0.62 + ripple * noise * 0.18
		bands[index] = math.clamp(value * sensitivity, 0, 1)
	end

	local rms = math.clamp(0.12 + breath * 0.08 + bassWave * 0.16 + kick * 0.34, 0, 1)
	local peak = math.clamp(rms + kick * 0.28 + bands[Constants.VISUAL_BAND_COUNT] * 0.06, 0, 1)
	local bass = math.clamp((bands[1] + bands[2] + bands[3] + bands[4]) / 4, 0, 1)

	self:_ApplyRawFrame(bands, rms, peak, bass, deltaTime)
end

function AudioController:Init(_context: any)
	if initialized then
		return
	end

	initialized = true
end

function AudioController:Start()
	if started then
		return
	end

	started = true

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

	if Constants.DEFAULT_AUDIO_MODE == "Asset" then
		self:PlayBaseSong()
	else
		self:SetMode("Demo")
	end
end

function AudioController:SetMode(nextMode: AudioMode)
	if nextMode == "Demo" then
		nextAudioAttempt()
		stopAudioGraph()
		mode = "Demo"
		setStatus("Demo signal active")
	elseif nextMode == "Asset" then
		setStatus("Enter an audio asset id")
	elseif nextMode == "Mic" then
		local attemptId = nextAudioAttempt()
		stopAudioGraph()
		setStatus("Trying mic input")
		if tryMicInput(attemptId) then
			mode = "Mic"
			setStatus("Mic mode active")
		else
			mode = "Demo"
			setStatus("Mic unavailable - using demo signal")
		end
	end
end

function AudioController:PlayAsset(assetIdText: string)
	playAssetWithStatus(
		assetIdText,
		"Trying asset audio",
		"Asset loaded",
		"Asset unavailable - using demo signal",
		"Invalid asset ID"
	)
end

function AudioController:PlayBaseSong(): boolean
	return playAssetWithStatus(
		Constants.DEFAULT_AUDIO_ASSET_ID,
		"Loading base song",
		"Playing base song",
		"Base song unavailable - using demo signal",
		"Base song unavailable - using demo signal"
	)
end

function AudioController:Stop()
	nextAudioAttempt()
	stopAudioGraph()
	mode = "Demo"
	setStatus("Demo signal active")
end

function AudioController:SetSensitivity(value: number)
	local cleanValue = NumberUtil.sanitizeFiniteNumber(value, Constants.DEFAULT_SENSITIVITY)
	sensitivity = math.clamp(cleanValue, 0.25, 3)
end

function AudioController:GetSensitivity(): number
	return sensitivity
end

function AudioController:GetFrame(): AudioFrame
	return currentFrame
end

function AudioController:GetMode(): AudioMode
	return mode
end

function AudioController:GetStatus(): string
	return status
end

function AudioController:SetStatus(nextStatus: string)
	setStatus(nextStatus)
end

function AudioController:OnFrameChanged(callback: (AudioFrame) -> ()): () -> ()
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

function AudioController:Destroy()
	maid:Cleanup()
	audioMaid:Cleanup()
end

return AudioController
