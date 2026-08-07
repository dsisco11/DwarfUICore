local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local pointer_path = 'src/scripts_modinstalled/dwarfuicore/pointer.lua'
local pointer
local enum_path = 'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua'

local function load_pointer(mouse_pos)
    local _, immutable_enum = module_loader.load(repo_root, enum_path)
    local _, loaded = module_loader.load(repo_root, pointer_path, {
        globals={
            dfhack={
                screen={getMousePos=mouse_pos or function() return nil, nil end},
            },
        },
        reqscript={
            ['dwarfuicore/utils/immutable_enum']=immutable_enum,
        },
    })
    pointer = loaded
    return loaded
end

local function view(policy, x, y, width, height, children)
    local result = {
        pointer_policy=policy,
        visible=true,
        active=true,
        subviews=children or {},
    }
    result.frame_rect = {
        x1 = 0,
        y1 = 0,
        width = width,
        height = height,
    }
    local widget_harness = require('support.widget_harness')
    return widget_harness.set_frame(result, x, y, width, height)
end

describe('DwarfUICore gui-view pointer obstruction classifier', function()
    it('delegates gui-view obstruction classification through invoke', function()
        local pointer = load_pointer()
        local root = view(pointer.PointerPolicy.TARGET, 0, 0, 20, 20, {
            view(pointer.PointerPolicy.TARGET, 4, 4, 3, 3),
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
        assert.equals(pointer.PointerClassificationKind.TARGET, result.kind)

        pointer.PointerObstructionClassifier.invoke = original_invoke
    end)

    it('preserves target on unknown with no lifecycle transitions', function()
        local pointer = load_pointer()
        local events = {}
        local target = view(pointer.PointerPolicy.TARGET, 1, 1, 4, 4)
        target.on_pointer_enter = function(self, x, y)
            table.insert(events, {'enter', self, x, y})
        end
        target.on_pointer_update = function(self, x, y)
            table.insert(events, {'update', self, x, y})
        end
        target.on_pointer_leave = function(self)
            table.insert(events, {'leave', self})
        end
        local root = view(pointer.PointerPolicy.TARGET, 0, 0, 10, 10, {target})
        local context = pointer.PointerContext.new(root)
        local original = pointer.GuiViewPointerObstructionClassifier._classify

        pointer.PointerDispatcher.sample(context, 3, 3)
        assert.is.equal(target, context.target)
        assert.equals(2, #events)

        pointer.GuiViewPointerObstructionClassifier._classify = function()
            return {kind=pointer.PointerClassificationKind.UNKNOWN}
        end
        local result = pointer.PointerDispatcher.sample(context, 3, 3)
        assert.is.equal(target, context.target)
        assert.equals(pointer.PointerClassificationKind.UNKNOWN, result.kind)
        assert.equals(2, #events)

        pointer.GuiViewPointerObstructionClassifier._classify = original
    end)

    it('clears current target and emits leave for blocked and miss', function()
        local pointer = load_pointer()
        local leaves = 0
        local target = view(pointer.PointerPolicy.TARGET, 1, 1, 4, 4)
        target.on_pointer_leave = function()
            leaves = leaves + 1
        end
        local blocker = view(pointer.PointerPolicy.BLOCK, 0, 0, 10, 10)
        local root = view(pointer.PointerPolicy.TARGET, 0, 0, 10, 10, {target})
        local context = pointer.PointerContext.new(root)

        pointer.PointerDispatcher.sample(context, 2, 2)
        assert.is.equal(target, context.target)
        root.subviews = {target, blocker}
        local blocked = pointer.PointerDispatcher.sample(context, 2, 2)
        assert.equals(pointer.PointerClassificationKind.BLOCKED, blocked.kind)
        assert.is_nil(context.target)
        assert.equals(1, leaves)

        blocker.pointer_policy = pointer.PointerPolicy.NONE
        local missed = pointer.PointerDispatcher.sample(context, 2, 2)
        assert.equals(pointer.PointerClassificationKind.MISS, missed.kind)
        assert.is_nil(context.target)
        assert.equals(1, leaves)
    end)
end)
