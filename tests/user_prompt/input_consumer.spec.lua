local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

---Builds an immutable snapshot-shaped test value.
---@param map_position table|nil
---@return table
local function snapshot(map_position)
    return {map_position=map_position}
end

---Loads one prompt-first consumer with observable terminal callbacks.
---@return table
local function load_context()
    local results = {PASS=1, CONSUME=2}
    local _, module = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/user_prompt/input_consumer.lua', {
            reqscript={
                ['dwarfuicore/input_event/types']={
                    InputDispatchResult=results,
                },
            },
        })
    local state = {active=true, completions={}, cancellations={}, failures={}}
    local causes = {RIGHT_RELEASE=2, ESCAPE=3, INTERNAL_FAILURE=9}
    local consumer = module.UserPromptInputConsumer.new{
        is_active=function() return state.active end,
        complete=function(position)
            table.insert(state.completions, position)
            return true
        end,
        cancel=function(cause)
            table.insert(state.cancellations, cause)
            return true
        end,
        on_failure=function(message) table.insert(state.failures, message) end,
        causes=causes,
    }
    return {state=state, causes=causes, results=results, consumer=consumer}
end

describe('UserPrompt input consumer', function()
    it('consumes only active prompt-owned boundaries', function()
        local context = load_context()
        for _, key in ipairs{
                'LEAVESCREEN', '_MOUSE_L', '_MOUSE_R', '_MOUSE_L_DOWN',
                '_MOUSE_R_DOWN',
            } do
            assert.equals(context.results.CONSUME,
                context.consumer:consume({[key]=true}, snapshot(nil)), key)
        end
        assert.equals(context.results.PASS,
            context.consumer:consume({D_PAUSE=true}, snapshot(nil)))
    end)

    it('uses cancellation-before-completion precedence and the shared snapshot',
            function()
        local context = load_context()
        local position = {x=4, y=5, z=6}
        assert.equals(context.results.CONSUME, context.consumer:consume({
            LEAVESCREEN=true, _MOUSE_R=true, _MOUSE_L=true,
        }, snapshot(position)))
        assert.same({context.causes.ESCAPE}, context.state.cancellations)
        assert.same({}, context.state.completions)

        context = load_context()
        assert.equals(context.results.CONSUME,
            context.consumer:consume({_MOUSE_L=true}, snapshot(position)))
        assert.same({position}, context.state.completions)
    end)

    it('does not complete for down boundaries or cancellation boundaries',
            function()
        local context = load_context()
        assert.equals(context.results.CONSUME,
            context.consumer:consume({_MOUSE_L_DOWN=true}, snapshot(nil)))
        assert.equals(context.results.CONSUME,
            context.consumer:consume({_MOUSE_R=true}, snapshot(nil)))
        assert.same({}, context.state.completions)
        assert.same({context.causes.RIGHT_RELEASE}, context.state.cancellations)
    end)

    it('exposes a typed private-consumer callback and forwards failures',
            function()
        local context = load_context()
        local callbacks = context.consumer:callbacks()
        assert.equals(context.results.PASS,
            callbacks.consume({D_PAUSE=true}, snapshot(nil)))
        callbacks.on_failure('dispatch failed')
        assert.same({'dispatch failed'}, context.state.failures)
    end)
end)
