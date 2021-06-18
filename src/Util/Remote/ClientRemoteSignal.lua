-- ClientRemoteSignal
-- Stephen Leitnick
-- January 07, 2021

--[[

	remoteSignal = ClientRemoteSignal.new(remoteEvent: RemoteEvent)

	remoteSignal:Connect(handler: (...args: any)): Connection
	remoteSignal:Fire(...args: any): void
	remoteSignal:Wait(): (...any)
	remoteSignal:Destroy(): void

--]]

local RunService = game:GetService("RunService")
local Ser = require(script.Parent.Parent.Ser)
local IS_SERVER = RunService:IsServer()

--------------------------------------------------------------
-- Connection

local Connection = {}
Connection.ClassName = "Connection"
Connection.__index = Connection

function Connection.new(event, connection)
	return setmetatable({
		_conn = connection;
		_event = event;
		Connected = true;
	}, Connection)
end

function Connection:IsConnected()
	if self._conn then
		return self._conn.Connected
	end

	return false
end

function Connection:Disconnect()
	if self._conn then
		self._conn:Disconnect()
		self._conn = nil
	end

	if not self._event then
		return
	end

	self.Connected = false
	local connections = self._event._connections
	local i = table.find(connections, self)
	if i then
		local n = #connections
		connections[i] = connections[n]
		connections[n] = nil
	end

	self._event = nil
	setmetatable(self, nil)
end

Connection.Destroy = Connection.Disconnect

function Connection:__tostring()
	return "Connection"
end

-- End Connection
--------------------------------------------------------------
-- ClientRemoteSignal

local ClientRemoteSignal = {}
ClientRemoteSignal.ClassName = "ClientRemoteSignal"
ClientRemoteSignal.__index = ClientRemoteSignal

local Ser_SerializeArgsAndUnpack = Ser.SerializeArgsAndUnpack
local Ser_DeserializeArgsAndUnpack = Ser.DeserializeArgsAndUnpack

function ClientRemoteSignal.new(remoteEvent)
	assert(not IS_SERVER, "ClientRemoteSignal can only be created on the client")
	assert(typeof(remoteEvent) == "Instance", "Argument #1 (RemoteEvent) expected Instance; got " .. typeof(remoteEvent))
	assert(remoteEvent:IsA("RemoteEvent"), "Argument #1 (RemoteEvent) expected RemoteEvent; got" .. remoteEvent.ClassName)
	return setmetatable({
		_remote = remoteEvent;
		_connections = {};
	}, ClientRemoteSignal)
end

function ClientRemoteSignal.Is(object)
	return type(object) == "table" and getmetatable(object) == ClientRemoteSignal
end

function ClientRemoteSignal:Fire(...)
	self._remote:FireServer(Ser_SerializeArgsAndUnpack(...))
end

function ClientRemoteSignal:Wait()
	return Ser_DeserializeArgsAndUnpack(self._remote.OnClientEvent:Wait())
end

function ClientRemoteSignal:Connect(handler)
	local connection = Connection.new(self, self._remote.OnClientEvent:Connect(function(...)
		handler(Ser_DeserializeArgsAndUnpack(...))
	end))

	table.insert(self._connections, connection)
	return connection
end

function ClientRemoteSignal:Destroy()
	for _, c in ipairs(self._connections) do
		if c._conn then
			c._conn:Disconnect()
		end
	end

	self._connections = nil
	self._remote = nil
	setmetatable(self, nil)
end

function ClientRemoteSignal:__tostring()
	return "ClientRemoteSignal"
end

return ClientRemoteSignal
