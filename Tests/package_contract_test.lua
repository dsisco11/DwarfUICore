local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local separator = package.config:sub(1, 1)
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

local function contains(text, expected)
    assert.is_truthy(text:find(expected, 1, true))
end

local function load_public_module(package_path)
    local options
    if package_path == 'scripts_modinstalled/dwarfui/widget_extensions.lua' then
        local widget_harness = require('support.widget_harness')
        local default_nil = widget_harness.default_nil()
        options = {
            globals={DEFAULT_NIL=default_nil},
            require_modules={
                ['gui.widgets']=widget_harness.widgets(nil, default_nil),
            },
        }
    end
    return module_loader.load(repo_root, 'src/' .. package_path, options)
end

describe('DwarfUI package contract', function()
    it('publishes the expected metadata', function()
        local info = read_source('info.txt')
        local expected = {
            ID='dwarfui',
            NAME='DwarfUI',
            NUMERIC_VERSION='1',
            DISPLAYED_VERSION='0.1.0',
            DESCRIPTION='Reusable DFHack UI infrastructure and user-facing interface enhancements.',
        }
        for key, value in pairs(expected) do
            contains(info, ('[%s:%s]'):format(key, value))
        end
    end)

    it('keeps stable public module contracts', function()
        for _, relative_path in ipairs(public_modules) do
            local package_path = 'scripts_modinstalled/' .. relative_path
            local source = read_source(package_path)
            contains(source, '--@ module=true')
            assert.is_nil(source:lower():find('soulsearch', 1, true))

            local _, module_result = load_public_module(package_path)
            assert.equals('table', type(module_result), package_path)
        end
    end)

    it('roots the public namespace in the package', function()
        for _, relative_path in ipairs(public_modules) do
            local file = assert(io.open(source_path(
                'scripts_modinstalled/' .. relative_path), 'rb'))
            file:close()
        end
    end)
end)
