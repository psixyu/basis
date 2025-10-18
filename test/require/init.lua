local basis = require('basis/require')	--[[@as basis.require]]

------------------------------------------------------

local last_promise = nil	---@type basis.require.promise
local pending_tests = 0
local passed_tests = 0

---@param name string
---@param func fun()
local function test_simple(name, func)
	pending_tests = pending_tests + 1

	local function run()
		last_promise = basis.promise(
			function(resolve, error)
				local status, result = pcall(func)
				if not status then
					error(result, 0)
				end
				
				basis.on_load(function()
					passed_tests = passed_tests + 1
					print('[TEST ' .. name .. '] PASSED')
					
					basis.__clear_libs()
					
					resolve()
				end)
				
				basis.on_error(error)
			end
		)
	end
	
	if last_promise then
		last_promise:Then(run)
	else
		run()
	end
end

---@param tag string
local function assert_lib(tag)
	assert(basis.__check_lib(tag))
end

------------------------------------------------------
-- path loader vid ejection from manifest

test_simple('path_manifest_vid', function()
	basis.lib({
		loader = basis.loader.path('scripts/vscripts/test/require/lib1')
	})
	
	basis.on_load(function()
		assert_lib('@test/lib1#1.0.0')
	end)
end)

------------------------------------------------------
-- path loader options vid without manifest

------------------------------------------------------
-- path loader manifest version check

------------------------------------------------------
-- path loader unspecified id error

------------------------------------------------------
-- path loader unspecified version error


--- github loader default version in main thread
--- 