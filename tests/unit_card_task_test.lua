local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local stockpile = {z=4}
local _, task_details = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfui/unit_card_task.lua', {
        globals={
            df={
                job_role_type={Hauled=2},
                global={world={buildings={other={STOCKPILE={stockpile}}}}},
            },
            dfhack={buildings={
                findAtTile=function() return nil end,
                containsTile=function(building, x, y)
                    return building == stockpile and x == 10 and y == 20
                end,
                getName=function(building)
                    return building == stockpile and 'Finished goods' or ''
                end,
            }},
        },
    })

describe('DwarfUI unit-card task details', function()
    it('reports a named stockpile destination for an active haul job', function()
        local unit = {job={current_job={
            items={{role=2}},
            pos={x=10, y=20, z=4},
        }}}

        assert.is_true(task_details.is_haul_job(unit.job.current_job))
        assert.equals('Destination: Finished goods',
            task_details.get_haul_destination_text(unit))
    end)

    it('does not add details for a non-hauling active job', function()
        local unit = {job={current_job={
            items={{role=0}},
            pos={x=10, y=20, z=4},
        }}}

        assert.is_false(task_details.is_haul_job(unit.job.current_job))
        assert.is_nil(task_details.get_haul_destination_text(unit))
    end)
end)
