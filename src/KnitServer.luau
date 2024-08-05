--!nonstrict
--!optimize 2

local RunService = game:GetService("RunService")

local IS_STUDIO = RunService:IsStudio()

--[=[
	@interface Middleware
	@field Inbound ServerMiddleware?
	@field Outbound ServerMiddleware?
	@within KnitServer
]=]
type Middleware = {
	Inbound: ServerMiddleware?,
	Outbound: ServerMiddleware?,
	[any]: never,
}

--[=[
	@type ServerMiddlewareFn (player: Player, args: {any}) -> (shouldContinue: boolean, ...: any)
	@within KnitServer

	For more info, see [ServerComm](https://sleitnick.github.io/RbxUtil/api/ServerComm/) documentation.
]=]
type ServerMiddlewareFn = (player: Player, args: {any}) -> (boolean, ...any)

--[=[
	@type ServerMiddleware {ServerMiddlewareFn}
	@within KnitServer
	An array of server middleware functions.
]=]
type ServerMiddleware = {ServerMiddlewareFn}

--[=[
	@interface ServiceDef
	@field Name string
	@field Client table?
	@field Middleware Middleware?
	@field [any] any
	@within KnitServer
	Used to define a service when creating it in `CreateService`.

	The middleware tables provided will be used instead of the Knit-level
	middleware (if any). This allows fine-tuning each service's middleware.
	These can also be left out or `nil` to not include middleware.
]=]
type ServiceDef = {
	Name: string,
	Client: {[any]: any}?,
	Middleware: Middleware?,
	[any]: any,
}

--[=[
	@interface Service
	@field dName string
	@field dClient ServiceClient
	@field dKnitComm Comm
	@field [any] any
	@within KnitServer
]=]
type Service = {
	Name: string,
	Client: ServiceClient,
	KnitComm: any,
	[any]: any,
}

--[=[
	@interface ServiceClient
	@field Server Service
	@field [any] any
	@within KnitServer
]=]
type ServiceClient = {
	Server: Service,
	[any]: any,
}

--[=[
	@interface KnitOptions
	@field Middleware Middleware?
	@field SpawnRunServiceFunctions "None" | "Defer" | "Spawn" | nil
	@within KnitServer

	- Middleware will apply to all services _except_ ones that define
	their own middleware.
]=]
type KnitOptions = {
	Middleware: Middleware?,
	SpawnRunServiceFunctions: "None" | "Defer" | "Spawn" | nil,
	[any]: never,
}

local defaultOptions: KnitOptions = {
	Middleware = nil;
	SpawnRunServiceFunctions = "Spawn";
}

local selectedOptions = nil

--[=[
	@class KnitServer
	@server
	Knit server-side lets developers create services and expose methods and signals
	to the clients.

	```lua
	local Knit = require(somewhere.Knit)

	-- Load service modules within some folder:
	Knit.AddServices(somewhere.Services)

	-- Start Knit:
	Knit.Start():andThen(function()
		print("Knit started")
	end):catch(warn)
	```
]=]
local KnitServer = {}

--[=[
	@prop Util Folder
	@within KnitServer
	@readonly
	References the Util folder. Should only be accessed when using Knit as
	a standalone module. If using Knit from Wally, modules should just be
	pulled in via Wally instead of relying on Knit's Util folder, as this
	folder only contains what is necessary for Knit to run in Wally mode.
]=]
KnitServer.Util = (script.Parent :: Instance).Parent

local SIGNAL_MARKER = newproxy(true)
getmetatable(SIGNAL_MARKER).__tostring = function()
	return "SIGNAL_MARKER"
end

local UNRELIABLE_SIGNAL_MARKER = newproxy(true)
getmetatable(UNRELIABLE_SIGNAL_MARKER).__tostring = function()
	return "UNRELIABLE_SIGNAL_MARKER"
end

local PROPERTY_MARKER = newproxy(true)
getmetatable(PROPERTY_MARKER).__tostring = function()
	return "PROPERTY_MARKER"
end

local knitRepServiceFolder = Instance.new("Folder")
knitRepServiceFolder.Name = "Services"

local Comm = require(KnitServer.Util.Comm)
local Promise = require(KnitServer.Util.Promise)
local ThreadUtilities = require(KnitServer.Util.ThreadUtilities)

local ServerComm = Comm.ServerComm

local services: {[string]: Service} = {}
local started = false
local startedComplete = false
local onStartedComplete = Instance.new("BindableEvent")

local function DoesServiceExist(serviceName: string): boolean
	local service: Service? = services[serviceName]

	return service ~= nil
end

--[=[
	Constructs a new service.

	:::caution
	Services must be created _before_ calling `Knit.Start()`.
	:::
	```lua
	-- Create a service
	local MyService = Knit.CreateService {
		Name = "MyService",
		Client = {},
	}

	-- Expose a ToAllCaps remote function to the clients
	function MyService.Client:ToAllCaps(player, msg)
		return msg:upper()
	end

	-- Knit will call KnitStart after all services have been initialized
	function MyService:KnitStart()
		print("MyService started")
	end

	-- Knit will call KnitInit when Knit is first started
	function MyService:KnitInit()
		print("MyService initialize")
	end
	```
]=]
function KnitServer.CreateService(serviceDefinition: ServiceDef): Service
	assert(type(serviceDefinition) == "table", `Service must be a table; got {type(serviceDefinition)}`)
	assert(
		type(serviceDefinition.Name) == "string",
		`Service.Name must be a string; got {type(serviceDefinition.Name)}`
	)
	assert(#serviceDefinition.Name > 0, "Service.Name must be a non-empty string")
	assert(not DoesServiceExist(serviceDefinition.Name), `Service "{serviceDefinition.Name}" already exists`)
	assert(not started, "Services cannot be created after calling \"Knit.Start()\"")

	local service = serviceDefinition
	service.KnitComm = ServerComm.new(knitRepServiceFolder, serviceDefinition.Name)

	if type(service.Client) ~= "table" then
		service.Client = {Server = service}
	else
		if service.Client.Server ~= service then
			service.Client.Server = service
		end
	end

	services[service.Name] = service

	return service
end

--[=[
	Requires all the modules that are children of the given parent. This is an easy
	way to quickly load all services that might be in a folder.
	```lua
	Knit.AddServices(somewhere.Services)
	```
]=]
function KnitServer.AddServices(parent: Instance): {Service}
	assert(not started, "Services cannot be added after calling \"Knit.Start()\"")

	local addedServices = {}
	local length = 0
	local require = require

	for _, child in parent:GetChildren() do
		if not child:IsA("ModuleScript") then
			continue
		end

		length += 1
		addedServices[length] = require(child)
	end

	return addedServices
end

--[=[
	Requires all the modules that are descendants of the given parent.
]=]
function KnitServer.AddServicesDeep(parent: Instance): {Service}
	assert(not started, "Services cannot be added after calling \"Knit.Start()\"")

	local addedServices = {}
	local length = 0
	local require = require

	for _, descendant in parent:GetDescendants() do
		if not descendant:IsA("ModuleScript") then
			continue
		end

		length += 1
		addedServices[length] = require(descendant)
	end

	return addedServices
end

--[=[
	Gets the service by name. Throws an error if the service is not found.
]=]
function KnitServer.GetService(serviceName: string): Service
	assert(started, "Cannot call GetService until Knit has been started")
	assert(type(serviceName) == "string", `ServiceName must be a string; got {type(serviceName)}`)

	local service = services[serviceName]
	assert(service, `Could not find service "{serviceName}"`)
	return service :: Service
end

--[=[
	Gets a table of all services.
]=]
function KnitServer.GetServices(): {[string]: Service}
	assert(started, "Cannot call GetServices until Knit has been started")

	return services
end

--[=[
	@return SIGNAL_MARKER
	Returns a marker that will transform the current key into
	a RemoteSignal once the service is created. Should only
	be called within the Client table of a service.

	See [RemoteSignal](https://sleitnick.github.io/RbxUtil/api/RemoteSignal)
	documentation for more info.
	```lua
	local MyService = Knit.CreateService {
		Name = "MyService",
		Client = {
			-- Create the signal marker, which will turn into a
			-- RemoteSignal when Knit.Start() is called:
			MySignal = Knit.CreateSignal(),
		},
	}

	function MyService:KnitInit()
		-- Connect to the signal:
		self.Client.MySignal:Connect(function(player, ...) end)
	end
	```
]=]
function KnitServer.CreateSignal()
	return SIGNAL_MARKER
end

--[=[
	@return UNRELIABLE_SIGNAL_MARKER

	Returns a marker that will transform the current key into
	an unreliable RemoteSignal once the service is created. Should
	only be called within the Client table of a service.

	See [RemoteSignal](https://sleitnick.github.io/RbxUtil/api/RemoteSignal)
	documentation for more info.

	:::info Unreliable Events
	Internally, this uses UnreliableRemoteEvents, which allows for
	network communication that is unreliable and unordered. This is
	useful for events that are not crucial for gameplay, since the
	delivery of the events may occur out of order or not at all.

	See  the documentation for [UnreliableRemoteEvents](https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent)
	for more info.
]=]
function KnitServer.CreateUnreliableSignal()
	return UNRELIABLE_SIGNAL_MARKER
end

--[=[
	@return PROPERTY_MARKER
	Returns a marker that will transform the current key into
	a RemoteProperty once the service is created. Should only
	be called within the Client table of a service. An initial
	value can be passed along as well.

	RemoteProperties are great for replicating data to all of
	the clients. Different data can also be set per client.

	See [RemoteProperty](https://sleitnick.github.io/RbxUtil/api/RemoteProperty)
	documentation for more info.

	```lua
	local MyService = Knit.CreateService {
		Name = "MyService",
		Client = {
			-- Create the property marker, which will turn into a
			-- RemoteProperty when Knit.Start() is called:
			MyProperty = Knit.CreateProperty("HelloWorld"),
		},
	}

	function MyService:KnitInit()
		-- Change the value of the property:
		self.Client.MyProperty:Set("HelloWorldAgain")
	end
	```
]=]
function KnitServer.CreateProperty(initialValue: any)
	return {PROPERTY_MARKER, initialValue}
end

--[=[
	@return Promise
	Starts Knit. Should only be called once.

	Optionally, `KnitOptions` can be passed in order to set
	Knit's custom configurations.

	:::caution
	Be sure that all services have been created _before_
	calling `Start`. Services cannot be added later.
	:::

	```lua
	Knit.Start():andThen(function()
		print("Knit started!")
	end):catch(warn)
	```
	
	Example of Knit started with options:
	```lua
	Knit.Start({
		Middleware = {
			Inbound = {
				function(player, args)
					print("Player is giving following args to server:", args)
					return true
				end
			},
		},
	}):andThen(function()
		print("Knit started!")
	end):catch(warn)
	```
]=]
function KnitServer.Start(options: KnitOptions?)
	if started then
		return Promise.reject("Knit already started")
	end

	started = true

	table.freeze(services)

	if options == nil then
		selectedOptions = defaultOptions
	else
		assert(type(options) == "table", `KnitOptions should be a table or nil; got {typeof(options)}`)
		selectedOptions = options
		for key, value in defaultOptions do
			if selectedOptions[key] == nil then
				selectedOptions[key] = value
			end
		end
	end

	return Promise.new(function(resolve)
		local knitMiddleware = selectedOptions.Middleware or {}

		-- Bind remotes:
		for _, service in services do
			local middleware = service.Middleware or {}
			local inbound = middleware.Inbound or knitMiddleware.Inbound
			local outbound = middleware.Outbound or knitMiddleware.Outbound

			service.Middleware = nil

			for key, value in service.Client do
				if type(value) == "function" then
					service.KnitComm:WrapMethod(service.Client, key, inbound, outbound)
				elseif value == SIGNAL_MARKER then
					service.Client[key] = service.KnitComm:CreateSignal(key, false, inbound, outbound)
				elseif value == UNRELIABLE_SIGNAL_MARKER then
					service.Client[key] = service.KnitComm:CreateSignal(key, true, inbound, outbound)
				elseif type(value) == "table" and value[1] == PROPERTY_MARKER then
					service.Client[key] = service.KnitComm:CreateProperty(key, value[2], inbound, outbound)
				end
			end
		end

		-- Init:
		local promisesInitializeServices = {}
		local length = 0
		for _, service in services do
			local knitInit = service.KnitInit
			if type(knitInit) == "function" then
				length += 1
				promisesInitializeServices[length] = Promise.new(function(internalResolve)
					debug.setmemorycategory(service.Name)

					if IS_STUDIO then
						local success, exception = pcall(ThreadUtilities.NoYield, knitInit, service)
						if not success then
							warn(`Failed to call {service.Name}.KnitInit - {exception}`)
						end
					else
						knitInit(service)
					end

					internalResolve()
				end)
			end
		end

		resolve(Promise.all(promisesInitializeServices))
	end):andThen(function()
		-- Start:

		type StandardCallback = (deltaTime: number) -> ()
		type SteppedCallback = (time: number, deltaTime: number) -> ()

		local postSimulationQueue: {StandardCallback}? = nil
		local preSimulationQueue: {StandardCallback}? = nil
		local preAnimationQueue: {StandardCallback}? = nil

		local heartbeatQueue: {StandardCallback}? = nil
		local steppedQueue: {SteppedCallback}? = nil

		type AddToQueue =
			((queue: {StandardCallback}?, callback: StandardCallback) -> {StandardCallback})
			& ((queue: {SteppedCallback}?, callback: SteppedCallback) -> {SteppedCallback})

		local addToQueue: AddToQueue
		function addToQueue(queue, callback)
			if selectedOptions.SpawnRunServiceFunctions == "Spawn" then
				local legacyCallback = callback
				function callback(time, deltaTime)
					ThreadUtilities.FastSpawn(legacyCallback, time, deltaTime)
				end
			elseif selectedOptions.SpawnRunServiceFunctions == "Defer" then
				local legacyCallback = callback
				function callback(time, deltaTime)
					ThreadUtilities.FastDefer(legacyCallback, time, deltaTime)
				end
			end

			if queue then
				table.insert(queue, callback)
				return queue
			end

			return {callback}
		end

		-- Start:
		for _, service in services do
			local knitStart = service.KnitStart
			if type(knitStart) == "function" then
				ThreadUtilities.FastSpawn(function()
					debug.setmemorycategory(service.Name)
					knitStart(service)
				end)
			end

			local onPostSimulation = service.OnPostSimulation
			if type(onPostSimulation) == "function" then
				postSimulationQueue = addToQueue(postSimulationQueue, function(deltaTime)
					onPostSimulation(service, deltaTime)
				end)
			end
			local onPreSimulation = service.OnPreSimulation
			if type(onPreSimulation) == "function" then
				preSimulationQueue = addToQueue(preSimulationQueue, function(deltaTime)
					onPreSimulation(service, deltaTime)
				end)
			end
			local onPreAnimation = service.OnPreAnimation
			if type(onPreAnimation) == "function" then
				preAnimationQueue = addToQueue(preAnimationQueue, function(deltaTime)
					onPreAnimation(service, deltaTime)
				end)
			end

			local onHeartbeat = service.OnHeartbeat
			if type(onHeartbeat) == "function" then
				heartbeatQueue = addToQueue(heartbeatQueue, function(deltaTime)
					onHeartbeat(service, deltaTime)
				end)
			end
			local onStepped = service.OnStepped
			if type(onStepped) == "function" then
				steppedQueue = addToQueue(steppedQueue, function(time, deltaTime)
					onStepped(service, time, deltaTime)
				end)
			end
		end

		if postSimulationQueue then
			RunService.PostSimulation:Connect(function(deltaTime)
				for _, callback in postSimulationQueue do
					callback(deltaTime)
				end
			end)
		end
		if preSimulationQueue then
			RunService.PreSimulation:Connect(function(deltaTime)
				for _, callback in preSimulationQueue do
					callback(deltaTime)
				end
			end)
		end
		if preAnimationQueue then
			RunService.PreAnimation:Connect(function(deltaTime)
				for _, callback in preAnimationQueue do
					callback(deltaTime)
				end
			end)
		end
		if heartbeatQueue then
			RunService.Heartbeat:Connect(function(deltaTime)
				for _, callback in heartbeatQueue do
					callback(deltaTime)
				end
			end)
		end
		if steppedQueue then
			RunService.Stepped:Connect(function(time, deltaTime)
				for _, callback in steppedQueue do
					callback(time, deltaTime)
				end
			end)
		end

		startedComplete = true
		onStartedComplete:Fire()

		ThreadUtilities.FastDefer(function()
			onStartedComplete:Destroy()
		end)

		-- Expose service remotes to everyone:
		knitRepServiceFolder.Parent = script.Parent
	end)
end

--[=[
	@return Promise
	Returns a promise that is resolved once Knit has started. This is useful
	for any code that needs to tie into Knit services but is not the script
	that called `Start`.
	```lua
	Knit.OnStart():andThen(function()
		local MyService = Knit.Services.MyService
		MyService:DoSomething()
	end):catch(warn)
	```
]=]
function KnitServer.OnStart()
	return if startedComplete then Promise.resolve() else Promise.fromEvent(onStartedComplete.Event)
end

return KnitServer
