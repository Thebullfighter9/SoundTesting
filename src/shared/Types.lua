--!strict

export type AudioMode = "Demo" | "Asset" | "Mic"
export type VisualStyle = "Field" | "Orbit" | "Marbles" | "Minimal"

export type AudioFrame = {
	rms: number,
	peak: number,
	bass: number,
	beat: boolean,
	bands: BandArray,
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
