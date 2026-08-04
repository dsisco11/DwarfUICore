--@ module=true

local acquisition = reqscript('dwarfuicore/service_provider/acquisition')
local api = reqscript('dwarfuicore/service_provider/api')
local contracts = reqscript('dwarfuicore/service_provider/contracts')
local immutable_proxy = reqscript('dwarfuicore/service_provider/immutable_proxy')

local API_FACTORY = api.new_factory(contracts.ServiceKind.USER_PROMPT,
    'UserPromptServiceApi', {'prompt_map_location', 'cancel', 'is_active',
        'clear_namespace'})

---Creates namespace-bound UserPrompt APIs for the exact supported contract.
---@class dwarfuicore.UserPromptServiceProvider
---@field new fun(self: dwarfuicore.UserPromptServiceProvider, contract_version: integer, consumer_namespace: string): dwarfuicore.UserPromptServiceApi

---Loads the private UserPrompt adapter only after constructor validation.
---@return dwarfuicore.ServiceAcquisitionAdapter adapter
local function load_adapter()
    return reqscript('dwarfuicore/service_provider/user_prompt_adapter_v1')
end

local provider_factory
local methods = {}

---Creates a distinct immutable UserPrompt API for one namespace contract.
---@param self table
---@param contract_version integer
---@param consumer_namespace string
---@return dwarfuicore.UserPromptServiceApi
function methods:new(contract_version, consumer_namespace)
    assert(provider_factory:is_instance(self),
        'DwarfUICore UserPromptServiceProvider receiver is invalid.')
    local metadata = acquisition.acquire(contracts.ServiceKind.USER_PROMPT, 1,
        load_adapter, contract_version, consumer_namespace, true)
    return API_FACTORY:create(metadata)
end

provider_factory = immutable_proxy.new_factory(
    'UserPromptServiceProvider', methods)

---Returns the one immutable public UserPrompt provider export.
---@return dwarfuicore.UserPromptServiceProvider provider
function get_provider()
    return provider_factory:create({})
end

