local separator = package.config:sub(1, 1)
local source = debug.getinfo(1, 'S').source
assert(source:sub(1, 1) == '@', 'Tests/run.lua must be loaded from a file')

local tests_root = assert(source:sub(2):match('^(.*)[/\\][^/\\]+$'),
    'could not resolve the tests directory')
local repo_root = tests_root .. separator .. '..'
local production_root = repo_root .. separator .. 'src' .. separator ..
    'scripts_modinstalled'

package.path = table.concat({
    tests_root .. separator .. '?.lua',
    tests_root .. separator .. '?' .. separator .. 'init.lua',
    production_root .. separator .. '?.lua',
    production_root .. separator .. '?' .. separator .. 'init.lua',
    package.path,
}, ';')

local luaunit = require('luaunit')

-- Run-UnitTests.ps1 owns deterministic discovery. Keeping its file list in an
-- environment variable leaves LuaUnit's command-line arguments untouched for
-- targeted cases, verbosity, and output format selection.
local discovered_files = assert(os.getenv('LUA_TEST_FILES'),
    'LUA_TEST_FILES must be provided by Tools/Run-UnitTests.ps1')
local normalized_tests_root = tests_root:gsub('\\', '/') .. '/'

for path in discovered_files:gmatch('[^\r\n]+') do
    local normalized_path = path:gsub('\\', '/')
    assert(normalized_path:sub(1, #normalized_tests_root) ==
        normalized_tests_root,
        'discovered test is outside Tests/: ' .. path)

    local relative_path = normalized_path:sub(#normalized_tests_root + 1)
    local module_name = relative_path:gsub('%.lua$', ''):gsub('/', '.')
    local suite = require(module_name)
    assert(type(suite) == 'table',
        module_name .. ' must return a LuaUnit test table')

    local global_name = 'Test_' .. module_name:gsub('[^%w]', '_')
    assert(_G[global_name] == nil,
        'duplicate LuaUnit suite name: ' .. global_name)
    _G[global_name] = suite
end

os.exit(luaunit.LuaUnit.run())
