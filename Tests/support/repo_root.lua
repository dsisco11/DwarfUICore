local separator = package.config:sub(1, 1)
local source = debug.getinfo(1, 'S').source
assert(source:sub(1, 1) == '@',
    'support/repo_root.lua must be loaded from a file')

local support_root = assert(source:sub(2):match('^(.*)[/\\][^/\\]+$'),
    'could not resolve the test support directory')

return support_root .. separator .. '..' .. separator .. '..'
