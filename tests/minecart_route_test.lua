local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

---Creates a minimal callable class for pure-model tests.
---@param class table|nil
---@return table
local function test_defclass(class)
    class = class or {}
    return setmetatable(class, {__call=function(class_table, attributes)
        local instance = attributes or {}
        setmetatable(instance, {__index=class_table})
        if instance.init then instance:init() end
        return instance
    end})
end

local route_environment = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfui/minecart_route.lua', {
        globals={defclass=test_defclass},
    })

local MinecartRouteMenuLayout = route_environment.MinecartRouteMenuLayout
local MinecartRouteSelection = route_environment.MinecartRouteSelection

---Creates a zero-based vector fixture.
---@param values table[]
---@return table
local function zero_vector(values)
    local vector = {}
    for index, value in ipairs(values) do vector[index - 1] = value end
    return vector
end

---Creates native-style flattened route and stop row fixtures.
---@return table hauling
---@return table[] routes
local function route_fixture()
    local first = {id=10, name='Duplicate'}
    local second = {id=11, name='Duplicate'}
    local first_stop = {id=1, name='Stop'}
    local second_stop = {id=1, name='Stop'}
    return {
        scroll_position=0,
        view_routes=zero_vector({first, first, second, second}),
        view_stops=zero_vector({false, first_stop, false, second_stop}),
    }, {first, second}
end

describe('DwarfUI minecart route menu layout', function()
    it('maps the complete three-cell route header to row zero', function()
        local hauling, routes = route_fixture()
        local layout = MinecartRouteMenuLayout{}

        for mouse_y=10,12 do
            for _, mouse_x in ipairs({0, 6, 71}) do
                local row = layout:resolve_row(mouse_x, mouse_y, hauling,
                    'dwarfmode/Hauling')
                assert.equals(0, row.index)
                assert.is_equal(routes[1], row.route)
                assert.is_nil(row.stop)
                assert.is_true(row.is_route_header)
            end
        end
    end)

    it('maps a stop row to its owning route', function()
        local hauling, routes = route_fixture()
        local row = MinecartRouteMenuLayout{}:resolve_row(6, 14, hauling,
            'dwarfmode/Hauling')

        assert.equals(1, row.index)
        assert.is_equal(routes[1], row.route)
        assert.equals(1, row.stop.id)
        assert.is_false(row.is_route_header)
    end)

    it('adds native scrolling to the visible row offset', function()
        local routes = {}
        local stops = {}
        for index=0,7 do
            routes[index] = {id=100 + index}
            stops[index] = index % 2 == 0 and false or {id=index}
        end
        local row = MinecartRouteMenuLayout{}:resolve_row(20, 14, {
            scroll_position=5,
            view_routes=routes,
            view_stops=stops,
        }, 'dwarfmode/Hauling')

        assert.equals(6, row.index)
        assert.equals(106, row.route.id)
    end)

    it('rejects pointers outside every list boundary', function()
        local hauling = route_fixture()
        local layout = MinecartRouteMenuLayout{}
        local points = {
            {-1, 10}, {72, 10}, {0, 9}, {nil, 10}, {0, nil},
        }

        for _, point in ipairs(points) do
            assert.is_nil(layout:resolve_row(point[1], point[2], hauling,
                'dwarfmode/Hauling'))
        end
    end)

    it('rejects invalid rows, scrolling, and missing vectors', function()
        local hauling = route_fixture()
        local layout = MinecartRouteMenuLayout{}

        assert.is_nil(layout:resolve_row(6, 40, hauling,
            'dwarfmode/Hauling'))
        assert.is_nil(layout:resolve_row(6, 10, {
            scroll_position=-1, view_routes=hauling.view_routes,
        }, 'dwarfmode/Hauling'))
        assert.is_nil(layout:resolve_row(6, 10, {}, 'dwarfmode/Hauling'))
    end)

    it('fails closed for base and nested non-Hauling contexts', function()
        local hauling = route_fixture()
        local layout = MinecartRouteMenuLayout{}

        for _, focus in ipairs({
                'dwarfmode/Default',
                'dwarfmode/Hauling/DefineStop',
                'dwarfmode/Hauling/AssignVehicle',
            }) do
            assert.is_nil(layout:resolve_row(6, 10, hauling, focus))
        end
        assert.is_nil(layout:resolve_row(6, 10, hauling, nil))
    end)

    it('supports injected geometry without changing row semantics', function()
        local hauling, routes = route_fixture()
        local layout = MinecartRouteMenuLayout{
            list_x1=20, list_x2=40, first_row_top=30, row_height=4,
        }
        local row = layout:resolve_row(20, 34, hauling,
            'dwarfmode/Hauling')

        assert.equals(1, row.index)
        assert.is_equal(routes[1], row.route)
    end)
end)

describe('DwarfUI minecart route selection', function()
    it('selects route headers and passes the click through', function()
        local hauling, routes = route_fixture()
        local selection = MinecartRouteSelection{}

        assert.is_false(selection:observe_input({_MOUSE_L=true}, 6, 11,
            hauling, 'dwarfmode/Hauling'))
        assert.equals(routes[1].id, selection:get_selected_route_id())
    end)

    it('selects the owning route from a stop row after scrolling', function()
        local hauling, routes = route_fixture()
        hauling.scroll_position = 2
        local selection = MinecartRouteSelection{}

        assert.is_false(selection:observe_input({_MOUSE_L=true}, 6, 14,
            hauling, 'dwarfmode/Hauling'))
        assert.equals(routes[2].id, selection:get_selected_route_id())
    end)

    it('preserves selection for unhandled input and invalid pointers', function()
        local hauling, routes = route_fixture()
        local selection = MinecartRouteSelection{selected_route_id=routes[1].id}

        assert.is_false(selection:observe_input({CURSOR_DOWN=true}, 6, 11,
            hauling, 'dwarfmode/Hauling'))
        assert.is_false(selection:observe_input({_MOUSE_L=true}, 80, 11,
            hauling, 'dwarfmode/Hauling'))
        assert.is_false(selection:observe_input({_MOUSE_L=true}, 6, 11,
            hauling, 'dwarfmode/Hauling/DefineStop'))
        assert.equals(routes[1].id, selection:get_selected_route_id())
    end)

    it('uses numeric identity when route and stop names are duplicated', function()
        local hauling, routes = route_fixture()
        local selection = MinecartRouteSelection{}

        selection:observe_input({_MOUSE_L=true}, 6, 20, hauling,
            'dwarfmode/Hauling')

        assert.equals('Duplicate', routes[1].name)
        assert.equals('Duplicate', routes[2].name)
        assert.equals('Stop', hauling.view_stops[1].name)
        assert.equals('Stop', hauling.view_stops[3].name)
        assert.equals(11, selection:get_selected_route_id())
    end)

    it('resolves zero-based native vectors and standard Lua sequences', function()
        local first = {id=0}
        local second = {id=2}
        local selection = MinecartRouteSelection{selected_route_id=0}

        assert.is_equal(first, selection:resolve_selected_route(
            zero_vector({first, second})))
        selection.selected_route_id = 2
        assert.is_equal(second, selection:resolve_selected_route({first, second}))
    end)

    it('clears a selected ID when its native route no longer exists', function()
        local selection = MinecartRouteSelection{selected_route_id=99}

        assert.is_nil(selection:resolve_selected_route(zero_vector({{id=1}})))
        assert.is_nil(selection:get_selected_route_id())
    end)

    it('rejects routes without numeric IDs and supports explicit clearing', function()
        local selection = MinecartRouteSelection{selected_route_id=5}

        assert.is_false(selection:select_route(nil))
        assert.is_false(selection:select_route({id='5'}))
        assert.equals(5, selection:get_selected_route_id())
        selection:clear()
        assert.is_nil(selection:get_selected_route_id())
    end)
end)
