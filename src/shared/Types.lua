--!strict

export type AudioMode = "Demo" | "Asset" | "Mic"
export type VisualStyle = "Grid" | "Row" | "Circle" | "All" | "Minimal"

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
	bands: { number },
	time: number,
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
