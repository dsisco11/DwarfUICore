-- Focused live proof for tooltip rendering owned by foreground Lua screens.

local gui = require('gui')
local widgets = require('gui.widgets')

local LOWER_TOOLTIP = 'Lower screen tooltip'
local UPPER_TOOLTIP = 'Upper screen tooltip'

---@class tests.TooltipFinalRenderTarget: gui.widgets.Label
local TooltipFinalRenderTarget = defclass(nil, widgets.Label)
TooltipFinalRenderTarget.ATTRS{
    owner=DEFAULT_NIL,
}

---Records that the registered control completed its normal render.
---@param dc gui.Painter
function TooltipFinalRenderTarget:onRenderBody(dc)
    TooltipFinalRenderTarget.super.onRenderBody(self, dc)
    table.insert(self.owner.render_trace, 'target')
end

---@class tests.TooltipFinalRenderScreen: gui.ZScreen
local TooltipFinalRenderScreen = defclass(nil, gui.ZScreen)
TooltipFinalRenderScreen.ATTRS{
    focus_path='dwarfspec/tooltip-final-render',
    initial_pause=false,
    tooltip_text=LOWER_TOOLTIP,
    sentinel='X',
    target_frame={l=6, t=5, w=24, h=1},
}

---Builds and registers the screen's real tooltip-bearing control.
function TooltipFinalRenderScreen:init()
    self.render_trace = {}
    self.idle_count = 0
    self.input_count = 0
    self.dismiss_count = 0
    self.tooltip_target = TooltipFinalRenderTarget{
        view_id='tooltip_target',
        owner=self,
        frame=self.target_frame,
        text='Registered tooltip target',
        tooltip=self.tooltip_text,
    }
    self:addviews{self.tooltip_target}
    assert(reqscript('dwarfuicore/tooltip/api').register(
        self.tooltip_target))
end

---Records the parent composition boundary.
function TooltipFinalRenderScreen:renderParent()
    table.insert(self.render_trace, 'parent_before')
    TooltipFinalRenderScreen.super.renderParent(self)
    table.insert(self.render_trace, 'parent_after')
end

---Records completion of the screen frame.
---@param dc gui.Painter
function TooltipFinalRenderScreen:onRenderFrame(dc)
    table.insert(self.render_trace, 'frame')
    TooltipFinalRenderScreen.super.onRenderFrame(self, dc)
end

---Records completion of the screen body.
---@param dc gui.Painter
function TooltipFinalRenderScreen:onRenderBody(dc)
    table.insert(self.render_trace, 'body')
    TooltipFinalRenderScreen.super.onRenderBody(self, dc)
end

---Paints a conflicting sentinel after complete class-specific composition.
function TooltipFinalRenderScreen:onRender()
    TooltipFinalRenderScreen.super.onRender(self)
    table.insert(self.render_trace, 'override')
    if self.probe_x and self.probe_y then
        gui.Painter.new():seek(
            self.probe_x, self.probe_y):char(self.sentinel, {
                fg=COLOR_WHITE,
                bg=COLOR_MAGENTA,
            })
        table.insert(self.render_trace, 'sentinel')
    end
end

---Records normal screen logic cadence.
function TooltipFinalRenderScreen:onIdle()
    self.idle_count = self.idle_count + 1
    if TooltipFinalRenderScreen.super.onIdle then
        TooltipFinalRenderScreen.super.onIdle(self)
    end
end

---Records and consumes one harmless routed input.
---@param keys table
---@return boolean
function TooltipFinalRenderScreen:onInput(keys)
    if keys.D_HAULING then
        self.input_count = self.input_count + 1
        return true
    end
    return TooltipFinalRenderScreen.super.onInput(self, keys)
end

---Records ordinary screen dismissal.
function TooltipFinalRenderScreen:onDismiss()
    self.dismiss_count = self.dismiss_count + 1
    if TooltipFinalRenderScreen.super.onDismiss then
        TooltipFinalRenderScreen.super.onDismiss(self)
    end
end

---Copies an array without retaining its source table.
---@param values any[]
---@return any[]
local function copy_array(values)
    local result = {}
    for index, value in ipairs(values) do result[index] = value end
    return result
end

---Returns the first rendered text cell for one tooltip intent.
---@param intent table
---@return integer x
---@return integer y
local function tooltip_text_cell(intent)
    local screen_width, screen_height = dfhack.screen.getWindowSize()
    local content_width = math.max(1, math.min(60, screen_width - 2))
    local lines = reqscript('dwarfuicore/text').wrap_text(
        intent.text, content_width)
    local width = 2
    for _, line in ipairs(lines) do
        width = math.max(width, #line + 2)
    end
    local height = #lines + 2
    local left = math.max(0,
        math.min(intent.anchor_x + 2, screen_width - width))
    local top = math.max(0,
        math.min(intent.anchor_y + 1, screen_height - height))
    return left + 1, top + 1
end

---Returns the display character currently occupying one screen cell.
---@param x integer
---@param y integer
---@return string|nil
local function read_character(x, y)
    local pen = dfhack.screen.readTile(x, y)
    if not pen or pen.ch == nil then return nil end
    if type(pen.ch) == 'number' then return string.char(pen.ch) end
    return pen.ch
end

---Returns the first index of one trace entry.
---@param trace string[]
---@param expected string
---@return integer|nil
local function index_of(trace, expected)
    for index, value in ipairs(trace) do
        if value == expected then return index end
    end
    return nil
end

---Moves onto a registered screen control and awaits its intent.
---@param target gui.View
---@param expected_text string
---@return table state
local function select_target(target, expected_text)
    local body = assert(target.frame_body,
        'registered screen target has no rendered body')
    local x = math.floor((body.x1 + body.x2) / 2)
    local y = math.floor((body.y1 + body.y2) / 2)
    ds.move_pointer(x, y)
    ds.redraw()
    ds.await('registered foreground target publishes intent', function()
        local state = ds.tooltip_state()
        return state.target == target and state.intent and
            state.intent.text == expected_text
    end)
    return ds.tooltip_state()
end

---Asserts one coherent selected screen-render generation.
---@param state table
---@param minimum_rendered_revision integer
---@param expected_hook_count integer
local function assert_screen_render_diagnostics(
        state, minimum_rendered_revision, expected_hook_count)
    local transport =
        reqscript('dwarfuicore/tooltip/render_hook').TooltipRenderTransport
    assert.is_true(state.presenter.active)
    assert.is_true(state.presenter.supported_surface)
    assert.equals(transport.SCREEN,
        state.presenter.selected_transport)
    assert.equals(state.intent.revision,
        state.presenter.current_intent_revision)
    assert.is_true(state.presenter.last_rendered_revision >=
        minimum_rendered_revision)
    assert.is_true(state.presenter.last_rendered_revision <=
        state.intent.revision)
    assert.is_true(state.render_hook.presenter_installed)
    assert.equals(state.presenter.generation,
        state.render_hook.generation)
    assert.equals(transport.SCREEN,
        state.render_hook.selected_transport)
    assert.equals(state.intent.revision,
        state.render_hook.current_intent_revision)
    assert.equals(state.presenter.last_rendered_revision,
        state.render_hook.last_rendered_revision)
    assert.equals(transport.SCREEN,
        state.render_hook.last_transport)
    assert.equals(expected_hook_count,
        state.render_hook.screen_hook_count)
    local selected_count = 0
    for _, screen in ipairs(state.render_hook.screens) do
        assert.is_true(screen.installed)
        assert.is_true(screen.outermost)
        if screen.selected then selected_count = selected_count + 1 end
    end
    assert.equals(1, selected_count)
end

---Captures screen ownership state before tooltip presentation.
---@param subject dwarfspec.Subject
---@param screen tests.TooltipFinalRenderScreen
---@return table
local function capture_environment(subject, screen)
    return {
        focus=copy_array(subject:getFocusList()),
        current_viewscreen=dfhack.gui.getCurViewscreen(true),
        native_viewscreen=dfhack.gui.getDFViewscreen(true),
        parent=screen._native.parent,
        paused=ds.isGamePaused(),
        subview_count=#screen.subviews,
    }
end

---Asserts tooltip activity did not change screen ownership state.
---@param expected table
---@param subject dwarfspec.Subject
---@param screen tests.TooltipFinalRenderScreen
---@param label string
local function assert_environment(expected, subject, screen, label)
    assert.same(expected.focus, subject:getFocusList(),
        label .. ' changed focus strings')
    assert.is_equal(expected.current_viewscreen,
        dfhack.gui.getCurViewscreen(true),
        label .. ' changed the current viewscreen')
    assert.is_equal(expected.native_viewscreen,
        dfhack.gui.getDFViewscreen(true),
        label .. ' changed the native viewscreen')
    assert.is_equal(expected.parent, screen._native.parent,
        label .. ' changed the screen parent')
    assert.equals(expected.paused, ds.isGamePaused(),
        label .. ' changed pause state')
    assert.equals(expected.subview_count, #screen.subviews,
        label .. ' changed the screen subviews')
    assert.is_true(screen:isActive(),
        label .. ' changed active state')
    assert.is_true(screen:hasFocus(),
        label .. ' changed focus ownership')
end

describe('foreground Lua-screen tooltip final rendering', function()
    it('renders after class overrides and transfers only to the top screen',
            function()
        local subject
        local lower
        local upper
        local lower_target
        local upper_target
        local lower_original_raw
        local upper_original_raw
        local unmounted = false

        local ok, failure = xpcall(function()
            subject = ds.mount(TooltipFinalRenderScreen, {
                tooltip_text=LOWER_TOOLTIP,
                sentinel='X',
            })
            lower = subject:raw()
            lower_target = lower.tooltip_target
            lower_original_raw = rawget(lower, 'onRender')
            local lower_environment =
                capture_environment(subject, lower)

            local state = select_target(lower_target, LOWER_TOOLTIP)
            local text_x, text_y = tooltip_text_cell(state.intent)
            lower.probe_x, lower.probe_y = text_x, text_y
            lower.render_trace = {}
            local minimum_rendered_revision = state.intent.revision
            local render_count_before = state.presenter.render_count
            ds.redraw()
            state = ds.tooltip_state()

            assert.equals(render_count_before + 1,
                state.presenter.render_count)
            assert.equals('L', read_character(text_x, text_y),
                'lower tooltip did not paint after its class override')
            local parent_after =
                assert(index_of(lower.render_trace, 'parent_after'))
            local frame =
                assert(index_of(lower.render_trace, 'frame'))
            local body =
                assert(index_of(lower.render_trace, 'body'))
            local target =
                assert(index_of(lower.render_trace, 'target'))
            local override =
                assert(index_of(lower.render_trace, 'override'))
            local sentinel =
                assert(index_of(lower.render_trace, 'sentinel'))
            assert.is_true(parent_after < frame)
            assert.is_true(frame < body)
            assert.is_true(body < target)
            assert.is_true(target < override)
            assert.is_true(override < sentinel)
            assert.is_not_equal(lower_original_raw,
                rawget(lower, 'onRender'))
            assert_screen_render_diagnostics(
                state, minimum_rendered_revision, 1)
            assert_environment(lower_environment, subject, lower,
                'lower tooltip rendering')

            local idle_before = lower.idle_count
            ds.wait_frames(1)
            assert.is_true(lower.idle_count > idle_before,
                'screen hook interrupted logic cadence')
            ds.input('D_HAULING')
            assert.equals(1, lower.input_count,
                'screen hook interrupted input delivery')
            assert_environment(lower_environment, subject, lower,
                'lower tooltip input and logic')

            upper = TooltipFinalRenderScreen{
                focus_path='dwarfspec/tooltip-final-render-top',
                tooltip_text=UPPER_TOOLTIP,
                sentinel='Y',
                target_frame={l=40, t=12, w=24, h=1},
            }
            upper_target = upper.tooltip_target
            upper_original_raw = rawget(upper, 'onRender')
            upper:show()
            local upper_environment =
                capture_environment(subject, upper)
            local renders_before_cover =
                ds.tooltip_state().presenter.render_count
            lower.render_trace = {}
            ds.redraw()
            state = ds.tooltip_state()
            assert.equals(renders_before_cover,
                state.presenter.render_count,
                'covered lower screen remained eligible to present')
            assert.is_not_nil(rawget(lower, 'onRender'),
                'lower screen hook was unexpectedly removed')

            state = select_target(upper_target, UPPER_TOOLTIP)
            text_x, text_y = tooltip_text_cell(state.intent)
            lower.probe_x, lower.probe_y = text_x, text_y
            upper.probe_x, upper.probe_y = text_x, text_y
            lower.render_trace = {}
            upper.render_trace = {}
            minimum_rendered_revision = state.intent.revision
            render_count_before = state.presenter.render_count
            ds.redraw()
            state = ds.tooltip_state()

            assert.equals(render_count_before + 1,
                state.presenter.render_count,
                'nested screens painted the tooltip more than once')
            assert.equals('U', read_character(text_x, text_y),
                'upper tooltip did not paint after its class override')
            override =
                assert(index_of(upper.render_trace, 'override'))
            sentinel =
                assert(index_of(upper.render_trace, 'sentinel'))
            assert.is_true(override < sentinel)
            assert_screen_render_diagnostics(
                state, minimum_rendered_revision, 2)
            assert_environment(upper_environment, subject, upper,
                'upper tooltip rendering')

            ds.input('D_HAULING')
            assert.equals(1, upper.input_count,
                'upper screen input delivery changed')
            local upper_idle_before = upper.idle_count
            ds.wait_frames(1)
            assert.is_true(upper.idle_count > upper_idle_before,
                'upper screen logic cadence changed')
            assert_environment(upper_environment, subject, upper,
                'upper tooltip input and logic')

            local wrapped_upper = rawget(upper, 'onRender')
            local module_generation_before =
                state.poller_module_generation
            local presenter_generation_before =
                state.presenter.generation
            local hook_generation_before =
                state.render_hook.generation
            dfhack.run_command('DwarfUICore', 'reload')
            ds.await('foreground tooltip recovers after reload', function()
                local current = ds.tooltip_state()
                return current.target == upper_target and
                    current.intent and
                    current.intent.text == UPPER_TOOLTIP and
                    current.poller_module_generation ==
                        module_generation_before + 1 and
                    current.presenter.generation ==
                        presenter_generation_before + 1 and
                    current.render_hook.generation ==
                        hook_generation_before + 1
            end)
            state = ds.tooltip_state()
            assert.is_equal(wrapped_upper,
                rawget(upper, 'onRender'),
                'reload replaced instead of adopting the existing trampoline')
            text_x, text_y = tooltip_text_cell(state.intent)
            upper.probe_x, upper.probe_y = text_x, text_y
            upper.render_trace = {}
            minimum_rendered_revision = state.intent.revision
            render_count_before = state.presenter.render_count
            ds.redraw()
            state = ds.tooltip_state()
            assert.equals(render_count_before + 1,
                state.presenter.render_count,
                'reload produced duplicate screen tooltip painting')
            assert.equals('U', read_character(text_x, text_y))
            assert_screen_render_diagnostics(
                state, minimum_rendered_revision, 2)
            assert_environment(upper_environment, subject, upper,
                'foreground tooltip reload')

            ds.move_pointer(0, 0)
            ds.await('foreground tooltip clears before dismissal', function()
                local current = ds.tooltip_state()
                return current.target == nil and current.intent == nil
            end)
            assert.is_true(reqscript('dwarfuicore/tooltip/api').unregister(
                upper_target))
            assert.is_true(reqscript('dwarfuicore/tooltip/api').unregister(
                lower_target))

            local lower_native = lower._native
            upper:dismiss()
            ds.await('upper tooltip screen dismisses normally', function()
                return upper._native == nil and
                    dfhack.gui.getCurViewscreen(true) == lower_native
            end)
            assert.equals(1, upper.dismiss_count)
            local lower_parent = lower._native.parent
            lower:dismiss()
            ds.await('lower tooltip screen dismisses normally', function()
                return lower._native == nil and
                    dfhack.gui.getCurViewscreen(true) == lower_parent
            end)
            assert.equals(1, lower.dismiss_count)

            reqscript('dwarfuicore/tooltip/render_hook').manager:shutdown()
            assert.is_equal(upper_original_raw,
                rawget(upper, 'onRender'))
            assert.is_equal(lower_original_raw,
                rawget(lower, 'onRender'))
            ds.unmount()
            unmounted = true
            local root_ok = pcall(ds.root)
            assert.is_false(root_ok,
                'DwarfSpec retained a current mount after explicit unmount')
            subject = nil
            lower, upper = nil, nil
            lower_target, upper_target = nil, nil
            local final = ds.tooltip_state()
            assert.equals(0, final.render_hook.screen_hook_count)
            assert.is_false(final.render_hook.selected_owner_present)
        end, debug.traceback)

        local cleanup_failures = {}

        ---Runs one cleanup action without suppressing later restoration.
        ---@param label string
        ---@param callback function
        local function cleanup_step(label, callback)
            local step_ok, step_failure =
                xpcall(callback, debug.traceback)
            if not step_ok then
                table.insert(cleanup_failures,
                    label .. ': ' .. tostring(step_failure))
            end
        end

        cleanup_step('clear tooltip registrations', function()
            local tooltip = reqscript('dwarfuicore/tooltip/api')
            if upper_target then tooltip.unregister(upper_target) end
            if lower_target then tooltip.unregister(lower_target) end
        end)
        cleanup_step('retire screen render hooks', function()
            reqscript('dwarfuicore/tooltip/render_hook').manager:shutdown()
        end)
        cleanup_step('dismiss upper screen', function()
            if upper and upper._native then upper:dismiss() end
        end)
        cleanup_step('dismiss lower screen', function()
            if lower and lower._native then lower:dismiss() end
        end)
        cleanup_step('release mounted subject', function()
            if not unmounted and subject then
                ds.unmount()
                unmounted = true
            end
        end)
        cleanup_step('restore current DwarfUICore runtime', function()
            dfhack.run_command('DwarfUICore', 'reload')
        end)
        if #cleanup_failures > 0 then
            local cleanup_message =
                'cleanup failures: ' .. table.concat(cleanup_failures, '; ')
            failure = failure and
                (tostring(failure) .. '\n' .. cleanup_message) or
                cleanup_message
            ok = false
        end
        assert.is_true(ok, failure)
    end)

end)
