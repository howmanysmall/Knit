local SchedulerSafe = require(script.Safe)
local SchedulerUnsafe = require(script.Unsafe)
local SHOULD_USE_UNSAFE = false

return setmetatable({
	Safe = SchedulerSafe;
	Unsafe = SchedulerUnsafe;
}, {__index = SHOULD_USE_UNSAFE and SchedulerUnsafe or SchedulerSafe})
