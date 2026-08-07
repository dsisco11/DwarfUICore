local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local pointer_path = 'src/scripts_modinstalled/dwarfuicore/pointer.lua'
local extensions_path =
    'src/scripts_modinstalled/dwarfuicore/widget_extensions.lua'
local enum_path =
    'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua'
local Policy
local Kind

local function load_pointer(mouse_pos)
    local _, immutable_enum = module_loader.load(repo_root, enum_path)
    local _, pointer = module_loader.load(repo_root, pointer_path, {
        globals={
            dfhack={
                screen={
                    getMousePos=mouse_pos or function() return nil, nil end,
                },
            },
        },
        reqscript={['dwarfuicore/utils/immutable_enum']=immutable_enum},
    })
    Policy = pointer.PointerPolicy
    Kind = pointer.PointerClassificationKind
    return pointer
end

local function load_extensions(widgets, default_nil, pointer)
    local _, extensions = module_loader.load(repo_root, extensions_path, {
        globals={
            DEFAULT_NIL=default_nil,
            COLOR_RED=4,
            dfhack={
                dwarfuicore={},
                gui={showAnnouncement=function() end},
                printerr=function() end,
            },
        },
        require_modules={['gui.widgets']=widgets},
        reqscript={['dwarfuicore/pointer']=pointer},
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

---@param type_name string
---@param rect table|nil
---@param overrides table|nil
---@return table
local function native(type_name, rect, overrides)
    overrides = overrides or {}
    return {
        type = type_name,
        rect = rect,
        flags = overrides.flags,
        CAN_KEY_ACTIVATE = overrides.can_activate,
        children = overrides.children,
        visible = overrides.visible,
        active = overrides.active,
    }
end

describe('DwarfUICore pointer dispatcher', function()
    it('publishes immutable numeric policy and result enums', function()
        local pointer = load_pointer()

        assert.equals('number', type(pointer.PointerPolicy.TARGET))
        assert.equals('number', type(pointer.PointerPolicy.PASS))
        assert.equals('number', type(pointer.PointerPolicy.BLOCK))
        assert.equals('number', type(pointer.PointerPolicy.NONE))
        assert.equals('number', type(pointer.PointerClassificationKind.TARGET))
        assert.equals('number', type(pointer.PointerClassificationKind.BLOCKED))
        assert.equals('number', type(pointer.PointerClassificationKind.MISS))
        assert.has_error(function()
            pointer.PointerPolicy.TARGET = pointer.PointerPolicy.PASS
        end)
        assert.has_error(function()
            pointer.PointerClassificationKind.MISS =
                pointer.PointerClassificationKind.TARGET
        end)
    end)

    it('owns state per supplied root and starts with a miss', function()
        local pointer = load_pointer()
        local root = view(Policy.TARGET, 0, 0, 10, 10)
        local context = pointer.PointerContext.new(root)

        assert.is.equal(root, context.root)
        assert.is_nil(context.target)
        assert.equals(Kind.MISS, context.result.kind)
    end)

    it('returns explicit results and resolves overlaps in reverse render order', function()
        local pointer = load_pointer()
        local lower = view(Policy.TARGET, 2, 2, 5, 5)
        local upper = view(Policy.TARGET, 3, 3, 5, 5)
        local panel = view(Policy.PASS, 0, 0, 12, 12, {lower, upper})
        local root = view(Policy.TARGET, 0, 0, 20, 20, {panel})

        local result = pointer.PointerDispatcher.resolve(root, 4, 4)
        assert.equals(Kind.TARGET, result.kind)
        assert.is.equal(upper, result.subject)
        assert.same({1, 1}, {result.local_position.x, result.local_position.y})

        result = pointer.PointerDispatcher.resolve(root, 1, 1)
        assert.same({kind=Kind.MISS}, result)
        panel.pointer_policy = Policy.BLOCK
        result = pointer.PointerDispatcher.resolve(root, 1, 1)
        assert.equals(Kind.BLOCKED, result.kind)
        assert.is.equal(panel, result.subject)
    end)

    it('treats the root as a boundary instead of selecting it', function()
        local pointer = load_pointer()
        local root = view(Policy.TARGET, 0, 0, 10, 10)

        assert.equals(Kind.MISS,
            pointer.PointerDispatcher.resolve(root, 2, 2).kind)
    end)

    it('keeps terminal composites above implementation children', function()
        local pointer = load_pointer()
        local implementation = view(Policy.TARGET, 2, 2, 6, 2)
        local control = view(Policy.TARGET, 1, 1, 8, 4, {implementation})
        local root = view(Policy.TARGET, 0, 0, 12, 8, {control})
        local _, result = sample_target(pointer, root, 3, 3)

        assert.equals(Kind.TARGET, result.kind)
        assert.is.equal(control, result.subject)
        assert.same({2, 2}, {result.local_position.x, result.local_position.y})
    end)

    it('keeps pass containers transparent and none subtrees excluded', function()
        local pointer = load_pointer()
        local behind = view(Policy.TARGET, 0, 0, 20, 20)
        local empty_panel = view(Policy.PASS, 1, 1, 8, 8)
        local excluded_child = view(Policy.TARGET, 10, 1, 5, 5)
        local excluded = view(
            Policy.NONE, 10, 1, 5, 5, {excluded_child})
        local root = view(
            Policy.TARGET, 0, 0, 20, 20,
            {behind, empty_panel, excluded})

        local result = pointer.PointerDispatcher.resolve(root, 2, 2)
        assert.is.equal(behind, result.subject)
        result = pointer.PointerDispatcher.resolve(root, 11, 2)
        assert.is.equal(behind, result.subject)
    end)

    it('respects clipped bodies for targets and the root', function()
        local pointer = load_pointer()
        local behind = view(Policy.TARGET, 0, 0, 20, 20)
        local clipped = view(Policy.TARGET, 1, 1, 8, 8)
        clipped.frame_body = widget_harness.rect(1, 1, 8, 8,
            {x1=1, y1=1, x2=4, y2=8})
        local root = view(
            Policy.TARGET, 0, 0, 20, 20, {behind, clipped})

        assert.is.equal(clipped,
            pointer.PointerDispatcher.resolve(root, 3, 2).target)
        assert.is.equal(behind,
            pointer.PointerDispatcher.resolve(root, 6, 2).target)

        root.frame_body = widget_harness.rect(0, 0, 20, 20,
            {x1=0, y1=0, x2=5, y2=19})
        assert.equals(Kind.MISS,
            pointer.PointerDispatcher.resolve(root, 6, 2).kind)
    end)

    it('uses full window frames for blocking while retaining child targets', function()
        local pointer = load_pointer()
        local behind = view(Policy.TARGET, 0, 0, 20, 20)
        local child = view(Policy.TARGET, 4, 4, 3, 3)
        local window = view(Policy.BLOCK, 2, 2, 10, 10, {child})
        window.frame_body = widget_harness.rect(3, 3, 8, 8)
        local root = view(
            Policy.TARGET, 0, 0, 20, 20, {behind, window})

        local result = pointer.PointerDispatcher.resolve(root, 4, 4)
        assert.is.equal(child, result.subject)
        result = pointer.PointerDispatcher.resolve(root, 2, 2)
        assert.equals(Kind.BLOCKED, result.kind)
        assert.is.equal(window, result.subject)
        result = pointer.PointerDispatcher.resolve(root, 15, 15)
        assert.is.equal(behind, result.subject)
    end)

    it('lets nested modal windows block only their own frames', function()
        local pointer = load_pointer()
        local outer = view(Policy.BLOCK, 1, 1, 16, 16)
        local inner = view(Policy.BLOCK, 5, 5, 6, 6)
        outer.subviews = {inner}
        local root = view(Policy.TARGET, 0, 0, 20, 20, {outer})

        local result = pointer.PointerDispatcher.resolve(root, 6, 6)
        assert.equals(Kind.BLOCKED, result.kind)
        assert.is.equal(inner, result.subject)
        result = pointer.PointerDispatcher.resolve(root, 3, 3)
        assert.equals(Kind.BLOCKED, result.kind)
        assert.is.equal(outer, result.subject)
        result = pointer.PointerDispatcher.resolve(root, 18, 18)
        assert.equals(Kind.MISS, result.kind)
    end)

    it('evaluates visible and active state through the ancestor chain', function()
        local pointer = load_pointer()
        local target = view(Policy.TARGET, 2, 2, 4, 4)
        local parent = view(Policy.PASS, 1, 1, 8, 8, {target})
        local root = view(Policy.TARGET, 0, 0, 12, 12, {parent})
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
        assert.equals(Kind.MISS,
            pointer.PointerDispatcher.resolve(root, 3, 3).kind)
        visible = true
        active = false
        assert.equals(Kind.MISS,
            pointer.PointerDispatcher.resolve(root, 3, 3).kind)
    end)

    it('emits ordered transitions and terminal-local callback coordinates', function()
        local pointer = load_pointer()
        local events = {}
        local first = view(Policy.TARGET, 1, 1, 4, 4)
        local second = view(Policy.TARGET, 6, 1, 3, 3)
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
        local root = view(Policy.TARGET, 0, 0, 12, 8, {first, second})
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
        assert.equals(Kind.MISS, context.result.kind)
    end)

    it('samples the mouse once and clears on missing coordinates', function()
        local samples = 0
        local mouse_x, mouse_y = 2, 2
        local pointer = load_pointer(function()
            samples = samples + 1
            return mouse_x, mouse_y
        end)
        local target = view(Policy.TARGET, 1, 1, 4, 4)
        local root = view(Policy.TARGET, 0, 0, 8, 8, {target})
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
        assert.equals(Kind.MISS, result.kind)
        assert.is_nil(context.target)

        result = pointer.PointerDispatcher.sample(context, nil, nil)
        assert.equals(2, samples)
        assert.equals(Kind.MISS, result.kind)
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
                    local detached = view(
                        Policy.PASS, 0, 0, 8, 8, {target})
                    root.subviews = {view(Policy.PASS, 0, 0, 8, 8)}
                    assert.is.equal(target, detached.subviews[1])
                end,
            },
        }

        for _, case in ipairs(cases) do
            local leaves = 0
            local target = view(Policy.TARGET, 1, 1, 4, 4)
            target.on_pointer_leave = function() leaves = leaves + 1 end
            local root = view(Policy.TARGET, 0, 0, 8, 8, {target})
            local context = pointer.PointerContext.new(root)
            pointer.PointerDispatcher.sample(context, 2, 2)
            assert.is.equal(target, context.target, case.name)

            case.mutate(target, root)
            local result = pointer.PointerDispatcher.sample(context, 2, 2)
            assert.equals(Kind.MISS, result.kind, case.name)
            assert.is_nil(context.target, case.name)
            assert.equals(1, leaves, case.name)
        end
    end)

    it('keeps contexts isolated between independently rendered roots', function()
        local pointer = load_pointer()
        local first_target = view(Policy.TARGET, 0, 0, 8, 8)
        local second_target = view(Policy.TARGET, 0, 0, 8, 8)
        local first_root = view(
            Policy.TARGET, 0, 0, 8, 8, {first_target})
        local second_root = view(
            Policy.TARGET, 0, 0, 8, 8, {second_target})
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
        local pointer = load_pointer()
        load_extensions(widgets, default_nil, pointer)
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
        local context = pointer.PointerContext.new(root)

        pointer.PointerDispatcher.sample(context, 3, 5)
        assert.is.equal(target, target.callback_self)
        assert.same({1, 2}, target.callback_coordinates)
    end)

    it('targets controls independently of tooltip content', function()
        local pointer = load_pointer()
        local target = view(Policy.TARGET, 1, 1, 4, 4)
        local root = view(Policy.TARGET, 0, 0, 8, 8, {target})

        assert.is.equal(target,
            pointer.PointerDispatcher.resolve(root, 2, 2).target)
        target.tooltip = 'presentation data'
        assert.is.equal(target,
            pointer.PointerDispatcher.resolve(root, 2, 2).target)
        target.tooltip = nil
        assert.is.equal(target,
            pointer.PointerDispatcher.resolve(root, 2, 2).target)
    end)

    local function make_classifier(pointer, classify)
        local classifier = setmetatable({}, {__index=pointer.PointerObstructionClassifier})
        if classify then
            classifier._classify = classify
        end
        return classifier
    end

    it('invokes classifiers only through invoke()', function()
        local pointer = load_pointer()
        local classifier = make_classifier(pointer, function(_, _, screen_position)
            return {kind=Kind.TARGET, subject='leaf',
                local_position={x=screen_position.x, y=screen_position.y}}
        end)

        local result = pointer.PointerObstructionClassifier.invoke(
            classifier, {}, {x=3, y=4})
        assert.equals(Kind.TARGET, result.kind)
        assert.equals('leaf', result.subject)
        assert.same({3, 4}, {result.local_position.x, result.local_position.y})
        assert.is_nil(pointer.PointerObstructionClassifier.get_diagnostic(classifier))
    end)

    it('records validation diagnostics without throwing for malformed invocation inputs', function()
        local pointer = load_pointer()
        local classifier = make_classifier(pointer, function()
            return {kind=Kind.MISS}
        end)

        local result = pointer.PointerObstructionClassifier.invoke(classifier, 42, {x=1, y=2})
        assert.equals(Kind.UNKNOWN, result.kind)
        local diagnostic = pointer.PointerObstructionClassifier.get_diagnostic(classifier)
        assert.equals('validation', diagnostic.kind)
        assert.truthy(diagnostic.message)
        assert.is_nil(result.local_position)

        result = pointer.PointerObstructionClassifier.invoke(classifier, {}, {x=1.5, y=2})
        assert.equals(Kind.UNKNOWN, result.kind)
        diagnostic = pointer.PointerObstructionClassifier.get_diagnostic(classifier)
        assert.equals('validation', diagnostic.kind)
        assert.equals('invalid screen_position', diagnostic.message)
    end)

    it('contains classifier exceptions as unknown obstruction', function()
        local pointer = load_pointer()
        local classifier = make_classifier(pointer, function()
            error('broken classifier')
        end)

        local result = pointer.PointerObstructionClassifier.invoke(classifier, {}, {x=1, y=2})
        assert.equals(Kind.UNKNOWN, result.kind)
        local diagnostic = pointer.PointerObstructionClassifier.get_diagnostic(classifier)
        assert.equals('invocation', diagnostic.kind)
        assert.match('broken classifier', diagnostic.message)
    end)

    it('contains malformed classifier results as unknown obstruction', function()
        local pointer = load_pointer()
        local classifier = make_classifier(pointer, function()
            return {kind=Kind.TARGET}
        end)

        local result = pointer.PointerObstructionClassifier.invoke(classifier, {}, {x=1, y=2})
        assert.equals(Kind.UNKNOWN, result.kind)
        local diagnostic = pointer.PointerObstructionClassifier.get_diagnostic(classifier)
        assert.equals('malformed', diagnostic.kind)
        assert.match('local_position', diagnostic.message)
        assert.is_nil(diagnostic.root)
    end)

    it('returns unknown when implementation is missing _classify', function()
        local pointer = load_pointer()
        local classifier = make_classifier(pointer)

        local result = pointer.PointerObstructionClassifier.invoke(classifier, {}, {x=1, y=2})
        assert.equals(Kind.UNKNOWN, result.kind)
        local diagnostic = pointer.PointerObstructionClassifier.get_diagnostic(classifier)
        assert.equals('validation', diagnostic.kind)
        assert.equals('classifier implementation is missing _classify', diagnostic.message)
    end)

    it('delegates gui-view obstruction classification through invoke()', function()
        local pointer = load_pointer()
        local root = view(Policy.TARGET, 0, 0, 20, 20, {
            view(Policy.TARGET, 4, 4, 3, 3),
        })
        local leaf = root.subviews[1]
        local invocations = 0
        local original_invoke = pointer.PointerObstructionClassifier.invoke
        pointer.PointerObstructionClassifier.invoke = function(...)
            invocations = invocations + 1
            return original_invoke(...)
        end

        local result = pointer.PointerDispatcher.resolve(root, 5, 5)
        assert.equals(1, invocations)
        assert.is.equal(leaf, result.subject)
        assert.equals(Kind.TARGET, result.kind)

        pointer.PointerObstructionClassifier.invoke = original_invoke
    end)

    it('preserves target on unknown with no lifecycle transitions', function()
        local pointer = load_pointer()
        local events = {}
        local target = view(Policy.TARGET, 1, 1, 4, 4)
        target.on_pointer_enter = function(self, x, y)
            table.insert(events, {'enter', self, x, y})
        end
        target.on_pointer_update = function(self, x, y)
            table.insert(events, {'update', self, x, y})
        end
        target.on_pointer_leave = function(self)
            table.insert(events, {'leave', self})
        end
        local root = view(Policy.TARGET, 0, 0, 10, 10, {target})
        local context = pointer.PointerContext.new(root)
        local original = pointer.GuiViewPointerObstructionClassifier._classify

        pointer.PointerDispatcher.sample(context, 3, 3)
        assert.is.equal(target, context.target)
        assert.equals(2, #events)

        pointer.GuiViewPointerObstructionClassifier._classify = function()
            return {kind=Kind.UNKNOWN}
        end
        local result = pointer.PointerDispatcher.sample(context, 3, 3)
        assert.is.equal(target, context.target)
        assert.equals(Kind.UNKNOWN, result.kind)
        assert.equals(2, #events)

        pointer.GuiViewPointerObstructionClassifier._classify = original
    end)

    it('clears current target and emits leave for blocked and miss', function()
        local pointer = load_pointer()
        local leaves = 0
        local target = view(Policy.TARGET, 1, 1, 4, 4)
        target.on_pointer_leave = function()
            leaves = leaves + 1
        end
        local blocker = view(Policy.BLOCK, 0, 0, 10, 10)
        local root = view(Policy.TARGET, 0, 0, 10, 10, {target})
        local context = pointer.PointerContext.new(root)

        pointer.PointerDispatcher.sample(context, 2, 2)
        assert.is.equal(target, context.target)
        root.subviews = {target, blocker}
        local blocked = pointer.PointerDispatcher.sample(context, 2, 2)
        assert.equals(Kind.BLOCKED, blocked.kind)
        assert.is_nil(context.target)
        assert.equals(1, leaves)

        blocker.pointer_policy = Policy.NONE
        local missed = pointer.PointerDispatcher.sample(context, 2, 2)
        assert.equals(Kind.MISS, missed.kind)
        assert.is_nil(context.target)
        assert.equals(1, leaves)
    end)

    it('classifies native widgets by exact type policy and ancestry geometry', function()
        local pointer = load_pointer()
        local root = native('widget_container', {
            x1=0, y1=0, x2=49, y2=19,
        }, {
            children = {
                native('widget_better_button', {
                    x1=10, y1=2, width=8, height=5,
                }),
            },
        })
        local child = root.children[1]

        local result = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, child, {x=11, y=4}, {x=0, y=0}, true, true)
        assert.equals(Kind.TARGET, result.kind)
        assert.equals(child, result.subject)
        local child_result = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, root, {x=11, y=4}, {x=0, y=0}, true, true)
        assert.equals(Kind.TARGET, child_result.kind)
        assert.equals(child, child_result.subject)
        assert.same({10, 2}, {child_result.local_position.x, child_result.local_position.y})
    end)

    it('honors global vs parent-relative geometry with ancestry', function()
        local pointer = load_pointer()
        local child = native('widget_better_button', {
            x1=300, y1=20, x2=305, y2=23,
        }, {
            flags = {GLOBAL_POSITIONING=true},
        })
        local root = native('widget_container', {x1=0, y1=0, x2=500, y2=500}, {
            children = {child},
        })

        local result = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, root, {x=300, y=22}, {x=0, y=0}, true, true)
        assert.equals(Kind.TARGET, result.kind)
        assert.equals(child, result.subject)
    end)

    it('applies exact policy before CAN_KEY_ACTIVATE fallback', function()
        local pointer = load_pointer()
        local button = native('widget_container', {x1=2, y1=2, x2=6, y2=6}, {
            flags = {CAN_KEY_ACTIVATE=true},
        })
        local result = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, button, {x=4, y=4}, {x=0, y=0}, true, true)
        assert.equals(Kind.MISS, result.kind)

        local fallback = native('mystery_widget', {x1=2, y1=2, x2=6, y2=6}, {
            can_activate = true,
        })
        result = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, fallback, {x=4, y=4}, {x=0, y=0}, true, true)
        assert.equals(Kind.TARGET, result.kind)
        assert.equals(fallback, result.subject)
    end)

    it('maps pass and none policies to traversal and no-hit behaviors', function()
        local pointer = load_pointer()
        local child = native('widget_better_button', {x1=2, y1=2, x2=4, y2=4})
        local pass = native('widget_container', {x1=0, y1=0, x2=6, y2=6}, {
            children = {child},
        })
        local none = native('widget', {x1=0, y1=0, x2=6, y2=6}, {
            children = {child},
        })

        local result = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, pass, {x=3, y=3}, {x=0, y=0}, true, true)
        assert.equals(Kind.TARGET, result.kind)
        assert.equals(child, result.subject)

        result = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, none, {x=3, y=3}, {x=0, y=0}, true, true)
        assert.equals(Kind.MISS, result.kind)
    end)

    it('supports block traversal, blocking policy, and descendant precedence', function()
        local pointer = load_pointer()
        local original = pointer.NativeUiPointerObstructionClassifier._policy_for_type
        pointer.NativeUiPointerObstructionClassifier._policy_for_type = function(_, _, type_name)
            if type_name == 'blocker' then return Policy.BLOCK end
            return original({}, {}, type_name)
        end

        local child = native('widget_better_button', {x1=4, y1=4, x2=6, y2=6})
        local block = native('blocker', {x1=0, y1=0, x2=8, y2=8}, {
            children = {child},
        })
        local hit_child = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, block, {x=5, y=5}, {x=0, y=0}, true, true)
        assert.equals(Kind.TARGET, hit_child.kind)
        assert.equals(child, hit_child.subject)

        local block_only = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, block, {x=1, y=1}, {x=0, y=0}, true, true)
        assert.equals(Kind.BLOCKED, block_only.kind)
        assert.equals(block, block_only.subject)

        pointer.NativeUiPointerObstructionClassifier._policy_for_type = original
    end)

    it('traverses unregistered containers and misses recognized occupied geometry', function()
        local pointer = load_pointer()
        local with_desc = native('mystery_widget', {x1=0, y1=0, x2=12, y2=12}, {
            children = {
                native('widget_better_button', {x1=5, y1=5, x2=7, y2=7}),
            },
        })
        local hit = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, with_desc, {x=6, y=6}, {x=0, y=0}, true, true)
        assert.equals(Kind.TARGET, hit.kind)

        local occupied = native('mystery_widget', {x1=0, y1=0, x2=12, y2=12})
        local miss = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, occupied, {x=3, y=3}, {x=0, y=0}, true, true)
        assert.equals(Kind.MISS, miss.kind)
    end)

    it('returns unknown for malformed recognized native widgets and clips hit testing', function()
        local pointer = load_pointer()
        local malformed = native('widget_better_button', {x1='bad', y1=0, x2=10, y2=10})
        local result = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, malformed, {x=2, y=2}, {x=0, y=0}, true, true)
        assert.equals(Kind.UNKNOWN, result.kind)

        local clipped = native('widget_better_button', {
            x1=0, y1=0, x2=10, y2=10,
            clip = {x1=2, y1=2, x2=4, y2=4},
        })
        result = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, clipped, {x=1, y=1}, {x=0, y=0}, true, true)
        assert.equals(Kind.MISS, result.kind)
        result = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, clipped, {x=2, y=2}, {x=0, y=0}, true, true)
        assert.equals(Kind.TARGET, result.kind)
    end)
end)


