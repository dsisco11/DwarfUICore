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

describe('DwarfUICore native-ui pointer obstruction classifier', function()
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
        assert.equals(pointer.PointerClassificationKind.TARGET, result.kind)
        assert.equals(child, result.subject)
        local child_result = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, root, {x=11, y=4}, {x=0, y=0}, true, true)
        assert.equals(pointer.PointerClassificationKind.TARGET, child_result.kind)
        assert.equals(child, child_result.subject)
        assert.same({1, 2}, {child_result.local_position.x, child_result.local_position.y})
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
        assert.equals(pointer.PointerClassificationKind.TARGET, result.kind)
        assert.equals(child, result.subject)
    end)

    it('applies exact policy before CAN_KEY_ACTIVATE fallback', function()
        local pointer = load_pointer()
        local button = native('widget_container', {x1=2, y1=2, x2=6, y2=6}, {
            flags = {CAN_KEY_ACTIVATE=true},
        })
        local result = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, button, {x=4, y=4}, {x=0, y=0}, true, true)
        assert.equals(pointer.PointerClassificationKind.MISS, result.kind)

        local fallback = native('mystery_widget', {x1=2, y1=2, x2=6, y2=6}, {
            can_activate = true,
        })
        result = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, fallback, {x=4, y=4}, {x=0, y=0}, true, true)
        assert.equals(pointer.PointerClassificationKind.TARGET, result.kind)
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
        assert.equals(pointer.PointerClassificationKind.TARGET, result.kind)
        assert.equals(child, result.subject)

        result = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, none, {x=3, y=3}, {x=0, y=0}, true, true)
        assert.equals(pointer.PointerClassificationKind.MISS, result.kind)
    end)

    it('supports block traversal, blocking policy, and descendant precedence', function()
        local pointer = load_pointer()
        local original = pointer.NativeUiPointerObstructionClassifier._policy_for_type
        pointer.NativeUiPointerObstructionClassifier._policy_for_type = function(_, type_name)
            if type_name == 'blocker' then return pointer.PointerPolicy.BLOCK end
            return original({}, type_name)
        end

        local child = native('widget_better_button', {x1=4, y1=4, x2=6, y2=6})
        local block = native('blocker', {x1=0, y1=0, x2=8, y2=8}, {
            children = {child},
        })
        local hit_child = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, block, {x=5, y=5}, {x=0, y=0}, true, true)
        assert.equals(pointer.PointerClassificationKind.TARGET, hit_child.kind)
        assert.equals(child, hit_child.subject)

        local block_only = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, block, {x=1, y=1}, {x=0, y=0}, true, true)
        assert.equals(pointer.PointerClassificationKind.BLOCKED, block_only.kind)
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
        assert.equals(pointer.PointerClassificationKind.TARGET, hit.kind)

        local occupied = native('mystery_widget', {x1=0, y1=0, x2=12, y2=12})
        local miss = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, occupied, {x=3, y=3}, {x=0, y=0}, true, true)
        assert.equals(pointer.PointerClassificationKind.MISS, miss.kind)
    end)

    it('returns unknown for malformed recognized native widgets and clips hit testing', function()
        local pointer = load_pointer()
        local malformed = native('widget_better_button', {x1='bad', y1=0, x2=10, y2=10})
        local result = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, malformed, {x=2, y=2}, {x=0, y=0}, true, true)
        assert.equals(pointer.PointerClassificationKind.UNKNOWN, result.kind)

        local clipped = native('widget_better_button', {
            x1=0, y1=0, x2=10, y2=10,
            clip = {x1=2, y1=2, x2=4, y2=4},
        })
        result = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, clipped, {x=1, y=1}, {x=0, y=0}, true, true)
        assert.equals(pointer.PointerClassificationKind.MISS, result.kind)
        result = pointer.NativeUiPointerObstructionClassifier._classify(
            {}, clipped, {x=2, y=2}, {x=0, y=0}, true, true)
        assert.equals(pointer.PointerClassificationKind.TARGET, result.kind)
    end)
end)
