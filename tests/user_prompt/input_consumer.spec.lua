local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

---Loads one isolated prompt input consumer with observable callbacks.
---@return table context
local function load_context()
    local _, module = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/user_prompt/input_consumer.lua')
    local state = {
        active=true,
        samples={},
        completions={},
        cancellations={},
        failures={},
    }
    local causes = {RIGHT_RELEASE=2, ESCAPE=3, INTERNAL_FAILURE=9}
    local consumer = module.UserPromptInputConsumer.new{
        is_active=function() return state.active end,
        get_map_position=function()
            local value = table.remove(state.samples, 1)
            state.sample_count = (state.sample_count or 0) + 1
            return value
        end,
        complete=function(position)
            table.insert(state.completions,
                position == nil and '<nil>' or position)
            return true
        end,
        cancel=function(cause)
            table.insert(state.cancellations, cause)
            return true
        end,
        on_failure=function(message)
            table.insert(state.failures, message)
        end,
        causes=causes,
    }
    return {module=module, state=state, causes=causes, consumer=consumer}
end

describe('UserPrompt input consumer', function()
    it('owns only exact prompt boundaries while active', function()
        local context = load_context()
        for _, key in ipairs{
                '_MOUSE_L_DOWN', '_MOUSE_L', '_MOUSE_R_DOWN', '_MOUSE_R',
                'LEAVESCREEN',
            } do
            assert.is_true(context.consumer:owns({[key]=true}), key)
        end
        for _, key in ipairs{'CURSOR_UP', 'D_PAUSE', 'CONTEXT_SCROLL_UP'} do
            assert.is_false(context.consumer:owns({[key]=true}), key)
        end
        assert.is_false(context.consumer:owns({}))
        assert.is_false(context.consumer:owns(nil))
        context.state.active = false
        assert.is_false(context.consumer:owns({_MOUSE_L=true}))
    end)

    it('consumes down boundaries without sampling or terminating', function()
        local context = load_context()

        assert.is_true(context.consumer:handle({_MOUSE_L_DOWN=true}))
        assert.is_true(context.consumer:handle({_MOUSE_R_DOWN=true}))
        assert.is_nil(context.state.sample_count)
        assert.same({}, context.state.completions)
        assert.same({}, context.state.cancellations)
    end)

    it('samples each left release exactly once and accepts nil without a latch',
            function()
        local context = load_context()
        local sampled = {x=1, y=2, z=3}
        context.state.samples = {sampled}

        assert.is_true(context.consumer:handle({_MOUSE_L=true}))
        assert.equals(1, context.state.sample_count)
        assert.same({{x=1, y=2, z=3}}, context.state.completions)
        assert.is_not_equal(sampled, context.state.completions[1])

        context.state.samples = {}
        assert.is_true(context.consumer:handle({_MOUSE_L=true}))
        assert.equals(2, context.state.sample_count)
        assert.same({{x=1, y=2, z=3}, '<nil>'},
            context.state.completions)
    end)

    it('applies cancellation then completion then down precedence', function()
        local context = load_context()
        context.state.samples = {{x=4, y=5, z=6}}

        assert.is_true(context.consumer:handle{
            LEAVESCREEN=true, _MOUSE_R=true, _MOUSE_L=true,
            _MOUSE_L_DOWN=true, _MOUSE_R_DOWN=true,
        })
        assert.same({context.causes.ESCAPE}, context.state.cancellations)
        assert.same({}, context.state.completions)
        assert.is_nil(context.state.sample_count)

        context = load_context()
        context.state.samples = {{x=4, y=5, z=6}}
        assert.is_true(context.consumer:handle{
            _MOUSE_R=true, _MOUSE_L=true, _MOUSE_L_DOWN=true,
        })
        assert.same({context.causes.RIGHT_RELEASE},
            context.state.cancellations)
        assert.is_nil(context.state.sample_count)

        context = load_context()
        context.state.samples = {{x=4, y=5, z=6}}
        assert.is_true(context.consumer:handle{
            _MOUSE_L=true, _MOUSE_L_DOWN=true, _MOUSE_R_DOWN=true,
        })
        assert.same({{x=4, y=5, z=6}}, context.state.completions)
        assert.equals(1, context.state.sample_count)
    end)

    it('cancels on right release and Escape with no completion sample',
            function()
        local context = load_context()

        assert.is_true(context.consumer:handle({_MOUSE_R=true}))
        assert.same({context.causes.RIGHT_RELEASE},
            context.state.cancellations)
        assert.is_nil(context.state.sample_count)

        context = load_context()
        assert.is_true(context.consumer:handle({LEAVESCREEN=true}))
        assert.same({context.causes.ESCAPE}, context.state.cancellations)
        assert.is_nil(context.state.sample_count)
    end)

    it('delegates unowned input and forwards protected-failure notification',
            function()
        local context = load_context()
        local callbacks = context.consumer:callbacks()

        assert.is_false(callbacks.owns({D_PAUSE=true}))
        assert.is_false(callbacks.handle({D_PAUSE=true}))
        callbacks.on_failure('dispatch failed')
        assert.same({'dispatch failed'}, context.state.failures)
    end)
end)
