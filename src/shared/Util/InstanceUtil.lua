--!strict

local InstanceUtil = {}

function InstanceUtil.create(className: string, props: { [string]: any }?, parent: Instance?): Instance
	local instance = Instance.new(className)
	local explicitParent: Instance? = parent

	if props ~= nil then
		for key, value in pairs(props) do
			if key == "Parent" then
				explicitParent = value
			else
				(instance :: any)[key] = value
			end
		end
	end

	if explicitParent ~= nil then
		instance.Parent = explicitParent
	end

	return instance
end

return table.freeze(InstanceUtil)
