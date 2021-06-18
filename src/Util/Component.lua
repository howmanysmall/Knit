-- Component
-- Stephen Leitnick
-- July 25, 2020

--[[

	Component.Auto(folder: Instance)
		-> Create components automatically from descendant modules of this folder
		-> Each module must have a '.Tag' string property
		-> Each module optionally can have '.RenderPriority' number property

	component = Component.FromTag(tag: string)
		-> Retrieves an existing component from the tag name

	Component.ObserveFromTag(tag: string, observer: (component: Component, janitor: Janitor) -> void): Janitor

	component = Component.new(tag: string, class: table [, renderPriority: RenderPriority, requireComponents: {string}])
		-> Creates a new component from the tag name, class module, and optional render priority

	component:GetAll(): ComponentInstance[]
	component:GetFromInstance(instance: Instance): ComponentInstance | nil
	component:GetFromID(id: number): ComponentInstance | nil
	component:Filter(filterFunc: (comp: ComponentInstance) -> boolean): ComponentInstance[]
	component:WaitFor(instanceOrName: Instance | string [, timeout: number = 60]): Promise<ComponentInstance>
	component:Observe(instance: Instance, observer: (component: ComponentInstance, janitor: Janitor) -> void): Janitor
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
Component.ClassName = "Component"
Component.__index = Component

local componentsByTag = {}

local componentByTagCreated = Signal.new()
local componentByTagDestroyed = Signal.new()

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

function Component.ObserveFromTag(tag, observer)
	local janitor = Janitor.new()
	local observeJanitor = janitor:Add(Janitor.new(), "Destroy")
	local function OnCreated(component)
		if component._tag == tag then
			observer(component, observeJanitor)
		end
	end

	local function OnDestroyed(component)
		if component._tag == tag then
			observeJanitor:Cleanup()
		end
	end

	do
		local component = Component.FromTag(tag)
		if component then
			Thread.SpawnNow(OnCreated, component)
		end
	end

	janitor:Add(componentByTagCreated:Connect(OnCreated), "Disconnect")
	janitor:Add(componentByTagDestroyed:Connect(OnDestroyed), "Disconnect")
	return janitor
end

function Component.Auto(folder)
	local function Setup(moduleScript)
		local m = require(moduleScript)
		assert(type(m) == "table", "Expected table for component")
		assert(type(m.Tag) == "string", "Expected .Tag property")
		Component.new(m.Tag, m, m.RenderPriority, m.RequiredComponents)
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

local function startHeartbeatUpdate(this)
	local self = this
	local all = self._objects
	self._heartbeatUpdate = self._lifecycleJanitor:Add(RunService.Heartbeat:Connect(function(dt)
		for _, v in ipairs(all) do
			v:HeartbeatUpdate(dt)
		end
	end), "Disconnect")
end

local function startSteppedUpdate(this)
	local self = this
	local all = self._objects
	self._steppedUpdate = self._lifecycleJanitor:Add(RunService.Stepped:Connect(function(_, dt)
		for _, v in ipairs(all) do
			v:SteppedUpdate(dt)
		end
	end), "Disconnect")
end

local function startRenderUpdate(this)
	local self = this
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

local function startLifecycle(this)
	local self = this
	self._lifecycle = true
	if self._hasHeartbeatUpdate then
		startHeartbeatUpdate(self)
	end

	if self._hasSteppedUpdate then
		startSteppedUpdate(self)
	end

	if self._hasRenderUpdate then
		startRenderUpdate(self)
	end
end

local function stopLifecycle(this)
	local self = this
	self._lifecycle = false
	self._lifecycleJanitor:Cleanup()
end

local function instanceAdded(this, instance)
	local self = this
	if self._instancesToObjects[instance] then
		return
	end

	if not self._lifecycle then
		startLifecycle(self)
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

local function instanceRemoved(this, instance)
	local self = this
	if not self._instancesToObjects[instance] then
		return
	end

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
		stopLifecycle(self)
	end
end

function Component.new(tag, class, renderPriority, requireComponents)
	assert(type(tag) == "string", "Argument #1 (tag) should be a string; got " .. type(tag))
	assert(type(class) == "table", "Argument #2 (class) should be a table; got " .. type(class))
	assert(type(class.new) == "function", "Class must contain a .new constructor function")
	assert(type(class.Destroy) == "function", "Class must contain a :Destroy function")
	assert(componentsByTag[tag] == nil, "Component already bound to this tag")

	local self = setmetatable({
		Added = nil;
		Removed = nil;

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
		_requireComponents = requireComponents or {};
		_lifecycle = false;
		_nextId = 0;
	}, Component)

	self._lifecycleJanitor = self._janitor:Add(Janitor.new(), "Destroy")
	self.Added = Signal.new(self._janitor)
	self.Removed = Signal.new(self._janitor)

	local observeJanitor = self._janitor:Add(Janitor.new(), "Destroy")

	local function ObserveTag()
		local function HasRequiredComponents(instance)
			for _, reqComp in ipairs(self._requireComponents) do
				local comp = Component.FromTag(reqComp)
				if comp:GetFromInstance(instance) == nil then
					return false
				end
			end

			return true
		end

		observeJanitor:Add(CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
			if IsDescendantOfWhitelist(instance) and HasRequiredComponents(instance) then
				instanceAdded(self, instance)
			end
		end), "Disconnect")

		observeJanitor:Add(CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
			instanceRemoved(self, instance)
		end), "Disconnect")

		for _, reqComp in ipairs(self._requireComponents) do
			local comp = Component.FromTag(reqComp)
			observeJanitor:Add(comp.Added:Connect(function(obj)
				if CollectionService:HasTag(obj.Instance, tag) and HasRequiredComponents(obj.Instance) then
					instanceAdded(self, obj.Instance)
				end
			end), "Disconnect")

			observeJanitor:Add(comp.Removed:Connect(function(obj)
				if CollectionService:HasTag(obj.Instance, tag) then
					instanceRemoved(self, obj.Instance)
				end
			end), "Disconnect")
		end

		observeJanitor:Add(function()
			stopLifecycle(self)
			for instance in next, self._instancesToObjects do
				instanceRemoved(self, instance)
			end
		end, true)

		do
			local b = Instance.new("BindableEvent")
			for _, instance in ipairs(CollectionService:GetTagged(tag)) do
				if IsDescendantOfWhitelist(instance) and HasRequiredComponents(instance) then
					local c = b.Event:Connect(function()
						instanceAdded(self, instance)
					end)

					b:Fire()
					c:Disconnect()
				end
			end

			b:Destroy()
		end
	end

	if #self._requireComponents == 0 then
		ObserveTag()
	else
		-- Only observe tag when all required components are available:
		local tagsReady = {}
		for _, reqComp in ipairs(self._requireComponents) do
			tagsReady[reqComp] = false
		end

		local function Check()
			for _, ready in next, tagsReady do
				if not ready then
					return
				end
			end

			ObserveTag()
		end

		local function Cleanup()
			observeJanitor:Cleanup()
		end

		for _, requiredComponent in ipairs(self._requireComponents) do
			tagsReady[requiredComponent] = false
			self._janitor:Add(Component.ObserveFromTag(requiredComponent, function(_, janitor)
				tagsReady[requiredComponent] = true
				Check()
				janitor:Add(function()
					tagsReady[requiredComponent] = false
					Cleanup()
				end, true)
			end), "Destroy")
		end
	end

	componentsByTag[tag] = self
	componentByTagCreated:Fire(self)
	self._janitor:Add(function()
		componentsByTag[tag] = nil
		componentByTagDestroyed:Fire(self)
	end, true)

	return self
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

function Component:Observe(instance, observer)
	local janitor = Janitor.new()
	local observeJanitor = janitor:Add(Janitor.new(), "Destroy")
	janitor:Add(self.Added:Connect(function(obj)
		if obj.Instance == instance then
			observer(obj, observeJanitor)
		end
	end), "Disconnect")

	janitor:Add(self.Removed:Connect(function(obj)
		if obj.Instance == instance then
			observeJanitor:Cleanup()
		end
	end), "Disconnect")

	for _, obj in ipairs(self._objects) do
		if obj.Instance == instance then
			Thread.SpawnNow(observer, obj, observeJanitor)
			break
		end
	end

	return janitor
end

function Component:Destroy()
	self._janitor:Destroy()
	setmetatable(self, nil)
end

function Component:__tostring()
	return "Component"
end

return Component
