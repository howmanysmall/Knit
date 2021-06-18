local RunService = game:GetService("RunService")
local Heartbeat = RunService.Heartbeat

type GenericFunction = (any?) -> any?
type QueueFunction = BindableEvent | GenericFunction

local Queue = {}
local CurrentLength = 0
local Connection

local USE_DATE_TIME = false
local GetUnixTime
local TimeFunction = RunService:IsRunning() and time or os.clock

if USE_DATE_TIME then
	function GetUnixTime()
		return DateTime.now().UnixTimestampMillis / 1000
	end
else
	GetUnixTime = tick
end

local Scheduler = {}
Scheduler.GetUnixTime = GetUnixTime
Scheduler.TimeFunction = TimeFunction

local function HeartbeatStep()
	local ClockTick = TimeFunction()

	repeat
		local PossibleCurrent = Queue[1]
		if PossibleCurrent == nil then
			break
		end

		local Current = PossibleCurrent
		if Current.EndTime > ClockTick then
			break
		end

		local Done = CurrentLength == 1

		if Done then
			Queue[1] = nil
			CurrentLength = 0
			Connection = Connection:Disconnect()
		else
			local LastNode = Queue[CurrentLength]
			Queue[CurrentLength] = nil
			CurrentLength -= 1
			local TargetIndex = 1

			while true do
				local ChildIndex = 2 * TargetIndex
				if ChildIndex > CurrentLength then
					break
				end

				local MinChild = Queue[ChildIndex]
				local RightChildIndex = ChildIndex + 1

				if RightChildIndex <= CurrentLength then
					local RightChild = Queue[RightChildIndex]
					if RightChild.EndTime < MinChild.EndTime then
						ChildIndex = RightChildIndex
						MinChild = RightChild
					end
				end

				if LastNode.EndTime < MinChild.EndTime then
					break
				end

				Queue[TargetIndex] = MinChild
				TargetIndex = ChildIndex
			end

			Queue[TargetIndex] = LastNode
		end

		local Arguments = Current.Arguments
		local Function = Current.Function

		if typeof(Function) == "Instance" then
			if Arguments then
				(Function :: BindableEvent):Fire(table.unpack(Arguments, 2, Arguments[1]))
			else
				(Function :: BindableEvent):Fire(TimeFunction() - Current.StartTime)
			end
		else
			local BindableEvent = Instance.new("BindableEvent")

			if Arguments then
				BindableEvent.Event:Connect(function()
					BindableEvent:Destroy()
					Function(table.unpack(Arguments, 2, Arguments[1]))
				end)
			else
				BindableEvent.Event:Connect(function(...)
					BindableEvent:Destroy()
					Function(...)
				end)
			end

			BindableEvent:Fire(TimeFunction() - Current.StartTime)
		end
	until Done
end

--[[**
	"Overengineered" `delay` reimplementation that also allows calling with parameters. This should be significantly faster than the built-in `delay`.
	@param [t:number?] DelayTime The amount of time to delay for.
	@param [t:function] Function The function to call.
	@param [t:...any?] ... Optional arguments to call the function with.
	@returns [t:void]
**--]]
function Scheduler.Delay(Seconds: number?, Function: QueueFunction, ...)
	-- If seconds is nil, -INF, INF, NaN, or less than MINIMUM_DELAY, assume seconds is MINIMUM_DELAY.
	if Seconds == nil or Seconds <= 0 or Seconds == math.huge then
		Seconds = 0
	end

	local StartTime = TimeFunction()
	local EndTime = StartTime + Seconds
	local Length = select("#", ...)

	if Connection == nil then -- first is nil when connection is nil
		Connection = Heartbeat:Connect(HeartbeatStep)
	end

	local Node = {
		Arguments = Length > 0 and {Length + 1, ...} or nil;
		EndTime = EndTime;
		Function = Function;
		StartTime = StartTime;
	}

	local TargetIndex = CurrentLength + 1
	CurrentLength = TargetIndex

	while true do
		local ParentIndex = (TargetIndex - TargetIndex % 2) / 2
		if ParentIndex < 1 then
			break
		end

		local ParentNode = Queue[ParentIndex]
		if ParentNode.EndTime < Node.EndTime then
			break
		end

		Queue[TargetIndex] = ParentNode
		TargetIndex = ParentIndex
	end

	Queue[TargetIndex] = Node
end

local Scheduler_Delay = Scheduler.Delay

--[[**
	Overengineered `wait` reimplementation. Uses `Scheduler.Delay`.
	@param [t:number?] Seconds The amount of time to yield for. Defaults to 0.03.
	@returns [t:number] The actual time yielded.
**--]]
function Scheduler.Wait(Seconds: number?): number
	local BindableEvent = Instance.new("BindableEvent")
	Scheduler_Delay(math.max(Seconds or 0.03, 0.029), BindableEvent)
	return BindableEvent.Event:Wait()
end

--[[**
	A recreation of `spawn`, delay and all. This should in theory run better than the original spawn, as well as not using a garbage legacy scheduler. Use it Michal.
	@param [t:function] Function The function you are calling.
	@param [t:...any?] ... The optional arguments to call the function with.
	@returns [t:void]
**--]]
function Scheduler.Spawn(Function: QueueFunction, ...)
	local StartTime = TimeFunction()
	local EndTime = StartTime + 0.029
	local Length = select("#", ...)

	if Connection == nil then -- first is nil when connection is nil
		Connection = Heartbeat:Connect(HeartbeatStep)
	end

	local Node = {
		Arguments = Length > 0 and {Length + 1, ...} or nil;
		EndTime = EndTime;
		Function = Function;
		StartTime = StartTime;
	}

	local TargetIndex = CurrentLength + 1
	CurrentLength = TargetIndex

	while true do
		local ParentIndex = (TargetIndex - TargetIndex % 2) / 2
		if ParentIndex < 1 then
			break
		end

		local ParentNode = Queue[ParentIndex]
		if ParentNode.EndTime < Node.EndTime then
			break
		end

		Queue[TargetIndex] = ParentNode
		TargetIndex = ParentIndex
	end

	Queue[TargetIndex] = Node
end

-- @source https://devforum.roblox.com/t/psa-you-can-get-errors-and-stack-traces-from-coroutines/455510/2
local function Finish(Thread: thread, Success: boolean, ...)
	if not Success then
		warn(debug.traceback(Thread, tostring((...))))
	end

	return Success, ...
end

--[[**
	Spawns the passed function immediately using coroutines. This keeps the traceback as well, and warns if the function errors.
	@param [t:function] Function The function you are calling.
	@param [t:...any?] ... The optional arguments to call the function with.
	@returns [t:boolean,...any?] Whether or not the call was successful and the returned values.
**--]]
function Scheduler.ThreadSpawn(Function: GenericFunction, ...)
	local Thread = coroutine.create(Function)
	return Finish(Thread, coroutine.resume(Thread, ...))
end

--[[**
	Spawns the passed function immediately using a BindableEvent. This keeps the traceback as well, and will throw an error if the function errors.
	@param [t:function] Function The function you are calling.
	@param [t:...any?] ... The optional arguments to call the function with.
	@returns [t:void]
**--]]
function Scheduler.FastSpawn(Function: GenericFunction, ...)
	local Arguments = table.pack(...)
	local BindableEvent = Instance.new("BindableEvent")
	BindableEvent.Event:Connect(function()
		BindableEvent:Destroy()
		Function(table.unpack(Arguments, 1, Arguments.n))
	end)

	BindableEvent:Fire()
end

--[[**
	Spawns the passed function with a delay using Heartbeat. This keeps the traceback as well, and will throw an error if the function errors.
	@param [t:function] Function The function you are calling.
	@param [t:...any?] ... The optional arguments to call the function with.
	@returns [t:void]
**--]]
function Scheduler.HeartbeatSpawn(Function: GenericFunction, ...)
	local Length = select("#", ...)
	if Length > 0 then
		local Arguments = {...}
		local HeartbeatConnection

		HeartbeatConnection = Heartbeat:Connect(function()
			if HeartbeatConnection.Connected then
				HeartbeatConnection:Disconnect()
				Function(table.unpack(Arguments, 1, Length))
			end
		end)
	else
		local HeartbeatConnection
		HeartbeatConnection = Heartbeat:Connect(function()
			if HeartbeatConnection.Connected then
				HeartbeatConnection:Disconnect()
				Function()
			end
		end)
	end
end

return Scheduler
