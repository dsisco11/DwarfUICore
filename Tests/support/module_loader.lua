local M = {}

local function join_path(root, relative_path)
    local separator = package.config:sub(1, 1)
    return root .. separator .. relative_path:gsub('[/\\]', separator)
end

local function lookup(modules, kind, name)
    local value = modules and modules[name]
    assert(value ~= nil, ('unexpected %s: %s'):format(kind, tostring(name)))
    return value
end

---Loads a DFHack-style module with test-controlled collaborators.
---@param repo_root string
---@param relative_path string
---@param options? {globals?: table, reqscript?: table<string, any>, require_modules?: table<string, any>}
---@return table environment
---@return any module_result
function M.load(repo_root, relative_path, options)
    assert(type(repo_root) == 'string' and repo_root ~= '',
        'module loader requires a repository root')
    assert(type(relative_path) == 'string' and relative_path ~= '',
        'module loader requires a relative module path')
    options = options or {}

    local environment = {}
    for key, value in pairs(options.globals or {}) do
        environment[key] = value
    end

    -- reqscript is always controlled. A unit test must explicitly supply every
    -- DFHack script dependency instead of accidentally reaching a live install.
    environment.reqscript = function(name)
        return lookup(options.reqscript, 'reqscript', name)
    end

    if options.require_modules then
        environment.require = function(name)
            return lookup(options.require_modules, 'require', name)
        end
    else
        environment.require = require
    end

    setmetatable(environment, {__index=_G})
    local chunk, err = loadfile(join_path(repo_root, relative_path), 't', environment)
    assert(chunk, err)
    local module_result = chunk()
    return environment, module_result
end

return M
