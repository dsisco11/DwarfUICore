--@ module=true

local scripted = reqscript('fixture/scripted')
local required = require('fixture.required')

result = scripted.value + required.value + GLOBAL_OFFSET

return {result=result}
