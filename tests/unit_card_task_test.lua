local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local stockpile = {z=4}
local _, task_details = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfui/unit_card_task.lua', {
        globals={
            df={
                job_role_type={Hauled=2, QueuedContainer=7},
                job_type={
                    BringItemToDepot='BringItemToDepot',
                    BringItemToShop='BringItemToShop',
                    StoreItemInStockpile='StoreItemInStockpile',
                    StoreItemInBag='StoreItemInBag',
                    StoreItemInLocation='StoreItemInLocation',
                    StoreItemInBarrel='StoreItemInBarrel',
                    StoreItemInBin='StoreItemInBin',
                    StoreItemInVehicle='StoreItemInVehicle',
                    DumpItem='DumpItem',
                },
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
            }, items={
                getDescription=function(item)
                    return item.description
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

    it('recognizes store-in-container jobs without a Hauled item role',
            function()
        local unit = {job={current_job={
            job_type='StoreItemInBin',
            items={{role=6}, {role=7}},
            pos={x=10, y=20, z=4},
        }}}

        assert.is_true(task_details.is_haul_job(unit.job.current_job))
        assert.equals('Destination: Finished goods',
            task_details.get_haul_destination_text(unit))
    end)

    it('shows the queued item while a hauler is assigned to collect it',
            function()
        local goblet = {description='gold goblet'}
        local unit = {job={current_job={
            job_type='StoreItemInBin',
            items={{role=6}, {role=7, item=goblet}},
            pos={x=10, y=20, z=4},
        }}}

        assert.equals(goblet, task_details.get_grab_item(unit.job.current_job))
        assert.equals('Grab: gold goblet', task_details.get_grab_item_text(unit))
    end)

    it('shows an uncollected Hauled item as the primary grab target', function()
        local book = {description='Records of the Monastery',
            flags={in_inventory=false}}
        local unit = {job={current_job={
            job_type='StoreItemInLocation',
            items={{role=2, item=book}, {role=7, item={
                description='fallback container'}}},
            pos={x=10, y=20, z=4},
        }}}

        assert.equals(book, task_details.get_grab_item(unit.job.current_job))
        assert.equals('Grab: Records of the Monastery',
            task_details.get_grab_item_text(unit))
    end)

    it('does not show a grab target after the item enters the inventory',
            function()
        local book = {description='carried book', flags={in_inventory=true}}
        local unit = {job={current_job={
            job_type='StoreItemInLocation',
            items={{role=2, item=book}},
            pos={x=10, y=20, z=4},
        }}}

        assert.is_nil(task_details.get_grab_item(unit.job.current_job))
        assert.is_nil(task_details.get_grab_item_text(unit))
    end)

    it('truncates task-detail rows to the available panel width', function()
        assert.equals('Destination: Finished go',
            task_details.truncate_panel_text('Destination: Finished goods', 24))
        assert.equals('Gra', task_details.truncate_panel_text('Grab: log', 3))
    end)
end)
