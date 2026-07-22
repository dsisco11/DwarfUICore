local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

---Creates a minimal valid registry generation for command testing.
---@param names string[]
---@param generation string
---@param events table[]
---@return table
local function make_registry(names, generation, events)
    local specs = {}
    for _, name in ipairs(names) do
        table.insert(specs, {name=name})
    end
    return {
        MODULES=specs,
        get_script_names=function()
            return {'dwarfui/module_registry', table.unpack(names)}
        end,
        load_all=function(loader)
            table.insert(events, {'validate', generation})
            local loaded = {}
            for _, name in ipairs(names) do loaded[name] = loader(name) end
            return loaded
        end,
    }
end

describe('dwarfui command', function()
    it('reloads the manifest, modules, and overlays in order', function()
        local events = {}
        local old_names = {'dwarfui/consumer', 'dwarfui/dependency'}
        local fresh_names = {'dwarfui/dependency', 'dwarfui/consumer'}
        local old_registry = make_registry(old_names, 'old', events)
        local fresh_registry = make_registry(fresh_names, 'fresh', events)
        local registry = old_registry
        local scripts = {}
        local all_names = {
            'dwarfui/module_registry',
            'dwarfui/consumer',
            'dwarfui/dependency',
            'dwarfui-mood-popover',
            'dwarfui-unit-card-task-details',
        }
        for _, name in ipairs(all_names) do
            scripts['/scripts/' .. name .. '.lua'] = {generation='old'}
        end

        local environment = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfui.lua', {
                globals={
                    dfhack_flags={module=true},
                    dfhack={
                        internal={scripts=scripts},
                        findScript=function(name)
                            return '/scripts/' .. name .. '.lua'
                        end,
                        run_command=function(...)
                            table.insert(events, {'clear', ...})
                        end,
                        run_script=function(name)
                            table.insert(events, {'run', name})
                            if name == 'dwarfui/module_registry' then
                                registry = fresh_registry
                            end
                        end,
                    },
                },
                reqscript=setmetatable({}, {__index=function(_, name)
                    if name == 'dwarfui/module_registry' then return registry end
                    return {generation='fresh'}
                end}),
                require_modules={
                    ['plugins.overlay']={rescan=function()
                        table.insert(events, {'overlay_rescan'})
                    end},
                },
            })

        environment.reload()

        assert.same({'clear', 'devel/clear-script-env',
            'dwarfui/consumer', 'dwarfui/dependency'}, events[1])
        assert.same({'clear', 'devel/clear-script-env',
            'dwarfui/module_registry'}, events[2])
        assert.same({'run', 'dwarfui/module_registry'}, events[3])
        assert.same({'clear', 'devel/clear-script-env',
            'dwarfui/dependency', 'dwarfui/consumer'}, events[4])
        assert.same({'run', 'dwarfui/dependency'}, events[5])
        assert.same({'run', 'dwarfui/consumer'}, events[6])
        assert.same({'overlay_rescan'}, events[7])
        assert.same({'validate', 'fresh'}, events[8])
        assert.is_nil(scripts['/scripts/dwarfui-mood-popover.lua'])
        assert.is_nil(scripts[
            '/scripts/dwarfui-unit-card-task-details.lua'])
    end)

    it('validates modules without clearing them for the default command',
            function()
        local events = {}
        local registry = make_registry({'dwarfui/text'}, 'current', events)
        local environment = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfui.lua', {
                globals={dfhack_flags={module=true}, dfhack={}},
                reqscript=setmetatable({}, {__index=function(_, name)
                    if name == 'dwarfui/module_registry' then return registry end
                    return {wrap_text=function() end}
                end}),
            })

        environment.main()

        assert.same({{'validate', 'current'}}, events)
    end)
end)
