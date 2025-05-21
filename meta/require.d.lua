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
---@field loader? basis.require.loader | basis.require.loader[]

--- Register library with the following options
--- - `alias` – local to this project library name, which can later be referred by `require`
--- - `id` – public library name (in format "user/lib")
--- - `version` – minimum version required
--- - `loader` – Sequence of [loaders](lua://basis.loader) to try (most to least desirable)
--- 
--- At least one of the fields `id` / `loader` should be provided.
--- - If only `id` is provided, loader sequence defaults to "github loader → path loader"
--- - If only `loader` is provided, the `id` is populated from the library init file
--- - If both are provided, `id` is checked to match the value in the library init file (if one exists)
--- 
--- `alias` defaults to the "lib" part of the `id`. If multiple libraries are registered with the same alias, error is thrown.
--- 
--- `version` defaults to "1". It is checked against the value in library init file (if one exists). They should be compatible (that is the major parts are same and the minor specified in init file should not be lower)
---@param options basis.require.lib_options
function exports.lib(options) end

--- Register library by a single string, which may be one of the following:
--- - library tag (id + version (optional) in format "user/lib#version")
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
--- It is very useful to preload dependencies in parallel to speed up loading time.
---@param list string[]
function exports.require(list) end

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------

--- Table of loaders and some related utilities
---@class basis.require.loader
exports.loader = {}

--- Retrieve data from a library tag string of format "user/lib#version"
---@param tag string
---@return string	# user (library publisher)
---@return string	# library name
---@return string?	# version
function exports.loader.parse_lib_tag(tag) end

------------------------------------------------------

--- Yes
---@class basis.require.loader.base
exports.loader.base = (class{})

---@param user string
---@param lib string
---@param version? string
function exports.loader.base:SetLib(user, lib, version) end

--- Allows to override version, which is checked against init file. In base class, just returns passed version
---@return string?
function exports.loader.base:Version() end

---@param module string
---@param callback fun(body?: fun(), err?: string)
function exports.loader.base:Load(module, callback) end

---@param other basis.require.loader.base
---@return boolean
function exports.loader.base:Covers(other) end

------------------------------------------------------

---@class basis.require.loader.path: basis.require.loader

------------------------------------------------------

---@class basis.require.loader.url: basis.require.loader

------------------------------------------------------

---@class basis.require.loader.github: basis.require.loader

---@return basis.require.loader.github
function exports.loader.github() end
exports.loader.github = (class{}) --[[@as basis.require.loader.github]]

------------------------------------------------------

---@class basis.require.loader.private: basis.require.loader