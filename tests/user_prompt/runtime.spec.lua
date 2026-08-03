local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

---Loads one runtime assembly over a controlled state-machine service.
---@param generation? integer
---@return table runtime_module
---@return table state
local function load_runtime(generation)
    local state = {generation=generation or 7, retire_causes={}}
    local service = {
        start=function() end,
        cancel=function() end,
        is_active=function() end,
        clear_namespace=function() end,
        get_diagnostics=function()
            return {runtime_generation=state.generation}
        end,
        cancel_active=function(_, cause)
            table.insert(state.retire_causes, cause)
            return true
        end,
    }
    local service_module = {
        service=service,
        UserPromptTerminalCause={CORE_RELOAD=10},
    }
    local _, runtime_module = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/user_prompt/runtime.lua', {
            reqscript={
                ['dwarfuicore/user_prompt/service']=service_module,
            },
        })
    state.service = service
    return runtime_module, state
end

describe('UserPrompt runtime assembly', function()
    it('publishes one generation-bound assembly over the process service',
            function()
        local runtime_module, state = load_runtime(7)
        local runtime = runtime_module.get(7)

        assert.equals(7, runtime.generation)
        assert.is_equal(state.service, runtime.service)
        assert.is_equal(runtime, runtime_module.get(7))
        assert.is_equal(runtime, runtime_module.validate(runtime, 7))
    end)

    it('rejects stale generations and malformed service contracts', function()
        local runtime_module, state = load_runtime(7)

        assert.has_error(function() runtime_module.get(8) end,
            'DwarfUICore UserPrompt runtime is incomplete or stale.')
        state.generation = 8
        assert.has_error(function()
            runtime_module.validate(runtime_module.runtime, 7)
        end, 'DwarfUICore UserPrompt runtime is incomplete or stale.')
        assert.has_error(function()
            runtime_module.validate({generation=8, service={}}, 8)
        end, 'DwarfUICore UserPrompt runtime is incomplete or stale.')
    end)

    it('retires the active prompt with the Core-reload cause', function()
        local runtime_module, state = load_runtime(7)

        assert.is_true(runtime_module.retire_for_reload())
        assert.same({10}, state.retire_causes)
    end)
end)
