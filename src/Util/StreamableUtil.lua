-- StreamableUtil
-- Stephen Leitnick
-- March 03, 2021

--[[

	StreamableUtil.Compound(observers: {Observer}, handler: ({[child: string]: Instance}, janitor: Janitor) -> void): Janitor

	Example:

		local streamable1 = Streamable.new(someModel, "SomeChild")
		local streamable2 = Streamable.new(anotherModel, "AnotherChild")

		StreamableUtil.Compound({S1 = streamable1, S2 = streamable2}, function(streamables, janitor)
			local someChild = streamables.S1.Instance
			local anotherChild = streamables.S2.Instance
			janitor:GiveTask(function()
				-- Cleanup
			end)
		end)

--]]

local Janitor = require(script.Parent.Janitor)

local StreamableUtil = {}

function StreamableUtil.Compound(streamables, handler)
	local compoundJanitor = Janitor.new()
	local observeAllJanitor = Janitor.new()
	local allAvailable = false
	local function Check()
		if allAvailable then
			return
		end

		for _, streamable in next, streamables do
			if not streamable.Instance then
				return
			end
		end

		allAvailable = true
		handler(streamables, observeAllJanitor)
	end

	local function Cleanup()
		if not allAvailable then
			return
		end

		allAvailable = false
		observeAllJanitor:Cleanup()
	end

	for _, streamable in next, streamables do
		compoundJanitor:Add(streamable:Observe(function(_, janitor)
			Check()
			janitor:Add(Cleanup, true)
		end), "Disconnect")
	end

	compoundJanitor:Add(Cleanup, true)
	return compoundJanitor
end

return StreamableUtil
