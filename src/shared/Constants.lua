--!strict

local Constants = {
	REMOTES_FOLDER_NAME = "Remotes",
	MARBLE_REMOTE_NAME = "MarbleRequested",
	GALLERY_FOLDER_NAME = "ResonanceGallery",
	STATIC_FOLDER_NAME = "Static",
	ANCHORS_FOLDER_NAME = "Anchors",
	MARBLES_FOLDER_NAME = "Marbles",
	SPAWN_FOLDER_NAME = "Spawn",
	VISUAL_BAND_COUNT = 32,
	FIELD_GRID_SIZE = 17,
	MARBLE_COOLDOWN = 0.45,
	MAX_MARBLES_PER_PLAYER = 6,
	MARBLE_LIFETIME = 12,
	MAX_MARBLE_ENERGY = 1,
	DEFAULT_SENSITIVITY = 1,
	DEFAULT_INTENSITY = 1,
	UI_PANEL_WIDTH = 300,
	UI_PANEL_MAX_WIDTH_SCALE = 0.2,
	VISUAL_STYLES = { "Field", "Orbit", "Marbles", "Minimal" },
	PALETTE = {
		Background = Color3.fromRGB(10, 11, 12),
		Charcoal = Color3.fromRGB(18, 20, 21),
		Graphite = Color3.fromRGB(34, 37, 38),
		SoftWhite = Color3.fromRGB(220, 228, 224),
		Cyan = Color3.fromRGB(104, 190, 194),
		Amber = Color3.fromRGB(212, 180, 116),
	},
}

return table.freeze(Constants)
