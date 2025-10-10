---@type basis.require
local exports = ({})

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------

---@generic T: table
---@param src T
---@param dst? T
---@return T
local function copy(src, dst)
	if dst == nil then
		dst = {}
	end
	
	for k, v in pairs(src) do
		dst[k] = v
	end
	
	return dst
end

------------------------------------------------------

---@param t table
---@return number
local function max_key(t)
	local max = 0
	for k, v in pairs(t) do
		if type(k) == 'number' then
			if k > max then
				max = k
			end
		end
	end
	return max
end


------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
-- setup threads and thinkers

local SETUP_STATE = 2

---@type fun()[]
local setup_callbacks = {}

---@param func fun()
local function on_setup(func)
	if GameRules and GameRules:State_Get() >= SETUP_STATE then
		func()
	else
		table.insert(setup_callbacks, func)
	end
end

ListenToGameEvent(
	'game_rules_state_change',
	function()
		if GameRules:State_Get() == SETUP_STATE then
			for _, func in ipairs(setup_callbacks) do
				func()
			end
			setup_callbacks = {}
		end
	end,
	nil
)

ListenToGameEvent(
	'player_chat',
	function()
		print('niga')
	end,
	nil
)

------------------------------------------------------

---@type fun()[]
local thinkers = {}
local main_thinker_number = 0

---@param func fun()
local function add_thinker(func)
	table.insert(thinkers, func)
end

local function get_thinker_ent()
	if IsServer() then
		return GameRules:GetGameModeEntity()
	end
	return Entities:First()
end

local function reset_main_thinker()
	main_thinker_number = main_thinker_number + 1
	
	get_thinker_ent():SetContextThink(
		'basis.require' .. main_thinker_number,
		function()
			for i = #thinkers, 1, -1 do
				local func = thinkers[i]
				local status, err = pcall(func)
				
				if not status then
					table.remove(thinkers, i)
					
					reset_main_thinker()
					error(err, 0)
				end
			end
			
			return FrameTime()
		end,
		0
	)
end

------------------------------------------------------

---@param msg string
local function async_error(msg)
	add_thinker(
		function()
			error(msg, 0)
		end
	)
end

------------------------------------------------------

---@type thread[]
local threads = {}

---@param func fun()
local function add_thread(func)
	table.insert(threads, coroutine.create(func))
end

add_thinker(
	function()
		local to_delete = {}	---@type integer[]
		local errors = {}		---@type string[]
		
		for i, thread in ipairs(threads) do
			local ok, err = coroutine.resume(thread)
			
			if coroutine.status(thread) == "dead" then
				table.insert(to_delete, i)
				if not ok then
					table.insert(errors, err)
				end
			end
		end
		
		for i = #to_delete, 1, -1 do
			table.remove(threads, i)
		end
		
		for _, err in ipairs(errors) do
			async_error(err)
		end
	end
)

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
-- promise

local function is_main_thread()
	local thread, main = coroutine.running()
	return main
end

------------------------------------------------------

---@class basis.require.promise
local promise = {
	resolved = false,
	result_count = 0,
}

---@private
---@return ...
function promise:unpack()
	return table.unpack(self.result, 1, self.result_count)
end

---@private
function promise:call()
	if self.callback ~= nil then
		self.callback(self:unpack())
	end
end

---@private
function promise:call_error()
	if self.error_callback ~= nil then
		self.error_callback(self.error_msg, 0)
	end
end

---@private
---@param run basis.require.promise.runner
function promise:constructor(run)
	self.result = {}
	
	run(
		function(...)
			if self.resolved or self.error then
				error('Multiple resolve', 0)
			end
		
			self.resolved = true
			self.result = {...}
			self.result_count = max_key(self.result)
		
			self:call()
		end,
		
		function(msg)
			if self.resolved or self.error then
				error('Multiple resolve', 0)
			end
			
			self.error = true
			self.error_msg = debug.traceback(msg, 2)
			
			self:call_error()
		end
	)
end

function promise:Then(callback, error_callback)
	if self.callback ~= nil then
		error('Chaining the same promise twice', 0)
	end

	self.callback = callback
	self.error_callback = error_callback
		
	if self.resolved then
		self:call()
	elseif self.error then
		self:call_error()
	end
	
	return self
end

function promise:Await()
	if not is_main_thread() then
		while true do
			if self.resolved then
				return self:unpack()
			end
			if self.error then
				error(self.error_msg, 0)
			end
		end
	end
end

exports.promise = class(promise)

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
--- module class

---@class basis.require._module
local c_module = {
	lib = nil,			---@type basis.require._lib
	exports = nil,		---@type table
	name = nil,			---@type string
	loaded = false,		---@type boolean
		
	---@param self basis.require._module
	---@param lib basis.require._lib
	---@param name string
	constructor = function(self, lib, name)
		self.lib = lib
		self.name = name
		self.exports = {}
	end,
	
	---@param self basis.require._module
	---@param func basis.require.module_body
	exec = function(self, func)
		func = self:setup_executable(func)
		
		add_thread(
			function()
				copy(func(), self.exports)
				self.loaded = true
			end
		)
	end,
	
	---@param self basis.require._module
	---@param func basis.require.module_body
	---@return fun(): table
	setup_executable = function(self, func)
		return func
	end,
}
---@overload fun(lib: basis.require._lib, name: string): basis.require._module
local c_module = class(c_module)

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
--- lib class

local pending_libs = 0

---@return boolean
local function libs_ready()
	return pending_libs == 0
end

------------------------------------------------------

local libs_ready_callbacks = {}		---@type fun()[]

---@return basis.require.promise
local function on_libs_ready()
	return exports.promise(
		function(resolve)
			table.insert(libs_ready_callbacks, resolve)
		end
	)
end

local function check_libs_ready()
	if libs_ready() then
		for _, callback in ipairs(libs_ready_callbacks) do
			callback()
		end
		
		libs_ready_callbacks = {}
	end
end

------------------------------------------------------

---@class basis.require._lib
local c_lib = {
	modules = nil,		---@type {[string]: basis.require._module}
	options = nil,		---@type basis.require.lib_options
	
	---@param self basis.require._lib
	---@param options basis.require.lib_options
	constructor = function(self, options)
		self.options = copy(options)
		modules = {}
	end,
	
	has_id = function(self)
	end,
	
	has_version = function(self)
	end,
	
	---@param self basis.require._lib
	load_init = function(self)
		self.options.loader:LoadInit(function(src, err)
			
		end)
	end,
	
	---@param self basis.require._lib
	---@param name string
	---@return basis.require._module
	get_module = function(self, name)
		local module = self.modules[name]
		if module then
			return module
		end
		
		module = c_module(self, name)
		self.modules[name] = module
		return module
	end,
}
---@overload fun(options: basis.require.lib_options): basis.require._lib
local c_lib = class(c_lib)

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------

-- ---@param lib string
-- ---@return string
-- local function lib_name(lib)
	
-- end

---@param name string
---@return string?, string
local function parse_module_name(name)
	if name:match('[^:]+:[^:]+') then
		return name:match('(.*):(.*)')
		
	elseif name:match('[^:]+') then
		return nil, name
		
	else
		error('invalid module name', 0)
	end
end

---@param loader basis.require.loader.base
---@param module string
---@return table?
local function find_module(loader, module)
	
end

-- local function create

---@param lib string?
---@return basis.require.loader.base[]
local function get_loaders(lib)
	
end


------------------------------------------------------

---@param user string
---@param lib string
---@return string
local function lib_id(user, lib)
	return '@' .. user .. '/' .. lib
end

------------------------------------------------------

---@param str string
---@return string?, string?, string?
local function parse_lib_tag(str)
	return str:match('@(%w+)/(%w+)#?(%w*)')
end

------------------------------------------------------

---@param str string
---@return string?
local function parse_url(str)
	return str:match('https?://(.+)')
end

------------------------------------------------------

---@param str string
---@return boolean
local function is_file_path(str)
	local start = 0
	
	while true do
		local left, right = str:find('/?%w+', start)
		if left then
			start = right + 1
		else
			break
		end
	end
	
	return str ~= '' and str:sub(start) == ''
end

------------------------------------------------------

---@param str string
---@return basis.require.lib_options
local function lib_string_options(str)
	local user, lib, version = parse_lib_tag(str)
	if user and lib then
		return {
			alias = lib,
			id = lib_id(user, lib),
			version = version,
			loader = exports.loader.github(),
		}
	end
	
	local adr = parse_url(str)
	if adr then
		return {
			alias = adr,
			loader = exports.loader.url(str),
		}
	end
	
	if is_file_path(str) then
		return {
			alias = str,
			loader = exports.loader.path(str),
		}
	end
	
	error('Bad library string', 0)
end

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------

---@return basis.require._lib
local function get_current_lib()

end

------------------------------------------------------

---@param tag string|nil
---@return basis.require._lib
local function get_lib(tag)

end

------------------------------------------------------

exports.lib = function(options)
	if type(options) == "string" then
		options = lib_string_options(options)
	end
	
	local lib = c_lib(options)
	lib:load_init()
	
	
	
	
end

------------------------------------------------------

---@param name string
local function require_single(name)
	local tag, module = parse_module_name(name)
	local lib = get_lib(tag)
	
	
end

------------------------------------------------------

exports.require = function(arg)
	if type(arg) == 'string' then
		on_libs_ready()
			:Then(
				function()
					require_single(arg)
				end,
				error
			)
			:Await()
			
		-- on_ready(function()
		
		-- end)
		-- -- await(libs_ready,
	
	
		-- local loaders = get_loaders(lib)
		-- local errs = {}
		
		-- local next = ipairs(loaders)
		-- local i, loader = next(loaders)
		
		-- local function try_loader()
		-- 	if loader == nil then
		-- 		error()
		-- 	end
			
		-- 	loader:Load(
		-- 		module,
		-- 		function(body, err)
		-- 			if body == nil then
		-- 				table.insert(errs, err)
					
		-- 				i, loader = next(loaders, i)
		-- 				try_loader()
		-- 			else
						
						
		-- 			end
		-- 		end
		-- 	)
		-- end
		
		-- try_loader()
		
		-- for _, loader in ipairs(loaders) do
		-- 	local exports = find_module(loader, module)
		-- 	if exports ~= nil then
		-- 		return exports
		-- 	end
			
		-- 	exports = {}
		
	else
		
	end
end

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------

exports.loader = ({})

function exports.loader.parse_lib_tag(tag)
	local user, lib, version = string.match(tag, '^@([%w_]+)/([%w_]+)#?([%w_]*)$')
	if user == nil or lib == nil then
		error('Failed to parse library tag', 0)
	end
	if version == '' then
		version = nil
	end
	return user, lib, version
end

------------------------------------------------------

exports.loader.base = class{}

function exports.loader.base:SetLib(user, lib, version)
end

function exports.loader.base:Version()
end

------------------------------------------------------

exports.loader.github = class{}

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------

---@param reload boolean
local function init(reload)
	on_setup(reset_main_thinker)
end

------------------------------------------------------

init(false)
 
local info = debug.getinfo(1, 'S')
local file = info.source:match('@scripts\\vscripts\\(.*)%.lua'):gsub('\\', '/')
package.preload[file] = function()
	init(true)
	return exports
end

------------------------------------------------------

return exports