local SchedulerSafe = require(script.Safe)
local SchedulerUnsafe = require(script.Unsafe)
local SHOULD_USE_UNSAFE = false

return setmetatable({
	Safe = SchedulerSafe;
	Unsafe = SchedulerUnsafe;
}, SHOULD_USE_UNSAFE and {__index = SchedulerUnsafe} or {__index = SchedulerSafe})
