--@ module=true

-- Reusable row-action layout and button pooling for the native Hauling menu.

local AssetButton =
    reqscript('dwarfui/widgets/asset_button').AssetButton

---Returns whether a value is a positive integer.
---@param value any
---@return boolean
local function is_positive_integer(value)
    return type(value) == 'number' and value % 1 == 0 and value > 0
end

---Returns whether a value is a nonnegative integer.
---@param value any
---@return boolean
local function is_nonnegative_integer(value)
    return type(value) == 'number' and value % 1 == 0 and value >= 0
end

---Returns a shallow sequence copy that preserves declared action order.
---@param values table[]|nil
---@return table[]
local function copy_sequence(values)
    local result = {}
    for _, value in ipairs(values or {}) do table.insert(result, value) end
    return result
end

---Returns a fresh screen-bounds snapshot.
---@param x integer
---@param y integer
---@param width integer
---@param height integer
---@return {x1: integer, y1: integer, x2: integer, y2: integer, width: integer, height: integer}
local function make_bounds(x, y, width, height)
    return {
        x1=x,
        y1=y,
        x2=x + width - 1,
        y2=y + height - 1,
        width=width,
        height=height,
    }
end

---@class dwarfui.MinecartStopActionDefinition: dfhack.class
---@field id string
---@field width integer
---@field height integer
---@field gap_after integer
---@field asset {page: string, x: integer, y: integer}|false
---@field asset_hover {page: string, x: integer, y: integer}|false
---@field chars (string|string[])[]
---@field chars_hover (string|string[])[]|false
---@field pens dfhack.color|dfhack.pen|(dfhack.color|dfhack.pen)[][]|false
---@field pens_hover dfhack.color|dfhack.pen|(dfhack.color|dfhack.pen)[][]|false
---@field tooltip string|false
---@field on_activate fun(descriptor: dwarfui.MinecartStopActionDescriptor)
MinecartStopActionDefinition = defclass(MinecartStopActionDefinition)
MinecartStopActionDefinition.ATTRS{
    id=false,
    width=0,
    height=0,
    gap_after=0,
    asset=false,
    asset_hover=false,
    chars=false,
    chars_hover=false,
    pens=false,
    pens_hover=false,
    tooltip=false,
    on_activate=false,
}

---Validates the stable identity, geometry, visual config, and callback.
function MinecartStopActionDefinition:init()
    assert(type(self.id) == 'string' and self.id ~= '',
        'MinecartStopActionDefinition.id must be a non-empty string')
    assert(is_positive_integer(self.width),
        'MinecartStopActionDefinition.width must be a positive integer')
    assert(is_positive_integer(self.height),
        'MinecartStopActionDefinition.height must be a positive integer')
    assert(is_nonnegative_integer(self.gap_after),
        'MinecartStopActionDefinition.gap_after must be a nonnegative integer')
    assert(type(self.chars) == 'table',
        'MinecartStopActionDefinition.chars must be a row table')
    assert(type(self.on_activate) == 'function',
        'MinecartStopActionDefinition.on_activate must be a function')
end

---@class dwarfui.MinecartStopActionDescriptor: dfhack.class
---@field route_id integer
---@field stop_id integer
---@field row_index integer
---@field action_id string
---@field bounds {x1: integer, y1: integer, x2: integer, y2: integer, width: integer, height: integer}
---@field action dwarfui.MinecartStopActionDefinition
MinecartStopActionDescriptor = defclass(MinecartStopActionDescriptor)
MinecartStopActionDescriptor.ATTRS{
    route_id=-1,
    stop_id=-1,
    row_index=-1,
    action_id='',
    bounds=false,
    action=false,
}

---@class dwarfui.MinecartStopActionLayout: dfhack.class
---@field actions dwarfui.MinecartStopActionDefinition[]
MinecartStopActionLayout = defclass(MinecartStopActionLayout)
MinecartStopActionLayout.ATTRS{
    actions=false,
}

---Copies and validates the ordered action-definition list.
function MinecartStopActionLayout:init()
    self.actions = copy_sequence(self.actions)
    local seen_ids = {}
    for index, action in ipairs(self.actions) do
        assert(type(action) == 'table',
            ('minecart stop action %d must be a definition'):format(index))
        assert(type(action.id) == 'string' and action.id ~= '',
            ('minecart stop action %d has no stable ID'):format(index))
        assert(not seen_ids[action.id],
            ('duplicate minecart stop action ID: %s'):format(action.id))
        assert(is_positive_integer(action.width) and
                is_positive_integer(action.height),
            ('minecart stop action %s has invalid dimensions'):format(
                action.id))
        assert(is_nonnegative_integer(action.gap_after),
            ('minecart stop action %s has an invalid gap'):format(action.id))
        seen_ids[action.id] = true
    end
end

---Builds immutable screen descriptors for all fully visible native stop rows.
---@param hauling table|nil
---@param menu_layout dwarfui.MinecartRouteMenuLayout|nil
---@return dwarfui.MinecartStopActionDescriptor[]
function MinecartStopActionLayout:build(hauling, menu_layout)
    if not hauling or not hauling.view_routes or
            not hauling.view_stops or not menu_layout or
            not menu_layout.bounds then
        return {}
    end

    local bounds = menu_layout.bounds
    local first_row_top = menu_layout.first_row_top
    local row_height = menu_layout.row_height
    local scroll_position = hauling.scroll_position or 0
    if not is_nonnegative_integer(scroll_position) or
            not is_nonnegative_integer(first_row_top) or
            not is_positive_integer(row_height) or
            type(bounds.x2) ~= 'number' or type(bounds.y2) ~= 'number' then
        return {}
    end

    for _, action in ipairs(self.actions) do
        assert(action.height <= row_height,
            ('minecart stop action %s height exceeds native row height'):format(
                action.id))
    end

    local visible_row_count = math.max(0,
        math.floor((bounds.y2 - first_row_top + 1) / row_height))
    local descriptors = {}
    for visible_index=0,visible_row_count - 1 do
        local row_index = scroll_position + visible_index
        local route = hauling.view_routes[row_index]
        local stop = hauling.view_stops[row_index]
        if route and stop and type(route.id) == 'number' and
                type(stop.id) == 'number' then
            local action_x = bounds.x2 + 1
            local action_y = first_row_top + visible_index * row_height
            for _, action in ipairs(self.actions) do
                table.insert(descriptors, MinecartStopActionDescriptor{
                    route_id=route.id,
                    stop_id=stop.id,
                    row_index=row_index,
                    action_id=action.id,
                    bounds=make_bounds(
                        action_x, action_y, action.width, action.height),
                    action=action,
                })
                action_x = action_x + action.width + action.gap_after
            end
        end
    end
    return descriptors
end

---Constructs one generic button for a stop-action definition.
---@param action dwarfui.MinecartStopActionDefinition
---@param on_activate fun()
---@return dwarfui.AssetButton
local function default_button_factory(action, on_activate)
    return AssetButton{
        frame={w=action.width, h=action.height},
        asset=action.asset or nil,
        asset_hover=action.asset_hover or nil,
        chars=action.chars,
        chars_hover=action.chars_hover or nil,
        pens=action.pens or nil,
        pens_hover=action.pens_hover or nil,
        tooltip=action.tooltip or nil,
        visible=false,
        on_activate=on_activate,
    }
end

---@class dwarfui.MinecartStopActionPoolSlot
---@field action dwarfui.MinecartStopActionDefinition
---@field button dwarfui.AssetButton

---@class dwarfui.MinecartStopActionPool: dfhack.class
---@field button_factory fun(action: dwarfui.MinecartStopActionDefinition, on_activate: fun()): dwarfui.AssetButton
---@field on_button_created fun(button: dwarfui.AssetButton)|false
---@field slots_by_action table<string, dwarfui.MinecartStopActionPoolSlot[]>
---@field active_buttons dwarfui.AssetButton[]
MinecartStopActionPool = defclass(MinecartStopActionPool)
MinecartStopActionPool.ATTRS{
    button_factory=default_button_factory,
    on_button_created=false,
}

---Initializes an empty pool with no retained row bindings.
function MinecartStopActionPool:init()
    self.slots_by_action = {}
    self.active_buttons = {}
end

---Invokes the action currently bound to a pooled button.
---@param button dwarfui.AssetButton
---@return boolean activated
function MinecartStopActionPool:activate_button(button)
    local descriptor = button.action_descriptor
    if not descriptor then return false end
    descriptor.action.on_activate(descriptor)
    return true
end

---Creates one reusable slot for an action ID.
---@param action dwarfui.MinecartStopActionDefinition
---@return dwarfui.MinecartStopActionPoolSlot
function MinecartStopActionPool:create_slot(action)
    local button
    button = self.button_factory(
        action, function() self:activate_button(button) end)
    assert(type(button) == 'table',
        'minecart stop action button factory must return a widget')
    local slot = {action=action, button=button}
    if self.on_button_created then self.on_button_created(button) end
    return slot
end

---Reuses visible slots, clears unused bindings, and updates screen frames.
---@param descriptors dwarfui.MinecartStopActionDescriptor[]|nil
---@param parent_rect? table
function MinecartStopActionPool:bind(descriptors, parent_rect)
    local used_by_action = {}
    self.active_buttons = {}

    for _, descriptor in ipairs(descriptors or {}) do
        local action_id = descriptor.action_id
        local slots = self.slots_by_action[action_id]
        if not slots then
            slots = {}
            self.slots_by_action[action_id] = slots
        end
        local used = (used_by_action[action_id] or 0) + 1
        used_by_action[action_id] = used
        local slot = slots[used]
        if not slot then
            slot = self:create_slot(descriptor.action)
            table.insert(slots, slot)
        end
        assert(slot.action == descriptor.action,
            ('minecart stop action definition changed for ID: %s'):format(
                action_id))

        local bounds = descriptor.bounds
        local button = slot.button
        button.action_descriptor = descriptor
        button.frame = {
            l=bounds.x1,
            t=bounds.y1,
            w=bounds.width,
            h=bounds.height,
        }
        button.visible = true
        local layout_parent = parent_rect or button.frame_parent_rect
        if layout_parent then button:updateLayout(layout_parent) end
        table.insert(self.active_buttons, button)
    end

    for action_id, slots in pairs(self.slots_by_action) do
        local used = used_by_action[action_id] or 0
        for index=used + 1,#slots do
            local button = slots[index].button
            button.visible = false
            button.action_descriptor = nil
        end
    end
end

---Returns a copy of the currently active buttons in descriptor order.
---@return dwarfui.AssetButton[]
function MinecartStopActionPool:get_active_buttons()
    return copy_sequence(self.active_buttons)
end

---Returns all allocated buttons for one stable action ID.
---@param action_id string
---@return dwarfui.AssetButton[]
function MinecartStopActionPool:get_buttons(action_id)
    local result = {}
    for _, slot in ipairs(self.slots_by_action[action_id] or {}) do
        table.insert(result, slot.button)
    end
    return result
end

---Hides every pooled button and removes every native row binding.
function MinecartStopActionPool:clear()
    self:bind({})
end
