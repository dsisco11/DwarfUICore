local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local separator = package.config:sub(1, 1)
local public_modules = {
    'dwarfui/text.lua',
    'dwarfui/widget_extensions.lua',
    'dwarfui/pointer.lua',
    'dwarfui/mood_popover.lua',
    'dwarfui/tooltip.lua',
    'dwarfui/tooltip_registration.lua',
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

---Reads one repository file as binary text.
---@param relative_path string
---@return string
local function read_repository_file(relative_path)
    local file = assert(io.open(repo_root .. separator ..
        relative_path:gsub('/', separator), 'rb'))
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
    elseif package_path == 'scripts_modinstalled/dwarfui/tooltip.lua' then
        local widget_harness = require('support.widget_harness')
        local default_nil = widget_harness.default_nil()
        local widgets = widget_harness.widgets(nil, default_nil)
        options = {
            globals={
                COLOR_BLACK='black',
                COLOR_WHITE='white',
                DEFAULT_NIL=default_nil,
                defclass=widget_harness.defclass,
                dfhack={
                    pen={parse=function(value) return value end},
                    screen={
                        getMousePos=function() return nil, nil end,
                        getWindowSize=function() return 80, 25 end,
                    },
                },
            },
            require_modules={
                gui={FRAME_INTERIOR='interior', paint_frame=function() end},
                ['gui.widgets']=widgets,
            },
            reqscript={
                ['dwarfui/widget_extensions']={},
                ['dwarfui/pointer']={
                    PointerContext={new=function() return {} end},
                    PointerDispatcher={sample=function() return {kind='miss'} end},
                },
                ['dwarfui/text']={wrap_text=function() return {''} end},
                ['dwarfui/tooltip_registration']={
                    register=function() return true end,
                    unregister=function() return true end,
                },
            },
        }
    elseif package_path ==
            'scripts_modinstalled/dwarfui/tooltip_registration.lua' then
        local widget_harness = require('support.widget_harness')
        local default_nil = widget_harness.default_nil()
        local widgets = widget_harness.widgets(nil, default_nil)
        widgets.Widget.ATTRS{visible=true, active=true}
        ---@class tests.PackageContractZScreen
        local ZScreen = widget_harness.defclass(nil, widgets.Widget)
        ---@class tests.PackageContractOverlay
        local OverlayWidget = widget_harness.defclass(nil, widgets.Panel)
        options = {
            globals={
                defclass=widget_harness.defclass,
                dfhack={
                    gui={
                        getDFViewscreen=function() return nil end,
                        matchFocusString=function() return false end,
                    },
                    screen={getMousePos=function() return nil, nil end},
                    timeout=function() end,
                },
            },
            require_modules={
                gui={ZScreen=ZScreen, Painter={new=function() return {} end}},
                ['plugins.overlay']={
                    OverlayWidget=OverlayWidget,
                    get_state=function() return {config={}, db={}} end,
                    isOverlayEnabled=function() return false end,
                    normalize_list=function(value) return {value} end,
                    simplify_viewscreen_name=function(value) return value end,
                },
            },
            reqscript={
                ['dwarfui/pointer']={PointerDispatcher={resolve=function()
                    return {kind='miss'}
                end}},
                ['dwarfui/tooltip']={TooltipRenderer=function() return {} end},
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

    it('supports Lua 5.3 and newer without an artificial upper bound',
            function()
        local rockspec = read_repository_file('dwarfui.rockspec')
        contains(rockspec, '"lua >= 5.3"')
        assert.is_nil(rockspec:find('< 5.4', 1, true))
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
