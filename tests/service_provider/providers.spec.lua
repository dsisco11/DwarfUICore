local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local _, immutable_enum = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua')
local _, contracts = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/contracts.lua', {
        reqscript={['dwarfuicore/utils/immutable_enum']=immutable_enum},
    })
local _, immutable_proxy = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/immutable_proxy.lua')
local _, namespaces = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/namespace.lua')

---Loads one provider through the real acquisition boundary with no adapter.
---@param relative_path string
---@return table provider_module
local function load_provider_without_implementation(relative_path)
    local process = {dwarfuicore={}}
    local _, runtime = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/runtime.lua', {
            globals={dfhack=process},
            reqscript={
                ['dwarfuicore/service_provider/contracts']=contracts,
            },
        })
    local _, acquisition = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/acquisition.lua', {
            reqscript={
                ['dwarfuicore/service_provider/contracts']=contracts,
                ['dwarfuicore/service_provider/namespace']=namespaces,
                ['dwarfuicore/service_provider/runtime']=runtime,
            },
        })
    local _, api = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/service_provider/api.lua', {
            reqscript={
                ['dwarfuicore/service_provider/contracts']=contracts,
                ['dwarfuicore/service_provider/identity']={
                    get_map_handle_identity=function() end,
                },
                ['dwarfuicore/service_provider/immutable_proxy']=immutable_proxy,
                ['dwarfuicore/service_provider/runtime']=runtime,
            },
        })
    local _, provider_module = module_loader.load(repo_root, relative_path, {
        reqscript={
            ['dwarfuicore/service_provider/acquisition']=acquisition,
            ['dwarfuicore/service_provider/api']=api,
            ['dwarfuicore/service_provider/contracts']=contracts,
            ['dwarfuicore/service_provider/immutable_proxy']=immutable_proxy,
        },
    })
    return provider_module
end

---Asserts one stable provider construction failure category.
---@param callback function
---@param service_name string
---@param category string
local function assert_provider_category(callback, service_name, category)
    local ok, failure = pcall(callback)
    assert.is_false(ok)
    assert.equals(('DwarfUICore %sServiceProvider: [%s] '):format(
        service_name, category), tostring(failure):sub(1,
        #('DwarfUICore %sServiceProvider: [%s] '):format(
            service_name, category)))
end

---Loads one provider over controlled acquisition and API construction seams.
---@param relative_path string
---@return table provider
---@return table calls
local function load_provider(relative_path)
    local calls = {acquire={}, api={}}
    local acquisition = {acquire=function(...)
        table.insert(calls.acquire, {...})
        return {facade={}, contract_major=1, namespace=select(5, ...),
            generation=1, service_kind=select(1, ...)}
    end}
    local api = {new_factory=function(_, _, _)
        return {create=function(_, metadata)
            local object = {metadata=metadata}
            table.insert(calls.api, object)
            return object
        end}
    end}
    local _, provider = module_loader.load(repo_root, relative_path, {
        reqscript={
            ['dwarfuicore/service_provider/acquisition']=acquisition,
            ['dwarfuicore/service_provider/api']=api,
            ['dwarfuicore/service_provider/contracts']=contracts,
            ['dwarfuicore/service_provider/immutable_proxy']=immutable_proxy,
        },
    })
    return provider, calls
end

describe('service provider exports', function()
    for _, case in ipairs({
            {name='tooltip', path='src/scripts_modinstalled/dwarfuicore/service_provider/tooltip_provider.lua', kind=contracts.ServiceKind.TOOLTIP},
            {name='context menu', path='src/scripts_modinstalled/dwarfuicore/service_provider/context_menu_provider.lua', kind=contracts.ServiceKind.CONTEXT_MENU},
        }) do
        it('creates immutable distinct ' .. case.name .. ' APIs lazily', function()
            local provider_module, calls = load_provider(case.path)
            local provider = provider_module.get_provider()
            local first = provider:new(1, 'consumer')
            local second = provider:new(1, 'consumer')
            assert.is_not_equal(first, second)
            assert.equals(2, #calls.acquire)
            assert.equals(case.kind, calls.acquire[1][1])
            assert.equals(1, calls.acquire[1][2])
            assert.equals(1, calls.acquire[1][4])
            assert.equals('consumer', calls.acquire[1][5])
            assert.is_true(calls.acquire[1][6])
            assert.is_true(type(calls.acquire[1][3]) == 'function')
            assert.same({}, (function()
                local keys = {}
                for key in pairs(provider) do table.insert(keys, key) end
                return keys
            end)())
            assert.has_error(function() provider.extra = true end)
            assert.has_error(function() provider.new = function() end end)
        end)
    end

    for _, case in ipairs({
            {name='tooltip', service='Tooltip',
                path='src/scripts_modinstalled/dwarfuicore/service_provider/tooltip_provider.lua'},
            {name='context menu', service='ContextMenu',
                path='src/scripts_modinstalled/dwarfuicore/service_provider/context_menu_provider.lua'},
        }) do
        it('reports a missing private ' .. case.name ..
                ' implementation through its public provider', function()
            local provider = load_provider_without_implementation(case.path)
                .get_provider()
            assert_provider_category(function()
                provider:new(1, 'consumer')
            end, case.service, 'INITIALIZATION_FAILED')
        end)
    end
end)
