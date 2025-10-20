---@type basis.require
local exports = ({})

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
-- traceback

---@param lvl? integer
---@return basis.require._traceback_line | nil
local function traceback_line(lvl)
	local info = debug.getinfo((lvl or 1) + 1, 'lnS')

	---@class basis.require._traceback_line
	local data = {
		what = info.what,
		source = info.short_src,
		line = info.currentline,
		def = info.linedefined,
		name = info.name,
		namewhat = info.namewhat,

		---@param self basis.require._traceback_line
		---@param rv basis.require._traceback_line
		---@return boolean
		equal = function(self, rv)
			return self.what == rv.what
				and self.source == rv.source
				and self.line == rv.line
		end,

		---@param self basis.require._traceback_line
		tostring = function(self)
			local pos = self.source
			if self.line > 0 then
				pos = pos .. ':' .. self.line
			end

			local fname
			if self.namewhat == '' then
				if self.what == 'main' then
					fname = 'main chunk'
				elseif self.def >= 0 then
					fname = self.source .. ':' .. self.def
				else
					fname '?'
				end
			else
				fname = "function '" .. self.name .. "'"
			end

			return pos .. ': in ' .. fname
		end,
	}

	return data
end

---@param lvl? integer
---@param target? basis.require._traceback_line[] 
---@return basis.require._traceback_line[]
local function traceback_lines(lvl, target)
	lvl = lvl or 1
	target = target or {}

	local line = traceback_line(lvl + 1)
	if line then
		table.insert(target, line)
		return traceback_lines(lvl + 1, target)
	end

	return target
end

---@param lvl? integer
---@return basis.require._traceback
local function traceback(lvl)
	lvl = lvl or 1

	---@class basis.require._traceback
	local tb = {
		lines = traceback_lines(lvl + 1),

		---@param self basis.require._traceback
		---@param sidesize? integer
		---@return string
		tostring = function(self, sidesize)
			sidesize = sidesize or 12
			local text = 'stack traceback:'
			local size = #self.lines

			---@param l basis.require._traceback_line
			local function addline(l)
				text = text .. '\n\t' .. l:tostring()
			end

			if size <= sidesize * 2 then
				for _, line in ipairs(self.lines) do
					addline(line)
				end
			else
				for i = 1, sidesize do
					addline(self.lines[i])
				end

				text = text .. '\n\t...'

				for i = size - sidesize + 1, size do
					addline(self.lines[i])
				end
			end

			return text
		end,

		---@param self basis.require._traceback
		---@param rv basis.require._traceback
		cutend = function(self, rv)
			local i = #self.lines
			local j = #rv.lines

			while self.lines[i]:equal(rv.lines[j]) do
				i = i - 1
				j = j - 1
			end

			self.lines = {unpack(self.lines, 1, i)}
		end,
	}

	return tb
end


------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
-- generic utilities

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

exports.__spcall = function(func, error, cleanup)
	local smsg = ''
	local base_tb = traceback(1)

	local status = xpcall(
		func,
		function(msg)
			local tb = traceback(2)
			tb:cutend(base_tb)
			smsg = msg .. '\n' .. tb:tostring()
		end
	)
	
	if cleanup then
		cleanup()
	end

	if not status then
		error(smsg, 0)
	end
end

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
-- contexts

---@class basis.require._thread_context
---@field context? basis.require._context

local thread_contexts = {}	---@type table<thread, basis.require._thread_context>
local main_thread_tag = ({}	--[[@as thread]])

local function get_thread_tag()
	return coroutine.running() or main_thread_tag
end

---@param thread? thread
---@return basis.require._thread_context
local function get_thread_context(thread)
	if thread == nil then
		thread = get_thread_tag()
	end

	if thread_contexts[thread] == nil then
		thread_contexts[thread] = {}
	end

	return thread_contexts[thread]
end

---@param thread thread
local function destroy_thread_context(thread)
	local context = thread_contexts[thread]
	if context == nil then
		return
	end

	thread_contexts[thread] = nil
end

------------------------------------------------------

---@class basis.require._context
---@field main boolean
---@field on_lib_resolve fun()[]
---@field resolve_promises basis.require.promise[]
---@field resolve_promise_count integer

---@param ctx basis.require._context
---@param func fun()
local function with_context(ctx, func)
	local tctx = get_thread_context()
	local old_ctx = ctx
	tctx.context = ctx

	exports.__spcall(
		func,
		error,
		function()
			tctx.context = old_ctx
		end
	)
end

---@return basis.require._context
local function make_context()
	return {
		main = false,
		on_lib_resolve = {},
		resolve_promises = {},
		resolve_promise_count = 0,
	}
end

---@param func fun()
local function new_context(func)
	with_context(make_context(), func)
end

---@param context? basis.require._context
---@return basis.require._context
local function get_context(context)
	if context then
		return context
	end

	local tctx = get_thread_context()

	if tctx.context == nil then
		tctx.context = make_context()
		tctx.context.main = true
	end

	return tctx.context
end

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
-- setup threads and thinkers

local SETUP_STATE = 2

local load_index = 0

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

---@type basis.require.thinker_func[]
local thinkers = {}
local main_thinker_number = 0

---@param func basis.require.thinker_func
local function add_thinker(func)
	table.insert(thinkers, func)
end
exports.add_thinker = add_thinker

local function clear_thinkers()
	thinkers = {}
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
				exports.__spcall(
					function()
						local stop = func()
						if stop then
							table.remove(thinkers, i)
						end
					end,
					
					function(err)
						table.remove(thinkers, i)
						reset_main_thinker()
						error(err, 0)
					end
				)
			end
			
			return FrameTime()
		end,
		0
	)
end

------------------------------------------------------

---@param msg string
local function async_error(msg)
	msg = debug.traceback(msg, 2)

	add_thinker(
		function()
			error(msg, 0)
		end
	)
end

------------------------------------------------------

local function is_main_thread()
	return coroutine.running() == nil
end

------------------------------------------------------

---@type thread[]
local threads = {}

---@param func fun()
---@param context? basis.require._context
local function add_thread(func, context)
	if context == nil then
		context = get_context()
	end

	table.insert(
		threads,
		coroutine.create(function()
			with_context(context, func)
		end)
	)
end

local function setup_threads()
	threads = {}
	thread_contexts = {}

	add_thinker(
		function()
			local to_delete = {}	---@type integer[]
			local errors = {}		---@type string[]
			
			for i, thread in ipairs(threads) do
				local ok, err = coroutine.resume(thread)
				
				if coroutine.status(thread) == "dead" then
					table.insert(to_delete, i)
					if not ok then
						table.insert(errors, debug.traceback(thread, err, 0))
					end
				end
			end
			
			for i = #to_delete, 1, -1 do
				destroy_thread_context(threads[i])
				table.remove(threads, i)
			end
			
			for _, err in ipairs(errors) do
				async_error(err)
			end
		end
	)
end

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
-- promise

---@class basis.require.promise
local promise = {
	resolved = false,
	result_count = 0,
}

---@return ...
function promise:Result()
	return unpack(self.result, 1, self.result_count)
end

---@private
function promise:call()
	if self.callback ~= nil then
		with_context(self.context, function()
			self.callback(self:Result())
		end)
	end
end

---@private
function promise:call_error()
	if self.error_callback ~= nil then
		with_context(self.context, function()
			self.error_callback(self.error_msg, 0)
		end)
	end
end

---@private
---@param func? fun(msg: string, lvl?: integer)
function promise:set_error_handler(func)
	if func then
		self.error_callback = func
	end
end

---@private
---@param run basis.require.promise.runner
---@param setup? fun(self: basis.require.promise)
function promise:constructor(run, setup)
	self.result = {}
	
	if setup then
		setup(self)
	end
	
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

function promise:Resolved()
	return self.resolved
end

function promise:RaiseErrors()
	self:set_error_handler(error)
	return self
end

function promise:Then(callback, error_callback)
	if self.callback ~= nil then
		error('Chaining the same promise twice', 0)
	end

	self.context = get_context()
	self.callback = callback
	self:set_error_handler(error_callback)
		
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
				return self:Result()
			end
			if self.error then
				error(self.error_msg, 0)
			end
		end
	end
end

exports.promise = class(promise)

------------------------------------------------------

function exports.multi_then(promises, callback, error_callback)
	local count = 0
	for _, promise in ipairs(promises) do
		if not promise:Resolved() then
			count = count + 1
			promise:Then(
				function()
					count = count - 1
					if count == 0 then
						callback()
					end
				end,
				error_callback
			)
		end
	end
end

exports.chain = function(promise, run, setup)
	return exports.promise(
		function(resolve, error)
			local function task()
				run(resolve, error)
			end
		
			if promise then
				promise:Then(task)
			else
				task()
			end
		end,
		setup
	)
end

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

---@class basis.require._lib
local c_lib = {
	modules = nil,		---@type {[string]: basis.require._module}
	loader = nil,		---@type basis.require.loader.base
	version = nil,		---@type string
	
	---@param self basis.require._lib
	---@param loader basis.require.loader.base
	constructor = function(self, loader)
		self.loader = loader
		self.modules = {}
	end,
	
	-- has_id = function(self)
	-- end,
	
	-- has_version = function(self)
	-- end,

	-- ---@param self basis.require._lib
	-- ---@return integer
	-- get_major_version = function(self)

	-- end,

	-- ---@param self basis.require._lib
	-- ---@return string
	-- get_major_tag = function(self)

	-- end,
	
	-- ---@param self basis.require._lib
	-- ---@param name string
	-- ---@return basis.require._module
	-- get_module = function(self, name)
	-- 	local tag = self:get_major_tag()
	-- 	local module = modules[tag]
	-- 	if module then
	-- 		return module
	-- 	end
		
	-- 	-- module = c_module(self, name)
	-- 	-- self.modules[name] = module
	-- 	-- return module
	-- end,
}
---@overload fun(loader: basis.require.loader.base): basis.require._lib
local c_lib = class(c_lib)

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
-- string id utilities

---@param version string
---@return integer, integer, integer
local function parse_version(version)
	local a, b, c = version:match('(%d+)%.(%d+)%.(%d+)')
	if a == nil or b == nil or c == nil then
		error('bad version format', 0)
	end
	
	local major = tonumber(a)	--[[@as integer]]
	local minor = tonumber(b)	--[[@as integer]]
	local patch = tonumber(c)	--[[@as integer]]
	return major, minor, patch
end

------------------------------------------------------

---@param lv string
---@param rv string
---@return boolean
local function version_gt(lv, rv)
	local lmajor, lminor, lpatch = parse_version(lv)
	local rmajor, rminor, rpatch = parse_version(rv)

	if lmajor > rmajor then
		return true
	elseif lmajor < rmajor then
		return false
	end
	
	if lminor > rminor then
		return true
	elseif lminor < rminor then
		return false
	end
	
	return lpatch > rpatch
end

------------------------------------------------------

---@param version string
---@return integer
local function version_major(version)
	local major = parse_version(version)
	return major
end

------------------------------------------------------

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

------------------------------------------------------

---@param str string
---@return string?, string?, string?
local function parse_lib_tag(str)
	return str:match('^@([%w_]+)/([%w_]+)#?([%d%.]*)$')
end

------------------------------------------------------

---@param user string
---@param lib string
---@return string
local function lib_id(user, lib)
	return '@' .. user .. '/' .. lib
end

------------------------------------------------------

---@param id string
---@param version string
---@return string
local function lib_vid(id, version)
	local user, name = parse_lib_tag(id)
	if user == nil or name == nil then
		error('invalid lib id', 0)
	end

	return id .. '#' .. version_major(version)
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
------------------------------------------------------
------------------------------------------------------
-- options utilities

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

---@param options basis.require.lib_options
---@return basis.require.loader.base
local function get_options_loader(options)
	local loader = options.loader
	if loader == nil then
		loader = exports.loader.github()
	end
	loader.options = options
	return loader
end

---@param options basis.require.lib_options
---@return string?
local function get_options_version(options)
	local loader = get_options_loader(options)
	local ver = loader:GetVersion()
	if ver then
		return ver
	end
	return options.version
end

---@param options basis.require.lib_options
---@return string?
local function get_options_vid(options)
	local version = get_options_version(options)
	if version and options.id then
		return lib_vid(options.id, version)
	end
end

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
-- setup callbacks

local on_load_callbacks = {}		---@type [fun(), basis.require._context][]
local on_error_callbacks = {}		---@type [fun(msg: string, level?: integer), basis.require._context][]

exports.on_load = function(callback)
	table.insert(on_load_callbacks, {callback, get_context()})
end

exports.on_error = function(callback)
	table.insert(on_error_callbacks, {callback, get_context()})
end

local function call_on_load()
	for _, t in ipairs(on_load_callbacks) do
		with_context(t[2], t[1])
	end
end

---@param msg string
---@param level? integer
local function call_error(msg, level)
	if #on_error_callbacks == 0 then
		error(msg, level)
	else
		for _, t in ipairs(on_error_callbacks) do
			with_context(t[2], function()
				t[1](msg, level)
			end)
		end
	end
end

local function clear_callbacks()
	on_load_callbacks = {}
	on_error_callbacks = {}
end

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
-- lib declaration

local libs = {}			---@type table<string, basis.require._lib[]>

---@param vid string
---@param loader basis.require.loader.base
---@return basis.require._lib?
local function get_lib(vid, loader)
	local storage = libs[vid]
	if storage == nil then
		return nil
	end
	
	for _, lib in ipairs(storage) do
		if exports.loader.equal(lib.loader, loader) then
			return lib
		end
	end
end

---@param vid string
---@param loader basis.require.loader.base
---@param version string
local function set_lib(vid, loader, version)
	local lib = get_lib(vid, loader)
	
	if lib == nil then
		lib = c_lib(loader)
		
		local storage = libs[vid]
		if storage == nil then
			storage = {}
			libs[vid] = storage
		end
		
		table.insert(storage, lib)
	end
	
	lib.version = version
end

exports.__clear_libs = function()
	libs = {}
end

exports.__check_lib = function(tag)
	local name, user, version = parse_lib_tag(tag)
	if name == nil or user == nil or version == nil then
		error('bad tag', 0)
	end
	
	local id = lib_id(name, user)
	local vid = lib_vid(id, version)
	
	local storage = libs[vid]
	if storage then
		for _, lib in ipairs(storage) do
			if lib.version == version then
				return true
			end
		end
	end
	
	return false
end

------------------------------------------------------

local pending_libs = 0

local function add_pending_lib()
	pending_libs = pending_libs + 1
end

local function resolve_pending_lib()
	pending_libs = pending_libs - 1
	if pending_libs == 0 then
		call_on_load()
	end
end

local function stop_pending_libs()
	pending_libs = 0
end

------------------------------------------------------

---@param runner basis.require.promise.runner
---@param context? basis.require._context
local function resolve_promise(runner, context)
	context = get_context(context)
	local p = exports.promise(runner)

	table.insert(context.resolve_promises, p)
	context.resolve_promise_count = context.resolve_promise_count + 1

	p:Then(
		function()
			context.resolve_promise_count = context.resolve_promise_count - 1
			if context.resolve_promise_count == 0 then
				for _, p in ipairs(context.resolve_promises) do
					local callback, next_ctx = p:Result()
					callback(next_ctx)
				end
			end
		end,
		call_error
	)
end

---@param runner basis.require.promise.runner
local function on_lib_resolve(runner)
	if is_main_thread() then
		resolve_promise(runner)
	else
		table.insert(get_context().on_lib_resolve, runner)
	end
end

---@param context basis.require._context
local function lib_resolve(context)
	context = get_context(context)

	for _, runner in ipairs(context.on_lib_resolve) do
		resolve_promise(runner, context)
	end
	
	resolve_pending_lib()
end

------------------------------------------------------

exports.lib = function(options)
print('lib req')
	on_lib_resolve(function(resolve, error)
print('neger')
		if type(options) == "string" then
			options = lib_string_options(options)
		end
		
		local vid = get_options_vid(options)
		local loader = get_options_loader(options)

		if vid then
			local old_lib = get_lib(vid, loader)
			if old_lib then
				if not version_gt(options.version, old_lib.version) then
					return
				end
			end
		end
		
		add_pending_lib()
		local li = load_index
		
print(vid, loader)
		loader:LoadInit(
			function(body, err)
				if li ~= load_index then
					return
				end
			
				add_thread(
					function()
						if body then
							local manifest	---@type basis.require.manifest | nil

							exports.__spcall(
								function()
									manifest = body()
								end,

								function(err)
									error('failed to load ' .. loader:GetName() .. ':\n' .. err, 0)
								end
							)
							
							if manifest == nil then
								if vid == nil then
									error('lib has no manifest and tag is not specified: ' .. loader:GetName(), 0)
								end
								
								local user, name = parse_lib_tag(options.id) --[[@as string, string]]
								manifest = {
									user = user,
									name = name,
									version = options.version,
								}
							end

							local id = lib_id(manifest.user, manifest.name)
							if options.id then
								if id ~= options.id then
									error('manifest id mismatch: ' .. loader:GetName(), 0)
								end
							end

							local version = manifest.version
							if options.version then
								if version_gt(options.version, version) then
									error('manifest version mismatch: ' .. loader:GetName(), 0)
								end
							end

							local vid = lib_vid(id, version)
							local old_lib = get_lib(vid, loader)

							if old_lib then
								if not version_gt(version, old_lib.version) then
									return
								end
							end
							
							set_lib(vid, loader, version)
							
							resolve(lib_resolve, get_context())
						else
							error('failed to load ' .. loader:GetName() .. ': ' .. err, 0)
						end
					end,
					make_context()
				)
			end
		)
	end)
end

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
-- require

-- ---@param name string
-- local function require_single(name)
-- 	local tag, module = parse_module_name(name)
-- 	local lib = get_lib(tag)
-- end

-- ------------------------------------------------------

-- exports.require = function(arg)
-- 	if type(arg) == 'string' then
-- 		on_libs_ready()
-- 			:Then(
-- 				function()
-- 					require_single(arg)
-- 				end,
-- 				error
-- 			)
-- 			:Await()
			
-- 		-- on_ready(function()
		
-- 		-- end)
-- 		-- -- await(libs_ready,
	
	
-- 		-- local loaders = get_loaders(lib)
-- 		-- local errs = {}
		
-- 		-- local next = ipairs(loaders)
-- 		-- local i, loader = next(loaders)
		
-- 		-- local function try_loader()
-- 		-- 	if loader == nil then
-- 		-- 		error()
-- 		-- 	end
			
-- 		-- 	loader:Load(
-- 		-- 		module,
-- 		-- 		function(body, err)
-- 		-- 			if body == nil then
-- 		-- 				table.insert(errs, err)
					
-- 		-- 				i, loader = next(loaders, i)
-- 		-- 				try_loader()
-- 		-- 			else
						
						
-- 		-- 			end
-- 		-- 		end
-- 		-- 	)
-- 		-- end
		
-- 		-- try_loader()
		
-- 		-- for _, loader in ipairs(loaders) do
-- 		-- 	local exports = find_module(loader, module)
-- 		-- 	if exports ~= nil then
-- 		-- 		return exports
-- 		-- 	end
			
-- 		-- 	exports = {}
		
-- 	else
		
-- 	end
-- end

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------

exports.loader = ({})

function exports.loader.parse_lib_tag(tag)
	local user, lib, version = parse_lib_tag(tag)
	if user == nil or lib == nil then
		error('Failed to parse library tag', 0)
	end
	if version == '' then
		version = nil
	end
	return user, lib, version
end

function exports.loader.equal(l, r)
	if getclass(l) ~= getclass(r) then
		return false
	end
	return l:Equal(r)
end

------------------------------------------------------

exports.loader.base = class{}

function exports.loader.base:GetName()
	return 'unnamed loader'
end

function exports.loader.base:GetOptionsID()
	return self.options.id
end

function exports.loader.base:GetOptionsVersion()
	return self.options.version
end

function exports.loader.base:GetVersion()
	local version = self:GetOptionsVersion()
	if version then
		return version
	end
	return self:DefaultVersion()
end

function exports.loader.base:DefaultVersion()
	return '1.0.0'
end

function exports.loader.base:Load()
	error('Load is not implemented', 0)
end

function exports.loader.base:LoadInit()
	error('LoadInit is not implemented', 0)
end

function exports.loader.base:Equal()
	error('Equal is not implemented', 0)
end

------------------------------------------------------

---@class basis.require.loader.path
exports.loader.path = class({}, {}, exports.loader.base)

---@param root any
function exports.loader.path:constructor(root)
	root = root:gsub('\\', '/')
	if not root:match('/$') then
		root = root .. '/'
	end
	self.root = root
end

function exports.loader.path:GetName()
	return 'path loader (' .. self.root .. ')'
end

function exports.loader.path:Load(module, callback)
	local path = self.root .. module
	local func, err = loadfile(path)
	callback(func, err)
end

function exports.loader.path:LoadInit(callback)
	self:Load('init', callback)
end

---@param loader basis.require.loader.path
---@return boolean
function exports.loader.path:Equal(loader)
	return self.root == loader.root
end

------------------------------------------------------

exports.loader.github = class{}

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
-- init

---@param reload boolean
local function init(reload)
	if reload then
		load_index = load_index + 1
		clear_thinkers()
		clear_callbacks()
		stop_pending_libs()
	end
	
	setup_threads()
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