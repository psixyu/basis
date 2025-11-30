---@type basis
local exports = ({})

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
-- generic utilities

local NIL = nil

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

---@generic K, V
---@param table table<K, V>
---@param key K
---@param default V
---@return V
local function fetch(table, key, default)
	if table[key] == nil then
		table[key] = default
	end
	return table[key]
end

------------------------------------------------------

---@param s string
local function multiprint(s)
	for l in s:gmatch('[^\n]+') do
		print(l)
	end
end

------------------------------------------------------

---@generic T
---@param t T[]
---@param edgesize integer
---@return T[], T[]?
local function midcut(t, edgesize)
	local size = #t
	if size > edgesize * 2 then
		local left = {}
		for i = 1, edgesize do
			table.insert(left, t[i])
		end
		
		local right = {}
		for i = size - edgesize + 1, size do
			table.insert(right, t[i])
		end
		
		return left, right
	else
		return t
	end
end

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
-- traceback

---@param thread thread
---@param lvl? integer
---@return basis._traceback_line | nil
---@overload fun(lvl?: integer): basis._traceback_line | nil
local function traceback_line(thread, lvl)
	local info ---@type debuginfo
	if type(thread) == 'thread' then
		info = debug.getinfo(thread, (lvl or 1) + 1, 'lnS')
	else
		lvl = (thread --[[@as integer | nil]])
		thread = (NIL --[[@as thread]])
		info = debug.getinfo((lvl or 1) + 1, 'lnS')
	end
	
	if info == nil then
		return nil
	end

	---@class basis._traceback_line
	local data = {
		what = info.what,
		source = info.short_src,
		line = info.currentline,
		def = info.linedefined,
		name = info.name,
		namewhat = info.namewhat,

		---@param self basis._traceback_line
		---@param rv basis._traceback_line
		---@return boolean
		equal = function(self, rv)
			return self.what == rv.what
				and self.source == rv.source
				and self.line == rv.line
		end,

		---@param self basis._traceback_line
		---@return string
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
					fname = 'function <' .. self.source .. ':' .. self.def .. '>'
				else
					fname '?'
				end
			else
				fname = self.namewhat .. " '" .. self.name .. "'"
			end

			return pos .. ': in ' .. fname
		end,
	}

	return data
end

---@param thread thread
---@param lvl? integer
---@param target? basis._traceback_line[] 
---@return basis._traceback_line[]
---@overload fun(lvl?: integer, target?: basis._traceback_line[]): basis._traceback_line[]
local function traceback_lines(thread, lvl, target)
	local omit_thread = (type(thread) ~= "thread")
	if omit_thread then
		target = (lvl --[[@as basis._traceback_line[] ]])
		lvl = (thread --[[@as integer|nil ]])
		thread = (NIL --[[@as thread]])
	end

	lvl = lvl or 1
	target = target or {}

	local line ---@type basis._traceback_line?
	if omit_thread then
		line = traceback_line(lvl + 1)
	else
		line = traceback_line(thread, lvl + 1)
	end
	
	if line then
		table.insert(target, line)
		return traceback_lines(lvl + 1, target)
	end

	return target
end

---@param thread thread
---@param lvl? integer
---@return basis._traceback
---@overload fun(lvl?: integer): basis._traceback
local function traceback(thread, lvl)
	local omit_thread = (type(thread) ~= "thread")
	if omit_thread then
		lvl = (thread --[[@as integer|nil ]])
		thread = (NIL --[[@as thread]])
	end
	
	lvl = lvl or 1

	---@class basis._traceback
	local tb = {
		lines = nil, ---@type basis._traceback_line[]

		---@param self basis._traceback
		---@param edgesize? integer
		---@return string
		tostring = function(self, edgesize)
			edgesize = edgesize or 12
			local text = ''

			---@param l basis._traceback_line
			local function addline(l)
				text = text .. '\n\t' .. l:tostring()
			end

			local l, r = midcut(self.lines, edgesize)
			
			for _, line in ipairs(l) do
				addline(line)
			end
			
			if r then
				text = text .. '\n\t...'
				
				for _, line in ipairs(r) do
					addline(line)
				end
			end

			return text:sub(2)
		end,

		---@param self basis._traceback
		---@param rv basis._traceback
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
	
	if omit_thread then
		tb.lines = traceback_lines(lvl + 1)
	else
		tb.lines = traceback_lines(thread, lvl + 1)
	end

	return tb
end

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
-- contexts

---@class basis._thread_context
---@field context? basis._context
---@field origin string[]

local thread_contexts = {}	---@type table<thread, basis._thread_context>
local main_thread_tag = ({}	--[[@as thread]])

---@return thread
local function get_thread_tag()
	return coroutine.running() or main_thread_tag
end

---@param thread? thread
---@return basis._thread_context
local function get_thread_context(thread)
	if thread == nil then
		thread = get_thread_tag()
	end

	if thread_contexts[thread] == nil then
		thread_contexts[thread] = {
			origin = {}
		}
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

---@class basis._context
---@field resolved boolean
---@field awaitable boolean
---@field lib basis._lib?
---@field on_lib_resolve fun()[]
---@field cluster_promises basis.promise[]
---@field cluster_promise_count integer
---@field on_load fun()[]
---@field on_error fun(msg: string, level?: integer)[]
---@field loading_deps integer
---@field error_occured boolean
---@field aliases table<string, basis._lib>

---@param ctx basis._context
---@param func fun()
local function with_context(ctx, func)
	local tctx = get_thread_context()
	local old_ctx = tctx.context
	tctx.context = ctx

	exports.__spcall(
		func,
		error,
		function()
			tctx.context = old_ctx
		end
	)
end

---@return basis._context
local function make_context()
	---@type basis._context
	return {
		resolved = true,
		awaitable = true,
		on_lib_resolve = {},
		cluster_promises = {},
		cluster_promise_count = 0,
		on_load = {},
		on_error = {},
		error_occured = false,
		loading_deps = 0,
		aliases = {},
	}
end

---@param context? basis._context
---@return basis._context
local function get_context(context)
	if context then
		return context
	end

	local tctx = get_thread_context()

	if tctx.context == nil then
		tctx.context = make_context()
		tctx.context.awaitable = false
	end

	return tctx.context
end

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
-- spcall

---@class basis._jerr
---@field message string
---@field traceback string

---@param msg string
---@return boolean
local function is_jerr(msg)
	return msg:sub(1, 1) == '$'
end

---@param jerr basis._jerr
---@return string
local function jerr_encode(jerr)
	return '$' .. json.encode(jerr)
end

---@param msg string
---@return basis._jerr
local function jerr_decode(msg)
	return json.decode(msg:sub(2))
end

---@param msg string
---@param traceback string
---@return string
local function jerr_set_traceback(msg, traceback)
	if is_jerr(msg) then
		return msg
	end
	
	---@type basis._jerr
	local jerr = {
		message = msg,
		traceback = traceback,
	}
	
	return jerr_encode(jerr)
end

---@param msg string
---@param text string
---@return string
local function jerr_add_traceback_text(msg, text)
	if text == nil then
		return msg
	end
	
	if not is_jerr(msg) then
		return jerr_set_traceback(msg, text)
	end
	
	local jerr = jerr_decode(msg)
	
	jerr.traceback = jerr.traceback .. '\n' .. text
	
	return jerr_encode(jerr)
end

---@param msg string
---@return string
local function jerr_resolve(msg)
	if not is_jerr(msg) then
		return msg
	end
	
	local jerr = jerr_decode(msg)
	
	print(jerr.message)
	print('stack traceback:')
	multiprint(jerr.traceback)
	
	return jerr.message
end

exports.__spcall = function(func, error, cleanup)
	local smsg = ''

	local status = xpcall(
		func,
		function(msg)
			smsg = jerr_set_traceback(msg, traceback(2):tostring())
		end
	)
	
	if cleanup then
		cleanup()
	end

	if not status then
		error(smsg, 0)
	end
	
	return status
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

------------------------------------------------------

---@type basis.thinker_func[]
local thinkers = {}
local main_thinker_number = 0

---@param func basis.thinker_func
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
	else
		return Entities:First()
	end
end

local function reset_main_thinker()
	main_thinker_number = main_thinker_number + 1
	
	get_thinker_ent():SetContextThink(
		'basis' .. main_thinker_number,
		function()
			for i = #thinkers, 1, -1 do
				local func = thinkers[i]
				local status, result = pcall(func)
				
				if status then
					if result then
						table.remove(thinkers, i)
					end
				else
					---@diagnostic disable-next-line: cast-type-mismatch
					---@cast result string
					table.remove(thinkers, i)
					reset_main_thinker()
					local msg = jerr_resolve(result)
					error(msg, 0)
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

local function is_main_thread()
	return coroutine.running() == nil
end

------------------------------------------------------

---@type thread[]
local threads = {}

---@param origin string[]
---@return string
local function tostring_origin(origin)
	local l, r = midcut(origin, 2)
	local result = ''
	
	for _, s in ipairs(l) do
		result = result .. '\n' .. s
	end
	
	if r then
		result = result .. '\n.....'
		
		for _, s in ipairs(r) do
			result = result .. '\n' .. s
		end
	end
	
	return result:sub(2)
end

---@param func fun()
---@param context? basis._context
local function add_thread(func, context)
	if context == nil then
		context = get_context()
	end
	
	local thread = coroutine.create(func)
	
	local tcx = get_thread_context(thread)
	tcx.origin = {
		'started from:\n' .. traceback(2):tostring(),
		unpack(get_thread_context().origin)
	}
	tcx.context = context
	
	table.insert(threads, thread)
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
						local context = get_thread_context(thread)
						if not is_jerr(err) then
							err = jerr_set_traceback(err, traceback(thread, 1):tostring())
						end
						err = jerr_add_traceback_text(err, tostring_origin(context.origin))
						table.insert(errors, err)
					end
				end
			end
			
			for i = #to_delete, 1, -1 do
				local idel = to_delete[i]
				destroy_thread_context(threads[idel])
				table.remove(threads, idel)
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

function exports.is_awaitable()
	return get_context().awaitable
end

---@class basis.promise
local promise = {
	resolved = false,
	sync_resolve = false,
	sync_error = false,
}

---@return ...
function promise:Result()
	return unpack(self.result, 1, max_key(self.result))
end

---@private
function promise:call()
	if self.callback ~= nil then
		local function task()
			self.callback(self:Result())
		end
	
		if self.sync_resolve then
			with_context(self.context, task)
		else
			add_thread(task, self.context)
		end
	end
end

---@private
function promise:call_error()
	if self.error_callback ~= nil then
		local function task()
			self.error_callback(self.error_msg, 0)
		end
		
		if self.sync_error then
			with_context(self.context, task)
		else
			add_thread(task, self.context)
		end
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
---@param run basis.promise.runner
---@param setup? fun(self: basis.promise)
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
		
			self:call()
		end,
		
		function(msg)
			if self.resolved or self.error then
				error('Multiple resolve', 0)
			end
			
			self.error = true
			self.error_msg = msg
			
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

function promise:SyncResolve()
	self.sync_resolve = true
	return self
end

function promise:SyncError()
	self.sync_error = true
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
	if not exports.is_awaitable() then
		error('Await is not allowed in this context', 0)
	end
	
	while true do
		if self.resolved then
			return self:Result()
		end
		if self.error then
			error(self.error_msg, 0)
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

---@alias basis._module_callback fun(exports: table)

---@class basis._module
local c_module = {
	lib = nil,			---@type basis._lib
	exports = nil,		---@type table
	name = nil,			---@type string
	loaded = false,		---@type boolean
	on_load = {},		---@type basis._module_callback[]
		
	---@param self basis._module
	---@param lib basis._lib
	---@param name string
	constructor = function(self, lib, name)
		self.lib = lib
		self.name = name
		self.exports = {}
	end,
	
	---@param self basis._module
	---@param func basis.module_body
	Exec = function(self, func)
		func = self:SetupExecutable(func)
		
		local context = make_context()
		context.lib = self.lib
		
		add_thread(
			function()
				copy(func(), self.exports)
				self.loaded = true
				self:CallOnLoad()
			end,
			context
		)
	end,
	
	---@param self basis._module
	---@param func basis.module_body
	---@return fun(): table
	SetupExecutable = function(self, func)
		return func
	end,
	
	---@param self basis._module
	---@param callback basis._module_callback
	OnLoad = function(self, callback)
		if self.loaded then
			callback(self.exports)
		else
			table.insert(self.on_load, callback)
		end
	end,
	
	---@param self basis._module
	CallOnLoad = function(self)
		for _, callback in ipairs(self.on_load) do
			callback(self.exports)
		end
	end,
}

---@overload fun(lib: basis._lib, name: string): basis._module
local c_module = class(c_module)

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
--- lib class

---@class basis._lib
local c_lib = {
	loader = nil,		---@type basis.loader.base
	vid = nil,			---@type string
	version = nil,		---@type string
	modules = nil,		---@type {[string]: basis._module}
	requesters = nil,	---@type table<basis._context, boolean>
	
	---@param self basis._lib
	---@param vid string
	---@param loader basis.loader.base
	constructor = function(self, vid, loader)
		self.vid = vid
		self.loader = loader
		self.modules = {}
		self.requesters = {}
	end,
	
	---@param self basis._lib
	---@param context basis._context
	AddRequester = function(self, context)
		self.requesters[context] = true
	end,
	
	---@param self basis._lib
	---@param context basis._context
	---@return boolean
	IsRequested = function(self, context)
		return self.requesters[context] or false
	end,
	
	---@param self basis._lib
	---@param name string
	---@param callback basis._module_callback
	Module = function(self, name, callback)
		local module = self.modules[name]
		
		if not module then
			module = c_module(self, name)
			self.modules[name] = module
		
			module:OnLoad(callback)
			
			self.loader:Load(
				name,
				function(body, err)
					if err then
						error('[' .. self.loader:GetName() .. ']: Failed to load module ' .. name .. ':\n' .. err, 0)
					else
						module:Exec(body)
					end
				end
			)
		else
			module:OnLoad(callback)
		end
	end,
}
---@overload fun(vid: string, loader: basis.loader.base): basis._lib
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
		error('Bad version format', 0)
	end
	
	local major = tonumber(a)	--[[@as integer]]
	local minor = tonumber(b)	--[[@as integer]]
	local patch = tonumber(c)	--[[@as integer]]
	return major, minor, patch
end

------------------------------------------------------

---@param lv string
---@param rv string?
---@return boolean
local function version_gt(lv, rv)
	if rv == nil then
		return true
	end

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

---@param lv string
---@param rv string
---@return boolean
local function version_gte(lv, rv)
	return lv == rv or version_gt(lv, rv)
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
		error('Invalid module name', 0)
	end
end

------------------------------------------------------

---@param str string
---@return string, string, string, boolean
local function parse_lib_tag(str)
	local user, name, version = str:match('^@([%w_]+)/([%w_]+)#?([%d%.]*)$')
	if version == '' then
		version = nil
	end
	return user, name, version, (user ~= nil and name ~= nil and version ~= nil)
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
		error('Invalid lib id', 0)
	end

	return id .. '#' .. version_major(version)
end

------------------------------------------------------

---@param str string
---@return string?
local function parse_url(str)
	return str:match('^https?://(.+)$')
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
---@return basis.lib_options
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

---@param options basis.lib_options | string
---@return basis.lib_options
local function parse_options(options)
	if type(options) == 'string' then
		options = lib_string_options(options)
	end

	local loader = options.loader
	if loader == nil then
		loader = exports.loader.github()
	end
	loader.options = options
	
	return {
		alias = options.alias,
		id = options.id,
		version = loader:GetVersion(),
		loader = loader,
	}
end

------------------------------------------------------

---@param options basis.lib_options
---@return string?
local function options_vid(options)
	if options.id and options.version then
		return lib_vid(options.id, options.version)
	end
end

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
-- setup finish callbacks

---@param context basis._context
local function clear_callbacks(context)
	context.on_load = {}
	context.on_error = {}
end

------------------------------------------------------

---@param context basis._context
---@param callback fun()
local function on_load_with_context(context, callback)
	if context.error_occured then
		return
	end

	if context.loading_deps == 0 then
		with_context(context, callback)
	else
		table.insert(context.on_load, callback)
	end
end

exports.on_load = function(callback)
	on_load_with_context(get_context(), callback)
end

---@param context basis._context
local function call_on_load(context)
	for _, func in ipairs(context.on_load) do
		with_context(context, func)
	end
	clear_callbacks(context)
end

---@param context basis._context
local function add_loading_dep(context)
	context.loading_deps = context.loading_deps + 1
end

---@param context basis._context
local function finish_loading_dep(context)
	context.loading_deps = context.loading_deps - 1
	if context.loading_deps == 0 then
		call_on_load(context)
	end
end

------------------------------------------------------

---@param context basis._context
---@param callback fun(msg: string, lvl?: integer)
local function on_error_with_context(context, callback)
	table.insert(context.on_error, callback)
end

exports.on_error = function(callback)
	on_error_with_context(get_context(), callback)
end

---@param context basis._context
---@param msg string
---@param level? integer
local function call_error(context, msg, level)
	if context.error_occured then
		return
	end
	
	context.error_occured = true
	context.loading_deps = context.loading_deps - 1
	
	if #context.on_error == 0 then
		error(msg, level)
	else
		for _, func in ipairs(context.on_error) do
			local safe
			
			with_context(context, function()
				safe = func(msg, level)
			end)
			
			if safe then
				context.error_occured = false
				return
			end
		end
	
		clear_callbacks(context)
	end
end

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------
-- lib declaration

local libs = {}			---@type table<string, basis._lib[]>

---@param storage basis._lib[]
---@param loader basis.loader.base
---@return basis._lib?
local function _find_lib_in_storage(storage, loader)
	for _, lib in ipairs(storage) do
		if exports.loader.equal(lib.loader, loader) then
			return lib
		end
	end
end

---@param vid string
---@param loader basis.loader.base
---@return basis._lib
local function fetch_lib(vid, loader)
	local storage = fetch(libs, vid, {})
	
	local lib = _find_lib_in_storage(storage, loader)
	if lib then
		return lib
	end
	
	lib = c_lib(vid, loader)
	table.insert(storage, lib)
	return lib
end

---@param vid string
---@param loader basis.loader.base
---@return basis._lib?
local function get_lib(vid, loader)
	local storage = libs[vid]
	if storage == nil then
		return nil
	end
	
	return _find_lib_in_storage(storage, loader)
end

------------------------------------------------------

---@param alias string
---@return boolean
local function is_good_alias(alias)
	return alias:match('[_%w%./\\]+') and true or false
end

---@param context basis._context
---@param alias string
---@return basis._lib?
local function get_lib_by_alias(context, alias)
	return context.aliases[alias]
end

---@param context basis._context
---@param lib basis._lib
---@param alias? string
local function set_lib_alias(context, lib, alias)
	if alias == nil then
		return
	end
	
	if not is_good_alias(alias) then
		error('Invalid alias', 0)
	end
	
	local old_lib = get_lib_by_alias(context, alias)
	if old_lib and old_lib ~= lib then
		error('An alias is already occupied by the lib ' .. old_lib.loader:GetName(), 0)
	end
	
	context.aliases[alias] = lib
end

------------------------------------------------------

---@param id string
---@param version string
---@param context basis._context?
---@return basis._lib?
local function get_lib_by_id_version(id, version, context)
	local vid = lib_vid(id, version)
	local storage = libs[vid]

	if storage then
		for _, lib in ipairs(storage) do
			if context == nil or lib:IsRequested(context) then
				if version_gte(lib.version, version) then
					return lib
				end
			end
		end
	end
end

------------------------------------------------------

---@param libspec string
---@param no_tag_context boolean?
---@return basis._lib?
local function get_lib_by_spec(libspec, no_tag_context)
	local name, user, version, tag_ok = parse_lib_tag(libspec)
	
	if tag_ok then
		local id = lib_id(name, user)
		local context = nil
		if not no_tag_context then
			context = get_context()
		end
		return get_lib_by_id_version(id, version, context)
	end
	
	if is_good_alias(libspec) then
		return get_lib_by_alias(get_context(), libspec)
	end
	
	error('Failed to parse lib specifier', 0)
end

------------------------------------------------------

exports.__clear_libs = function()
	libs = {}
	
	local context = get_context()
	context.error_occured = false
	context.aliases = {}
end

------------------------------------------------------

exports.__check_lib = function(tag)
	local name, user, version, tag_ok = parse_lib_tag(tag)
	if not tag_ok then
		tag, version = tag:match('([^#]+)#([^#]+)')
		if not version then
			error('Bad check spec', 0)
		end
	end
	local lib = get_lib_by_spec(tag, true)
	return lib ~= nil and lib.version == version
end

------------------------------------------------------

---@param runner basis.promise.runner
---@param context? basis._context
local function cluster_promise(runner, context)
	context = get_context(context)
	
	with_context(context, function()
		local prom = exports.promise(runner)

		table.insert(context.cluster_promises, prom)
		context.cluster_promise_count = context.cluster_promise_count + 1

		prom:Then(
			function()
				context.cluster_promise_count = context.cluster_promise_count - 1
				if context.cluster_promise_count == 0 then
					for _, each_prom in ipairs(context.cluster_promises) do
						local callspec = { each_prom:Result() }
						callspec[1](unpack(callspec, 2, max_key(callspec)))
					end
					
					context.cluster_promises = {}
				end
			end,
			
			function(msg, lvl)
				context.cluster_promise_count = context.cluster_promise_count - 1
				for i, other_prom in ipairs(context.cluster_promises) do
					if other_prom == prom then
						table.remove(context.cluster_promises, i)
						break
					end
				end
			
				call_error(context, msg, lvl)
			end
		)
	end)
end

---@param runner basis.promise.runner
local function on_lib_resolve(runner)
	local context = get_context()
	if context.resolved then
		cluster_promise(runner)
	else
		table.insert(context.on_lib_resolve, runner)
	end
end

---@param context basis._context
---@param parent basis._context
local function lib_resolve(context, parent)
	context.resolved = true

	for _, runner in ipairs(context.on_lib_resolve) do
		cluster_promise(runner, context)
	end
	
	on_load_with_context(context, function()
		finish_loading_dep(parent)
	end)
end

------------------------------------------------------

---@param context basis._context
---@param vid string
---@param loader basis.loader.base
---@param version string
---@return boolean
local function cover_by_old_lib(context, vid, loader, version)
	local old_lib = get_lib(vid, loader)
	if not old_lib then
		return false
	end
	
	if version_gt(version, old_lib.version) then
		return false
	end
	
	old_lib:AddRequester(context)
	return true
end

------------------------------------------------------

exports.lib = function(options)
	on_lib_resolve(function(resolve, error)
		options = parse_options(options)
		local context = get_context()
		local vid = options_vid(options)

		if vid then
			if cover_by_old_lib(context, vid, options.loader, options.version) then
				return
			end
		end
		
		add_loading_dep(context)

		local li = load_index
		
		options.loader:LoadInit(
			function(body, err)
				if li ~= load_index then
					return
				end
			
				add_thread(
					function()
						exports.__spcall(
							function()
								local error = _G.error
									
								if body then
									local lib_context = get_context()
									lib_context.resolved = false
									lib_context.awaitable = false
									
									local manifest = body()
									
									lib_context.awaitable = true
									
									if manifest == nil then
										if vid == nil then
											error('Lib has no manifest and tag is not specified', 0)
										end
										
										local user, name = parse_lib_tag(options.id) --[[@as string, string]]
										manifest = {
											user = user,
											name = name,
											version = options.version,
										}
									else
										if manifest.user == nil
										or manifest.name == nil
										or manifest.version == nil then
											error('Incomplite manifest', 0)
										end
									end

									local id = lib_id(manifest.user, manifest.name)
									if options.id then
										if id ~= options.id then
											error('Maifest id mismatch', 0)
										end
									end

									local version = manifest.version
									if options.version then
										if version_gt(options.version, version) then
											error('Manifest version mismatch', 0)
										end
									end

									local vid = lib_vid(id, version)
									local lib = fetch_lib(vid, options.loader)
									lib:AddRequester(context)
									set_lib_alias(context, lib, options.alias)
									
									if version_gt(version, lib.version) then
										lib.version = version
										lib_context.lib = lib
										resolve(lib_resolve, lib_context, context) return
									else
										resolve(finish_loading_dep, context) return
									end
								else
									error('Failed to init: ' .. err, 0)
								end
							end,

							function(err)
								local jerr = jerr_decode(err)
								jerr.message = '[' .. options.loader:GetName() .. ']: ' .. jerr.message
								error(jerr_encode(jerr), 0)
							end
						)
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

---@return basis._lib?
local function current_lib()
	return get_context().lib
end

---@param libspec string?
---@return basis._lib?
local function require_get_lib(libspec)
	if libspec == nil then
		return current_lib()
	end
	
	return get_lib_by_spec(libspec)
end

---@param name string
---@param callback basis._module_callback
local function require_single(name, callback)
	local libspec, module_name = parse_module_name(name)
	local lib = require_get_lib(libspec)
	
	if not lib then
		error('Failed to fetch lib "' .. libspec .. '"', 0)
	end
	
	lib:Module(module_name, callback)
end

------------------------------------------------------

exports.require = function(arg)
	local context = get_context()
	
	local prom = exports.promise(
		function(resolve, error)
			add_loading_dep(context)
			
			on_lib_resolve(function(lib_resolve)
				lib_resolve(function()
					if type(arg) == 'string' then
						require_single(
							arg,
							function(xprt)
								resolve(xprt)
								finish_loading_dep(context)
							end
						)
					end
				end) return
			end)
		end,
		
		function(prom)
			prom:SyncResolve()
		end
	)
	
	if type(arg) == 'string' then
		if exports.is_awaitable() then
			return prom:Await()
			
		elseif prom:Resolved() then
			return prom:Result()
			
		else
			local content = {}
			prom:Then(function(xprt)
				copy(xprt, content)
			end)
			return content
		end
	end
	
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
end

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------

exports.loader = ({})

function exports.loader.parse_lib_tag(tag)
	local user, lib, version = parse_lib_tag(tag)
	if user == nil or lib == nil then
		error('Failed to parse library tag', 0)
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

function exports.loader.base:Equal(_)
	return true
end

------------------------------------------------------

---@class basis.loader.path
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
	local path = self.root .. 'init'
	local func, err = loadfile(path)

	if func == nil and err and err:match('^Failed to find') then
		func = function() end
		err = nil
	end

	callback(func, err)
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
	end
	
	clear_thinkers()
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

package.preload['basis'] = function()
	return exports
end

------------------------------------------------------

return exports