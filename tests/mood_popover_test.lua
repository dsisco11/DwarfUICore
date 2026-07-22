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
    get_stress_value=function(unit) return unit.stress end,
    get_readable_name=function(unit) return unit.name end,
}

describe('DwarfUI mood popover model', function()
    it('maps every native mood hover instruction to its descriptor', function()
        local expected = {
            {label='Ecstatic', category=6, descending=false},
            {label='Very Happy', category=5, descending=false},
            {label='Happy', category=4, descending=false},
            {label='Content', category=3, descending=false},
            {label='Unhappy', category=2, descending=true},
            {label='Very Unhappy', category=1, descending=true},
            {label='Miserable', category=0, descending=true},
        }

        for index, expectation in ipairs(expected) do
            local hover_index = index - 1
            local descriptor = mood_popover:resolve_hover(
                hover_instructions['INFO_STRESSED_' .. hover_index],
                hover_instructions)

            assert.equals(hover_index, descriptor.hover_index)
            assert.equals(expectation.category, descriptor.stress_category)
            assert.equals(expectation.label, descriptor.label)
            assert.equals(expectation.descending,
                descriptor.stress_descending)
        end
    end)

    it('rejects unsupported native hover instructions', function()
        assert.is_nil(mood_popover:resolve_hover(nil, hover_instructions))
        assert.is_nil(mood_popover:resolve_hover(999, hover_instructions))
    end)

    it('uses the top-bar citizen population and excludes insane citizens',
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
                                stress_category=1, stress=30000, valid=true,
                                status={current_soul={personality={stress=30000}}}},
                            {id=2, name='Visitor', citizen=false,
                                stress_category=1, stress=30000, valid=true,
                                status={current_soul={personality={stress=30000}}}},
                            {id=3, name='Removed', citizen=true,
                                stress_category=1, stress=30000, valid=false,
                                status={current_soul={personality={stress=30000}}}},
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
            assert.is_nil(arguments.include_insane)
        end
    end)

    it('filters a fresh snapshot to valid active citizens in one category',
            function()
        local descriptor = mood_popover:resolve_hover(
            hover_instructions.INFO_STRESSED_5, hover_instructions)
        local invalid_classifications = 0
        local rows = mood_popover:build_snapshot({
            {id=1, name='Target', citizen=true, stress_category=1, stress=30000},
            {id=2, name='Visitor', citizen=false, stress_category=1, stress=30000},
            {id=3, name='Other mood', citizen=true, stress_category=2, stress=15000},
            {id=4, name='Removed', citizen=true, stress_category=1, stress=30000, valid=false},
        }, descriptor, {
            is_valid=dependencies.is_valid,
            is_citizen=dependencies.is_citizen,
            get_stress_category=function(unit)
                if unit.valid == false then invalid_classifications =
                    invalid_classifications + 1 end
                return unit.stress_category
            end,
            get_stress_value=dependencies.get_stress_value,
            get_readable_name=dependencies.get_readable_name,
        })

        assert.same({1}, {rows[1].id})
        assert.equals('Target', rows[1].name)
        assert.equals(0, invalid_classifications)
    end)

    it('sorts happy and unhappy categories in opposite stress directions',
            function()
        local units = {
            {id=1, name='Lower', citizen=true, stress=-30000},
            {id=2, name='Higher', citizen=true, stress=-40000},
        }
        local happy = mood_popover:resolve_hover(
            hover_instructions.INFO_STRESSED_1, hover_instructions)
        for _, unit in ipairs(units) do unit.stress_category = 5 end
        local happy_rows = mood_popover:build_snapshot(units, happy, dependencies)

        units[1].stress, units[2].stress = 30000, 40000
        units[1].stress_category, units[2].stress_category = 1, 1
        local unhappy = mood_popover:resolve_hover(
            hover_instructions.INFO_STRESSED_5, hover_instructions)
        local unhappy_rows = mood_popover:build_snapshot(
            units, unhappy, dependencies)

        assert.same({2, 1}, {happy_rows[1].id, happy_rows[2].id})
        assert.same({2, 1}, {unhappy_rows[1].id, unhappy_rows[2].id})
        assert.equals(-40000, happy_rows[1].stress)
        assert.equals(40000, unhappy_rows[1].stress)
    end)

    it('uses name and unit ID to break equal-stress ties', function()
        local descriptor = mood_popover:resolve_hover(
            hover_instructions.INFO_STRESSED_6, hover_instructions)
        local rows = mood_popover:build_snapshot({
            {id=4, name='apple', citizen=true, stress_category=0, stress=60000},
            {id=3, name='zinc', citizen=true, stress_category=0, stress=60000},
            {id=2, name='Apple', citizen=true, stress_category=0, stress=60000},
            {id=1, name='apple', citizen=true, stress_category=0, stress=60000},
        }, descriptor, dependencies)

        assert.same({1, 2, 4, 3},
            {rows[1].id, rows[2].id, rows[3].id, rows[4].id})
    end)

    it('does not retain unit rows between snapshot refreshes', function()
        local descriptor = mood_popover:resolve_hover(
            hover_instructions.INFO_STRESSED_4, hover_instructions)
        local first_unit = {
            id=1, name='First', citizen=true, stress_category=2, stress=15000,
        }
        local second_unit = {
            id=2, name='Second', citizen=true, stress_category=2, stress=15000,
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
            {id=1, name='Different', citizen=true, stress_category=5, stress=-30000},
            {id=2, name='Visitor', citizen=false, stress_category=6, stress=-60000},
        }, descriptor, dependencies))
    end)
end)
