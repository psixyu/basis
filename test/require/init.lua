local basis = require('basis/require')	--[[@as basis]]

------------------------------------------------------

local last_promise = nil	---@type basis.promise?
local pending_tests = 0
local passed_tests = 0

local function sv()
	return IsServer() and 'SV ' or 'CL '
end

---@param promise basis.promise
local function promise_setup(promise)
	promise:RaiseErrors()
end

---@param run basis.promise.runner
local function queue(run)
	last_promise = basis.chain(last_promise, run, promise_setup)
end

---@param name string
local function print_run(name)
	print(sv() .. 'RUNNING [TEST ' .. name .. ']')
end

---@param name string
local function pass(name)
	print(sv() .. '[TEST ' .. name .. '] PASSED')
	passed_tests = passed_tests + 1
	basis.__clear_libs()
end

---@param name string
---@param func fun()
local function test_simple(name, func)
	pending_tests = pending_tests + 1

	queue(
		function(resolve, error)
			print_run(name)
			
			if not basis.__spcall(func, error) then
				return
			end
			
			basis.on_load(function()
				pass(name)
				resolve() return
			end)
			
			basis.on_error(error)
		end
	)
end

local function test_error(name, func)
	pending_tests = pending_tests + 1
	
	queue(
		function(resolve, error)
			print_run(name)
			
			if not basis.__spcall(func, error) then
				return
			end
			
			basis.on_load(function()
				error('loading expected to fail, but passed successfully', 0)
			end)
			
			basis.on_error(function()
				pass(name)
				resolve() return
			end)
		end
	)
end

---@param tag string
local function assert_lib(tag)
	assert(basis.__check_lib(tag))
end

---@param tag string
local function assert_no_lib(tag)
	assert(not basis.__check_lib(tag))
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

test_simple('path_manifest_options_vid', function()
	basis.lib({
		id = '@test/lib2',
		version = '1.1.4',	-- less than actual
		loader = basis.loader.path('basis/test/require/lib2')
	})

	basis.on_load(function()
		assert_lib('@test/lib2#1.1.5')
	end)
end)

------------------------------------------------------
-- path loader: manifest version mismatch

test_error('path_manifest_options_vid_mis', function()
	basis.lib({
		id = '@test/lib2',
		version = '1.1.6',	-- greater than actual
		loader = basis.loader.path('basis/test/require/lib2')
	})
end)

------------------------------------------------------
-- path loader: unspecified id error

test_error('path_manifest_no_id', function()
	basis.lib({
		version = '1.2.3',
		loader = basis.loader.path('basis/test/require/lib_no_init')
	})
end)

------------------------------------------------------
-- path loader: unspecified version defaults

test_simple('path_manifest_no_version', function()
	basis.lib({
		id = '@test/lib_no_init',
		loader = basis.loader.path('basis/test/require/lib_no_init')
	})
	
	basis.on_load(function()
		assert_lib('@test/lib_no_init#1.0.0')
	end)
end)

------------------------------------------------------
-- path loader: sublib

test_simple('path_sublib', function()
	basis.lib({
		loader = basis.loader.path('basis/test/require/lib3')
	})
	
	basis.on_load(function()
		assert_lib('@test/lib3#2.1.0')
		assert_lib('@test/lib2#1.1.5')
	end)
end)

------------------------------------------------------
-- path loader: upgrade resolution

test_simple('path_resolution_upgrade', function()
	basis.lib({
		loader = basis.loader.path('basis/test/require/lib1')
	})
	
	basis.lib({
		loader = basis.loader.path('basis/test/require/lib1_1')
	})
	
	basis.on_load(function()
		assert_lib('@test/lib1#1.1.0')
	end)
end)

test_simple('path_resolution_upgrade_order', function()
	basis.lib({
		loader = basis.loader.path('basis/test/require/lib1_1')
	})
	
	basis.lib({
		loader = basis.loader.path('basis/test/require/lib1')
	})
	
	basis.on_load(function()
		assert_lib('@test/lib1#1.1.0')
	end)
end)

------------------------------------------------------
-- path loader: major upgrade resolution

test_simple('path_resolution_major', function()
	basis.lib({
		loader = basis.loader.path('basis/test/require/lib2')
	})
	
	basis.lib({
		loader = basis.loader.path('basis/test/require/lib2_2')
	})
	
	basis.on_load(function()
		assert_lib('@test/lib2#1.1.5')
		assert_lib('@test/lib2#2.0.0')
	end)
end)

------------------------------------------------------
-- path loader: nested upgrade resolution

test_simple('path_resolution_nested_up', function()
	basis.lib({
		loader = basis.loader.path('basis/test/require/lib1')
	})
	
	basis.lib({
		loader = basis.loader.path('basis/test/require/lib4')
	})
	
	basis.on_load(function()
		assert_lib('@test/lib4#1.2.3')
		assert_lib('@test/lib1#1.1.0')
	end)
end)

------------------------------------------------------
-- path loader: no downgrade resolution

test_simple('path_resolution_no_downgrade', function()
	basis.lib({
		loader = basis.loader.path('basis/test/require/lib3_2'),
	})
	
	basis.lib({
		loader = basis.loader.path('basis/test/require/lib5'),
	})
	
	basis.on_load(function()
		assert_lib('@test/lib5#1.0.0')
		assert_lib('@test/lib3#2.1.2')
		assert_no_lib('@test/lib2#1.1.5')
	end)
end)

-- inlib error handling

--- github loader default version in main thread
--- 

queue(function(resolve)
	print(sv() .. 'TOTAL PASSED TESTS: ' .. passed_tests .. '/' .. pending_tests)
	resolve() return
end)