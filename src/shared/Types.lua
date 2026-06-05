--!strict

export type AudioMode = "Demo" | "Asset" | "Mic"
export type AnalyzerTruthMode = "Spectrum" | "LoudnessOnly" | "Demo" | "Silent"
export type VisualStyle = "Grid" | "Row" | "Circle" | "All" | "Minimal"
export type CameraMode = "Auto" | "Still" | "Wide" | "Close"

export type AudioFrame = {
	rms: number,
	peak: number,
	bass: number,
	lowMid: number,
	mid: number,
	high: number,
	air: number,
	beat: boolean,
	beatStrength: number,
	transient: number,
	spectralFlux: number,
	centroid: number,
	visualEnergy: number,
	bands: { number },
	time: number,
	audioMode: AudioMode,
	analyzerTruthMode: AnalyzerTruthMode,
	usingRealSpectrum: boolean,
	spectrumBinCount: number,
	spectrumVariance: number,
	loudness: number,
	fallbackReason: string?,
}

export type AudioDiagnostics = {
	audioMode: AudioMode,
	analyzerTruthMode: AnalyzerTruthMode,
	assetId: string?,
	usingRealSpectrum: boolean,
	spectrumBinCount: number,
	spectrumVariance: number,
	loudness: number,
	rms: number,
	peak: number,
	fallbackReason: string?,
}

export type VisualStats = {
	gridParts: number,
	rowBars: number,
	circleBars: number,
	rowHeightVariance: number,
	circleLengthVariance: number,
	gridHeightVariance: number,
	activeSprays: number,
	activeShockwaves: number,
	maxRecentGridJump: number,
	lastBeatStrength: number,
	rowSpectrumCorrelation: number,
	analyzerTruthMode: AnalyzerTruthMode,
	usingRealSpectrum: boolean,
	spectrumBinCount: number,
	spectrumVariance: number,
}

export type MarblePayload = {
	energy: number?,
}

export type Controller = {
	Init: (self: Controller, context: any) -> (),
	Start: (self: Controller) -> (),
}

export type Service = {
	Init: (self: Service, context: any?) -> (),
	Start: (self: Service) -> (),
}

return {}
