--@ module=true

local M = {}

---@param text any
---@param width integer
---@return string[]
function M.wrap_text(text, width)
    local lines = {}
    local line = ''
    for word in tostring(text or ''):gmatch('%S+') do
        if line == '' then
            line = word
        elseif #line + 1 + #word <= width then
            line = line .. ' ' .. word
        else
            table.insert(lines, line)
            line = word
        end
    end
    if line ~= '' then table.insert(lines, line) end
    return #lines > 0 and lines or {''}
end

return M
