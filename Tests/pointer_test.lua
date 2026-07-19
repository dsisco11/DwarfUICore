local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local pointer_path = 'src/scripts_modinstalled/dwarfui/pointer.lua'
local extensions_path =
    'src/scripts_modinstalled/dwarfui/widget_extensions.lua'

local function load_pointer(mouse_pos)
    local _, pointer = module_loader.load(repo_root, pointer_path, {
        globals={
            dfhack={
                screen={
                    getMousePos=mouse_pos or function() return nil, nil end,
                },
            },
        },
    })
    return pointer
end

local function load_extensions(widgets, default_nil)
    local _, extensions = module_loader.load(repo_root, extensions_path, {
        globals={DEFAULT_NIL=default_nil},
        require_modules={['gui.widgets']=widgets},
    })
    return extensions
end

local function view(policy, x, y, width, height, children)
    local result = {
        pointer_policy=policy,
        visible=true,
        active=true,
        subviews=children or {},
    }
    return widget_harness.set_frame(result, x, y, width, height)
end

local function sample_target(pointer, root, x, y)
    local context = pointer.PointerContext.new(root)
    local result = pointer.PointerDispatcher.sample(context, x, y)
    return context, result
end

describe('DwarfUI pointer dispatcher', function()
    it('owns state per supplied root and starts with a miss', function()
        local pointer = load_pointer()
        local root = view('target', 0, 0, 10, 10)
        local context = pointer.PointerContext.new(root)

        assert.is.equal(root, context.root)
        assert.is_nil(context.target)
        assert.equals('miss', context.result.kind)
    end)

    it('returns explicit results and resolves overlaps in reverse render order', function()
        local pointer = load_pointer()
        local lower = view('target', 2, 2, 5, 5)
        local upper = view('target', 3, 3, 5, 5)
        local panel = view('pass', 0, 0, 12, 12, {lower, upper})
        local root = view('target', 0, 0, 20, 20, {panel})

        local result = pointer.PointerDispatcher.resolve(root, 4, 4)
        assert.equals('target', result.kind)
        assert.is.equal(upper, result.target)
        assert.same({1, 1}, {result.x, result.y})

        result = pointer.PointerDispatcher.resolve(root, 1, 1)
        assert.same({kind='miss'}, result)
        panel.pointer_policy = 'block'
        result = pointer.PointerDispatcher.resolve(root, 1, 1)
        assert.equals('blocked', result.kind)
        assert.is.equal(panel, result.blocker)
    end)

    it('treats the root as a boundary instead of selecting it', function()
        local pointer = load_pointer()
        local root = view('target', 0, 0, 10, 10)

        assert.equals('miss',
            pointer.PointerDispatcher.resolve(root, 2, 2).kind)
    end)

    it('keeps terminal composites above implementation children', function()
        local pointer = load_pointer()
        local implementation = view('target', 2, 2, 6, 2)
        local control = view('target', 1, 1, 8, 4, {implementation})
        local root = view('target', 0, 0, 12, 8, {control})
        local _, result = sample_target(pointer, root, 3, 3)

        assert.equals('target', result.kind)
        assert.is.equal(control, result.target)
        assert.same({2, 2}, {result.x, result.y})
    end)

    it('keeps pass containers transparent and none subtrees excluded', function()
        local pointer = load_pointer()
        local behind = view('target', 0, 0, 20, 20)
        local empty_panel = view('pass', 1, 1, 8, 8)
        local excluded_child = view('target', 10, 1, 5, 5)
        local excluded = view('none', 10, 1, 5, 5, {excluded_child})
        local root = view(
            'target', 0, 0, 20, 20, {behind, empty_panel, excluded})

        local result = pointer.PointerDispatcher.resolve(root, 2, 2)
        assert.is.equal(behind, result.target)
        result = pointer.PointerDispatcher.resolve(root, 11, 2)
        assert.is.equal(behind, result.target)
    end)

    it('respects clipped bodies for targets and the root', function()
        local pointer = load_pointer()
        local behind = view('target', 0, 0, 20, 20)
        local clipped = view('target', 1, 1, 8, 8)
        clipped.frame_body = widget_harness.rect(1, 1, 8, 8,
            {x1=1, y1=1, x2=4, y2=8})
        local root = view('target', 0, 0, 20, 20, {behind, clipped})

        assert.is.equal(clipped,
            pointer.PointerDispatcher.resolve(root, 3, 2).target)
        assert.is.equal(behind,
            pointer.PointerDispatcher.resolve(root, 6, 2).target)

        root.frame_body = widget_harness.rect(0, 0, 20, 20,
            {x1=0, y1=0, x2=5, y2=19})
        assert.equals('miss',
            pointer.PointerDispatcher.resolve(root, 6, 2).kind)
    end)

    it('uses full window frames for blocking while retaining child targets', function()
        local pointer = load_pointer()
        local behind = view('target', 0, 0, 20, 20)
        local child = view('target', 4, 4, 3, 3)
        local window = view('block', 2, 2, 10, 10, {child})
        window.frame_body = widget_harness.rect(3, 3, 8, 8)
        local root = view('target', 0, 0, 20, 20, {behind, window})

        local result = pointer.PointerDispatcher.resolve(root, 4, 4)
        assert.is.equal(child, result.target)
        result = pointer.PointerDispatcher.resolve(root, 2, 2)
        assert.equals('blocked', result.kind)
        assert.is.equal(window, result.blocker)
        result = pointer.PointerDispatcher.resolve(root, 15, 15)
        assert.is.equal(behind, result.target)
    end)

    it('lets nested modal windows block only their own frames', function()
        local pointer = load_pointer()
        local outer = view('block', 1, 1, 16, 16)
        local inner = view('block', 5, 5, 6, 6)
        outer.subviews = {inner}
        local root = view('target', 0, 0, 20, 20, {outer})

        local result = pointer.PointerDispatcher.resolve(root, 6, 6)
        assert.equals('blocked', result.kind)
        assert.is.equal(inner, result.blocker)
        result = pointer.PointerDispatcher.resolve(root, 3, 3)
        assert.equals('blocked', result.kind)
        assert.is.equal(outer, result.blocker)
        result = pointer.PointerDispatcher.resolve(root, 18, 18)
        assert.equals('miss', result.kind)
    end)

    it('evaluates visible and active state through the ancestor chain', function()
        local pointer = load_pointer()
        local target = view('target', 2, 2, 4, 4)
        local parent = view('pass', 1, 1, 8, 8, {target})
        local root = view('target', 0, 0, 12, 12, {parent})
        local visible = true
        local active = true
        local evaluations = 0
        parent.visible = function()
            evaluations = evaluations + 1
            return visible
        end
        target.active = function()
            evaluations = evaluations + 1
            return active
        end

        assert.is.equal(target,
            pointer.PointerDispatcher.resolve(root, 3, 3).target)
        assert.equals(2, evaluations)
        visible = false
        assert.equals('miss',
            pointer.PointerDispatcher.resolve(root, 3, 3).kind)
        visible = true
        active = false
        assert.equals('miss',
            pointer.PointerDispatcher.resolve(root, 3, 3).kind)
    end)

    it('emits ordered transitions and terminal-local callback coordinates', function()
        local pointer = load_pointer()
        local events = {}
        local first = view('target', 1, 1, 4, 4)
        local second = view('target', 6, 1, 3, 3)
        first.on_pointer_enter = function(target, x, y)
            table.insert(events, {'enter', target, x, y})
        end
        first.on_pointer_update = function(target, x, y)
            table.insert(events, {'update', target, x, y})
        end
        first.on_pointer_leave = function(target)
            table.insert(events, {'leave', target})
        end
        second.on_pointer_enter = first.on_pointer_enter
        second.on_pointer_update = first.on_pointer_update
        second.on_pointer_leave = first.on_pointer_leave
        local root = view('target', 0, 0, 12, 8, {first, second})
        local context = pointer.PointerContext.new(root)

        pointer.PointerDispatcher.sample(context, 2, 3)
        pointer.PointerDispatcher.sample(context, 3, 3)
        pointer.PointerDispatcher.sample(context, 7, 2)
        pointer.PointerDispatcher.sample(context, 11, 7)

        assert.same({
            {'enter', first, 1, 2},
            {'update', first, 1, 2},
            {'update', first, 2, 2},
            {'leave', first},
            {'enter', second, 1, 1},
            {'update', second, 1, 1},
            {'leave', second},
        }, events)
        assert.is_nil(context.target)
        assert.equals('miss', context.result.kind)
    end)

    it('samples the mouse once and clears on missing coordinates', function()
        local samples = 0
        local mouse_x, mouse_y = 2, 2
        local pointer = load_pointer(function()
            samples = samples + 1
            return mouse_x, mouse_y
        end)
        local target = view('target', 1, 1, 4, 4)
        local root = view('target', 0, 0, 8, 8, {target})
        local context = pointer.PointerContext.new(root)

        pointer.PointerDispatcher.sample(context, 2, 2)
        assert.equals(0, samples)
        assert.is.equal(target, context.target)
        pointer.PointerDispatcher.sample(context)
        assert.equals(1, samples)
        assert.is.equal(target, context.target)
        mouse_x, mouse_y = nil, nil
        local result = pointer.PointerDispatcher.sample(context)
        assert.equals(2, samples)
        assert.equals('miss', result.kind)
        assert.is_nil(context.target)
    end)

    it('clears stale targets after every eligibility and reachability change', function()
        local pointer = load_pointer()

        local cases = {
            {
                name='hidden',
                mutate=function(target) target.visible = false end,
            },
            {
                name='inactive',
                mutate=function(target) target.active = false end,
            },
            {
                name='clipped',
                mutate=function(target)
                    target.frame_body = widget_harness.rect(1, 1, 4, 4,
                        {x1=3, y1=3, x2=4, y2=4})
                end,
            },
            {
                name='moved',
                mutate=function(target)
                    widget_harness.set_frame(target, 5, 5, 2, 2)
                end,
            },
            {
                name='removed',
                mutate=function(_, root) root.subviews = {} end,
            },
            {
                name='unreachable',
                mutate=function(target, root)
                    local detached = view('pass', 0, 0, 8, 8, {target})
                    root.subviews = {view('pass', 0, 0, 8, 8)}
                    assert.is.equal(target, detached.subviews[1])
                end,
            },
        }

        for _, case in ipairs(cases) do
            local leaves = 0
            local target = view('target', 1, 1, 4, 4)
            target.on_pointer_leave = function() leaves = leaves + 1 end
            local root = view('target', 0, 0, 8, 8, {target})
            local context = pointer.PointerContext.new(root)
            pointer.PointerDispatcher.sample(context, 2, 2)
            assert.is.equal(target, context.target, case.name)

            case.mutate(target, root)
            local result = pointer.PointerDispatcher.sample(context, 2, 2)
            assert.equals('miss', result.kind, case.name)
            assert.is_nil(context.target, case.name)
            assert.equals(1, leaves, case.name)
        end
    end)

    it('keeps contexts isolated between independently rendered roots', function()
        local pointer = load_pointer()
        local first_target = view('target', 0, 0, 8, 8)
        local second_target = view('target', 0, 0, 8, 8)
        local first_root = view('target', 0, 0, 8, 8, {first_target})
        local second_root = view('target', 0, 0, 8, 8, {second_target})
        local first = pointer.PointerContext.new(first_root)
        local second = pointer.PointerContext.new(second_root)

        pointer.PointerDispatcher.sample(first, 2, 2)
        pointer.PointerDispatcher.sample(second, 2, 2)
        assert.is.equal(first_target, first.target)
        assert.is.equal(second_target, second.target)
        first_root.subviews = {}
        pointer.PointerDispatcher.sample(first, 2, 2)
        assert.is_nil(first.target)
        assert.is.equal(second_target, second.target)
    end)

    it('passes local coordinates after self to defclass pointer methods', function()
        local default_nil = widget_harness.default_nil()
        local widgets = widget_harness.widgets(nil, default_nil)
        widgets.Widget.ATTRS{visible=true, active=true}
        load_extensions(widgets, default_nil)
        local Handler = widget_harness.defclass(nil, widgets.Label)
        function Handler:on_pointer_update(x, y)
            self.callback_self = self
            self.callback_coordinates = {x, y}
        end

        local target = Handler{}
        widget_harness.set_frame(target, 2, 3, 4, 4)
        local root = widgets.Widget{}
        widget_harness.set_frame(root, 0, 0, 10, 10)
        root:addviews{target}
        local pointer = load_pointer()
        local context = pointer.PointerContext.new(root)

        pointer.PointerDispatcher.sample(context, 3, 5)
        assert.is.equal(target, target.callback_self)
        assert.same({1, 2}, target.callback_coordinates)
    end)

    it('targets controls independently of tooltip content', function()
        local pointer = load_pointer()
        local target = view('target', 1, 1, 4, 4)
        local root = view('target', 0, 0, 8, 8, {target})

        assert.is.equal(target,
            pointer.PointerDispatcher.resolve(root, 2, 2).target)
        target.tooltip = 'presentation data'
        assert.is.equal(target,
            pointer.PointerDispatcher.resolve(root, 2, 2).target)
        target.tooltip = nil
        assert.is.equal(target,
            pointer.PointerDispatcher.resolve(root, 2, 2).target)
    end)
end)
