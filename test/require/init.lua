local basis = require('basis/require')	--[[@as basis.require]]

------------------------------------------------------

local last_promise = nil	---@type basis.require.promise?
local pending_tests = 0
local passed_tests = 0

local function sv()
	return IsServer() and 'SV ' or 'CL '
end

---@param promise basis.require.promise
local function promise_setup(promise)
	promise:RaiseErrors()
end

---@param run basis.require.promise.runner
local function queue(run)
	last_promise = basis.chain(last_promise, run, promise_setup)
end

---@param name string
---@param func fun()
local function test_simple(name, func)
	pending_tests = pending_tests + 1

	queue(
		function(resolve, error)
			print(sv() .. 'RUNNING [TEST ' .. name .. ']')
			
			if not basis.__spcall(func, error) then
				return
			end
			
			basis.on_load(function()
				print(sv() .. '[TEST ' .. name .. '] PASSED')
				passed_tests = passed_tests + 1
				basis.__clear_libs()
				last_promise = nil
				resolve() return
			end)
			
			basis.on_error(error)
		end
	)
end

---@param tag string
local function assert_lib(tag)
	assert(basis.__check_lib(tag))
end

------------------------------------------------------
-- path loader: vid ejection from manifest

test_simple('path_manifest_vid', function()
	basis.lib({
		loader = basis.loader.path('basis/test/require/lib1')
	})
	
	basis.on_load(function()
		assert_lib('@test/lib1#1.0.0')
	end)
end)

------------------------------------------------------
-- path loader: options vid without manifest

test_simple('path_options_vid', function()
	basis.lib({
		id = '@test/lib_no_init',
		version = '1.2.3',
		loader = basis.loader.path('basis/test/require/lib_no_init'),
	})

	basis.on_load(function()
		assert_lib('@test/lib_no_init#1.2.3')
	end)
end)

------------------------------------------------------
-- path loader: manifest version check

------------------------------------------------------
-- path loader: unspecified id error

------------------------------------------------------
-- path loader: unspecified version error

-- bad id / bad version

-- inlib error handling

--- github loader default version in main thread
--- 

queue(function(resolve)
	print(sv() .. ' total passed tests: ' .. passed_tests)
	resolve()
end)