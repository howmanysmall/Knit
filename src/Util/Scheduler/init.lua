local SHOULD_USE_UNSAFE = false
return SHOULD_USE_UNSAFE and require(script.Unsafe) or require(script.Safe)
