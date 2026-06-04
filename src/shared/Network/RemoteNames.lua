--!strict

local Constants = require(script.Parent.Parent.Constants)

local RemoteNames = {
	FieldPulseRequested = Constants.FIELD_PULSE_REMOTE_NAME,
}

return table.freeze(RemoteNames)
