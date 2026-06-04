--!strict

local Constants = require(script.Parent.Parent.Constants)

local RemoteNames = {
	MarbleRequested = Constants.MARBLE_REMOTE_NAME,
}

return table.freeze(RemoteNames)
