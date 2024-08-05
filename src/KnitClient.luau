--!nonstrict
--!optimize 2

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local IS_STUDIO = RunService:IsStudio()

--[=[
	@interface Middleware
	@field Inbound ClientMiddleware?
	@field Outbound ClientMiddleware?
	@within KnitClient
]=]
type Middleware = {
	Inbound: ClientMiddleware?,
	Outbound: ClientMiddleware?,
	[any]: never,
}

--[=[
	@type ClientMiddlewareFn (args: {any}) -> (shouldContinue: boolean, ...: any)
	@within KnitClient

	For more info, see [ClientComm](https://sleitnick.github.io/RbxUtil/api/ClientComm/) documentation.
]=]
type ClientMiddlewareFn = (args: {any}) -> (boolean, ...any)

--[=[
	@type ClientMiddleware {ClientMiddlewareFn}
	@within KnitClient
	An array of client middleware functions.
]=]
type ClientMiddleware = {ClientMiddlewareFn}

--[=[
	@type PerServiceMiddleware {[string]: Middleware}
	@within KnitClient
]=]
type PerServiceMiddleware = {[string]: Middleware}

--[=[
	@interface ControllerDef
	@field Name string
	@field [any] any
	@within KnitClient
	Used to define a controller when creating it in `CreateController`.
]=]
type ControllerDef = {
	Name: string,
	[any]: any,
}

--[=[
	@interface Controller
	@field Name string
	@field [any] any
	@within KnitClient
]=]
type Controller = {
	Name: string,
	[any]: any,
}

--[=[
	@interface Service
	@field [any] any
	@within KnitClient
]=]
type Service = {
	[any]: any,
}

--[=[
	@interface KnitOptions
	@field ServicePromises boolean?
	@field Middleware Middleware?
	@field PerServiceMiddleware PerServiceMiddleware?
	@field SpawnRunServiceFunctions "None" | "Defer" | "Spawn" | nil
	@within KnitClient

	- `ServicePromises` defaults to `true` and indicates if service methods use promises.
	- Each service will go through the defined middleware, unless the service
	has middleware defined in `PerServiceMiddleware`.
]=]
type KnitOptions = {
	ServicePromises: boolean,
	Middleware: Middleware?,
	PerServiceMiddleware: PerServiceMiddleware?,
	SpawnRunServiceFunctions: "None" | "Defer" | "Spawn" | nil,
	[any]: never,
}

local defaultOptions: KnitOptions = {
	Middleware = nil;
	PerServiceMiddleware = {};
	ServicePromises = false;
	SpawnRunServiceFunctions = "Spawn";
}

local selectedOptions = nil

--[=[
	@class KnitClient
	@client
]=]
local KnitClient = {}

--[=[
	@prop Player Player
	@within KnitClient
	@readonly
	Reference to the LocalPlayer.
]=]
KnitClient.Player = Players.LocalPlayer

--[=[
	@prop Util Folder
	@within KnitClient
	@readonly
	References the Util folder. Should only be accessed when using Knit as
	a standalone module. If using Knit from Wally, modules should just be
	pulled in via Wally instead of relying on Knit's Util folder, as this
	folder only contains what is necessary for Knit to run in Wally mode.
]=]
KnitClient.Util = (script.Parent :: Instance).Parent

local Comm = require(KnitClient.Util.Comm)
local Promise = require(KnitClient.Util.Promise)
local ThreadUtilities = require(KnitClient.Util.ThreadUtilities)
local ClientComm = Comm.ClientComm

local controllers: {[string]: Controller} = {}
local services: {[string]: Service} = {}
local servicesFolder = nil

local started = false
local startedComplete = false
local onStartedComplete = Instance.new("BindableEvent")

local function DoesControllerExist(controllerName: string): boolean
	local controller: Controller? = controllers[controllerName]

	return controller ~= nil
end

local function GetServicesFolder()
	if not servicesFolder then
		servicesFolder = (script.Parent :: Instance):WaitForChild("Services")
	end

	return servicesFolder
end

local function GetMiddlewareForService(serviceName: string)
	local knitMiddleware = if selectedOptions.Middleware ~= nil then selectedOptions.Middleware else {}
	local serviceMiddleware = selectedOptions.PerServiceMiddleware[serviceName]

	return if serviceMiddleware ~= nil then serviceMiddleware else knitMiddleware
end

local function BuildService(serviceName: string)
	local folder = GetServicesFolder()
	local middleware = GetMiddlewareForService(serviceName)
	local clientComm = ClientComm.new(folder, selectedOptions.ServicePromises, serviceName)
	local service = clientComm:BuildObject(middleware.Inbound, middleware.Outbound)

	services[serviceName] = service

	return service
end

--[=[
	Creates a new controller.

	:::caution
	Controllers must be created _before_ calling `Knit.Start()`.
	:::
	```lua
	-- Create a controller
	local MyController = Knit.CreateController {
		Name = "MyController",
	}

	function MyController:KnitStart()
		print("MyController started")
	end

	function MyController:KnitInit()
		print("MyController initialized")
	end
	```
]=]
function KnitClient.CreateController(controllerDefinition: ControllerDef): Controller
	assert(type(controllerDefinition) == "table", `Controller must be a table; got {type(controllerDefinition)}`)
	assert(
		type(controllerDefinition.Name) == "string",
		`Controller.Name must be a string; got {type(controllerDefinition.Name)}`
	)
	assert(#controllerDefinition.Name > 0, "Controller.Name must be a non-empty string")
	assert(not DoesControllerExist(controllerDefinition.Name), `Controller {controllerDefinition.Name} already exists`)
	assert(not started, "Controllers cannot be created after calling \"Knit.Start()\"")

	local controller = controllerDefinition :: Controller
	controllers[controller.Name] = controller

	return controller
end

--[=[
	Requires all the modules that are children of the given parent. This is an easy
	way to quickly load all controllers that might be in a folder.
	```lua
	Knit.AddControllers(somewhere.Controllers)
	```
]=]
function KnitClient.AddControllers(parent: Instance): {Controller}
	assert(not started, "Controllers cannot be added after calling \"Knit.Start()\"")

	local addedControllers = {}
	local length = 0
	local require = require

	for _, child in parent:GetChildren() do
		if not child:IsA("ModuleScript") then
			continue
		end

		length += 1
		addedControllers[length] = require(child)
	end

	return addedControllers
end

--[=[
	Requires all the modules that are descendants of the given parent.
]=]
function KnitClient.AddControllersDeep(parent: Instance): {Controller}
	assert(not started, "Controllers cannot be added after calling \"Knit.Start()\"")

	local addedControllers = {}
	local length = 0
	local require = require

	for _, descendant in parent:GetDescendants() do
		if not descendant:IsA("ModuleScript") then
			continue
		end

		length += 1
		addedControllers[length] = require(descendant)
	end

	return addedControllers
end

--[=[
	Returns a Service object which is a reflection of the remote objects
	within the Client table of the given service. Throws an error if the
	service is not found.

	If a service's Client table contains RemoteSignals and/or RemoteProperties,
	these values are reflected as
	[ClientRemoteSignals](https://sleitnick.github.io/RbxUtil/api/ClientRemoteSignal) and
	[ClientRemoteProperties](https://sleitnick.github.io/RbxUtil/api/ClientRemoteProperty).

	```lua
	-- Server-side service creation:
	local MyService = Knit.CreateService {
		Name = "MyService",
		Client = {
			MySignal = Knit.CreateSignal(),
			MyProperty = Knit.CreateProperty("Hello"),
		},
	}
	function MyService:AddOne(player, number)
		return number + 1
	end

	-------------------------------------------------

	-- Client-side service reflection:
	local MyService = Knit.GetService("MyService")

	-- Call a method:
	local num = MyService:AddOne(5) --> 6

	-- Fire a signal to the server:
	MyService.MySignal:Fire("Hello")

	-- Listen for signals from the server:
	MyService.MySignal:Connect(function(message)
		print(message)
	end)

	-- Observe the initial value and changes to properties:
	MyService.MyProperty:Observe(function(value)
		print(value)
	end)
	```

	:::caution
	Services are only exposed to the client if the service has remote-based
	content in the Client table. If not, the service will not be visible
	to the client. `KnitClient.GetService` will only work on services that
	expose remote-based content on their Client tables.
	:::
]=]
function KnitClient.GetService(serviceName: string): Service
	local service = services[serviceName]
	if service then
		return service
	end

	assert(started, "Cannot call GetService until Knit has been started")
	assert(type(serviceName) == "string", `ServiceName must be a string; got {type(serviceName)}`)

	return BuildService(serviceName)
end

--[=[
	Gets the controller by name. Throws an error if the controller
	is not found.
]=]
function KnitClient.GetController(controllerName: string): Controller
	local controller = controllers[controllerName]
	if controller then
		return controller
	end

	assert(started, "Cannot call GetController until Knit has been started")
	assert(type(controllerName) == "string", `ControllerName must be a string; got {type(controllerName)}`)
	error(`Could not find controller "{controllerName}". Check to verify a controller with this name exists.`, 2)
end

--[=[
	Gets a table of all controllers.
]=]
function KnitClient.GetControllers(): {[string]: Controller}
	assert(started, "Cannot call GetControllers until Knit has been started")

	return controllers
end

--[=[
	@return Promise
	Starts Knit. Should only be called once per client.
	```lua
	Knit.Start():andThen(function()
		print("Knit started!")
	end):catch(warn)
	```

	By default, service methods exposed to the client will return promises.
	To change this behavior, set the `ServicePromises` option to `false`:
	```lua
	Knit.Start({ServicePromises = false}):andThen(function()
		print("Knit started!")
	end):catch(warn)
	```
]=]
function KnitClient.Start(options: KnitOptions?)
	if started then
		return Promise.reject("Knit already started")
	end

	started = true

	table.freeze(controllers)

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

	if type(selectedOptions.PerServiceMiddleware) ~= "table" then
		selectedOptions.PerServiceMiddleware = {}
	end

	return Promise.new(function(resolve)
		-- Init:
		local promisesStartControllers = {}
		local length = 0

		for _, controller in controllers do
			local knitInit = controller.KnitInit
			if type(knitInit) == "function" then
				length += 1
				promisesStartControllers[length] = Promise.new(function(internalResolve)
					debug.setmemorycategory(controller.Name)
					if IS_STUDIO then
						local success, exception = pcall(ThreadUtilities.NoYield, knitInit, controller)
						if not success then
							warn(`Failed to call {controller.Name}.KnitInit - {exception}`)
						end
					else
						knitInit(controller)
					end

					internalResolve()
				end)
			end
		end

		resolve(Promise.all(promisesStartControllers))
	end):andThen(function()
		type StandardCallback = (deltaTime: number) -> ()
		type SteppedCallback = (time: number, deltaTime: number) -> ()

		local postSimulationQueue: {StandardCallback}? = nil
		local preSimulationQueue: {StandardCallback}? = nil
		local preAnimationQueue: {StandardCallback}? = nil
		local preRenderQueue: {StandardCallback}? = nil

		local heartbeatQueue: {StandardCallback}? = nil
		local steppedQueue: {SteppedCallback}? = nil
		local renderSteppedQueue: {StandardCallback}? = nil

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
		for _, controller in controllers do
			local knitStart = controller.KnitStart
			if type(knitStart) == "function" then
				ThreadUtilities.FastSpawn(function()
					debug.setmemorycategory(controller.Name)
					knitStart(controller)
				end)
			end

			local onPostSimulation = controller.OnPostSimulation
			if type(onPostSimulation) == "function" then
				postSimulationQueue = addToQueue(postSimulationQueue, function(deltaTime)
					onPostSimulation(controller, deltaTime)
				end)
			end
			local onPreSimulation = controller.OnPreSimulation
			if type(onPreSimulation) == "function" then
				preSimulationQueue = addToQueue(preSimulationQueue, function(deltaTime)
					onPreSimulation(controller, deltaTime)
				end)
			end
			local onPreAnimation = controller.OnPreAnimation
			if type(onPreAnimation) == "function" then
				preAnimationQueue = addToQueue(preAnimationQueue, function(deltaTime)
					onPreAnimation(controller, deltaTime)
				end)
			end
			local onPreRender = controller.OnPreRender
			if type(onPreRender) == "function" then
				preRenderQueue = addToQueue(preRenderQueue, function(deltaTime)
					onPreRender(controller, deltaTime)
				end)
			end

			local onHeartbeat = controller.OnHeartbeat
			if type(onHeartbeat) == "function" then
				heartbeatQueue = addToQueue(heartbeatQueue, function(deltaTime)
					onHeartbeat(controller, deltaTime)
				end)
			end
			local onStepped = controller.OnStepped
			if type(onStepped) == "function" then
				steppedQueue = addToQueue(steppedQueue, function(time, deltaTime)
					onStepped(controller, time, deltaTime)
				end)
			end
			local onRenderStepped = controller.OnRenderStepped
			if type(onRenderStepped) == "function" then
				renderSteppedQueue = addToQueue(renderSteppedQueue, function(deltaTime)
					onRenderStepped(controller, deltaTime)
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
		if preRenderQueue then
			RunService.PreRender:Connect(function(deltaTime)
				for _, callback in preRenderQueue do
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
		if renderSteppedQueue then
			RunService.RenderStepped:Connect(function(deltaTime)
				for _, callback in renderSteppedQueue do
					callback(deltaTime)
				end
			end)
		end

		startedComplete = true
		onStartedComplete:Fire()

		ThreadUtilities.FastDefer(function()
			onStartedComplete:Destroy()
		end)
	end)
end

--[=[
	@return Promise
	Returns a promise that is resolved once Knit has started. This is useful
	for any code that needs to tie into Knit controllers but is not the script
	that called `Start`.
	```lua
	Knit.OnStart():andThen(function()
		local MyController = Knit.GetController("MyController")
		MyController:DoSomething()
	end):catch(warn)
	```
]=]
function KnitClient.OnStart()
	return if startedComplete then Promise.resolve() else Promise.fromEvent(onStartedComplete.Event)
end

return KnitClient
