--[[

	Knit.CreateController(controller): Controller
	Knit.AddControllers(folder): Controller[]
	Knit.AddControllersDeep(folder): Controller[]
	Knit.GetService(serviceName): Service
	Knit.GetController(controllerName): Controller
	Knit.Start(): Promise<void>
	Knit.OnStart(): Promise<void>

--]]

local Players = game:GetService("Players")

local KnitClient = {
	Controllers = {};
	Player = Players.LocalPlayer;
	Util = script.Parent.Util;
	Version = script.Parent.Version.Value;
}

local ClientRemoteProperty = require(KnitClient.Util.Remote.ClientRemoteProperty)
local ClientRemoteSignal = require(KnitClient.Util.Remote.ClientRemoteSignal)
local Loader = require(KnitClient.Util.Loader)
local Promise = require(KnitClient.Util.Promise)
local Ser = require(KnitClient.Util.Ser)
local TableUtil = require(KnitClient.Util.TableUtil)
local Thread = require(KnitClient.Util.Thread)

local services = {}
local servicesFolder = script.Parent:WaitForChild("Services")

local started = false
local startedComplete = false
local onStartedComplete = Instance.new("BindableEvent")

local Promise_new = Promise.new
local Ser_DeserializeArgsAndUnpack = Ser.DeserializeArgsAndUnpack
local Ser_SerializeArgs = Ser.SerializeArgs
local Ser_SerializeArgsAndUnpack = Ser.SerializeArgsAndUnpack

local function BuildService(serviceName, folder)
	local service = {}
	if folder:FindFirstChild("RF") then
		for _, rf in ipairs(folder.RF:GetChildren()) do
			if rf:IsA("RemoteFunction") then
				service[rf.Name] = function(_, ...)
					return Ser_DeserializeArgsAndUnpack(rf:InvokeServer(Ser_SerializeArgsAndUnpack(...)))
				end

				service[rf.Name .. "Promise"] = function(_, ...)
					local args = Ser_SerializeArgs(...)
					return Promise_new(function(resolve)
						resolve(Ser_DeserializeArgsAndUnpack(rf:InvokeServer(table.unpack(args, 1, args.n))))
					end)
				end
			end
		end
	end

	if folder:FindFirstChild("RE") then
		for _, re in ipairs(folder.RE:GetChildren()) do
			if re:IsA("RemoteEvent") then
				service[re.Name] = ClientRemoteSignal.new(re)
			end
		end
	end

	if folder:FindFirstChild("RP") then
		for _, rp in ipairs(folder.RP:GetChildren()) do
			if rp:IsA("ValueBase") or rp:IsA("RemoteEvent") then
				service[rp.Name] = ClientRemoteProperty.new(rp)
			end
		end
	end

	services[serviceName] = service
	return service
end

function KnitClient.CreateController(controller)
	assert(type(controller) == "table", "Controller must be a table; got " .. type(controller))
	assert(type(controller.Name) == "string", "Controller.Name must be a string; got " .. type(controller.Name))
	assert(#controller.Name > 0, "Controller.Name must be a non-empty string")
	assert(KnitClient.Controllers[controller.Name] == nil, "Controller \"" .. controller.Name .. "\" already exists")
	controller = TableUtil.Assign(controller, {_knit_is_controller = true})

	KnitClient.Controllers[controller.Name] = controller
	return controller
end

KnitClient.AddControllers = Loader.LoadChildren
KnitClient.AddControllersDeep = Loader.LoadDescendants

function KnitClient.GetService(serviceName)
	assert(type(serviceName) == "string", "ServiceName must be a string; got " .. type(serviceName))
	local folder = servicesFolder:FindFirstChild(serviceName)
	assert(folder ~= nil, "Could not find service \"" .. serviceName .. "\"")
	return services[serviceName] or BuildService(serviceName, folder)
end

function KnitClient.GetController(controllerName)
	return KnitClient.Controllers[controllerName]
end

function KnitClient.Start()
	if started then
		return Promise.Reject("Knit already started")
	end

	started = true
	local controllers = KnitClient.Controllers
	return Promise_new(function(resolve)
		-- Init:
		local promisesStartControllers = {}
		local length = 0
		for _, controller in next, controllers do
			if type(controller.KnitInit) == "function" then
				length += 1
				promisesStartControllers[length] = Promise_new(function(r)
					controller:KnitInit()
					r()
				end)
			end
		end

		resolve(Promise.All(promisesStartControllers))
	end):Then(function()
		-- Start:
		for _, controller in next, controllers do
			if type(controller.KnitStart) == "function" then
				Thread.SpawnNow(controller.KnitStart, controller)
			end
		end

		startedComplete = true
		onStartedComplete:Fire()

		Thread.Spawn(function()
			onStartedComplete:Destroy()
		end)
	end)
end

function KnitClient.OnStart()
	if startedComplete then
		return Promise.Resolve()
	else
		return Promise.FromEvent(onStartedComplete.Event)
	end
end

return KnitClient
