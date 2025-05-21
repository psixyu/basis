---@type basis.require
local exports = ({})

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------

---@type {[string]: table}
local loaded = {}

------------------------------------------------------

---@param lib string
---@return string
local function lib_name(lib)
	
end

---@param name string
---@return string?, string
local function parse_module_name(name)
	if name:match(':') then
		local lib, module = name:match('(.*):(.*)')
		-- lib = 
	else
		return nil, name
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
------------------------------------------------------
------------------------------------------------------

exports.lib = function(arg)
	
end

------------------------------------------------------
------------------------------------------------------
------------------------------------------------------

exports.require = function(arg)
	if type(arg) == 'string' then
		local lib, module = parse_module_name(arg)
		local loaders = get_loaders(lib)
		local errs = {}
		
		local next = ipairs(loaders)
		local i, loader = next(loaders)
		
		local function try_loader()
			if loader == nil then
				error()
			end
			
			loader:Load(
				module,
				function(body, err)
					if body == nil then
						table.insert(errs, err)
					
						i, loader = next(loaders, i)
						try_loader()
					else
						
					end
				end
			)
		end
		
		try_loader()
		
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
	local user, lib, version = string.match(tag, '^([%w_]+)/([%w_]+)#?([%w_]*)$')
	if user == nil then
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

local info = debug.getinfo(1, 'S')
local file = info.source:match('@scripts\\vscripts\\(.*)%.lua'):gsub('\\', '/')
package.preload[file] = function()
	
	
	return exports
end

------------------------------------------------------

return exports