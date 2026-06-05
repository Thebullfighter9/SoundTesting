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
local shortEnvelope = 0.08
local longEnvelope = 0.08
local beatThreshold = 0.22
local rollingPeak = 0.18
local rollingRms = 0.12
local autoGain = 1
local lastBeatTime = 0
local audioAttemptSerial = 0
local assetAnalyzer: AudioAnalyzer? = nil
local micAnalyzer: AudioAnalyzer? = nil
local classicSound: Sound? = nil

local bandCount = Constants.AUDIO_BAND_COUNT or Constants.VISUAL_BAND_COUNT
local smoothedBands: { number } = table.create(bandCount, 0)
local previousBands: { number } = table.create(bandCount, 0)
local currentFrame: AudioFrame = {
	rms = 0,
	peak = 0,
	bass = 0,
	lowMid = 0,
	mid = 0,
	high = 0,
	air = 0,
	beat = false,
	beatStrength = 0,
	transient = 0,
	spectralFlux = 0,
	centroid = 0,
	visualEnergy = 0,
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

local function clamp01(value: any): number
	return math.clamp(NumberUtil.sanitizeFiniteNumber(value, 0), 0, 1)
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
		Name = "ArrayWaveAudio",
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

local function createWire(parent: Instance, source: Instance, target: Instance): boolean
	return pcall(function()
		InstanceUtil.create("Wire", {
			Name = `{source.Name}_To_{target.Name}`,
			SourceInstance = source,
			SourceName = "Output",
			TargetInstance = target,
			TargetName = "Input",
		}, parent)
	end)
end

local function resampleSpectrum(spectrum: { any }, rms: number, peak: number, timeNow: number): { number }
	local bands = table.create(bandCount, 0)
	local sourceCount = #spectrum

	if sourceCount == 0 then
		local energy = math.max(rms, peak * 0.78, 0.05)
		for index = 1, bandCount do
			local alpha = (index - 1) / math.max(1, bandCount - 1)
			local slow = (math.sin(timeNow * 2.4 + alpha * math.pi * 4.8) + 1) * 0.5
			local highPulse = (math.sin(timeNow * 12.5 + alpha * math.pi * 22) + 1) * 0.5
			local bassShape = math.max(0, 1 - alpha * 3.2)
			bands[index] = clamp01(energy * (0.22 + slow * 0.28 + highPulse * alpha * 0.16 + bassShape * 0.42))
		end
		return bands
	end

	for bandIndex = 1, bandCount do
		local startIndex = math.max(1, math.floor((bandIndex - 1) / bandCount * sourceCount) + 1)
		local endIndex = math.max(startIndex, math.floor(bandIndex / bandCount * sourceCount))
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

		bands[bandIndex] = clamp01(if samples > 0 then total / samples else 0)
	end

	return bands
end

local function averageRange(bands: { number }, startAlpha: number, endAlpha: number): number
	local first = math.max(1, math.floor(startAlpha * bandCount) + 1)
	local last = math.clamp(math.floor(endAlpha * bandCount), first, bandCount)
	local total = 0
	local samples = 0

	for index = first, last do
		total += clamp01(bands[index] or 0)
		samples += 1
	end

	return if samples > 0 then total / samples else 0
end

local function applyAnalysis(rawBands: { number }, rawRms: number, rawPeak: number, deltaTime: number)
	local now = os.clock()
	local cleanDelta = math.clamp(NumberUtil.sanitizeFiniteNumber(deltaTime, 1 / 60), 1 / 240, 0.2)
	local sanitizedRms = clamp01(rawRms)
	local sanitizedPeak = clamp01(math.max(rawPeak, sanitizedRms))
	local rawBandEnergy = 0
	local fluxTotal = 0
	local centroidNumerator = 0
	local energyTotal = 0

	for index = 1, bandCount do
		rawBandEnergy += clamp01(rawBands[index] or 0)
	end
	rawBandEnergy /= math.max(1, bandCount)

	local inputPeak = math.max(sanitizedPeak, sanitizedRms, rawBandEnergy, Constants.MIN_VISIBLE_ENERGY)
	local peakSpeed = if inputPeak > rollingPeak then 16 else 0.85
	local rmsSpeed = if sanitizedRms > rollingRms then 10 else 0.65
	rollingPeak = NumberUtil.expSmooth(rollingPeak, inputPeak, cleanDelta, peakSpeed)
	rollingRms = NumberUtil.expSmooth(rollingRms, math.max(sanitizedRms, rawBandEnergy), cleanDelta, rmsSpeed)

	local gainBase = math.max(rollingPeak * 0.78 + rollingRms * 0.22, Constants.MIN_VISIBLE_ENERGY)
	local targetGain = math.clamp(0.68 / gainBase, 1, Constants.MAX_VISUAL_GAIN)
	autoGain = NumberUtil.expSmooth(autoGain, targetGain, cleanDelta, if targetGain > autoGain then 3.5 else 0.9)

	local function normalizeForVisual(value: number): number
		local gained = math.clamp(value * sensitivity * autoGain, 0, 8)
		return clamp01(1 - math.exp(-gained * 2.4))
	end

	for index = 1, bandCount do
		local alpha = (index - 1) / math.max(1, bandCount - 1)
		local target = normalizeForVisual(clamp01(rawBands[index] or 0))
		local current = smoothedBands[index] or 0
		local attack = 20 - alpha * 8
		local release = 3.8 + alpha * 5.5
		local speed = if target > current then attack else release
		if alpha < 0.18 then
			speed *= 0.72
		elseif alpha > 0.72 then
			speed *= 1.24
		end

		local nextValue = NumberUtil.expSmooth(current, target, cleanDelta, speed)
		smoothedBands[index] = nextValue
		fluxTotal += math.max(0, nextValue - (previousBands[index] or 0))
		previousBands[index] = nextValue
		centroidNumerator += nextValue * alpha
		energyTotal += nextValue
	end

	local bass = averageRange(smoothedBands, 0, 0.14)
	local lowMid = averageRange(smoothedBands, 0.14, 0.34)
	local mid = averageRange(smoothedBands, 0.34, 0.62)
	local high = averageRange(smoothedBands, 0.62, 0.84)
	local air = averageRange(smoothedBands, 0.84, 1)
	local bandEnergy = math.clamp(energyTotal / math.max(1, bandCount), 0, 1)
	local normalizedRms = normalizeForVisual(sanitizedRms)
	local normalizedPeak = normalizeForVisual(sanitizedPeak)
	local rms = clamp01(math.max(normalizedRms, bandEnergy * 0.82, bass * 0.42, Constants.MIN_VISIBLE_ENERGY * 0.65))
	local peak = clamp01(math.max(normalizedPeak, rms, bass * 0.95, high * 0.76))
	local centroid = if energyTotal > 0.0001 then math.clamp(centroidNumerator / energyTotal, 0, 1) else 0
	local spectralFlux = math.clamp(fluxTotal / math.max(1, bandCount) * 8, 0, 1)
	local visualEnergy = clamp01(math.max(rms, peak * 0.88, bandEnergy, bass * 0.9))

	shortEnvelope = NumberUtil.expSmooth(shortEnvelope, math.max(peak, bass, spectralFlux * 0.9), cleanDelta, 20)
	longEnvelope = NumberUtil.expSmooth(longEnvelope, math.max(rms, bandEnergy), cleanDelta, 1.3)
	local transient = math.clamp((shortEnvelope - longEnvelope) * 3.4, 0, 1)
	beatThreshold = NumberUtil.expSmooth(beatThreshold, math.clamp(longEnvelope + 0.11 + spectralFlux * 0.1, 0.13, 0.58), cleanDelta, 1.6)

	local beatScore = math.max(transient * 1.05 + spectralFlux * 0.72, bass * 0.52 + peak * 0.34)
	local beat = false
	local beatStrength = 0
	if beatScore > beatThreshold and now - lastBeatTime > 0.18 then
		beat = true
		beatStrength = math.clamp((beatScore - beatThreshold) / math.max(0.08, 1 - beatThreshold) * 1.55, 0.35, 1)
		lastBeatTime = now
	end

	currentFrame = {
		rms = rms,
		peak = peak,
		bass = clamp01(bass),
		lowMid = clamp01(lowMid),
		mid = clamp01(mid),
		high = clamp01(high),
		air = clamp01(air),
		beat = beat,
		beatStrength = beatStrength,
		transient = transient,
		spectralFlux = spectralFlux,
		centroid = centroid,
		visualEnergy = visualEnergy,
		bands = smoothedBands,
		time = now,
	}

	notifyFrameChanged()
end

local function readAnalyzerFrame(analyzer: AudioAnalyzer, deltaTime: number)
	local rms = clamp01(readNumberProperty(analyzer, "RmsLevel", 0))
	local peak = clamp01(readNumberProperty(analyzer, "PeakLevel", rms))
	local spectrum: { any } = {}

	local okSpectrum, spectrumValues = pcall(function()
		return analyzer:GetSpectrum()
	end)
	if okSpectrum and typeof(spectrumValues) == "table" then
		spectrum = spectrumValues :: { any }
	end

	applyAnalysis(resampleSpectrum(spectrum, rms, peak, os.clock()), rms, peak, deltaTime)
end

local function readClassicSoundFrame(sound: Sound, deltaTime: number)
	local loudness = clamp01(readNumberProperty(sound, "PlaybackLoudness", 0) / 900)
	local peak = clamp01(loudness * 1.2)
	applyAnalysis(resampleSpectrum({}, loudness, peak, os.clock()), loudness, peak, deltaTime)
end

local function scheduleAssetReadinessCheck(readReady: () -> boolean, unavailableStatus: string, attemptId: number)
	local thread = task.spawn(function()
		for _ = 1, 4 do
			task.wait(0.75)
			if mode ~= "Asset" or not isCurrentAttempt(attemptId) then
				return
			end

			if readReady() or currentFrame.peak > 0.025 or currentFrame.spectralFlux > 0.025 then
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
		audioPlayer.Volume = 0.58
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
			createWire(folder, audioPlayer, output)
		end

		assetAnalyzer = analyzer
		pcall(function()
			audioPlayer:Play()
		end)

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
		sound.Volume = 0.58
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

function AudioController:_ApplyRawFrame(rawBands: { number }, rawRms: number, rawPeak: number, _rawBass: number, deltaTime: number)
	applyAnalysis(rawBands, rawRms, rawPeak, deltaTime)
end

function AudioController:_GenerateDemoFrame(deltaTime: number)
	demoTime += deltaTime

	local t = demoTime
	local bands = table.create(bandCount, 0)
	local kickPulse = math.max(0, math.sin(t * math.pi * 2 * 1.08)) ^ 7
	local snarePulse = math.max(0, math.sin(t * math.pi * 2 * 0.54 + math.pi * 0.85)) ^ 10
	local hatPulse = math.max(0, math.sin(t * math.pi * 2 * 4.35 + 0.4)) ^ 8
	local groove = (math.sin(t * math.pi * 2 * 0.18) + 1) * 0.5
	local bassSwell = (math.sin(t * math.pi * 2 * 0.27 + 0.3) + 1) * 0.5

	for index = 1, bandCount do
		local alpha = (index - 1) / math.max(1, bandCount - 1)
		local noise = (math.noise(t * 0.65, alpha * 8, 0.15) + 1) * 0.5
		local motion = (math.sin(t * (2.4 + alpha * 5.8) + alpha * math.pi * 9) + 1) * 0.5
		local bassShape = math.max(0, 1 - alpha * 4.4)
		local lowMidShape = math.max(0, 1 - math.abs(alpha - 0.25) * 5)
		local midShape = math.max(0, 1 - math.abs(alpha - 0.48) * 4)
		local highShape = math.max(0, 1 - math.abs(alpha - 0.76) * 4.8)
		local airShape = alpha ^ 4
		local value = 0.025
			+ groove * 0.04
			+ bassSwell * bassShape * 0.2
			+ kickPulse * bassShape * 0.92
			+ kickPulse * lowMidShape * 0.22
			+ snarePulse * (midShape * 0.52 + highShape * 0.2)
			+ hatPulse * (highShape * 0.38 + airShape * 0.32)
			+ motion * noise * (0.08 + alpha * 0.1)

		bands[index] = clamp01(value)
	end

	local rms = clamp01(0.12 + groove * 0.08 + bassSwell * 0.13 + kickPulse * 0.42 + snarePulse * 0.12 + hatPulse * 0.06)
	local peak = clamp01(rms + kickPulse * 0.34 + snarePulse * 0.18 + hatPulse * 0.12)
	applyAnalysis(bands, rms, peak, deltaTime)
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
