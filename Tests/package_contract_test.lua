local luaunit = require('luaunit')
local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local separator = package.config:sub(1, 1)
local tests = {}

local public_modules = {
    'dwarfui/text.lua',
    'dwarfui/widget_extensions.lua',
    'dwarfui/pointer.lua',
    'dwarfui/tooltip.lua',
}

local function source_path(relative_path)
    return repo_root .. separator .. 'src' .. separator ..
        relative_path:gsub('/', separator)
end

local function read_source(relative_path)
    local file = assert(io.open(source_path(relative_path), 'rb'))
    local text = file:read('*a')
    file:close()
    return text
end

function tests:test_metadata_contract()
    local info = read_source('info.txt')
    local expected = {
        ID='dwarfui',
        NAME='DwarfUI',
        NUMERIC_VERSION='1',
        DISPLAYED_VERSION='0.1.0',
        DESCRIPTION='Reusable DFHack UI infrastructure and user-facing interface enhancements.',
    }
    for key, value in pairs(expected) do
        luaunit.assertStrContains(info, ('[%s:%s]'):format(key, value))
    end
end

function tests:test_public_modules_have_stable_module_contracts()
    for _, relative_path in ipairs(public_modules) do
        local package_path = 'scripts_modinstalled/' .. relative_path
        local source = read_source(package_path)
        luaunit.assertStrContains(source, '--@ module=true')
        luaunit.assertNotStrContains(source:lower(), 'soulsearch')

        local _, module_result = module_loader.load(
            repo_root, 'src/' .. package_path)
        luaunit.assertEquals('table', type(module_result), package_path)
    end
end

function tests:test_public_namespace_is_package_rooted()
    for _, relative_path in ipairs(public_modules) do
        local file = assert(io.open(source_path(
            'scripts_modinstalled/' .. relative_path), 'rb'))
        file:close()
    end
end

return tests
