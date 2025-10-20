---@meta

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
-- main functions

---@class basis.require
local exports = {}

---@class (exact) basis.require.lib_options
---@field alias? string
---@field id? string
---@field version? string 
---@field loader? basis.require.loader.base

---@class (exact) basis.require.manifest
---@field user string
---@field name string
---@field version string

--- Register library with the following options
--- - `alias` – local to this project library name, which can later be referred by `require`
--- - `id` – public library name (in format "@user/lib")
--- - `version` – minimum version required
--- - `loader` – [loader](lua://basis.require.loader.base) to obtain source code
--- 
--- At least one of the fields `id` / `loader` should be provided.
--- - If only `id` is provided, loader defaults to github loader
--- - If only `loader` is provided, the `id` is populated from the library init file
--- - If both are provided, `id` is checked to match the value in the library init file (if one exists)
--- 
--- `alias` defaults to the "lib" part of the `id`. If multiple libraries are registered with the same alias, error is thrown.
--- 
--- `version` is checked to match the v alue in the library init file. If it's not specified, it will be resolved by loader.
---@param options basis.require.lib_options
function exports.lib(options) end

--- Register library by a single string, which may be one of the following:
--- - library tag: id + version (optional) in format "@user/lib#version" (uses github)
--- - web url (uses url loader)
--- - local path (uses path loader)
---@param source string
function exports.lib(source) end

--- Require module in format "lib:module". Lib name may be both tag or alias.
--- 
--- If only module name is specified, own module with that name will be loaded, hence this may be used only inside libraries.
--- 
--- Loading is async in main thread and is synced in other threads (and since modules are never executed in main thread, it is always synced inside any module). Async require of not-yet-loaded module returns empty table, which will be populated by the module when it is loaded.
---@param name string
---@return table
function exports.require(name) end

--- Asynchronously load set of modules (with no return). All the listed modules will be loaded in parallel.
--- 
--- Command itself is still synced in non-main thread, so it will wait until all the modules are loaded before proceeding to the next command.
--- 
--- It may be a good decision to preload dependencies in parallel to speed up loading time.
---@param list string[]
function exports.require(list) end

--- Specify callback to execute when all async require requests are successfully done
---@param callback fun()
function exports.on_load(callback) end

--- Specify callback to execute when some async require requests has failed. Error message is passed.
--- 
--- If set up, error will not be thrown on loading failure (in oppose to the default behaviour)
---@param callback fun(msg: string, level?: integer)
function exports.on_error(callback) end

--- Check wether the require process is in init state (requested libraries have not been yet resolved completely)
---@return boolean
function exports.is_init() end

---@alias basis.require.thinker_func fun(): boolean?

--- Add thinker function, which is executed every tick. Return `true` to stop.
--- 
--- If you need to setup thinkers in init state (especialy on client), please use this instead of SetThink or SetContextThink to avoid bugs. Throwing errors is safe and is logged.
---@param func basis.require.thinker_func
function exports.add_thinker(func) end

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
-- promise

---@alias basis.require.promise.runner fun(resolve: fun(...), error: fun(msg: string, level: integer))

---@class basis.require.promise
---@field private resolved boolean
---@field private error boolean
---@field private result any[]
---@field private result_count integer
---@field private error_msg? string
---@field private callback? fun(...)
local promise = {}

---@param callback fun(...)
---@param error_callback? fun(msg: string, lvl: integer)
---@return basis.require.promise
function promise:Then(callback, error_callback) end

---@return basis.require.promise
function promise:RaiseErrors() end

---@return ...
function promise:Await() end

---@return ...
function promise:Result() end

---@return boolean
function promise:Resolved() end

---@param run basis.require.promise.runner
---@param setup? fun(self: basis.require.promise)
---@return basis.require.promise
function exports.promise(run, setup) end
exports.promise = (class{}) --[[@as basis.require.promise]]

---@param promises basis.require.promise[]
---@param callback fun()
---@param error_callback? fun(msg: string, lvl: integer)
function exports.multi_then(promises, callback, error_callback) end

---@param promise basis.require.promise|nil
---@param run basis.require.promise.runner
---@param setup? fun(self: basis.require.promise)
---@return basis.require.promise
function exports.chain(promise, run, setup) end

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
-- loaders

---@alias basis.require.module_body fun(): table
---@alias basis.require.init_file_body fun(): basis.require.manifest?

------------------------------------------------------

--- Table of loaders and some related utilities
---@class basis.require.loaders
exports.loader = {}

--- Retrieve data from a library tag string of format "@user/lib#version"
---@param tag string
---@return string	# user (library author)
---@return string	# library name
---@return string?	# version
function exports.loader.parse_lib_tag(tag) end

--- Check loaders for equality
---@param l basis.require.loader.base
---@param r basis.require.loader.base
---@return boolean
function exports.loader.equal(l, r) end

------------------------------------------------------

--- Yes
---@class basis.require.loader.base
---@field options basis.require.lib_options
exports.loader.base = (class{})

--- Lib debug name for logs
---@return string
function exports.loader.base:GetName() end

--- Lib id specified in lib options
---@return string?
function exports.loader.base:GetOptionsID() end

--- Version specified in lib options
---@return string?
function exports.loader.base:GetOptionsVersion() end

--- Version of the lib to load
---@return string?
function exports.loader.base:GetVersion() end

--- Resolve default version if it was not provided in options
---@return string?
function exports.loader.base:DefaultVersion() end

--- Asynchronously load the module's source
--- 
--- `callback` is called then loading process is done.
--- - `body` – Module body which returns exports. If nil, loading error is thrown.
--- - `err` – Optional error message to throw when something went wrong. 
---@param module string
---@param callback fun(body?: basis.require.module_body, err?: string)
function exports.loader.base:Load(module, callback) end

--- Asynchronously load lib's init file source
--- 
--- `callback` is called then loading process is done.
--- - `body` – Init file content. If library have no init file, should be empty string. If nil, loading error is thrown.
--- - `err` – Optional error message to throw when something went wrong. 
---@param callback fun(body?: basis.require.init_file_body, err?: string)
function exports.loader.base:LoadInit(callback) end

--- Equality check (parameter has the same class)
--- 
--- Must be overridden for any custom loader
---@param loader basis.require.loader.base
---@return boolean
function exports.loader.base:Equal(loader) end

------------------------------------------------------

---@class basis.require.loader.path: basis.require.loader.base

---@param root string
---@return basis.require.loader.path
function exports.loader.path(root) end
exports.loader.path = (class{}) --[[@as basis.require.loader.path]]

------------------------------------------------------

---@class basis.require.loader.url: basis.require.loader.base

---@param adr string
---@return basis.require.loader.url
function exports.loader.url(adr) end
exports.loader.url = (class{}) --[[@as basis.require.loader.url]]

------------------------------------------------------

---@class basis.require.loader.github: basis.require.loader.base

---@return basis.require.loader.github
function exports.loader.github() end
exports.loader.github = (class{}) --[[@as basis.require.loader.github]]

------------------------------------------------------

---@class basis.require.loader.webkey: basis.require.loader.base

------------------------------------------------------

--- Sequence of loaders to try from most to least desirable. On every module load, they will be attempted in order until first successful loading.
---@class basis.require.loader.fallback: basis.require.loader.base

---@param sequence basis.require.loader.base[]
---@return basis.require.loader.fallback
function exports.loader.fallback(sequence) end
exports.loader.fallback = (class{}) --[[@as basis.require.loader.fallback]]

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
-- debug

function exports.__clear_libs() end

---@param tag string
---@return boolean
function exports.__check_lib(tag) end

---@param func fun()
---@param error fun(msg: string, lvl?: integer)
function exports.__spcall(func, error) end