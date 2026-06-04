--!strict

export type VisualizerPreset = "Field" | "Wave" | "Orbit" | "Still"
export type AudioMode = "Demo" | "Asset" | "Mic"
export type BandArray = { number }

export type AudioFrame = {
	rms: number,
	peak: number,
	bass: number,
	beat: boolean,
	bands: BandArray,
	time: number,
}

export type FieldPulsePayload = {
	intensity: number?,
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
