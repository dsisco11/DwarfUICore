local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local _, immutable_enum = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/utils/immutable_enum.lua')
local _, contracts = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/contracts.lua', {
        reqscript={['dwarfuicore/utils/immutable_enum']=immutable_enum},
    })

describe('service-provider internal contracts', function()
    it('defines immutable numeric closed state sets', function()
        assert.equals(1, contracts.ServiceKind.TOOLTIP)
        assert.equals(2, contracts.ServiceKind.CONTEXT_MENU)
        assert.equals(3, contracts.ServiceKind.USER_PROMPT)
        assert.equals(5, contracts.RuntimeStatus.RETIRED)
        assert.equals(3, contracts.ServiceHealth.HEALTHY)
        for _, enum in ipairs({contracts.ServiceKind, contracts.RuntimeStatus,
                contracts.ServiceHealth, contracts.ErrorCategory}) do
            assert.has_error(function() enum.NEW_VALUE = 99 end)
        end
    end)

    it('maps every error category to one unique approved token', function()
        local expected = {
            INVALID_VERSION=true, UNSUPPORTED_VERSION=true,
            INVALID_NAMESPACE=true, SERVICE_UNHEALTHY=true,
            INITIALIZATION_BUSY=true, INITIALIZATION_FAILED=true,
            STALE_API=true, INVALID_ARGUMENT=true, FOREIGN_HANDLE=true,
            STALE_HANDLE=true,
            SERVICE_BUSY=true,
        }
        local actual = {}
        local count = 0
        for _, category in pairs(contracts.ErrorCategory) do
            local token = contracts.get_error_token(category)
            assert.is_nil(actual[token], token)
            actual[token] = true
            count = count + 1
        end
        assert.same(expected, actual)
        assert.equals(count, contracts.get_error_category_count())
        assert.has_error(function() contracts.get_error_token(999) end,
            'DwarfUICore error category is not mapped.')
    end)
end)
