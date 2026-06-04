--!strict

local Constants = require(script.Parent.Parent.Constants)

local RemoteNames = {
	BeatOrbRequested = Constants.BEAT_ORB_REMOTE_NAME,
}

return table.freeze(RemoteNames)
