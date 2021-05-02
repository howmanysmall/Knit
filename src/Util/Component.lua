-- Component
-- Stephen Leitnick
-- July 25, 2020

--[[

	Component.Auto(folder)
		-> Create components automatically from descendant modules of this folder
		-> Each module must have a '.Tag' string property
		-> Each module optionally can have '.RenderPriority' number property

	component = Component.FromTag(tag)
		-> Retrieves an existing component from the tag name

	component = Component.new(tag, class [, renderPriority])
		-> Creates a new component from the tag name, class module, and optional render priority

	component:GetAll(): ComponentInstance[]
	component:GetFromInstance(instance): ComponentInstance | nil
	component:GetFromID(id): ComponentInstance | nil
	component:Filter(filterFunc): ComponentInstance[]
	component:WaitFor(instanceOrName: Instance | string [, timeout: number = 60]): Promise<ComponentInstance>
	component:Destroy()

	component.Added(obj: ComponentInstance)
	component.Removed(obj: ComponentInstance)

	-----------------------------------------------------------------------

	A component class must look something like this:

		-- DEFINE
		local MyComponent = {}
		MyComponent.__index = MyComponent

		-- CONSTRUCTOR
		function MyComponent.new(instance)
			local self = setmetatable({}, MyComponent)
			return self
		end

		-- FIELDS AFTER CONSTRUCTOR COMPLETES
		MyComponent.Instance: Instance

		-- OPTIONAL LIFECYCLE HOOKS
		function MyComponent:Init() end                     -> Called right after constructor
		function MyComponent:Deinit() end                   -> Called right before deconstructor
		function MyComponent:HeartbeatUpdate(dt) ... end    -> Updates every heartbeat
		function MyComponent:SteppedUpdate(dt) ... end      -> Updates every physics step
		function MyComponent:RenderUpdate(dt) ... end       -> Updates every render step

		-- DESTRUCTOR
		function MyComponent:Destroy()
		end


	A component is then registered like so:

		local Component = require(Knit.Util.Component)
		local MyComponent = require(somewhere.MyComponent)
		local tag = "MyComponent"

		local myComponent = Component.new(tag, MyComponent)


	Components can be listened and queried:

		myComponent.Added:Connect(function(instanceOfComponent)
			-- New MyComponent constructed
		end)

		myComponent.Removed:Connect(function(instanceOfComponent)
			-- New MyComponent deconstructed
		end)

--]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Janitor = require(script.Parent.Janitor)
local Promise = require(script.Parent.Promise)
local Signal = require(script.Parent.Signal)
local TableUtil = require(script.Parent.TableUtil)
local Thread = require(script.Parent.Thread)

local IS_SERVER = RunService:IsServer()
local DEFAULT_WAIT_FOR_TIMEOUT = 60
local ATTRIBUTE_ID_NAME = "ComponentServerId"

-- Components will only work on instances parented under these descendants:
local DESCENDANT_WHITELIST = {Workspace, Players}

local Component = {}
Component.__index = Component

local componentsByTag = {}

local function IsDescendantOfWhitelist(instance)
	for _, v in ipairs(DESCENDANT_WHITELIST) do
		if instance:IsDescendantOf(v) then
			return true
		end
	end

	return false
end

function Component.FromTag(tag)
	return componentsByTag[tag]
end

function Component.Auto(folder)
	local function Setup(moduleScript)
		local m = require(moduleScript)
		assert(type(m) == "table", "Expected table for component")
		assert(type(m.Tag) == "string", "Expected .Tag property")
		Component.new(m.Tag, m, m.RenderPriority)
	end

	for _, v in ipairs(folder:GetDescendants()) do
		if v:IsA("ModuleScript") then
			Setup(v)
		end
	end

	folder.DescendantAdded:Connect(function(v)
		if v:IsA("ModuleScript") then
			Setup(v)
		end
	end)
end

function Component.new(tag, class, renderPriority)
	assert(type(tag) == "string", "Argument #1 (tag) should be a string; got " .. type(tag))
	assert(type(class) == "table", "Argument #2 (class) should be a table; got " .. type(class))
	assert(type(class.new) == "function", "Class must contain a .new constructor function")
	assert(type(class.Destroy) == "function", "Class must contain a :Destroy function")
	assert(componentsByTag[tag] == nil, "Component already bound to this tag")

	local self = setmetatable({
		Added = Signal.new();
		Removed = Signal.new();

		_janitor = Janitor.new();
		_lifecycleJanitor = nil;

		_tag = tag;
		_class = class;
		_objects = {};
		_instancesToObjects = {};
		_hasHeartbeatUpdate = type(class.HeartbeatUpdate) == "function";
		_hasSteppedUpdate = type(class.SteppedUpdate) == "function";
		_hasRenderUpdate = type(class.RenderUpdate) == "function";
		_hasInit = type(class.Init) == "function";
		_hasDeinit = type(class.Deinit) == "function";
		_renderPriority = renderPriority or Enum.RenderPriority.Last.Value;
		_lifecycle = false;
		_nextId = 0;
	}, Component)

	self._lifecycleJanitor = self._janitor:Add(Janitor.new(), "Destroy")

	self._janitor:Add(CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
		if IsDescendantOfWhitelist(instance) then
			self:_instanceAdded(instance)
		end
	end), "Disconnect")

	self._janitor:Add(CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
		self:_instanceRemoved(instance)
	end), "Disconnect")

	do
		local b = Instance.new("BindableEvent")
		for _, instance in ipairs(CollectionService:GetTagged(tag)) do
			if IsDescendantOfWhitelist(instance) then
				local c = b.Event:Connect(function()
					self:_instanceAdded(instance)
				end)

				b:Fire()
				c:Disconnect()
			end
		end

		b:Destroy()
	end

	componentsByTag[tag] = self
	self._janitor:Add(function()
		componentsByTag[tag] = nil
	end, true)

	return self
end

function Component:_startHeartbeatUpdate()
	local all = self._objects
	self._heartbeatUpdate = self._lifecycleJanitor:Add(RunService.Heartbeat:Connect(function(dt)
		for _, v in ipairs(all) do
			v:HeartbeatUpdate(dt)
		end
	end), "Disconnect")
end

function Component:_startSteppedUpdate()
	local all = self._objects
	self._steppedUpdate = self._lifecycleJanitor:Add(RunService.Stepped:Connect(function(_, dt)
		for _, v in ipairs(all) do
			v:SteppedUpdate(dt)
		end
	end), "Disconnect")
end

function Component:_startRenderUpdate()
	local all = self._objects
	self._renderName = self._tag .. "RenderUpdate"
	RunService:BindToRenderStep(self._renderName, self._renderPriority, function(dt)
		for _, v in ipairs(all) do
			v:RenderUpdate(dt)
		end
	end)

	self._lifecycleJanitor:Add(function()
		RunService:UnbindFromRenderStep(self._renderName)
	end, true)
end

function Component:_startLifecycle()
	self._lifecycle = true
	if self._hasHeartbeatUpdate then
		self:_startHeartbeatUpdate()
	end

	if self._hasSteppedUpdate then
		self:_startSteppedUpdate()
	end

	if self._hasRenderUpdate then
		self:_startRenderUpdate()
	end
end

function Component:_stopLifecycle()
	self._lifecycle = false
	self._lifecycleJanitor:Cleanup()
end

function Component:_instanceAdded(instance)
	if self._instancesToObjects[instance] then
		return
	end

	if not self._lifecycle then
		self:_startLifecycle()
	end

	self._nextId += 1
	local id = self._tag .. tostring(self._nextId)
	if IS_SERVER then
		instance:SetAttribute(ATTRIBUTE_ID_NAME, id)
	end

	local obj = self._class.new(instance)
	obj.Instance = instance
	obj._id = id
	self._instancesToObjects[instance] = obj
	table.insert(self._objects, obj)

	if self._hasInit then
		Thread.Spawn(function()
			if self._instancesToObjects[instance] ~= obj then
				return
			end

			obj:Init()
		end)
	end

	self.Added:Fire(obj)
	return obj
end

function Component:_instanceRemoved(instance)
	self._instancesToObjects[instance] = nil
	for i, obj in ipairs(self._objects) do
		if obj.Instance == instance then
			if self._hasDeinit then
				obj:Deinit()
			end

			if IS_SERVER and instance.Parent and instance:GetAttribute(ATTRIBUTE_ID_NAME) ~= nil then
				instance:SetAttribute(ATTRIBUTE_ID_NAME, nil)
			end

			self.Removed:Fire(obj)
			obj:Destroy()
			obj._destroyed = true
			TableUtil.FastRemove(self._objects, i)
			break
		end
	end

	if #self._objects == 0 and self._lifecycle then
		self:_stopLifecycle()
	end
end

function Component:GetAll()
	return TableUtil.CopyShallow(self._objects)
end

function Component:GetFromInstance(instance)
	return self._instancesToObjects[instance]
end

function Component:GetFromId(id)
	for _, v in ipairs(self._objects) do
		if v._id == id then
			return v
		end
	end

	return nil
end

Component.GetFromID = Component.GetFromId

function Component:Filter(filterFunc)
	return TableUtil.Filter(self._objects, filterFunc)
end

function Component:WaitFor(instance, timeout)
	local isName = type(instance) == "string"
	local function IsInstanceValid(obj)
		return (isName and obj.Instance.Name == instance) or (not isName and obj.Instance == instance)
	end

	for _, obj in ipairs(self._objects) do
		if IsInstanceValid(obj) then
			return Promise.Resolve(obj)
		end
	end

	local lastObj = nil
	return Promise.FromEvent(self.Added, function(obj)
		lastObj = obj
		return IsInstanceValid(obj)
	end):Then(function()
		return lastObj
	end):Timeout(timeout or DEFAULT_WAIT_FOR_TIMEOUT)
end

function Component:Destroy()
	self._janitor:Destroy()
	setmetatable(self, nil)
end

return Component
