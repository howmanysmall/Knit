local FastEvent = {ClassName = "FastEvent"}
FastEvent.__index = FastEvent

function FastEvent.new(PreallocateSize: number?)
	return setmetatable(PreallocateSize and table.create(PreallocateSize) or {}, FastEvent)
end

function FastEvent.Is(Value)
	return type(Value) == "table" and getmetatable(Value) == FastEvent
end

local function Finish(Thread, Success, ...)
	if not Success then
		warn(debug.traceback(Thread, tostring((...))))
	end

	return Success, ...
end

function FastEvent:Fire(...)
	for _, Function in ipairs(self) do
		local Thread = coroutine.create(Function)
		Finish(Thread, coroutine.resume(Thread, ...))
	end
end

function FastEvent:Wait()
	local Thread = coroutine.running()

	local function Yield(...)
		local Index = table.find(self, Yield)
		if Index then
			local Length = #self
			self[Index] = self[Length]
			self[Length] = nil
		end

		Finish(Thread, coroutine.resume(Thread, ...))
	end

	table.insert(self, Yield)
	return coroutine.yield()
end

function FastEvent:Connect(Function)
	table.insert(self, Function)
end

function FastEvent:Disconnect(Function)
	local Index = table.find(self, Function)
	if Index then
		local Length = #self
		self[Index] = self[Length]
		self[Length] = nil
	end
end

function FastEvent:FireAndDestroy(...)
	self:Fire(...)
	self:Destroy()
end

function FastEvent:Destroy()
	table.clear(self)
	setmetatable(self, nil)
end

function FastEvent:__tostring()
	return "FastEvent"
end

return FastEvent
