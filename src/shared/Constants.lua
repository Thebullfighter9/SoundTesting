--!strict

local Constants = {
	REMOTES_FOLDER_NAME = "Remotes",
	BEAT_ORB_REMOTE_NAME = "BeatOrbRequested",
	LAB_FOLDER_NAME = "PulseForgeLab",
	VISUALIZER_BAND_COUNT = 32,
	MAX_ORBS_PER_PLAYER = 8,
	BEAT_ORB_COOLDOWN = 0.35,
	BEAT_ORB_LIFETIME = 12,
	MAX_ORB_ENERGY = 1,
	DEFAULT_SENSITIVITY = 1,
	DEFAULT_INTENSITY = 1,
	PRESETS = { "Bars", "Ring", "Orbit", "Physics", "Calm", "Chaos" },
}

return table.freeze(Constants)
