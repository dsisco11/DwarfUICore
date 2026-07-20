local separator = package.config:sub(1, 1)
local source = debug.getinfo(1, 'S').source
assert(source:sub(1, 1) == '@', 'tests/run.lua must be loaded from a file')

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

-- Run-Unittests.ps1 owns deterministic discovery. This Busted helper verifies
-- the same file list before any specs execute while leaving Busted's command-
-- line arguments available for filtering, verbosity, and output selection.
local discovered_files = assert(os.getenv('LUA_TEST_FILES'),
    'LUA_TEST_FILES must be provided by Tools/Run-Unittests.ps1')
local normalized_tests_root = tests_root:gsub('\\', '/') .. '/'

for path in discovered_files:gmatch('[^\r\n]+') do
    local normalized_path = path:gsub('\\', '/')
    assert(normalized_path:sub(1, #normalized_tests_root) ==
        normalized_tests_root,
        'discovered test is outside tests/: ' .. path)
end
