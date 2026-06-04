--!strict

type CleanupTask = RBXScriptConnection | Instance | (() -> ()) | thread | any

local Maid = {}
Maid.__index = Maid

export type Maid = typeof(setmetatable({} :: {
	_tasks: { CleanupTask },
}, Maid))

function Maid.new(): Maid
	return setmetatable({
		_tasks = {},
	}, Maid)
end

function Maid:Give(taskValue: CleanupTask): CleanupTask
	table.insert(self._tasks, taskValue)
	return taskValue
end

function Maid:Cleanup()
	local tasks = self._tasks
	self._tasks = {}

	for index = #tasks, 1, -1 do
		local taskValue = tasks[index]
		local taskType = typeof(taskValue)

		if taskType == "RBXScriptConnection" then
			local connection = taskValue :: RBXScriptConnection
			if connection.Connected then
				connection:Disconnect()
			end
		elseif taskType == "Instance" then
			(taskValue :: Instance):Destroy()
		elseif taskType == "function" then
			(taskValue :: () -> ())()
		elseif taskType == "thread" then
			pcall(task.cancel, taskValue :: thread)
		elseif taskType == "table" then
			local cleanupTarget = taskValue :: any
			if typeof(cleanupTarget.Destroy) == "function" then
				cleanupTarget:Destroy()
			elseif typeof(cleanupTarget.Cleanup) == "function" then
				cleanupTarget:Cleanup()
			end
		end
	end
end

function Maid:Destroy()
	self:Cleanup()
end

return Maid
