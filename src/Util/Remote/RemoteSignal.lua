-- RemoteSignal
-- Stephen Leitnick
-- January 07, 2021

--[[

	remoteSignal = RemoteSignal.new()

	remoteSignal:Connect(handler: (player: Player, ...args: any) -> void): RBXScriptConnection
	remoteSignal:Fire(player: Player, ...args: any): void
	remoteSignal:FireAll(...args: any): void
	remoteSignal:FireExcept(player: Player, ...args: any): void
	remoteSignal:Wait(): (...any)
	remoteSignal:Destroy(): void

--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Ser = require(script.Parent.Parent.Ser)

local IS_SERVER = RunService:IsServer()

local Ser_DeserializeArgsAndUnpack = Ser.DeserializeArgsAndUnpack
local Ser_SerializeArgs = Ser.SerializeArgs
local Ser_SerializeArgsAndUnpack = Ser.SerializeArgsAndUnpack
local Ser_UnpackArgs = Ser.UnpackArgs

local RemoteSignal = {}
RemoteSignal.ClassName = "RemoteSignal"
RemoteSignal.__index = RemoteSignal

function RemoteSignal.Is(object)
	return type(object) == "table" and getmetatable(object) == RemoteSignal
end

function RemoteSignal.new()
	assert(IS_SERVER, "RemoteSignal can only be created on the server")
	return setmetatable({
		_remote = Instance.new("RemoteEvent");
	}, RemoteSignal)
end

function RemoteSignal:Fire(player, ...)
	self._remote:FireClient(player, Ser_SerializeArgsAndUnpack(...))
end

function RemoteSignal:FireAll(...)
	self._remote:FireAllClients(Ser_SerializeArgsAndUnpack(...))
end

function RemoteSignal:FireExcept(player, ...)
	local args = Ser_SerializeArgs(...)
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= player then
			self._remote:FireClient(plr, Ser_UnpackArgs(args))
		end
	end
end

function RemoteSignal:Wait()
	return self._remote.OnServerEvent:Wait()
end

function RemoteSignal:Connect(handler)
	return self._remote.OnServerEvent:Connect(function(player, ...)
		handler(player, Ser_DeserializeArgsAndUnpack(...))
	end)
end

function RemoteSignal:Destroy()
	self._remote:Destroy()
	self._remote = nil
	setmetatable(self, nil)
end

function RemoteSignal:__tostring()
	return "RemoteSignal"
end

return RemoteSignal
