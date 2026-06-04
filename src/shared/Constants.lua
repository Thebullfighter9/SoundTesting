--!strict

local Constants = {
	REMOTES_FOLDER_NAME = "Remotes",
	FIELD_PULSE_REMOTE_NAME = "FieldPulseRequested",
	FIELD_FOLDER_NAME = "ResonanceField",
	FIELD_BAND_COUNT = 40,
	MAX_PULSES_PER_PLAYER = 6,
	FIELD_PULSE_COOLDOWN = 0.45,
	FIELD_PULSE_LIFETIME = 10,
	MAX_PULSE_INTENSITY = 1,
	DEFAULT_SENSITIVITY = 1,
	DEFAULT_INTENSITY = 1,
	PRESETS = { "Field", "Wave", "Orbit", "Still" },
}

return table.freeze(Constants)
