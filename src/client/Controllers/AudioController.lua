--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

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
type AnalyzerTruthMode = Types.AnalyzerTruthMode
type AudioDiagnostics = Types.AudioDiagnostics

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
local stopped = false
local currentAssetId: string? = Constants.DEFAULT_AUDIO_ASSET_ID
local analyzerTruthMode: AnalyzerTruthMode = "Silent"
local usingRealSpectrum = false
local spectrumBinCount = 0
local spectrumVariance = 0
local currentLoudness = 0
local fallbackReason: string? = nil
local demoReason = "Synthetic demo signal"
local diagnosticAccumulator = 0
local diagnosticFolder: Folder? = nil

local bandCount = Constants.AUDIO_BAND_COUNT or Constants.VISUAL_BAND_COUNT
local smoothedBands: { number } = table.create(bandCount, 0)
local previousBands: { number } = table.create(bandCount, 0)
local rollingBandPeaks: { number } = table.create(bandCount, 0.05)
local perBandAutoGain: { number } = table.create(bandCount, 1)
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
	audioMode = mode,
	analyzerTruthMode = analyzerTruthMode,
	usingRealSpectrum = usingRealSpectrum,
	spectrumBinCount = spectrumBinCount,
	spectrumVariance = spectrumVariance,
	loudness = currentLoudness,
	fallbackReason = fallbackReason,
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

local function getBandInterpolated(bands: { number }, normalizedIndex: number): number
	local count = #bands
	if count <= 0 then
		return 0
	end

	local cleanIndex = math.clamp(NumberUtil.sanitizeFiniteNumber(normalizedIndex, 0), 0, 1)
	local position = cleanIndex * (count - 1) + 1
	local lowerIndex = math.clamp(math.floor(position), 1, count)
	local upperIndex = math.clamp(lowerIndex + 1, 1, count)
	local alpha = position - lowerIndex
	local lower = clamp01(bands[lowerIndex] or 0)
	local upper = clamp01(bands[upperIndex] or lower)
	return lower + (upper - lower) * alpha
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

local function sanitizeSpectrumValue(value: any): number
	local clean = NumberUtil.sanitizeFiniteNumber(value, 0)
	if clean < 0 then
		clean = math.abs(clean)
	end
	if clean > 1 then
		clean /= 100
	end

	return math.clamp(clean, 0, 1)
end

local function computeSpectrumStats(spectrum: { [number]: any }): (number, number, boolean)
	local total = 0
	local totalSquares = 0
	local count = 0
	local maximum = 0

	for _, value in ipairs(spectrum) do
		local clean = sanitizeSpectrumValue(value)
		total += clean
		totalSquares += clean * clean
		maximum = math.max(maximum, clean)
		count += 1
	end

	if count <= 0 then
		return 0, 0, false
	end

	local mean = total / count
	local variance = math.max(0, totalSquares / count - mean * mean)
	local enoughBins = count >= (Constants.SPECTRUM_MIN_VALID_BINS or 8)
	local hasShape = variance >= (Constants.SPECTRUM_MIN_VARIANCE or 0.000001)
	return count, variance, enoughBins and hasShape and maximum > 0.000001
end

local function resampleSpectrum(spectrum: { [number]: any }): { number }
	local bands = table.create(bandCount, 0)
	local sourceCount = #spectrum

	for bandIndex = 1, bandCount do
		local startAlpha = ((bandIndex - 1) / bandCount) ^ 1.42
		local endAlpha = (bandIndex / bandCount) ^ 1.42
		local startIndex = math.max(1, math.floor(startAlpha * sourceCount) + 1)
		local endIndex = math.max(startIndex, math.floor(endAlpha * sourceCount))
		local total = 0
		local samples = 0

		for spectrumIndex = startIndex, endIndex do
			total += sanitizeSpectrumValue(spectrum[spectrumIndex])
			samples += 1
		end

		bands[bandIndex] = clamp01(if samples > 0 then total / samples else 0)
	end

	return bands
end

local function buildLoudnessBands(loudness: number, timeNow: number): { number }
	local bands = table.create(bandCount, 0)
	local energy = clamp01(loudness)
	local slowPhase = math.sin(timeNow * 2.1) * 0.18

	for index = 1, bandCount do
		local alpha = (index - 1) / math.max(1, bandCount - 1)
		local centered = 1 - math.abs(alpha - 0.5) * 2
		local wave = (math.sin(alpha * math.pi * 2.0 + slowPhase) + 1) * 0.5
		local silhouette = 0.22 + centered * 0.62 + wave * 0.16
		bands[index] = clamp01(energy * silhouette)
	end

	return bands
end

local function buildSilentBands(): { number }
	local bands = table.create(bandCount, 0)
	for index = 1, bandCount do
		bands[index] = 0
	end
	return bands
end

local function getDiagnosticFolder(): Folder?
	local folder = diagnosticFolder
	if folder ~= nil and folder.Parent ~= nil then
		return folder
	end

	local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
	if playerGui == nil then
		return nil
	end

	local existing = playerGui:FindFirstChild("ArrayWaveAudioDiagnostics")
	if existing ~= nil and existing:IsA("Folder") then
		diagnosticFolder = existing
		return existing
	end

	folder = InstanceUtil.create("Folder", {
		Name = "ArrayWaveAudioDiagnostics",
	}, playerGui) :: Folder
	diagnosticFolder = folder
	return folder
end

local function writeDiagnosticsTo(target: Instance)
	target:SetAttribute("AnalyzerTruthMode", analyzerTruthMode)
	target:SetAttribute("UsingRealSpectrum", usingRealSpectrum)
	target:SetAttribute("SpectrumBinCount", spectrumBinCount)
	target:SetAttribute("SpectrumVariance", spectrumVariance)
	target:SetAttribute("CurrentAssetId", currentAssetId)
	target:SetAttribute("AudioFallbackReason", fallbackReason)
	target:SetAttribute("CurrentAudioMode", mode)
	target:SetAttribute("CurrentLoudness", currentLoudness)
end

local function updateDiagnosticAttributes(deltaTime: number)
	diagnosticAccumulator += deltaTime
	if diagnosticAccumulator < (Constants.AUDIO_DIAGNOSTIC_ATTRIBUTE_INTERVAL or 0.35) then
		return
	end

	diagnosticAccumulator = 0
	local root = Workspace:FindFirstChild(Constants.CLIENT_VISUALS_FOLDER_NAME)
	if root ~= nil then
		writeDiagnosticsTo(root)
	end

	local folder = getDiagnosticFolder()
	if folder ~= nil then
		writeDiagnosticsTo(folder)
	end
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

local function applyAnalysis(
	rawBands: { number },
	rawRms: number,
	rawPeak: number,
	deltaTime: number,
	truthMode: AnalyzerTruthMode,
	sourceBinCount: number,
	sourceVariance: number,
	loudness: number,
	reason: string?
)
	local now = os.clock()
	local cleanDelta = math.clamp(NumberUtil.sanitizeFiniteNumber(deltaTime, 1 / 60), 1 / 240, 0.2)
	local sanitizedRms = clamp01(rawRms)
	local sanitizedPeak = clamp01(math.max(rawPeak, sanitizedRms))
	local sanitizedLoudness = clamp01(loudness)
	local rawBandEnergy = 0
	local fluxTotal = 0
	local centroidNumerator = 0
	local energyTotal = 0

	analyzerTruthMode = truthMode
	usingRealSpectrum = truthMode == "Spectrum"
	spectrumBinCount = math.max(0, math.floor(NumberUtil.sanitizeFiniteNumber(sourceBinCount, 0)))
	spectrumVariance = math.max(0, NumberUtil.sanitizeFiniteNumber(sourceVariance, 0))
	currentLoudness = sanitizedLoudness
	fallbackReason = reason

	for index = 1, bandCount do
		rawBandEnergy += clamp01(rawBands[index] or 0)
	end
	rawBandEnergy /= math.max(1, bandCount)

	local rawInputEnergy = math.max(sanitizedPeak, sanitizedRms, rawBandEnergy)
	local audible = rawInputEnergy > 0.006
	local inputPeak = if audible then math.max(rawInputEnergy, Constants.MIN_VISIBLE_ENERGY) else rawInputEnergy
	local peakSpeed = if inputPeak > rollingPeak then 16 else 0.85
	local rmsSpeed = if sanitizedRms > rollingRms then 10 else 0.65
	rollingPeak = NumberUtil.expSmooth(rollingPeak, inputPeak, cleanDelta, peakSpeed)
	rollingRms = NumberUtil.expSmooth(rollingRms, math.max(sanitizedRms, rawBandEnergy), cleanDelta, rmsSpeed)

	local gainBase = math.max(rollingPeak * 0.78 + rollingRms * 0.22, Constants.MIN_VISIBLE_ENERGY)
	local targetGain = math.clamp(0.68 / gainBase, 1, Constants.MAX_VISUAL_GAIN)
	autoGain = NumberUtil.expSmooth(autoGain, targetGain, cleanDelta, if targetGain > autoGain then 3.5 else 0.9)

	local function normalizeForVisual(value: number, gain: number, curve: number): number
		local gained = math.clamp(value * sensitivity * autoGain * gain, 0, 10)
		return clamp01(1 - math.exp(-gained * curve))
	end

	for index = 1, bandCount do
		local alpha = (index - 1) / math.max(1, bandCount - 1)
		local raw = clamp01(rawBands[index] or 0)
		local peakMemory = rollingBandPeaks[index] or 0.05
		local peakSpeed = if raw > peakMemory then 12 else 0.42
		peakMemory = NumberUtil.expSmooth(peakMemory, math.max(raw, Constants.MIN_VISIBLE_ENERGY * 0.18), cleanDelta, peakSpeed)
		rollingBandPeaks[index] = peakMemory

		local targetBandGain = math.clamp(0.36 / math.max(peakMemory, Constants.MIN_VISIBLE_ENERGY * 0.22), 0.85, Constants.MAX_VISUAL_GAIN * 1.25)
		local bandGain = perBandAutoGain[index] or 1
		bandGain = NumberUtil.expSmooth(bandGain, targetBandGain, cleanDelta, if targetBandGain > bandGain then 1.7 else 0.48)
		perBandAutoGain[index] = bandGain

		local curve = 2.15 + (1 - alpha) * 0.34 + alpha * 0.28
		local target = normalizeForVisual(raw, bandGain, curve)
		if rawInputEnergy > 0.02 then
			local visualFloor = Constants.MIN_VISIBLE_ENERGY * (0.08 + alpha * 0.06) * math.clamp(rollingRms * 7, 0, 1)
			target = math.max(target, visualFloor)
		end

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
	local normalizedRms = normalizeForVisual(sanitizedRms, 1, 2.4)
	local normalizedPeak = normalizeForVisual(sanitizedPeak, 1, 2.4)
	local energyFloor = if audible then Constants.MIN_VISIBLE_ENERGY * 0.65 else 0
	local rms = clamp01(math.max(normalizedRms, bandEnergy * 0.82, bass * 0.42, energyFloor))
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
		audioMode = mode,
		analyzerTruthMode = analyzerTruthMode,
		usingRealSpectrum = usingRealSpectrum,
		spectrumBinCount = spectrumBinCount,
		spectrumVariance = spectrumVariance,
		loudness = currentLoudness,
		fallbackReason = fallbackReason,
	}

	notifyFrameChanged()
end

local function readAnalyzerFrame(analyzer: AudioAnalyzer, deltaTime: number)
	local rms = clamp01(readNumberProperty(analyzer, "RmsLevel", 0))
	local peak = clamp01(readNumberProperty(analyzer, "PeakLevel", rms))
	local spectrum: { any } = {}
	local spectrumReason = "Analyzer spectrum unavailable"

	local okSpectrum, spectrumValues = pcall(function()
		return analyzer:GetSpectrum()
	end)
	if okSpectrum and typeof(spectrumValues) == "table" then
		spectrum = spectrumValues :: { any }
		spectrumReason = "Analyzer spectrum flat"
	end

	local binCount, variance, validSpectrum = computeSpectrumStats(spectrum)
	if validSpectrum then
		applyAnalysis(resampleSpectrum(spectrum), rms, peak, deltaTime, "Spectrum", binCount, variance, math.max(rms, peak), nil)
		return
	end

	local loudness = math.max(rms, peak)
	if loudness > 0.006 then
		applyAnalysis(buildLoudnessBands(loudness, os.clock()), rms, peak, deltaTime, "LoudnessOnly", binCount, variance, loudness, spectrumReason)
	else
		applyAnalysis(buildSilentBands(), 0, 0, deltaTime, "Silent", binCount, variance, 0, spectrumReason)
	end
end

local function readClassicSoundFrame(sound: Sound, deltaTime: number)
	local loudness = clamp01(readNumberProperty(sound, "PlaybackLoudness", 0) / 900)
	local peak = clamp01(loudness * 1.2)
	if loudness > 0.006 then
		applyAnalysis(buildLoudnessBands(loudness, os.clock()), loudness, peak, deltaTime, "LoudnessOnly", 0, 0, loudness, "PlaybackLoudness only")
	else
		applyAnalysis(buildSilentBands(), 0, 0, deltaTime, "Silent", 0, 0, 0, "PlaybackLoudness only")
	end
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
			stopped = false
			demoReason = unavailableStatus
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
		stopped = false
		currentAssetId = nil
		demoReason = invalidStatus
		setStatus(invalidStatus)
		return false
	end

	setStatus(tryingStatus)
	local attemptId = nextAudioAttempt()
	stopped = false
	currentAssetId = assetId
	fallbackReason = nil

	if tryModularAsset(assetId, unavailableStatus, attemptId) or tryClassicSound(assetId, unavailableStatus, attemptId) then
		mode = "Asset"
		setStatus(readyStatus)
		return true
	end

	stopAudioGraph()
	mode = "Demo"
	stopped = false
	demoReason = unavailableStatus
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
			stopped = false
			currentAssetId = nil
			demoReason = "Mic unavailable - using demo signal"
			setStatus("Mic unavailable - using demo signal")
		end
	end)
	audioMaid:Give(thread)

	return true
end

function AudioController:_ApplyRawFrame(rawBands: { number }, rawRms: number, rawPeak: number, _rawBass: number, deltaTime: number)
	local binCount, variance, validSpectrum = computeSpectrumStats(rawBands)
	local truthMode: AnalyzerTruthMode = if validSpectrum then "Spectrum" else "LoudnessOnly"
	local reason = if validSpectrum then nil else "Injected frame without shaped spectrum"
	applyAnalysis(rawBands, rawRms, rawPeak, deltaTime, truthMode, binCount, variance, math.max(rawRms, rawPeak), reason)
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
	local traveling = (math.sin(t * math.pi * 2 * 0.36) + 1) * 0.5

	for index = 1, bandCount do
		local alpha = (index - 1) / math.max(1, bandCount - 1)
		local noise = (math.noise(t * 0.65, alpha * 8, 0.15) + 1) * 0.5
		local motion = (math.sin(t * (2.4 + alpha * 5.8) + alpha * math.pi * 9) + 1) * 0.5
		local comb = (math.sin(t * (3.6 + alpha * 6.2) - alpha * math.pi * 14 + traveling * 2.2) + 1) * 0.5
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
			+ motion * noise * (0.07 + alpha * 0.08)
			+ comb * (lowMidShape * 0.06 + midShape * 0.08 + highShape * 0.04)

		bands[index] = clamp01(value)
	end

	local rms = clamp01(0.12 + groove * 0.08 + bassSwell * 0.13 + kickPulse * 0.42 + snarePulse * 0.12 + hatPulse * 0.06)
	local peak = clamp01(rms + kickPulse * 0.34 + snarePulse * 0.18 + hatPulse * 0.12)
	local _, variance = computeSpectrumStats(bands)
	applyAnalysis(bands, rms, peak, deltaTime, "Demo", #bands, variance, math.max(rms, peak), demoReason)
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
		if stopped then
			applyAnalysis(buildSilentBands(), 0, 0, deltaTime, "Silent", 0, 0, 0, "Stopped")
		elseif mode == "Demo" then
			self:_GenerateDemoFrame(deltaTime)
		elseif mode == "Asset" then
			if assetAnalyzer ~= nil then
				readAnalyzerFrame(assetAnalyzer, deltaTime)
			elseif classicSound ~= nil then
				readClassicSoundFrame(classicSound, deltaTime)
			else
				mode = "Demo"
				demoReason = "Audio graph unavailable - using demo signal"
				setStatus("Audio graph unavailable - using demo signal")
				self:_GenerateDemoFrame(deltaTime)
			end
		elseif mode == "Mic" then
			if micAnalyzer ~= nil then
				readAnalyzerFrame(micAnalyzer, deltaTime)
			else
				mode = "Demo"
				currentAssetId = nil
				demoReason = "Mic unavailable - using demo signal"
				setStatus("Mic unavailable - using demo signal")
				self:_GenerateDemoFrame(deltaTime)
			end
		end

		updateDiagnosticAttributes(deltaTime)
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
		stopped = false
		currentAssetId = nil
		demoReason = "Synthetic demo signal"
		setStatus("Demo signal active")
	elseif nextMode == "Asset" then
		stopped = false
		setStatus("Enter an audio asset id")
	elseif nextMode == "Mic" then
		local attemptId = nextAudioAttempt()
		stopAudioGraph()
		stopped = false
		currentAssetId = nil
		demoReason = "Mic unavailable - using demo signal"
		setStatus("Trying mic input")
		if tryMicInput(attemptId) then
			mode = "Mic"
			setStatus("Mic mode active")
		else
			mode = "Demo"
			demoReason = "Mic unavailable - using demo signal"
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
	stopped = true
	currentAssetId = nil
	setStatus("Stopped")
	applyAnalysis(buildSilentBands(), 0, 0, 1 / 60, "Silent", 0, 0, 0, "Stopped")
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

function AudioController:GetDiagnostics(): AudioDiagnostics
	return {
		audioMode = mode,
		analyzerTruthMode = analyzerTruthMode,
		assetId = currentAssetId,
		usingRealSpectrum = usingRealSpectrum,
		spectrumBinCount = spectrumBinCount,
		spectrumVariance = spectrumVariance,
		loudness = currentLoudness,
		rms = currentFrame.rms,
		peak = currentFrame.peak,
		fallbackReason = fallbackReason,
	}
end

function AudioController:GetSpectrumSnapshot(): { number }
	local snapshot = table.create(#smoothedBands, 0)
	for index, value in ipairs(smoothedBands) do
		snapshot[index] = value
	end
	return snapshot
end

function AudioController:GetBandInterpolated(normalizedIndex: number): number
	return getBandInterpolated(currentFrame.bands, normalizedIndex)
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
