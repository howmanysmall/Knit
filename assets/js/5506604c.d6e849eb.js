"use strict";(self.webpackChunkdocs=self.webpackChunkdocs||[]).push([[662],{63193:e=>{e.exports=JSON.parse('{"functions":[{"name":"CreateService","desc":"Constructs a new service.\\n\\n:::caution\\nServices must be created _before_ calling `Knit.Start()`.\\n:::\\n```lua\\n-- Create a service\\nlocal MyService = Knit.CreateService {\\n\\tName = \\"MyService\\",\\n\\tClient = {},\\n}\\n\\n-- Expose a ToAllCaps remote function to the clients\\nfunction MyService.Client:ToAllCaps(player, msg)\\n\\treturn msg:upper()\\nend\\n\\n-- Knit will call KnitStart after all services have been initialized\\nfunction MyService:KnitStart()\\n\\tprint(\\"MyService started\\")\\nend\\n\\n-- Knit will call KnitInit when Knit is first started\\nfunction MyService:KnitInit()\\n\\tprint(\\"MyService initialize\\")\\nend\\n```","params":[{"name":"serviceDefinition","desc":"","lua_type":"ServiceDef"}],"returns":[{"desc":"","lua_type":"Service\\n"}],"function_type":"static","source":{"line":198,"path":"src/KnitServer.luau"}},{"name":"AddServices","desc":"Requires all the modules that are children of the given parent. This is an easy\\nway to quickly load all services that might be in a folder.\\n```lua\\nKnit.AddServices(somewhere.Services)\\n```","params":[{"name":"parent","desc":"","lua_type":"Instance"}],"returns":[{"desc":"","lua_type":"{Service}\\n"}],"function_type":"static","source":{"line":231,"path":"src/KnitServer.luau"}},{"name":"AddServicesDeep","desc":"Requires all the modules that are descendants of the given parent.","params":[{"name":"parent","desc":"","lua_type":"Instance"}],"returns":[{"desc":"","lua_type":"{Service}\\n"}],"function_type":"static","source":{"line":253,"path":"src/KnitServer.luau"}},{"name":"GetService","desc":"Gets the service by name. Throws an error if the service is not found.","params":[{"name":"serviceName","desc":"","lua_type":"string"}],"returns":[{"desc":"","lua_type":"Service\\n"}],"function_type":"static","source":{"line":275,"path":"src/KnitServer.luau"}},{"name":"GetServices","desc":"Gets a table of all services.","params":[],"returns":[{"desc":"","lua_type":"{[string]: Service}\\n"}],"function_type":"static","source":{"line":287,"path":"src/KnitServer.luau"}},{"name":"CreateSignal","desc":"Returns a marker that will transform the current key into\\na RemoteSignal once the service is created. Should only\\nbe called within the Client table of a service.\\n\\nSee [RemoteSignal](https://sleitnick.github.io/RbxUtil/api/RemoteSignal)\\ndocumentation for more info.\\n```lua\\nlocal MyService = Knit.CreateService {\\n\\tName = \\"MyService\\",\\n\\tClient = {\\n\\t\\t-- Create the signal marker, which will turn into a\\n\\t\\t-- RemoteSignal when Knit.Start() is called:\\n\\t\\tMySignal = Knit.CreateSignal(),\\n\\t},\\n}\\n\\nfunction MyService:KnitInit()\\n\\t-- Connect to the signal:\\n\\tself.Client.MySignal:Connect(function(player, ...) end)\\nend\\n```","params":[],"returns":[{"desc":"","lua_type":"SIGNAL_MARKER"}],"function_type":"static","source":{"line":317,"path":"src/KnitServer.luau"}},{"name":"CreateUnreliableSignal","desc":"Returns a marker that will transform the current key into\\nan unreliable RemoteSignal once the service is created. Should\\nonly be called within the Client table of a service.\\n\\nSee [RemoteSignal](https://sleitnick.github.io/RbxUtil/api/RemoteSignal)\\ndocumentation for more info.\\n\\n:::info Unreliable Events\\nInternally, this uses UnreliableRemoteEvents, which allows for\\nnetwork communication that is unreliable and unordered. This is\\nuseful for events that are not crucial for gameplay, since the\\ndelivery of the events may occur out of order or not at all.\\n\\nSee  the documentation for [UnreliableRemoteEvents](https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent)\\nfor more info.","params":[],"returns":[{"desc":"","lua_type":"UNRELIABLE_SIGNAL_MARKER"}],"function_type":"static","source":{"line":340,"path":"src/KnitServer.luau"}},{"name":"CreateProperty","desc":"Returns a marker that will transform the current key into\\na RemoteProperty once the service is created. Should only\\nbe called within the Client table of a service. An initial\\nvalue can be passed along as well.\\n\\nRemoteProperties are great for replicating data to all of\\nthe clients. Different data can also be set per client.\\n\\nSee [RemoteProperty](https://sleitnick.github.io/RbxUtil/api/RemoteProperty)\\ndocumentation for more info.\\n\\n```lua\\nlocal MyService = Knit.CreateService {\\n\\tName = \\"MyService\\",\\n\\tClient = {\\n\\t\\t-- Create the property marker, which will turn into a\\n\\t\\t-- RemoteProperty when Knit.Start() is called:\\n\\t\\tMyProperty = Knit.CreateProperty(\\"HelloWorld\\"),\\n\\t},\\n}\\n\\nfunction MyService:KnitInit()\\n\\t-- Change the value of the property:\\n\\tself.Client.MyProperty:Set(\\"HelloWorldAgain\\")\\nend\\n```","params":[{"name":"initialValue","desc":"","lua_type":"any"}],"returns":[{"desc":"","lua_type":"PROPERTY_MARKER"}],"function_type":"static","source":{"line":373,"path":"src/KnitServer.luau"}},{"name":"Start","desc":"Starts Knit. Should only be called once.\\n\\nOptionally, `KnitOptions` can be passed in order to set\\nKnit\'s custom configurations.\\n\\n:::caution\\nBe sure that all services have been created _before_\\ncalling `Start`. Services cannot be added later.\\n:::\\n\\n```lua\\nKnit.Start():andThen(function()\\n\\tprint(\\"Knit started!\\")\\nend):catch(warn)\\n```\\n\\nExample of Knit started with options:\\n```lua\\nKnit.Start({\\n\\tMiddleware = {\\n\\t\\tInbound = {\\n\\t\\t\\tfunction(player, args)\\n\\t\\t\\t\\tprint(\\"Player is giving following args to server:\\", args)\\n\\t\\t\\t\\treturn true\\n\\t\\t\\tend\\n\\t\\t},\\n\\t},\\n}):andThen(function()\\n\\tprint(\\"Knit started!\\")\\nend):catch(warn)\\n```","params":[{"name":"options","desc":"","lua_type":"KnitOptions?"}],"returns":[{"desc":"","lua_type":"Promise"}],"function_type":"static","source":{"line":411,"path":"src/KnitServer.luau"}},{"name":"OnStart","desc":"Returns a promise that is resolved once Knit has started. This is useful\\nfor any code that needs to tie into Knit services but is not the script\\nthat called `Start`.\\n```lua\\nKnit.OnStart():andThen(function()\\n\\tlocal MyService = Knit.Services.MyService\\n\\tMyService:DoSomething()\\nend):catch(warn)\\n```","params":[],"returns":[{"desc":"","lua_type":"Promise"}],"function_type":"static","source":{"line":623,"path":"src/KnitServer.luau"}}],"properties":[{"name":"Util","desc":"References the Util folder. Should only be accessed when using Knit as\\na standalone module. If using Knit from Wally, modules should just be\\npulled in via Wally instead of relying on Knit\'s Util folder, as this\\nfolder only contains what is necessary for Knit to run in Wally mode.","lua_type":"Folder","readonly":true,"source":{"line":132,"path":"src/KnitServer.luau"}}],"types":[{"name":"Middleware","desc":"","fields":[{"name":"Inbound","lua_type":"ServerMiddleware?","desc":""},{"name":"Outbound","lua_type":"ServerMiddleware?","desc":""}],"source":{"line":14,"path":"src/KnitServer.luau"}},{"name":"ServerMiddlewareFn","desc":"For more info, see [ServerComm](https://sleitnick.github.io/RbxUtil/api/ServerComm/) documentation.","lua_type":"(player: Player, args: {any}) -> (shouldContinue: boolean, ...: any)","source":{"line":26,"path":"src/KnitServer.luau"}},{"name":"ServerMiddleware","desc":"An array of server middleware functions.","lua_type":"{ServerMiddlewareFn}","source":{"line":33,"path":"src/KnitServer.luau"}},{"name":"ServiceDef","desc":"Used to define a service when creating it in `CreateService`.\\n\\nThe middleware tables provided will be used instead of the Knit-level\\nmiddleware (if any). This allows fine-tuning each service\'s middleware.\\nThese can also be left out or `nil` to not include middleware.","fields":[{"name":"Name","lua_type":"string","desc":""},{"name":"Client","lua_type":"table?","desc":""},{"name":"Middleware","lua_type":"Middleware?","desc":""},{"name":"[any]","lua_type":"any","desc":""}],"source":{"line":48,"path":"src/KnitServer.luau"}},{"name":"Service","desc":"","fields":[{"name":"dName","lua_type":"string","desc":""},{"name":"dClient","lua_type":"ServiceClient","desc":""},{"name":"dKnitComm","lua_type":"Comm","desc":""},{"name":"[any]","lua_type":"any","desc":""}],"source":{"line":63,"path":"src/KnitServer.luau"}},{"name":"ServiceClient","desc":"","fields":[{"name":"Server","lua_type":"Service","desc":""},{"name":"[any]","lua_type":"any","desc":""}],"source":{"line":76,"path":"src/KnitServer.luau"}},{"name":"KnitOptions","desc":"- Middleware will apply to all services _except_ ones that define\\ntheir own middleware.","fields":[{"name":"Middleware","lua_type":"Middleware?","desc":""},{"name":"SpawnRunServiceFunctions","lua_type":"\\"None\\" | \\"Defer\\" | \\"Spawn\\" | nil","desc":""}],"source":{"line":90,"path":"src/KnitServer.luau"}}],"name":"KnitServer","desc":"Knit server-side lets developers create services and expose methods and signals\\nto the clients.\\n\\n```lua\\nlocal Knit = require(somewhere.Knit)\\n\\n-- Load service modules within some folder:\\nKnit.AddServices(somewhere.Services)\\n\\n-- Start Knit:\\nKnit.Start():andThen(function()\\n\\tprint(\\"Knit started\\")\\nend):catch(warn)\\n```","realm":["Server"],"source":{"line":121,"path":"src/KnitServer.luau"}}')}}]);