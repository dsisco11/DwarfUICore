local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

---Loads the resolver with deterministic generic pointer outcomes.
---@param outcomes table
---@return table resolver
local function load_resolver(outcomes)
    local pointer = {PointerResultKind={MISS=1, TARGET=2, BLOCKED=3},
        PointerDispatcher={resolve=function(root)
            local result = outcomes[root]
            if result == 'error' then error('uninspectable root') end
            return {kind=result}
        end}}
    local _, resolver = module_loader.load(repo_root,
        'src/scripts_modinstalled/dwarfuicore/input_event/ui_obstruction_resolver.lua', {
            reqscript={['dwarfuicore/pointer']=pointer}})
    return resolver.InputEventUiObstructionResolver
end

describe('Input Event UI obstruction resolution', function()
    it('permits semantic eligibility only for complete all-miss root inspection',
            function()
        local first, second = {}, {}
        local resolver = load_resolver({[first]=1, [second]=1})
        assert.is_true(resolver.is_unobstructed({first, second}, {x=1, y=2}))
    end)

    it('suppresses semantic eligibility for every obstructed or unknown root',
            function()
        local first, second = {}, {}
        for _, outcomes in ipairs({{[first]=2}, {[first]=3}, {[first]='error'}}) do
            local resolver = load_resolver(outcomes)
            assert.is_false(resolver.is_unobstructed({first}, {x=1, y=2}))
        end
        local resolver = load_resolver({[first]=1, [second]=1})
        assert.is_false(resolver.is_unobstructed(nil, {x=1, y=2}))
        assert.is_false(resolver.is_unobstructed({first, false}, {x=1, y=2}))
        assert.is_false(resolver.is_unobstructed({first}, nil))
    end)
end)
