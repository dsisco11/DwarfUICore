local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local DEFINITION_PATH =
    'src/scripts_modinstalled/dwarfuicore/context_menu/definition.lua'
local NUMBERS_PATH =
    'src/scripts_modinstalled/dwarfuicore/utils/numbers.lua'

local _, numbers = module_loader.load(repo_root, NUMBERS_PATH)
local _, definitions = module_loader.load(repo_root, DEFINITION_PATH, {
    reqscript={
        ['dwarfuicore/utils/numbers']=numbers,
    },
})

---Returns one minimal valid context-menu definition.
---@param handler? fun(context: table)
---@return table
local function valid_definition(handler)
    return {
        entries={{
            label='Inspect',
            on_select=handler or function() end,
        }},
    }
end

---Requires an operation to fail with one literal diagnostic fragment.
---@param fragment string
---@param callback function
local function assert_fails_with(fragment, callback)
    local ok, failure = pcall(callback)
    assert.is_false(ok)
    assert.is_truthy(tostring(failure):find(fragment, 1, true), failure)
end

describe('context-menu definitions', function()
    it('validates optional title, colors, entries, and fallback order',
            function()
        local handler = function() end
        local snapshot = definitions.validate{
            title='Tile',
            fg=2,
            bg=3,
            entries={
                {label='Inherited', on_select=handler},
                {label='Foreground', on_select=handler, fg=4},
                {label='Background', on_select=handler, bg=5},
                {label='Both', on_select=handler, fg=6, bg=7},
            },
        }

        assert.equals('Tile', snapshot.title)
        assert.same({fg=2, bg=3}, snapshot.pen)
        assert.same({fg=2, bg=3}, snapshot.entries[1].pen)
        assert.same({fg=4, bg=3}, snapshot.entries[2].pen)
        assert.same({fg=2, bg=5}, snapshot.entries[3].pen)
        assert.same({fg=6, bg=7}, snapshot.entries[4].pen)
        assert.is_equal(handler, snapshot.entries[1].on_select)

        local defaults = definitions.validate(valid_definition())
        assert.equals(15, defaults.fg)
        assert.equals(0, defaults.bg)
        assert.same({fg=15, bg=0}, defaults.entries[1].pen)
        assert.is_nil(defaults.title)
    end)

    it('accepts every display-color boundary and rejects COLOR_RESET',
            function()
        local black = valid_definition()
        black.fg = 0
        black.bg = 15
        black.entries[1].fg = 15
        black.entries[1].bg = 0
        local snapshot = definitions.validate(black)

        assert.equals(0, snapshot.fg)
        assert.equals(15, snapshot.bg)
        assert.equals(15, snapshot.entries[1].fg)
        assert.equals(0, snapshot.entries[1].bg)
        for _, value in ipairs{-1, 16, 1.5, '2', {}, function() end} do
            local invalid = valid_definition()
            invalid.fg = value
            assert_fails_with('context-menu definition fg', function()
                definitions.validate(invalid)
            end)
        end
    end)

    it('rejects invalid, empty, sparse, and unknown definition shapes',
            function()
        local cases = {
            {
                fragment='definition must be a table',
                value=false,
            },
            {
                fragment='entries must be a non-empty array',
                value={entries={}},
            },
            {
                fragment='entries must not contain missing entries',
                value={
                    entries={
                        [1]={label='One', on_select=function() end},
                        [3]={label='Three', on_select=function() end},
                    },
                },
            },
            {
                fragment='unsupported field extra',
                value={entries=valid_definition().entries, extra=true},
            },
            {
                fragment='title must be a non-empty string',
                value={title='', entries=valid_definition().entries},
            },
            {
                fragment='entry 1 label must be a non-empty string',
                value={entries={{label='', on_select=function() end}}},
            },
            {
                fragment='entry 1 contains unsupported field extra',
                value={
                    entries={{
                        label='One',
                        on_select=function() end,
                        extra=true,
                    }},
                },
            },
        }

        for _, case in ipairs(cases) do
            assert_fails_with(case.fragment, function()
                definitions.validate(case.value)
            end)
        end
    end)

    it('requires an actual Lua function handler', function()
        local callable = setmetatable({}, {
            __call=function() end,
        })
        for _, value in ipairs{false, 1, 'handler', callable} do
            local definition = valid_definition()
            definition.entries[1].on_select = value
            assert_fails_with('entry 1 on_select must be a Lua function',
                function()
                    definitions.validate(definition)
                end)
        end
    end)

    it('owns registration state and isolated opening snapshots', function()
        local original = {
            title='Original',
            fg=1,
            entries={{
                label='First',
                bg=2,
                on_select=function() end,
            }},
        }
        local slot = definitions.ContextMenuDefinitionSlot.new(original)
        original.title = 'Mutated'
        original.entries[1].label = 'Mutated'
        original.entries[1].bg = 9

        local first = slot:snapshot()
        assert.equals('Original', first.title)
        assert.equals('First', first.entries[1].label)
        assert.equals(2, first.entries[1].bg)

        first.title = 'Changed snapshot'
        first.pen.fg = 14
        first.entries[1].label = 'Changed snapshot'
        first.entries[1].pen.bg = 14
        local second = slot:snapshot()
        assert.equals('Original', second.title)
        assert.same({fg=1, bg=0}, second.pen)
        assert.equals('First', second.entries[1].label)
        assert.same({fg=1, bg=2}, second.entries[1].pen)
    end)

    it('uses class constructors to copy snapshots and nested values',
            function()
        local original = definitions.validate(valid_definition())
        local copy =
            definitions.ContextMenuDefinitionSnapshot.new(original)

        assert.is_equal(definitions.ContextMenuDefinitionSnapshot,
            getmetatable(copy))
        assert.is_equal(definitions.ContextMenuResolvedPen,
            getmetatable(copy.pen))
        assert.is_equal(definitions.ContextMenuResolvedEntry,
            getmetatable(copy.entries[1]))
        assert.is_not_equal(original, copy)
        assert.is_not_equal(original.pen, copy.pen)
        assert.is_not_equal(original.entries, copy.entries)
        assert.is_not_equal(original.entries[1], copy.entries[1])
        assert.is_not_equal(
            original.entries[1].pen, copy.entries[1].pen)
    end)

    it('replaces stored definitions atomically after validation', function()
        local slot = definitions.ContextMenuDefinitionSlot.new(
            valid_definition())
        slot:replace{
            title='Replacement',
            entries={{
                label='Second',
                on_select=function() end,
            }},
        }
        assert.equals('Replacement', slot:snapshot().title)

        assert_fails_with('entry 1 on_select must be a Lua function',
            function()
                slot:replace{
                    entries={{label='Invalid', on_select=false}},
                }
            end)
        local retained = slot:snapshot()
        assert.equals('Replacement', retained.title)
        assert.equals('Second', retained.entries[1].label)
    end)
end)
