-- Live characterization of the native-overlay and Lua-screen render seams.

local gui = require('gui')
local widgets = require('gui.widgets')
local overlay = require('plugins.overlay')

local PROBE_X = 2
local PROBE_Y = 2
local OVERLAY_SOURCE =
    'tests/tooltip/support/tooltip_render_seam_overlays.lua'
local PROBE_SENTINELS = {
    A=true,
    H=true,
    O=true,
    T=true,
    V=true,
    ['1']=true,
    ['2']=true,
}

---@class tests.TooltipRenderProbeChild: gui.Widget
local TooltipRenderProbeChild = defclass(nil, widgets.Widget)
TooltipRenderProbeChild.ATTRS{
    owner=DEFAULT_NIL,
    frame={l=0, t=0, w=1, h=1},
}

---Records child rendering and paints its sentinel.
---@param dc gui.Painter
function TooltipRenderProbeChild:onRenderBody(dc)
    table.insert(self.owner.render_trace, 'child')
    dc:seek(PROBE_X, PROBE_Y):char('C', {
        fg=COLOR_WHITE,
        bg=COLOR_BLACK,
    })
end

---@class tests.TooltipRenderProbeScreen: gui.ZScreen
local TooltipRenderProbeScreen = defclass(nil, gui.ZScreen)
TooltipRenderProbeScreen.ATTRS{
    focus_path='dwarfspec/tooltip-render-seam',
    initial_pause=false,
}

---Builds the child used to characterize complete screen composition.
function TooltipRenderProbeScreen:init()
    self.render_trace = {}
    self.idle_count = 0
    self.input_count = 0
    self.dismiss_count = 0
    self:addviews{TooltipRenderProbeChild{owner=self}}
end

---Records the parent-render boundary surrounding native overlays.
function TooltipRenderProbeScreen:renderParent()
    table.insert(self.render_trace, 'parent_before')
    TooltipRenderProbeScreen.super.renderParent(self)
    table.insert(self.render_trace, 'parent_after')
end

---Records frame rendering.
---@param dc gui.Painter
function TooltipRenderProbeScreen:onRenderFrame(dc)
    table.insert(self.render_trace, 'frame')
    dc:seek(PROBE_X, PROBE_Y):char('F', {
        fg=COLOR_WHITE,
        bg=COLOR_BLACK,
    })
end

---Records screen content rendering.
---@param dc gui.Painter
function TooltipRenderProbeScreen:onRenderBody(dc)
    table.insert(self.render_trace, 'content')
    dc:seek(PROBE_X, PROBE_Y):char('B', {
        fg=COLOR_WHITE,
        bg=COLOR_BLACK,
    })
end

---Preserves the class-specific render override and paints after composition.
---@return nil
function TooltipRenderProbeScreen:onRender()
    TooltipRenderProbeScreen.super.onRender(self)
    table.insert(self.render_trace, 'override')
    gui.Painter.new():seek(PROBE_X, PROBE_Y):char('O', {
        fg=COLOR_WHITE,
        bg=COLOR_MAGENTA,
    })
end

---Records normal logic cadence without changing superclass behavior.
function TooltipRenderProbeScreen:onIdle()
    self.idle_count = self.idle_count + 1
    if TooltipRenderProbeScreen.super.onIdle then
        TooltipRenderProbeScreen.super.onIdle(self)
    end
end

---Records one harmless routed input used by the characterization.
---@param keys table
---@return boolean
function TooltipRenderProbeScreen:onInput(keys)
    if keys.D_HAULING then
        self.input_count = self.input_count + 1
        return true
    end
    return TooltipRenderProbeScreen.super.onInput(self, keys)
end

---Records dismissal while preserving normal screen teardown.
function TooltipRenderProbeScreen:onDismiss()
    self.dismiss_count = self.dismiss_count + 1
    if TooltipRenderProbeScreen.super.onDismiss then
        TooltipRenderProbeScreen.super.onDismiss(self)
    end
end

---Returns the character currently painted at the probe cell.
---@return integer|nil
local function read_probe_character()
    local pen = dfhack.screen.readTile(PROBE_X, PROBE_Y)
    return pen and pen.ch or nil
end

---Paints one screen-global sentinel with an unclipped full-window painter.
---@param character string
local function paint_global(character)
    local backgrounds = {
        H=COLOR_GREEN,
        ['1']=COLOR_GREEN,
        ['2']=COLOR_CYAN,
        T=COLOR_YELLOW,
    }
    gui.Painter.new():seek(PROBE_X, PROBE_Y):char(character, {
        fg=COLOR_LIGHTGREEN,
        bg=assert(backgrounds[character],
            'missing probe background for ' .. character),
    })
end

---Returns the last real paint call for a probe sentinel.
---@param events table[]
---@return table|nil
local function last_paint_event(events)
    return events[#events]
end

---Installs a reversible observer around the real screen paint function.
---@param events table[]
---@return table
local function observe_probe_painting(events)
    local record = {
        predecessor=dfhack.screen.paintTile,
    }

    ---Records probe sentinels after forwarding the real paint operation.
    ---@param pen dfhack.pen
    ---@param x integer
    ---@param y integer
    ---@param character string|nil
    ---@param ... any
    ---@return ...
    record.installed = function(pen, x, y, character, ...)
        local results = table.pack(
            record.predecessor(pen, x, y, character, ...))
        if PROBE_SENTINELS[character] then
            table.insert(events, {
                character=character,
                pen=pen,
                x=x,
                y=y,
                graphics_mode=dfhack.screen.inGraphicsMode(),
            })
        end
        return table.unpack(results, 1, results.n)
    end
    dfhack.screen.paintTile = record.installed
    return record
end

---Finds one staged overlay entry by its local registration name.
---@param staged table
---@param local_name string
---@return table
local function find_staged_entry(staged, local_name)
    local suffix = '.' .. local_name
    for _, name in ipairs(staged.registered_names) do
        if name:sub(-#suffix) == suffix then
            return assert(overlay.get_state().db[name],
                'staged overlay entry is unavailable: ' .. name)
        end
    end
    error('staged overlay name is unavailable: ' .. local_name)
end

---Returns the current render count for one staged overlay.
---@param staged table
---@param local_name string
---@return integer
local function overlay_render_count(staged, local_name)
    local entry = find_staged_entry(staged, local_name)
    return entry.widget.render_count or 0
end

---Returns a stable array copy.
---@param values any[]
---@return any[]
local function copy_array(values)
    local result = {}
    for index, value in ipairs(values) do result[index] = value end
    return result
end

---Returns the first index of a value or nil.
---@param values any[]
---@param expected any
---@return integer|nil
local function index_of(values, expected)
    for index, value in ipairs(values) do
        if value == expected then return index end
    end
    return nil
end

---@class tests.OverlayRenderWrapperRecord
---@field owner table
---@field predecessor function
---@field installed function
---@field call_count integer
---@field append_enabled boolean
---@field calls table[]
---@field trace_sink table|nil
---@field paint_events table[]

---Installs one reversible wrapper around the exported native-overlay seam.
---@param staged table
---@param paint_events table[]
---@param records tests.OverlayRenderWrapperRecord[]
---@return tests.OverlayRenderWrapperRecord
local function wrap_overlay_render(staged, paint_events, records)
    local record = {
        owner=overlay,
        predecessor=assert(overlay.render_viewscreen_widgets),
        call_count=0,
        append_enabled=true,
        calls={},
        paint_events=paint_events,
    }

    ---Calls every normal overlay first, then paints the appended sentinel.
    ---@param ... any
    ---@return ...
    record.installed = function(...)
        local arguments = table.pack(...)
        local viewscreen_before =
            overlay_render_count(staged, 'viewscreen_probe')
        local all_before = overlay_render_count(staged, 'all_probe')
        local results = table.pack(record.predecessor(...))
        local call = {
            argument_count=arguments.n,
            arguments=arguments,
            result_count=results.n,
            results=results,
            viewscreen_before=viewscreen_before,
            viewscreen_after=
                overlay_render_count(staged, 'viewscreen_probe'),
            all_before=all_before,
            all_after=overlay_render_count(staged, 'all_probe'),
            predecessor_character=read_probe_character(),
            predecessor_paint=last_paint_event(paint_events),
            graphics_mode=dfhack.screen.inGraphicsMode(),
        }
        record.call_count = record.call_count + 1
        record.calls[record.call_count] = call
        if record.trace_sink then
            table.insert(record.trace_sink, 'overlay_append')
        end
        if record.append_enabled then paint_global('H') end
        return table.unpack(results, 1, results.n)
    end
    overlay.render_viewscreen_widgets = record.installed
    table.insert(records, record)
    return record
end

---@class tests.ScreenRenderWrapperRecord
---@field owner tests.TooltipRenderProbeScreen
---@field predecessor function
---@field original_raw function|nil
---@field installed function
---@field call_count integer
---@field eligible_count integer
---@field calls table[]
---@field paint_events table[]

---Wraps the effective onRender method on one displayed screen instance.
---@param screen tests.TooltipRenderProbeScreen
---@param character string
---@param paint_events table[]
---@param records tests.ScreenRenderWrapperRecord[]
---@return tests.ScreenRenderWrapperRecord
local function wrap_screen_render(screen, character, paint_events, records)
    local record = {
        owner=screen,
        predecessor=assert(screen.onRender),
        original_raw=rawget(screen, 'onRender'),
        call_count=0,
        eligible_count=0,
        calls={},
        paint_events=paint_events,
    }

    ---Calls the effective predecessor, then conditionally paints last.
    ---@param self tests.TooltipRenderProbeScreen
    ---@param ... any
    ---@return ...
    record.installed = function(self, ...)
        local arguments = table.pack(...)
        local results =
            table.pack(record.predecessor(self, ...))
        local eligible =
            dfhack.gui.getCurViewscreen(true) == self._native
        record.call_count = record.call_count + 1
        if eligible then record.eligible_count = record.eligible_count + 1 end
        record.calls[record.call_count] = {
            argument_count=arguments.n,
            result_count=results.n,
            eligible=eligible,
            predecessor_character=read_probe_character(),
            predecessor_paint=last_paint_event(paint_events),
        }
        table.insert(self.render_trace, 'screen_append')
        if eligible then paint_global(character) end
        return table.unpack(results, 1, results.n)
    end
    rawset(screen, 'onRender', record.installed)
    table.insert(records, record)
    return record
end

---Restores installed wrappers in reverse chain order when still outermost.
---@param overlay_records tests.OverlayRenderWrapperRecord[]
---@param screen_records tests.ScreenRenderWrapperRecord[]
local function restore_wrappers(overlay_records, screen_records)
    for index=#screen_records,1,-1 do
        local record = screen_records[index]
        if rawget(record.owner, 'onRender') == record.installed then
            rawset(record.owner, 'onRender', record.original_raw)
        end
    end
    for index=#overlay_records,1,-1 do
        local record = overlay_records[index]
        if record.owner.render_viewscreen_widgets == record.installed then
            record.owner.render_viewscreen_widgets = record.predecessor
        end
    end
end

describe('tooltip final render seams', function()
    local overlay_records
    local screen_records
    local manual_screens
    local paint_events
    local paint_observer
    local initial_pause

    before_each(function()
        overlay_records = {}
        screen_records = {}
        manual_screens = {}
        paint_events = {}
        paint_observer = observe_probe_painting(paint_events)
        initial_pause = nil
    end)

    after_each(function()
        restore_wrappers(overlay_records, screen_records)
        for index=#manual_screens,1,-1 do
            local screen = manual_screens[index]
            if screen._native then screen:dismiss() end
        end
        if paint_observer and
                dfhack.screen.paintTile == paint_observer.installed then
            dfhack.screen.paintTile = paint_observer.predecessor
        end
        if initial_pause ~= nil and ds.isGamePaused() ~= initial_pause then
            ds.input('D_PAUSE')
            ds.await('original pause state is restored', function()
                return ds.isGamePaused() == initial_pause
            end)
        end
    end)

    it('uses the exported function as the live native final-render seam',
            function()
        local native_subject = ds.mountNativeScreen()
        local native = assert(dfhack.gui.getDFViewscreen(true),
            'native DF viewscreen is unavailable')
        local staged = ds.stage_overlay_registration(
            OVERLAY_SOURCE, 'tooltip_render_native')
        initial_pause = ds.isGamePaused()
        if not initial_pause then
            ds.input('D_PAUSE')
            ds.await('native render probe pauses the game', function()
                return ds.isGamePaused()
            end)
        end

        local record =
            wrap_overlay_render(staged, paint_events, overlay_records)
        local exported_wrapper = overlay.render_viewscreen_widgets
        ds.redraw()

        assert.is_true(record.call_count > 0,
            'native C++ overlay interpose did not call the exported wrapper')
        local call = record.calls[record.call_count]
        assert.equals(2, call.argument_count)
        assert.equals('viewscreen_dwarfmodest', call.arguments[1])
        assert.is_equal(native, call.arguments[2])
        assert.equals(0, call.result_count)
        assert.is_true(call.graphics_mode,
            'configured live environment did not exercise graphics mode')
        assert.is_true(call.viewscreen_after > call.viewscreen_before)
        assert.is_true(call.all_after > call.all_before)
        assert.equals('A', call.predecessor_paint.character,
            'all-viewscreens overlay did not finish before the callback')
        assert.equals(PROBE_X, call.predecessor_paint.x)
        assert.equals(PROBE_Y, call.predecessor_paint.y)
        assert.equals('H', last_paint_event(paint_events).character,
            'appended painter was not final over native and overlay content')

        local pointer_x, pointer_y = ds.move_pointer(PROBE_X, PROBE_Y)
        assert.equals(PROBE_X, pointer_x)
        assert.equals(PROBE_Y, pointer_y)
        ds.redraw()
        local mouse_x, mouse_y = dfhack.screen.getMousePos()
        assert.equals(pointer_x, mouse_x)
        assert.equals(pointer_y, mouse_y)
        local pointer_paint = last_paint_event(paint_events)
        assert.equals('H', pointer_paint.character)
        assert.equals(pointer_x, pointer_paint.x)
        assert.equals(pointer_y, pointer_paint.y)
        assert.is_true(pointer_paint.graphics_mode)
        assert.equals(dfhack.screen.inGraphicsMode(),
            record.calls[record.call_count].graphics_mode)

        record.append_enabled = false
        ds.redraw()
        assert.equals('A', last_paint_event(paint_events).character,
            'paused redraw did not clear the appended painting immediately')

        overlay.rescan()
        assert.is_equal(exported_wrapper,
            overlay.render_viewscreen_widgets,
            'overlay rescan replaced the runtime render wrapper')
        record.append_enabled = true
        ds.redraw()
        assert.equals('H', last_paint_event(paint_events).character)

        -- End the first observation chain before replacing the module export;
        -- DwarfSpec owns its own reversible native render observer.
        overlay.render_viewscreen_widgets = record.predecessor
        assert.is_equal(native.widgets, native_subject:raw())
        if ds.isGamePaused() ~= initial_pause then
            ds.input('D_PAUSE')
            ds.await('original pause state is restored before reload',
                function()
                    return ds.isGamePaused() == initial_pause
                end)
        end
        initial_pause = nil
        ds.unmount()
        reload('plugins.overlay')
        assert.is_equal(overlay, require('plugins.overlay'),
            'overlay reload replaced the module table')
        assert.is_not_equal(exported_wrapper,
            overlay.render_viewscreen_widgets,
            'overlay reload unexpectedly retained the overwritten export')
        overlay.rescan()
        assert.is_function(overlay.render_viewscreen_widgets)
    end)

    it('looks up and completes the current screen instance method last',
            function()
        local staged = ds.stage_overlay_registration(
            OVERLAY_SOURCE, 'tooltip_render_screen')
        local overlay_record =
            wrap_overlay_render(staged, paint_events, overlay_records)

        local first_subject = ds.mount(TooltipRenderProbeScreen, {
            initial_pause=false,
        })
        local first = first_subject:raw()
        local first_parent = first._native.parent
        local first_focus = copy_array(first_subject:getFocusList())
        local first_wrapper =
            wrap_screen_render(first, '1', paint_events, screen_records)
        first.render_trace = {}
        overlay_record.trace_sink = first.render_trace
        ds.redraw()

        assert.is_true(first_wrapper.call_count > 0,
            'displayed screen did not call its assigned instance method')
        local first_call = first_wrapper.calls[first_wrapper.call_count]
        assert.equals(0, first_call.argument_count)
        assert.equals(0, first_call.result_count)
        assert.is_true(first_call.eligible)
        assert.equals('O', first_call.predecessor_paint.character,
            'class-specific onRender override did not complete first')
        assert.equals('1', last_paint_event(paint_events).character)
        assert.same({
            'parent_before',
            'overlay_append',
            'parent_after',
            'frame',
            'content',
            'child',
            'override',
            'screen_append',
        }, first.render_trace)
        assert.is_true(overlay_record.call_count > 0,
            'foreground ZScreen did not render after the native overlay hook')

        local replacement =
            wrap_screen_render(first, '2', paint_events, screen_records)
        first.render_trace = {}
        overlay_record.trace_sink = first.render_trace
        ds.redraw()
        assert.is_true(replacement.call_count > 0,
            'C++ screen path cached the prior onRender method')
        assert.equals('2', last_paint_event(paint_events).character,
            'replacement instance wrapper did not render last')

        assert.same(first_focus, first_subject:getFocusList())
        assert.is_equal(first_parent, first._native.parent)
        assert.is_true(first:isActive())
        assert.is_true(first:hasFocus())
        local idle_before = first.idle_count
        ds.wait_frames(1)
        assert.is_true(first.idle_count > idle_before,
            'instance wrapping interrupted screen logic cadence')
        ds.input('D_HAULING')
        assert.equals(1, first.input_count,
            'instance wrapping interrupted routed screen input')

        local first_calls_before_nested = first_wrapper.call_count
        local first_eligible_before_nested = first_wrapper.eligible_count
        local second = TooltipRenderProbeScreen{
            focus_path='dwarfspec/tooltip-render-seam-top',
            initial_pause=false,
        }
        second:show()
        table.insert(manual_screens, second)
        local second_parent = second._native.parent
        local second_focus =
            copy_array(first_subject:getFocusList())
        local second_wrapper =
            wrap_screen_render(second, 'T', paint_events, screen_records)
        second.render_trace = {}
        overlay_record.trace_sink = second.render_trace
        ds.redraw()

        assert.is_true(first_wrapper.call_count >
            first_calls_before_nested,
            'lower screen did not participate in parent rendering')
        assert.equals(first_eligible_before_nested,
            first_wrapper.eligible_count,
            'lower screen remained eligible while another screen was current')
        assert.is_true(second_wrapper.eligible_count > 0)
        assert.is_equal(second._native,
            dfhack.gui.getCurViewscreen(true))
        assert.equals('T', last_paint_event(paint_events).character)
        local overlay_index =
            assert(index_of(second.render_trace, 'overlay_append'))
        local frame_index = assert(index_of(second.render_trace, 'frame'))
        local override_index =
            assert(index_of(second.render_trace, 'override'))
        local append_index =
            assert(index_of(second.render_trace, 'screen_append'))
        assert.is_true(overlay_index < frame_index)
        assert.is_true(frame_index < override_index)
        assert.is_true(override_index < append_index)
        assert.same(second_focus, first_subject:getFocusList())
        assert.is_true(second:hasFocus())
        assert.is_equal(second_parent, second._native.parent)

        -- Restore the exact instance values before exercising dismissal.
        restore_wrappers(overlay_records, screen_records)
        assert.is_equal(first_wrapper.original_raw,
            rawget(first, 'onRender'))
        assert.is_equal(second_wrapper.original_raw,
            rawget(second, 'onRender'))
        assert.same(second_focus, first_subject:getFocusList())
        assert.is_equal(first_parent, first._native.parent)
        assert.is_equal(second_parent, second._native.parent)

        second:dismiss()
        ds.await('top render probe dismisses to its parent', function()
            return second._native == nil and
                dfhack.gui.getCurViewscreen(true) == first._native
        end)
        assert.equals(1, second.dismiss_count)
        assert.is_true(first:isActive())
        assert.same(first_focus, first_subject:getFocusList())
        first:dismiss()
        ds.await('parent render probe dismisses normally', function()
            return first._native == nil and
                dfhack.gui.getCurViewscreen(true) == first_parent
        end)
        assert.equals(1, first.dismiss_count)
    end)
end)
