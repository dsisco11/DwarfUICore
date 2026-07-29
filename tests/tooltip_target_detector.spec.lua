local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local DETECTOR_PATH =
    'src/scripts_modinstalled/dwarfui/tooltip_target_detector.lua'

---Builds a detector harness with real generic pointer resolution.
---@param state table|nil
---@return table environment
local function load_environment(state)
    state = state or {}
    state.focus = state.focus or 'dwarfmode'
    state.overlay_state = state.overlay_state or {config={}, db={}}
    state.presented = state.presented or setmetatable({}, {__mode='k'})
    local default_nil = widget_harness.default_nil()
    local widgets = widget_harness.widgets(nil, default_nil)
    widgets.Widget.ATTRS{visible=true, active=true}

    ---@class tests.TooltipDetectorOverlay
    local OverlayWidget = widget_harness.defclass(nil, widgets.Panel)
    local overlay = {
        OverlayWidget=OverlayWidget,
        get_state=function() return state.overlay_state end,
        isOverlayEnabled=function(name)
            local config = state.overlay_state.config[name]
            return config and config.enabled or false
        end,
        normalize_list=function(value)
            return type(value) == 'table' and value or {value}
        end,
        simplify_viewscreen_name=function(value) return value end,
    }
    local dfhack = {
        gui={
            getDFViewscreen=function()
                return {focus=state.focus, widgets=state.native_root}
            end,
            getCurViewscreen=function()
                return state.current_viewscreen
            end,
            matchFocusString=function(focus, viewscreen)
                return focus == viewscreen.focus
            end,
        },
    }
    local _, pointer = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/pointer.lua', {
            globals={dfhack=dfhack},
        })
    local _, detector_module = module_loader.load(
        repo_root, DETECTOR_PATH, {
            globals={dfhack=dfhack},
            require_modules={['plugins.overlay']=overlay},
            reqscript={['dwarfui/pointer']=pointer},
        })

    ---Creates one detector over a caller-owned weak registration table.
    ---@param registrations table
    ---@param options table|nil
    ---@return dwarfui.TooltipTargetDetector
    local function new_detector(registrations, options)
        options = options or {}
        local detector_options = {
            registrations=registrations,
            resolve=options.resolve,
        }
        if not options.use_default_presentation then
            detector_options.is_non_overlay_root_presented = function(root)
                return state.presented[root] ~= false
            end
        end
        return detector_module.TooltipTargetDetector.new(detector_options)
    end

    return {
        module=detector_module,
        new_detector=new_detector,
        overlay=overlay,
        OverlayWidget=OverlayWidget,
        pointer=pointer,
        state=state,
        widgets=widgets,
    }
end

---Creates a weak registration table with monotonically increasing metadata.
---@return table registrations
---@return fun(widget: table)
local function registrations()
    local values = setmetatable({}, {__mode='k'})
    local sequence = 0

    ---Registers one widget with the next deterministic sequence.
    ---@param widget table
    local function register(widget)
        sequence = sequence + 1
        values[widget] = {sequence=sequence}
    end

    return values, register
end

---Lays out a root in a stable screen-cell rectangle.
---@param root table
local function layout(root)
    root:updateLayout(widget_harness.rect(0, 0, 40, 20))
end

---Creates one normalized pointer sample.
---@param sequence integer
---@param x integer|nil
---@param y integer|nil
---@return dwarfui.PointerSample
local function sample(sequence, x, y)
    return {
        sequence=sequence,
        x=x,
        y=y,
        coordinate_space='screen-cells',
    }
end

describe('DwarfUI tooltip target detector', function()
    it('loads and runs without GUI or tooltip presentation modules', function()
        local env = load_environment()
        local values = setmetatable({}, {__mode='k'})
        local detector = env.new_detector(values)

        assert.equals('table', type(env.module.TooltipTargetDetector))
        assert.equals('miss', detector:detect(sample(1, nil, nil)).kind)
    end)

    it('skips detached controls and stale parent links', function()
        local env = load_environment()
        local values, register = registrations()
        local detached = env.widgets.Label{
            frame={l=1, t=1, w=5, h=2},
        }
        register(detached)
        local detector = env.new_detector(values)

        assert.equals('miss', detector:detect(sample(1, 2, 2)).kind)

        local root = env.widgets.Panel{subviews={detached}}
        layout(root)
        root.subviews = {}
        assert.equals('miss', detector:detect(sample(2, 2, 2)).kind)
    end)

    it('skips invisible and inactive controls or ancestors', function()
        local env = load_environment()
        local values, register = registrations()
        local target = env.widgets.Label{
            frame={l=1, t=1, w=5, h=2},
        }
        local parent = env.widgets.Panel{subviews={target}}
        local root = env.widgets.Panel{subviews={parent}}
        layout(root)
        register(target)
        local detector = env.new_detector(values)

        parent.visible = false
        assert.equals('miss', detector:detect(sample(1, 2, 2)).kind)
        parent.visible = true
        target.active = false
        assert.equals('miss', detector:detect(sample(2, 2, 2)).kind)
        target.active = true
        root.active = false
        assert.equals('miss', detector:detect(sample(3, 2, 2)).kind)
    end)

    it('requires current layout bounds before resolving a root', function()
        local env = load_environment()
        local values, register = registrations()
        local target = env.widgets.Label{
            frame={l=1, t=1, w=5, h=2},
        }
        env.widgets.Panel{subviews={target}}
        register(target)
        local resolve_count = 0
        local detector = env.new_detector(values, {
            resolve=function()
                resolve_count = resolve_count + 1
                return {kind='miss'}
            end,
        })

        assert.equals('miss', detector:detect(sample(1, 2, 2)).kind)
        assert.equals(0, resolve_count)
    end)

    it('rejects disabled, stale, and viewscreen-mismatched overlays', function()
        local env = load_environment()
        local values, register = registrations()
        local target = env.widgets.Label{
            frame={l=1, t=1, w=5, h=2},
        }
        local root = env.OverlayWidget{
            name='detector-overlay',
            viewscreens='dwarfmode',
            subviews={target},
        }
        layout(root)
        register(target)
        local detector = env.new_detector(values)
        local state = env.state.overlay_state
        state.config[root.name] = {enabled=false}
        state.db[root.name] = {widget=root}

        assert.equals('miss', detector:detect(sample(1, 2, 2)).kind)

        state.config[root.name].enabled = true
        state.db[root.name] = {
            widget=env.OverlayWidget{name=root.name},
        }
        assert.equals('miss', detector:detect(sample(2, 2, 2)).kind)

        state.db[root.name] = {widget=root}
        env.state.focus = 'title'
        assert.equals('miss', detector:detect(sample(3, 2, 2)).kind)

        env.state.focus = 'dwarfmode'
        assert.is_equal(target,
            detector:detect(sample(4, 2, 2)).target)
    end)

    it('recognizes only the current native-mounted root by identity', function()
        local env = load_environment()
        local values, register = registrations()
        local current = env.widgets.Label{
            frame={l=1, t=1, w=5, h=2},
        }
        local covered = env.widgets.Label{
            frame={l=1, t=1, w=5, h=2},
        }
        local current_root = env.widgets.Panel{subviews={current}}
        local covered_root = env.widgets.Panel{subviews={covered}}
        layout(current_root)
        layout(covered_root)
        env.state.native_root = current_root
        register(current)
        register(covered)
        local detector = env.new_detector(values, {
            use_default_presentation=true,
        })

        local result = detector:detect(sample(1, 2, 2))
        assert.equals('target', result.kind)
        assert.is_equal(current, result.target)
        assert.is_equal(current_root, result.root)
    end)

    it('recognizes only the current displayed Lua-screen root by identity',
            function()
        local env = load_environment()
        local values, register = registrations()
        local current = env.widgets.Label{
            frame={l=1, t=1, w=5, h=2},
        }
        local covered = env.widgets.Label{
            frame={l=1, t=1, w=5, h=2},
        }
        local current_root = env.widgets.Panel{subviews={current}}
        local covered_root = env.widgets.Panel{subviews={covered}}
        local current_native = {}
        local covered_native = {}
        rawset(current_root, '_native', current_native)
        rawset(covered_root, '_native', covered_native)
        layout(current_root)
        layout(covered_root)
        env.state.current_viewscreen = current_native
        register(current)
        register(covered)
        local detector = env.new_detector(values, {
            use_default_presentation=true,
        })

        local result = detector:detect(sample(1, 2, 2))
        assert.equals('target', result.kind)
        assert.is_equal(current, result.target)
        assert.is_equal(current_root, result.root)

        env.state.current_viewscreen = covered_native
        result = detector:detect(sample(2, 2, 2))
        assert.equals('target', result.kind)
        assert.is_equal(covered, result.target)
        assert.is_equal(covered_root, result.root)
    end)

    it('preserves reverse-subview priority and target-local coordinates',
            function()
        local env = load_environment()
        local values, register = registrations()
        local behind = env.widgets.Label{
            frame={l=1, t=1, w=8, h=4},
        }
        local front = env.widgets.Label{
            frame={l=2, t=2, w=8, h=4},
        }
        local root = env.widgets.Panel{subviews={behind, front}}
        layout(root)
        register(front)
        register(behind)
        local result = env.new_detector(values):detect(sample(9, 4, 3))

        assert.equals('target', result.kind)
        assert.is_equal(front, result.target)
        assert.same({4, 3}, {result.pointer_x, result.pointer_y})
        assert.same({2, 1}, {result.local_x, result.local_y})
        assert.is_equal(root, result.root)
    end)

    it('reports blocked regions and ignores unregistered resolved controls',
            function()
        local env = load_environment()
        local values, register = registrations()
        local registered = env.widgets.Label{
            frame={l=0, t=0, w=20, h=10},
        }
        local modal = env.widgets.Window{
            frame={l=2, t=2, w=8, h=5},
            frame_inset=1,
            pointer_policy='block',
        }
        local root = env.widgets.Panel{subviews={registered, modal}}
        layout(root)
        register(registered)
        local detector = env.new_detector(values)

        local blocked = detector:detect(sample(1, 3, 3))
        assert.equals('blocked', blocked.kind)
        assert.is_nil(blocked.target)
        assert.is_equal(root, blocked.root)

        local unregistered = env.widgets.Label{
            frame={l=10, t=1, w=5, h=2},
        }
        root:addviews{unregistered}
        layout(root)
        local miss = detector:detect(sample(2, 11, 2))
        assert.equals('miss', miss.kind)
        assert.is_nil(miss.target)
        assert.is_nil(miss.root)
    end)

    it('uses registration sequence deterministically across overlapping roots',
            function()
        local env = load_environment()
        local values, register = registrations()
        local first = env.widgets.Label{
            frame={l=1, t=1, w=6, h=3},
        }
        local second = env.widgets.Label{
            frame={l=1, t=1, w=6, h=3},
        }
        local first_root = env.widgets.Panel{subviews={first}}
        local second_root = env.widgets.Panel{subviews={second}}
        layout(first_root)
        layout(second_root)
        register(first)
        register(second)
        local detector = env.new_detector(values)

        local result = detector:detect(sample(1, 2, 2))
        assert.equals('target', result.kind)
        assert.is_equal(second, result.target)
        assert.is_equal(second_root, result.root)
    end)

    it('uses registration sequence for deterministic blocked-root diagnostics',
            function()
        local env = load_environment()
        local values, register = registrations()

        ---Creates a root whose registered target is covered by a blocker.
        ---@return table root
        ---@return table target
        local function blocked_root()
            local target = env.widgets.Label{
                frame={l=0, t=0, w=20, h=10},
            }
            local blocker = env.widgets.Panel{
                frame={l=1, t=1, w=6, h=3},
                pointer_policy='block',
            }
            local root = env.widgets.Panel{subviews={target, blocker}}
            layout(root)
            return root, target
        end

        local first_root, first = blocked_root()
        local second_root, second = blocked_root()
        register(first)
        register(second)
        local result = env.new_detector(values):detect(sample(1, 2, 2))

        assert.equals('blocked', result.kind)
        assert.is_equal(second_root, result.root)
        assert.is_not.equal(first_root, result.root)
    end)

    it('resolves each eligible root once and never resolves no-pointer samples',
            function()
        local env = load_environment()
        local values, register = registrations()
        local first = env.widgets.Label{
            frame={l=1, t=1, w=4, h=2},
        }
        local second = env.widgets.Label{
            frame={l=6, t=1, w=4, h=2},
        }
        local root = env.widgets.Panel{subviews={first, second}}
        layout(root)
        register(first)
        register(second)
        local resolve_count = 0
        local detector = env.new_detector(values, {
            resolve=function(candidate, x, y)
                resolve_count = resolve_count + 1
                return env.pointer.PointerDispatcher.resolve(candidate, x, y)
            end,
        })

        assert.is_equal(first,
            detector:detect(sample(1, 2, 2)).target)
        assert.equals(1, resolve_count)

        local result = detector:detect(sample(2, nil, nil))
        assert.equals('miss', result.kind)
        assert.is_nil(result.pointer_x)
        assert.is_nil(result.pointer_y)
        assert.equals(1, resolve_count)
    end)

    it('returns one winner without callbacks or tooltip reads', function()
        local env = load_environment()
        local values, register = registrations()
        local callbacks = 0

        ---Creates a target that fails if detection reads presentation data.
        ---@return table target
        local function guarded_target()
            local target = env.widgets.Label{
                frame={l=1, t=1, w=6, h=3},
                on_pointer_enter=function() callbacks = callbacks + 1 end,
                on_pointer_update=function() callbacks = callbacks + 1 end,
                on_pointer_leave=function() callbacks = callbacks + 1 end,
            }
            local class = getmetatable(target).__index
            setmetatable(target, {
                __index=function(_, key)
                    if key == 'tooltip' then
                        error('detector read tooltip presentation data')
                    end
                    return class[key]
                end,
            })
            return target
        end

        local first = guarded_target()
        local second = guarded_target()
        local first_root = env.widgets.Panel{subviews={first}}
        local second_root = env.widgets.Panel{subviews={second}}
        layout(first_root)
        layout(second_root)
        register(first)
        register(second)
        local result = env.new_detector(values):detect(sample(1, 2, 2))

        assert.equals('target', result.kind)
        assert.is_equal(second, result.target)
        assert.equals(0, callbacks)
    end)

    it('keeps caller-owned registrations weak and presentation-independent',
            function()
        local env = load_environment()
        local values = setmetatable({}, {__mode='k'})
        local detector = env.new_detector(values)

        assert.is_equal(values, detector._registrations)
        assert.equals('k', getmetatable(values).__mode)
        assert.is_nil(rawget(detector, 'renderer'))
        assert.is_nil(rawget(detector, 'screen'))
    end)
end)
