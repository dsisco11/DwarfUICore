local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local mood_environment = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfui/mood_popover.lua', {
        globals={
            COLOR_LIGHTGREEN='lightgreen',
            COLOR_GREEN='green',
            COLOR_LIGHTCYAN='lightcyan',
            COLOR_WHITE='white',
            COLOR_YELLOW='yellow',
            COLOR_LIGHTRED='lightred',
            COLOR_RED='red',
            defclass=function(class) return setmetatable(class or {}, {
                __call=function(class_table)
                    return setmetatable({}, {__index=class_table})
                end,
            }) end,
        },
    })
local mood_popover = mood_environment.MoodPopoverModel{}

local hover_instructions = {
    INFO_STRESSED_0=100,
    INFO_STRESSED_1=101,
    INFO_STRESSED_2=102,
    INFO_STRESSED_3=103,
    INFO_STRESSED_4=104,
    INFO_STRESSED_5=105,
    INFO_STRESSED_6=106,
}

local dependencies = {
    is_valid=function(unit) return unit.valid ~= false end,
    is_citizen=function(unit) return unit.citizen == true end,
    get_stress_category=function(unit) return unit.stress_category end,
    get_readable_name=function(unit) return unit.name end,
}

describe('DwarfUI mood popover model', function()
    it('maps every native mood hover instruction to its descriptor', function()
        local expected = {
            {label='Ecstatic', category=6},
            {label='Happy', category=5},
            {label='Pleased', category=4},
            {label='Content', category=3},
            {label='Displeased', category=2},
            {label='Unhappy', category=1},
            {label='Miserable', category=0},
        }

        for index, expectation in ipairs(expected) do
            local hover_index = index - 1
            local descriptor = mood_popover:resolve_hover(
                hover_instructions['INFO_STRESSED_' .. hover_index],
                hover_instructions)

            assert.equals(hover_index, descriptor.hover_index)
            assert.equals(expectation.category, descriptor.stress_category)
            assert.equals(expectation.label, descriptor.label)
        end
    end)

    it('rejects unsupported native hover instructions', function()
        assert.is_nil(mood_popover:resolve_hover(nil, hover_instructions))
        assert.is_nil(mood_popover:resolve_hover(999, hover_instructions))
    end)

    it('uses the active-citizen predicate and includes insane citizens',
            function()
        local is_citizen_arguments = {}
        local production_environment = module_loader.load(repo_root,
            'src/scripts_modinstalled/dwarfui/mood_popover.lua', {
                globals={
                    COLOR_LIGHTGREEN='lightgreen', COLOR_GREEN='green',
                    COLOR_LIGHTCYAN='lightcyan', COLOR_WHITE='white',
                    COLOR_YELLOW='yellow', COLOR_LIGHTRED='lightred',
                    COLOR_RED='red',
                    defclass=function(class) return setmetatable(class or {}, {
                        __call=function(class_table)
                            return setmetatable({}, {__index=class_table})
                        end,
                    }) end,
                    df={
                        global={world={units={active={
                            {id=1, name='Citizen', citizen=true,
                                stress_category=1, valid=true},
                            {id=2, name='Visitor', citizen=false,
                                stress_category=1, valid=true},
                            {id=3, name='Removed', citizen=true,
                                stress_category=1, valid=false},
                        }}}},
                        isvalid=function(unit)
                            return unit.valid and 'ref' or nil
                        end,
                    },
                    dfhack={units={
                        isCitizen=function(unit, include_insane)
                            table.insert(is_citizen_arguments, {
                                unit=unit, include_insane=include_insane,
                            })
                            return unit.citizen
                        end,
                        getStressCategory=function(unit)
                            return unit.stress_category
                        end,
                        getReadableName=function(unit) return unit.name end,
                    }},
                },
            })
        local production_model = production_environment.MoodPopoverModel{}
        local rows = production_model:build_active_snapshot({stress_category=1})

        assert.same({1}, {rows[1].id})
        assert.equals(2, #is_citizen_arguments)
        for _, arguments in ipairs(is_citizen_arguments) do
            assert.is_true(arguments.include_insane)
        end
    end)

    it('filters a fresh snapshot to valid active citizens in one category',
            function()
        local descriptor = mood_popover:resolve_hover(
            hover_instructions.INFO_STRESSED_5, hover_instructions)
        local invalid_classifications = 0
        local rows = mood_popover:build_snapshot({
            {id=1, name='Target', citizen=true, stress_category=1},
            {id=2, name='Visitor', citizen=false, stress_category=1},
            {id=3, name='Other mood', citizen=true, stress_category=2},
            {id=4, name='Removed', citizen=true, stress_category=1, valid=false},
        }, descriptor, {
            is_valid=dependencies.is_valid,
            is_citizen=dependencies.is_citizen,
            get_stress_category=function(unit)
                if unit.valid == false then invalid_classifications =
                    invalid_classifications + 1 end
                return unit.stress_category
            end,
            get_readable_name=dependencies.get_readable_name,
        })

        assert.same({1}, {rows[1].id})
        assert.equals('Target', rows[1].name)
        assert.equals(0, invalid_classifications)
    end)

    it('sorts case-insensitively with unit ID as a stable tie-break', function()
        local descriptor = mood_popover:resolve_hover(
            hover_instructions.INFO_STRESSED_6, hover_instructions)
        local rows = mood_popover:build_snapshot({
            {id=4, name='apple', citizen=true, stress_category=0},
            {id=3, name='zinc', citizen=true, stress_category=0},
            {id=2, name='Apple', citizen=true, stress_category=0},
            {id=1, name='apple', citizen=true, stress_category=0},
        }, descriptor, dependencies)

        assert.same({1, 2, 4, 3},
            {rows[1].id, rows[2].id, rows[3].id, rows[4].id})
    end)

    it('does not retain unit rows between snapshot refreshes', function()
        local descriptor = mood_popover:resolve_hover(
            hover_instructions.INFO_STRESSED_4, hover_instructions)
        local first_unit = {
            id=1, name='First', citizen=true, stress_category=2,
        }
        local second_unit = {
            id=2, name='Second', citizen=true, stress_category=2,
        }
        local first_rows = mood_popover:build_snapshot(
            {first_unit}, descriptor, dependencies)
        local second_rows = mood_popover:build_snapshot(
            {second_unit}, descriptor, dependencies)

        assert.is_not.equal(first_rows, second_rows)
        assert.is.equal(first_unit, first_rows[1].unit)
        assert.is.equal(second_unit, second_rows[1].unit)
        assert.equals(2, second_rows[1].id)
    end)

    it('returns an empty snapshot when no units match', function()
        local descriptor = mood_popover:resolve_hover(
            hover_instructions.INFO_STRESSED_0, hover_instructions)
        assert.same({}, mood_popover:build_snapshot({
            {id=1, name='Different', citizen=true, stress_category=5},
            {id=2, name='Visitor', citizen=false, stress_category=6},
        }, descriptor, dependencies))
    end)
end)
