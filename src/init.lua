local RunService = game:GetService("RunService")
if RunService:IsServer() then
	return require(script.KnitServer)
else
	script.KnitServer:Destroy()
	return require(script.KnitClient)
end
