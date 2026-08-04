local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local INDICATOR_PATH =
    'src/scripts_modinstalled/dwarfuicore/user_prompt/indicator.lua'

---Loads the isolated indicator adapter.
---@return table indicator
local function load_indicator()
    local _, indicator = module_loader.load(repo_root, INDICATOR_PATH, {
        globals={df={global={game={main_interface={
            recenter_indicator_m={x=-30000, y=-30000, z=-30000},
        }}}}},
    })
    return indicator
end

---Creates an observable native port and unrelated map-view state.
---@param initial table
---@return table port
---@return table state
local function port(initial)
    local state = {
        native={x=initial.x, y=initial.y, z=initial.z},
        reads=0,
        writes={},
        view={window_x=10, window_y=20, window_z=3,
            follow_unit=42, follow_item=77},
    }
    return {
        read=function()
            state.reads = state.reads + 1
            return state.native
        end,
        write=function(value)
            state.native = {x=value.x, y=value.y, z=value.z}
            table.insert(state.writes,
                {x=value.x, y=value.y, z=value.z})
        end,
    }, state
end

describe('UserPrompt native indicator adapter', function()
    it('prepares a detached snapshot before non-failing ownership commit',
            function()
        local indicator = load_indicator()
        local native_port, state = port({x=4, y=5, z=6})
        local adapter = indicator.NativeIndicatorAdapter.new(native_port)

        adapter:prepare()
        assert.equals(1, state.reads)
        assert.equals(0, #state.writes)
        assert.is_false(adapter:get_diagnostics().acquired)
        state.native = {x=7, y=8, z=9}
        adapter:acquire()

        assert.equals(1, state.reads)
        assert.is_true(adapter:get_diagnostics().owns)
        assert.same({x=4, y=5, z=6},
            adapter:get_diagnostics().snapshot)
    end)

    it('snapshots detached state, follows hover motion, and hides off-map',
            function()
        local indicator = load_indicator()
        local native_port, state = port({x=4, y=5, z=6})
        local adapter = indicator.NativeIndicatorAdapter.new(native_port)
        local view_before = {
            window_x=state.view.window_x, window_y=state.view.window_y,
            window_z=state.view.window_z, follow_unit=state.view.follow_unit,
            follow_item=state.view.follow_item,
        }

        adapter:acquire()
        state.native.x = 4
        assert.is_true(adapter:update({x=10, y=20, z=3}))
        assert.is_true(adapter:update({x=11, y=21, z=4}))
        assert.is_true(adapter:update(nil))

        assert.same({x=-30000, y=-30000, z=-30000}, state.native)
        assert.same(view_before, state.view)
        local diagnostics = adapter:get_diagnostics()
        assert.same({x=4, y=5, z=6}, diagnostics.snapshot)
        assert.same({x=-30000, y=-30000, z=-30000},
            diagnostics.last_written)
        diagnostics.snapshot.x = 999
        assert.equals(4, adapter:get_diagnostics().snapshot.x)
    end)

    it('restores the pre-prompt snapshot when it still owns native state',
            function()
        local indicator = load_indicator()
        local native_port, state = port({x=7, y=8, z=9})
        local adapter = indicator.NativeIndicatorAdapter.new(native_port)

        adapter:update({x=1, y=2, z=3})
        assert.is_true(adapter:release())

        assert.same({x=7, y=8, z=9}, state.native)
        assert.equals(2, #state.writes)
        assert.is_false(adapter:get_diagnostics().owns)
    end)

    it('detects takeover before a later hover write and never restores',
            function()
        local indicator = load_indicator()
        local native_port, state = port({x=7, y=8, z=9})
        local adapter = indicator.NativeIndicatorAdapter.new(native_port)
        adapter:update({x=1, y=2, z=3})
        state.native = {x=90, y=91, z=92}

        assert.is_false(adapter:update({x=4, y=5, z=6}))
        assert.is_false(adapter:release())
        assert.same({x=90, y=91, z=92}, state.native)
        assert.equals(1, #state.writes)
        assert.is_true(adapter:get_diagnostics().external_takeover)
    end)

    it('detects takeover before the later inactive write and never restores',
            function()
        local indicator = load_indicator()
        local native_port, state = port({x=7, y=8, z=9})
        local adapter = indicator.NativeIndicatorAdapter.new(native_port)
        adapter:update({x=1, y=2, z=3})
        state.native = {x=40, y=41, z=42}

        assert.is_false(adapter:update(nil))
        assert.is_false(adapter:release())
        assert.same({x=40, y=41, z=42}, state.native)
        assert.equals(1, #state.writes)
    end)

    it('detects takeover immediately before restoration', function()
        local indicator = load_indicator()
        local native_port, state = port({x=7, y=8, z=9})
        local adapter = indicator.NativeIndicatorAdapter.new(native_port)
        adapter:update({x=1, y=2, z=3})
        state.native = {x=70, y=71, z=72}

        assert.is_false(adapter:release())
        assert.same({x=70, y=71, z=72}, state.native)
        assert.equals(1, #state.writes)
        assert.is_true(adapter:get_diagnostics().external_takeover)
    end)

    it('models every termination invocation as one ownership-safe release',
            function()
        local indicator = load_indicator()
        for _, cause in ipairs({
                'left_release', 'right_release', 'escape', 'api_cancel',
                'namespace_clear', 'input_root_loss',
                'presentation_root_loss', 'world_unload',
                'internal_failure', 'core_reload',
            }) do
            local native_port, state = port({x=5, y=6, z=7})
            local adapter = indicator.NativeIndicatorAdapter.new(native_port)
            adapter:update({x=1, y=2, z=3})
            assert.is_true(adapter:release(), cause)
            assert.same({x=5, y=6, z=7}, state.native, cause)
            assert.is_false(adapter:release(), cause)
        end
    end)

    it('irrevocably relinquishes ownership when terminal restore fails',
            function()
        local indicator = load_indicator()
        for _, failure_point in ipairs{'read', 'write'} do
            local native_port, state = port({x=5, y=6, z=7})
            local adapter = indicator.NativeIndicatorAdapter.new(native_port)
            adapter:update({x=1, y=2, z=3})
            local original_read = native_port.read
            local original_write = native_port.write
            if failure_point == 'read' then
                native_port.read = function() error('release read failed') end
            else
                native_port.write = function(value)
                    if value.x == 5 then error('restore write failed') end
                    return original_write(value)
                end
            end

            local ok, failure = pcall(function() adapter:release() end)
            assert.is_false(ok)
            assert.is_truthy(tostring(failure):find(
                failure_point == 'read' and 'release read failed' or
                    'restore write failed', 1, true))
            local diagnostics = adapter:get_diagnostics()
            assert.is_false(diagnostics.acquired, failure_point)
            assert.is_false(diagnostics.owns, failure_point)
            assert.is_false(diagnostics.prepared, failure_point)
            native_port.read = original_read
            native_port.write = original_write
            assert.is_false(adapter:release(), failure_point)
            assert.same({x=1, y=2, z=3}, state.native, failure_point)
        end
    end)

    it('contains no map reveal, overlay render, or completion sample path',
            function()
        local file = assert(io.open(repo_root .. '/' .. INDICATOR_PATH, 'rb'))
        local source = file:read('*a')
        file:close()

        assert.is_nil(source:find('revealInDwarfmodeMap', 1, true))
        assert.is_nil(source:find('renderMapOverlay', 1, true))
        assert.is_nil(source:find('on_select', 1, true))
        assert.is_nil(source:find('complete', 1, true))
    end)
end)
