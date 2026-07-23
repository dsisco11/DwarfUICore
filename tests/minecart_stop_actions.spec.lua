local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local DEFAULT_NIL = {}

---Creates a callable class with DFHack-style defaults for model tests.
---@param class table|nil
---@param parent table|nil
---@return table
local function test_defclass(class, parent)
    class = class or {}
    class.super = parent
    local attributes = {}
    class.ATTRS = setmetatable(attributes, {
        __call=function(_, additions)
            for key, value in pairs(additions) do attributes[key] = value end
        end,
    })
    return setmetatable(class, {
        __index=parent,
        __call=function(class_table, values)
            local instance = {}
            local chain = {}
            local current = class_table
            while current do
                table.insert(chain, 1, current)
                current = rawget(current, 'super')
            end
            for _, ancestor in ipairs(chain) do
                for key, value in pairs(rawget(ancestor, 'ATTRS') or {}) do
                    if value ~= DEFAULT_NIL then instance[key] = value end
                end
            end
            for key, value in pairs(values or {}) do instance[key] = value end
            setmetatable(instance, {__index=class_table})
            if instance.init then instance:init() end
            return instance
        end,
    })
end

---Creates the production AssetButton against the local widget harness.
---@return table
local function load_asset_button()
    local default_nil = widget_harness.default_nil()
    local widgets = widget_harness.widgets(nil, default_nil)
    widgets.Widget.ATTRS{
        visible=true,
        enabled=true,
        disabled=false,
        tooltip=default_nil,
    }
    widgets.Label.makeButtonLabelText = function(spec) return spec.chars end
    local _, module = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfui/widgets/asset_button.lua', {
            globals={
                DEFAULT_NIL=default_nil,
                defclass=widget_harness.defclass,
            },
            require_modules={
                utils={getval=function(value)
                    if type(value) == 'function' then return value() end
                    return value
                end},
                ['gui.widgets']=widgets,
            },
            reqscript={
                ['dwarfui/widget_extensions']={},
            },
        })
    return module
end

local asset_button = load_asset_button()
local action_environment = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfui/minecart_stop_actions.lua', {
        globals={defclass=test_defclass},
        reqscript={
            ['dwarfui/widgets/asset_button']=asset_button,
        },
    })
local route_environment = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfui/minecart_route.lua', {
        globals={
            defclass=test_defclass,
            df={global={}},
            dfhack={screen={
                inGraphicsMode=function() return false end,
            }},
        },
    })

local ActionDefinition =
    action_environment.MinecartStopActionDefinition
local ActionLayout = action_environment.MinecartStopActionLayout
local ActionPool = action_environment.MinecartStopActionPool
local MenuLayout = route_environment.MinecartRouteMenuLayout

---Returns an explicitly supplied value or its default.
---@param values table
---@param key string
---@param default any
---@return any
local function value_or(values, key, default)
    if values[key] == nil then return default end
    return values[key]
end

---Constructs one valid action definition with optional overrides.
---@param values? table
---@return dwarfui.MinecartStopActionDefinition
local function action(values)
    values = values or {}
    return ActionDefinition{
        id=value_or(values, 'id', 'action'),
        width=value_or(values, 'width', 3),
        height=value_or(values, 'height', 3),
        gap_after=value_or(values, 'gap_after', 0),
        asset=value_or(values, 'asset', false),
        asset_hover=value_or(values, 'asset_hover', false),
        chars=value_or(values, 'chars', {'abc', 'def', 'ghi'}),
        chars_hover=value_or(values, 'chars_hover', false),
        pens=value_or(values, 'pens', false),
        pens_hover=value_or(values, 'pens_hover', false),
        tooltip=value_or(values, 'tooltip', false),
        on_activate=value_or(
            values, 'on_activate', function() end),
    }
end

---Creates a menu layout with cached native panel bounds.
---@param bounds table
---@return dwarfui.MinecartRouteMenuLayout
local function menu_layout(bounds)
    local layout = MenuLayout{}
    layout:cache_bounds(bounds)
    return layout
end

---Creates zero-based native flattened route and stop vectors.
---@param rows table[]
---@param scroll_position? integer
---@return table
local function hauling(rows, scroll_position)
    local view_routes, view_stops = {}, {}
    for _, row in ipairs(rows) do
        view_routes[row.index] = row.route
        view_stops[row.index] = row.stop or false
    end
    return {
        scroll_position=scroll_position or 0,
        view_routes=view_routes,
        view_stops=view_stops,
    }
end

---Returns one native-style stop row fixture.
---@param index integer
---@param route_id integer|nil
---@param stop_id integer|nil
---@return table
local function stop_row(index, route_id, stop_id)
    return {
        index=index,
        route=route_id and {id=route_id} or nil,
        stop=stop_id and {id=stop_id} or nil,
    }
end

---Returns one native-style route header fixture.
---@param index integer
---@param route_id integer
---@return table
local function header_row(index, route_id)
    return {index=index, route={id=route_id}, stop=false}
end

describe('DwarfUI minecart stop action definitions', function()
    it('retains stable identity, dimensions, visuals, tooltip, and callback',
            function()
        local activated
        local definition = action{
            id='zoom',
            width=4,
            height=2,
            gap_after=1,
            asset={page='PAGE', x=2, y=3},
            asset_hover={page='HOVER', x=4, y=5},
            chars={'abcd', 'efgh'},
            chars_hover={'ABCD', 'EFGH'},
            pens=1,
            pens_hover=2,
            tooltip='Zoom',
            on_activate=function(descriptor) activated = descriptor end,
        }

        assert.same({'zoom', 4, 2, 1, 'Zoom'}, {
            definition.id,
            definition.width,
            definition.height,
            definition.gap_after,
            definition.tooltip,
        })
        assert.equals('PAGE', definition.asset.page)
        local descriptor = {stop_id=7}
        definition.on_activate(descriptor)
        assert.is.equal(descriptor, activated)
    end)

    it('rejects missing identity, invalid dimensions, gaps, and callbacks',
            function()
        assert.has_error(function()
            action{id=''}
        end, 'MinecartStopActionDefinition.id must be a non-empty string')
        assert.has_error(function()
            action{width=-1}
        end,
            'MinecartStopActionDefinition.width must be a positive integer')
        assert.has_error(function()
            action{height=0}
        end,
            'MinecartStopActionDefinition.height must be a positive integer')
        assert.has_error(function()
            action{gap_after=-1}
        end,
            'MinecartStopActionDefinition.gap_after must be a nonnegative integer')
        assert.has_error(function()
            action{on_activate=false}
        end,
            'MinecartStopActionDefinition.on_activate must be a function')
    end)
end)

describe('DwarfUI minecart stop action layout', function()
    it('places one action outside every fully visible stop row', function()
        local layout = menu_layout{x1=4, y1=4, x2=59, y2=18}
        local model = ActionLayout{actions={action{id='zoom'}}}
        local descriptors = model:build(hauling({
            stop_row(0, 10, 100),
            header_row(1, 11),
            stop_row(2, 12, 102),
        }), layout)

        assert.equals(2, #descriptors)
        assert.same({10, 100, 0, 'zoom'}, {
            descriptors[1].route_id,
            descriptors[1].stop_id,
            descriptors[1].row_index,
            descriptors[1].action_id,
        })
        assert.same({
            x1=60, y1=10, x2=62, y2=12, width=3, height=3,
        }, descriptors[1].bounds)
        assert.same({
            x1=60, y1=16, x2=62, y2=18, width=3, height=3,
        }, descriptors[2].bounds)
        assert.is_nil(descriptors[1].route)
        assert.is_nil(descriptors[1].stop)

        layout.bounds.x2 = 100
        assert.equals(60, descriptors[1].bounds.x1)
    end)

    it('lays out ordered mixed-width actions with configured gaps', function()
        local actions = {
            action{id='first', width=3, gap_after=1},
            action{
                id='second',
                width=2,
                gap_after=2,
                chars={'ab', 'cd', 'ef'},
            },
            action{
                id='third',
                width=1,
                chars={'a', 'b', 'c'},
            },
        }
        local descriptors = ActionLayout{actions=actions}:build(
            hauling({stop_row(0, 1, 2)}),
            menu_layout{x1=4, y1=4, x2=59, y2=12})

        assert.equals(3, #descriptors)
        assert.same({'first', 'second', 'third'}, {
            descriptors[1].action_id,
            descriptors[2].action_id,
            descriptors[3].action_id,
        })
        assert.same({60, 62, 64, 65, 68, 68}, {
            descriptors[1].bounds.x1,
            descriptors[1].bounds.x2,
            descriptors[2].bounds.x1,
            descriptors[2].bounds.x2,
            descriptors[3].bounds.x1,
            descriptors[3].bounds.x2,
        })
    end)

    it('rebuilds from current scrolling, route edits, and panel bounds',
            function()
        local native = hauling({
            stop_row(5, 10, 105),
            stop_row(6, 11, 106),
            stop_row(7, 12, 107),
        }, 5)
        local layout = menu_layout{x1=4, y1=4, x2=59, y2=15}
        local model = ActionLayout{actions={action{id='zoom'}}}

        local first = model:build(native, layout)
        assert.same({5, 6}, {first[1].row_index, first[2].row_index})
        assert.same({105, 106}, {first[1].stop_id, first[2].stop_id})

        native.scroll_position = 6
        native.view_stops[6] = {id=206}
        local scrolled = model:build(native, layout)
        assert.same({6, 7}, {
            scrolled[1].row_index,
            scrolled[2].row_index,
        })
        assert.same({206, 107}, {
            scrolled[1].stop_id,
            scrolled[2].stop_id,
        })
        assert.equals(106, first[2].stop_id)

        layout:cache_bounds{x1=10, y1=10, x2=39, y2=21}
        local moved = model:build(native, layout)
        assert.same({40, 16}, {
            moved[1].bounds.x1,
            moved[1].bounds.y1,
        })
    end)

    it('skips stale rows and excludes partially visible final rows', function()
        local native = hauling({
            {index=0, route={}, stop={id=1}},
            {index=1, route={id=2}, stop={}},
            {index=2, route=nil, stop={id=3}},
            stop_row(3, 4, 5),
            stop_row(4, 6, 7),
        })
        local descriptors = ActionLayout{actions={action{}}}:build(
            native, menu_layout{x1=4, y1=4, x2=59, y2=22})

        assert.equals(1, #descriptors)
        assert.same({3, 4, 5}, {
            descriptors[1].row_index,
            descriptors[1].route_id,
            descriptors[1].stop_id,
        })
    end)

    it('requires unique actions that fit within one native row', function()
        local duplicate = action{id='same'}
        assert.has_error(function()
            ActionLayout{actions={duplicate, action{id='same'}}}
        end, 'duplicate minecart stop action ID: same')

        local model = ActionLayout{actions={
            action{
                id='too-tall',
                height=4,
                chars={'a', 'b', 'c', 'd'},
            },
        }}
        assert.has_error(function()
            model:build(
                hauling({stop_row(0, 1, 2)}),
                menu_layout{x1=4, y1=4, x2=59, y2=20})
        end,
            'minecart stop action too-tall height exceeds native row height')
    end)

    it('bounds output by visible rows instead of total native stops',
            function()
        local rows = {}
        for index=0,99 do
            table.insert(rows, stop_row(index, 1, 1000 + index))
        end
        local descriptors = ActionLayout{actions={
            action{id='first'},
            action{id='second'},
        }}:build(
            hauling(rows),
            menu_layout{x1=4, y1=4, x2=59, y2=18})

        assert.equals(6, #descriptors)
        assert.equals(2, descriptors[6].row_index)
    end)
end)

describe('DwarfUI minecart stop action button pool', function()
    it('reuses slots after scrolling and clears unused row bindings',
            function()
        local activated = {}
        local definition = action{
            id='zoom',
            on_activate=function(descriptor)
                table.insert(activated, descriptor.stop_id)
            end,
        }
        local model = ActionLayout{actions={definition}}
        local layout = menu_layout{x1=4, y1=4, x2=59, y2=15}
        local created = {}
        local pool = ActionPool{
            on_button_created=function(button)
                table.insert(created, button)
            end,
        }
        local parent = widget_harness.rect(0, 0, 100, 30)

        local first = model:build(hauling({
            stop_row(0, 1, 10),
            stop_row(1, 1, 11),
            stop_row(2, 1, 12),
        }), layout)
        pool:bind(first, parent)
        local buttons = pool:get_buttons('zoom')
        assert.equals(2, #created)
        assert.equals(2, #buttons)
        assert.same({60, 10}, {
            buttons[1].frame_body.x1,
            buttons[1].frame_body.y1,
        })
        assert.is_true(buttons[1].visible)
        assert.is_true(buttons[1]:activate())
        assert.same({10}, activated)

        local scrolled = model:build(hauling({
            stop_row(1, 1, 21),
            stop_row(2, 1, 22),
            stop_row(3, 1, 23),
        }, 1), layout)
        pool:bind(scrolled, parent)
        local rebound = pool:get_buttons('zoom')
        assert.is.equal(buttons[1], rebound[1])
        assert.is.equal(buttons[2], rebound[2])
        assert.equals(2, #created)
        assert.same({21, 22}, {
            rebound[1].action_descriptor.stop_id,
            rebound[2].action_descriptor.stop_id,
        })
        assert.is_nil(rebound[1].action_descriptor.stop)
        rebound[1]:activate()
        assert.same({10, 21}, activated)

        pool:bind({scrolled[1]}, parent)
        assert.is_true(rebound[1].visible)
        assert.is_false(rebound[2].visible)
        assert.is_nil(rebound[2].action_descriptor)
        pool:clear()
        assert.is_false(rebound[1].visible)
        assert.is_nil(rebound[1].action_descriptor)
        assert.equals(0, #pool:get_active_buttons())
    end)

    it('maintains independent bounded subpools for ordered actions', function()
        local first = action{id='first'}
        local second = action{
            id='second',
            width=1,
            chars={'x', 'y', 'z'},
        }
        local model = ActionLayout{actions={first, second}}
        local descriptors = model:build(hauling({
            stop_row(0, 1, 10),
            stop_row(1, 1, 11),
        }), menu_layout{x1=4, y1=4, x2=59, y2=15})
        local pool = ActionPool{}
        pool:bind(descriptors, widget_harness.rect(0, 0, 100, 30))

        assert.equals(2, #pool:get_buttons('first'))
        assert.equals(2, #pool:get_buttons('second'))
        local active = pool:get_active_buttons()
        assert.same({'first', 'second', 'first', 'second'}, {
            active[1].action_descriptor.action_id,
            active[2].action_descriptor.action_id,
            active[3].action_descriptor.action_id,
            active[4].action_descriptor.action_id,
        })
        assert.same({60, 63}, {
            active[1].frame.l,
            active[2].frame.l,
        })
    end)
end)
