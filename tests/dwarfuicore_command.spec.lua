local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local ROOT_PATH = 'src/scripts_modinstalled/dwarfuicore.lua'
local REGISTRY_NAME = 'dwarfuicore/module_registry'
local RUNTIME_NAME = 'dwarfuicore/service_provider/runtime'

---Creates a deterministic private runtime lifecycle seam.
---@return table runtime
local function runtime_stub()
    local state
    return {
        begin_initialization=function()
            if state then return state, false end
            state={generation=1, status='initializing'}
            return state, true
        end,
        complete_initialization=function(generation)
            assert.equals(state.generation, generation)
            state.status='healthy'
        end,
        fail_initialization=function(generation)
            assert.equals(state.generation, generation)
            state.status='disabled'
        end,
        begin_reload=function()
            if not state then state={generation=1, status='healthy'} end
            assert.equals('healthy', state.status)
            state.status='retiring'
            return state
        end,
        begin_reconstruction=function()
            state={generation=state.generation + 1, status='initializing'}
            return state
        end,
    }
end

---Creates a controlled DFHack command surface and call log.
---@param loaded? table<string, boolean>
---@return table dfhack
---@return table calls
local function dfhack_stub(loaded)
    loaded = loaded or {}
    local calls = {
        commands={},
        scripts={},
    }
    local dfhack = {
        internal={scripts={}},
        findScript=function(name)
            if loaded[name] then return name end
            return nil
        end,
        run_command=function(...)
            table.insert(calls.commands, {...})
        end,
        run_script=function(name)
            table.insert(calls.scripts, name)
        end,
    }
    for name in pairs(loaded) do dfhack.internal.scripts[name] = true end
    return dfhack, calls
end

---Loads the Core command module with controlled registry and DFHack seams.
---@param registry table
---@param dfhack table
---@return table root
local function load_root(registry, dfhack)
    local runtime = runtime_stub()
    local _, root = module_loader.load(repo_root, ROOT_PATH, {
        globals={
            dfhack=dfhack,
            dfhack_flags={module=true},
            qerror=function(message) error(message, 0) end,
        },
        reqscript={
            [REGISTRY_NAME]=registry,
            [RUNTIME_NAME]=runtime,
            ['dwarfuicore/tooltip/runtime']={},
            ['dwarfuicore/tooltip/render_hook']={},
            ['dwarfuicore/context_menu/service']={},
            ['dwarfuicore/context_menu/registration']={},
        },
    })
    return root
end

---Creates a valid registry with deterministic module names.
---@param modules? string[]
---@param load_all? fun(loader: fun(name: string): table): table<string, table>
---@return table
local function registry_stub(modules, load_all)
    modules = modules or {}
    local specs = {}
    for _, name in ipairs(modules) do
        table.insert(specs, {name=name})
    end
    return {
        MODULES=specs,
        get_script_names=function()
            local names = {REGISTRY_NAME}
            for index=#modules,1,-1 do
                table.insert(names, modules[index])
            end
            return names
        end,
        load_all=load_all or function()
            return {}
        end,
    }
end

describe('dwarfuicore command lifecycle', function()
    it('exports validation, teardown, and explicit reload as a module',
            function()
        local dfhack = dfhack_stub()
        local root = load_root(registry_stub(), dfhack)

        assert.is_function(root.initialize)
        assert.is_function(root.teardown)
        assert.is_function(root.reload)
        assert.is_function(root.main)
    end)

    it('performs no loading or destructive work when imported as a module',
            function()
        local dfhack, calls = dfhack_stub()
        load_root(registry_stub(), dfhack)

        assert.same({}, calls.commands)
        assert.same({}, calls.scripts)
    end)

    it('validates repeatedly without replacing healthy singleton state',
            function()
        local singleton = {}
        local calls = 0
        local registry = registry_stub({}, function()
            calls = calls + 1
            return {['dwarfuicore/tooltip/service']=singleton}
        end)
        local dfhack, command_calls = dfhack_stub()
        local root = load_root(registry, dfhack)

        assert.is_equal(singleton, root.initialize()
            ['dwarfuicore/tooltip/service'])
        assert.is_equal(singleton, root.initialize()
            ['dwarfuicore/tooltip/service'])
        assert.equals(2, calls)
        assert.same({}, command_calls.commands)
        assert.same({}, command_calls.scripts)
    end)

    it('does not repair a malformed registry during initialization', function()
        local registry = {}
        local dfhack, calls = dfhack_stub()
        local root = load_root(registry, dfhack)

        assert.has_error(root.initialize)
        assert.same({}, calls.commands)
        assert.same({}, calls.scripts)
    end)

    it('retires Core owners before rebuilding modules in registry order',
            function()
        local modules = {'dwarfuicore/alpha', 'dwarfuicore/beta'}
        local registry = registry_stub(modules)
        local loaded = {
            ['dwarfuicore/tooltip/runtime']=true,
            ['dwarfuicore/context_menu/service']=true,
            ['dwarfuicore/alpha']=true,
            ['dwarfuicore/beta']=true,
        }
        local dfhack, calls = dfhack_stub(loaded)
        local tooltip_namespace_registry = {}
        local unrelated_state = {}
        dfhack.dwarfuicore = {
            tooltip_namespace_registry=tooltip_namespace_registry,
            unrelated_state=unrelated_state,
        }
        local events = {}
        local root = load_root(registry, dfhack)
        local environments = {
            [RUNTIME_NAME]=runtime_stub(),
            ['dwarfuicore/tooltip/runtime']={
                presenter={retire_for_reload=function()
                    table.insert(events, 'tooltip')
                end},
            },
            ['dwarfuicore/context_menu/service']={
                service={shutdown=function()
                    table.insert(events, 'context-menu')
                end},
            },
        }
        local _, reloaded_root = module_loader.load(repo_root, ROOT_PATH, {
            globals={
                dfhack=dfhack,
                dfhack_flags={module=true},
                qerror=function(message) error(message, 0) end,
            },
            reqscript=setmetatable({[REGISTRY_NAME]=registry}, {
                __index=function(_, name)
                    return environments[name]
                end,
            }),
        })

        assert.same({}, reloaded_root.reload())
        assert.same({'context-menu', 'tooltip'}, events)
        assert.is_equal(tooltip_namespace_registry,
            dfhack.dwarfuicore.tooltip_namespace_registry)
        assert.is_equal(unrelated_state,
            dfhack.dwarfuicore.unrelated_state)
        assert.same({REGISTRY_NAME, 'dwarfuicore/alpha',
            'dwarfuicore/beta'}, calls.scripts)
        assert.same({
            {'devel/clear-script-env', 'dwarfuicore/beta',
                'dwarfuicore/alpha'},
            {'devel/clear-script-env', REGISTRY_NAME},
            {'devel/clear-script-env', 'dwarfuicore/alpha',
                'dwarfuicore/beta'},
        }, calls.commands)
    end)

    it('retires partial Core runtime owners during explicit teardown',
            function()
        local loaded = {
            ['dwarfuicore/tooltip/render_hook']=true,
            ['dwarfuicore/context_menu/registration']=true,
        }
        local dfhack = dfhack_stub(loaded)
        local events = {}
        local registry = registry_stub()
        local _, root = module_loader.load(repo_root, ROOT_PATH, {
            globals={
                dfhack=dfhack,
                dfhack_flags={module=true},
                qerror=function(message) error(message, 0) end,
            },
            reqscript={
                [REGISTRY_NAME]=registry,
                [RUNTIME_NAME]=runtime_stub(),
                ['dwarfuicore/tooltip/runtime']={},
                ['dwarfuicore/tooltip/render_hook']={
                    manager={shutdown=function()
                        table.insert(events, 'tooltip-partial')
                    end},
                },
                ['dwarfuicore/context_menu/service']={},
                ['dwarfuicore/context_menu/registration']={
                    manager={shutdown=function()
                        table.insert(events, 'context-menu-partial')
                    end},
                },
            },
        })

        root.teardown()
        assert.same({'context-menu-partial', 'tooltip-partial'}, events)
    end)

    it('reports the module that fails during explicit reconstruction',
            function()
        local module_name = 'dwarfuicore/broken'
        local registry = registry_stub({module_name})
        local dfhack = dfhack_stub({[module_name]=true})
        dfhack.run_script = function(name)
            if name == module_name then error('controlled reload failure') end
        end
        local root = load_root(registry, dfhack)

        local ok, failure = pcall(root.reload)
        assert.is_false(ok)
        assert.is_truthy(tostring(failure):find(
            'DwarfUICore reload failed while loading ' .. module_name,
            1, true))
    end)
end)
