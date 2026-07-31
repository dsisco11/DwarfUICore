--@ module=true

-- Synchronous, immutable pointer sampling for actionable opening input.

local numbers = reqscript('dwarfui/utils/numbers')

---@class dwarfui.ContextMenuInputSamplerOptions
---@field sample_screen_pointer? fun(): integer|nil, integer|nil
---@field sample_map_pointer? fun(): {x: integer, y: integer, z: integer}|nil
---@field has_map_demand? fun(): boolean

---@class dwarfui.ContextMenuInputSample
---@field x integer|nil
---@field y integer|nil
---@field map_x integer|nil
---@field map_y integer|nil
---@field map_z integer|nil

---@class dwarfui.ContextMenuInputSampler
---@field _sample_screen_pointer fun(): integer|nil, integer|nil
---@field _sample_map_pointer fun(): {x: integer, y: integer, z: integer}|nil
---@field _has_map_demand fun(): boolean
ContextMenuInputSampler = {}
ContextMenuInputSampler.__index = ContextMenuInputSampler

---Reads the current screen/interface pointer exactly once.
---@return integer|nil
---@return integer|nil
local function default_screen_sampler()
    return dfhack.screen.getMousePos()
end

---Reads the exact map tile under the pointer exactly once.
---@return {x: integer, y: integer, z: integer}|nil
local function default_map_sampler()
    return dfhack.gui.getMousePos()
end

---Reports that no map registration requires synchronous map sampling.
---@return boolean
local function no_map_demand()
    return false
end

---Creates one immutable input sample from copied scalar values.
---@param x integer|nil
---@param y integer|nil
---@param map_position {x: integer, y: integer, z: integer}|nil
---@return dwarfui.ContextMenuInputSample
local function immutable_sample(x, y, map_position)
    if not numbers.is_integer(x) or not numbers.is_integer(y) then
        x, y = nil, nil
    end
    local map_x, map_y, map_z
    if map_position and numbers.is_integer(map_position.x) and
            numbers.is_integer(map_position.y) and
            numbers.is_integer(map_position.z) then
        map_x = map_position.x
        map_y = map_position.y
        map_z = map_position.z
    end
    local values = {
        x=x,
        y=y,
        map_x=map_x,
        map_y=map_y,
        map_z=map_z,
    }
    return setmetatable({}, {
        __index=values,
        __newindex=function()
            error('DwarfUI context-menu input samples are immutable.', 2)
        end,
        __pairs=function()
            return next, values, nil
        end,
        __metatable=false,
    })
end

---Creates a synchronous context-menu input sampler.
---@param options? dwarfui.ContextMenuInputSamplerOptions
---@return dwarfui.ContextMenuInputSampler
function ContextMenuInputSampler.new(options)
    options = options or {}
    assert(type(options) == 'table',
        'DwarfUI context-menu input sampler options must be a table.')
    assert(options.sample_screen_pointer == nil or
            type(options.sample_screen_pointer) == 'function',
        'DwarfUI screen pointer sampler must be a function.')
    assert(options.sample_map_pointer == nil or
            type(options.sample_map_pointer) == 'function',
        'DwarfUI map pointer sampler must be a function.')
    assert(options.has_map_demand == nil or
            type(options.has_map_demand) == 'function',
        'DwarfUI map sampling demand predicate must be a function.')
    return setmetatable({
        _sample_screen_pointer=options.sample_screen_pointer or
            default_screen_sampler,
        _sample_map_pointer=options.sample_map_pointer or default_map_sampler,
        _has_map_demand=options.has_map_demand or no_map_demand,
    }, ContextMenuInputSampler)
end

---Captures one coherent screen/map sample for an opening input call.
---@return dwarfui.ContextMenuInputSample
function ContextMenuInputSampler:capture()
    local x, y = self._sample_screen_pointer()
    local map_position
    if self._has_map_demand() then
        map_position = self._sample_map_pointer()
    end
    return immutable_sample(x, y, map_position)
end
