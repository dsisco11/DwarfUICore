local repo_root = require('support.repo_root')

local separator = package.config:sub(1, 1)

---Reads one repository source file as binary text.
---@param relative_path string
---@return string
local function read_source(relative_path)
    local path = repo_root .. separator .. relative_path:gsub('/', separator)
    local file = assert(io.open(path, 'rb'))
    local text = file:read('*a')
    file:close()
    return text
end

describe('DwarfUICore package contract', function()
    it('declares the DwarfUICore mod identity and root module', function()
        local info = read_source('src/info.txt')
        local root = read_source('src/scripts_modinstalled/dwarfuicore.lua')

        assert.is_truthy(info:find('[ID:dwarfuicore]', 1, true))
        assert.is_truthy(root:find('--@ module=true', 1, true))
    end)
end)
