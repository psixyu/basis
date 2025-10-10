---@meta

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------

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
--- If set up, error will not be thrown in the main thread on loading failure (in oppose to the 0default behaviour)
---@param callback fun(string)
function exports.on_error(callback) end

--- Check wether the require process is in init state (requested libraries' init files have not been yet executed completely)
---@return boolean
function exports.is_init() end

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------

---@alias basis.require.promise.runner fun(resolve: fun(...), error: fun(msg: string))

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

---@return ...
function promise:Await() end

---@param run basis.require.promise.runner
---@return basis.require.promise
function exports.promise(run) end
exports.promise = (class{}) --[[@as basis.require.promise]]

------------------------------------------------------

---@param promise basis.require.promise
---@return ...
function exports.await(promise) end

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------

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

------------------------------------------------------

--- Yes
---@class basis.require.loader.base
exports.loader.base = (class{})

--- Lib id specified in lib options
---@return string?
function exports.loader.base:GetOptionsID() end

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
---@param callback fun(body?: string, err?: string)
function exports.loader.base:Load(module, callback) end

--- Asynchronously load lib's init file source
--- 
--- `callback` is called then loading process is done.
--- - `body` – Init file content. If library have no init file, should be empty string. If nil, loading error is thrown.
--- - `err` – Optional error message to throw when something went wrong. 
---@param callback fun(body?: string, err?: string)
function exports.loader.base:LoadInit(callback) end

------------------------------------------------------

---@class basis.require.loader.path: basis.require.loader.base

---@param adr string
---@return basis.require.loader.path
function exports.loader.path(adr) end
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