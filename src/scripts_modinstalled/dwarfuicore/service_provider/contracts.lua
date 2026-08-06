--@ module=true

local immutable_enum = reqscript('dwarfuicore/utils/immutable_enum')

---@enum dwarfuicore.ServiceKind
ServiceKind = immutable_enum.define({
    TOOLTIP=1,
    CONTEXT_MENU=2,
    USER_PROMPT=3,
    INPUT_EVENT=4,
}, 'ServiceKind')
---@enum dwarfuicore.RuntimeStatus
RuntimeStatus = immutable_enum.define({INITIALIZING=1, HEALTHY=2, DISABLED=3,
    RETIRING=4, RETIRED=5}, 'RuntimeStatus')
---@enum dwarfuicore.ServiceHealth
ServiceHealth = immutable_enum.define({MISSING=1, INITIALIZING=2, HEALTHY=3,
    UNHEALTHY=4, DISABLED=5}, 'ServiceHealth')
---@enum dwarfuicore.ErrorCategory
ErrorCategory = immutable_enum.define({
    INVALID_VERSION=1, UNSUPPORTED_VERSION=2, INVALID_NAMESPACE=3,
    SERVICE_UNHEALTHY=4, INITIALIZATION_BUSY=5, INITIALIZATION_FAILED=6,
    STALE_API=7, INVALID_ARGUMENT=8, FOREIGN_HANDLE=9, STALE_HANDLE=10,
    SERVICE_BUSY=11,
}, 'ErrorCategory')

local ERROR_TOKEN_BY_CATEGORY = {
    [ErrorCategory.INVALID_VERSION]='INVALID_VERSION',
    [ErrorCategory.UNSUPPORTED_VERSION]='UNSUPPORTED_VERSION',
    [ErrorCategory.INVALID_NAMESPACE]='INVALID_NAMESPACE',
    [ErrorCategory.SERVICE_UNHEALTHY]='SERVICE_UNHEALTHY',
    [ErrorCategory.INITIALIZATION_BUSY]='INITIALIZATION_BUSY',
    [ErrorCategory.INITIALIZATION_FAILED]='INITIALIZATION_FAILED',
    [ErrorCategory.STALE_API]='STALE_API',
    [ErrorCategory.INVALID_ARGUMENT]='INVALID_ARGUMENT',
    [ErrorCategory.FOREIGN_HANDLE]='FOREIGN_HANDLE',
    [ErrorCategory.STALE_HANDLE]='STALE_HANDLE',
    [ErrorCategory.SERVICE_BUSY]='SERVICE_BUSY',
}

---Returns the stable public token for an internal error category.
---@param category integer
---@return string token
function get_error_token(category)
    local token = ERROR_TOKEN_BY_CATEGORY[category]
    assert(token, 'DwarfUICore error category is not mapped.')
    return token
end

---Returns the number of stable public error categories.
---@return integer count
function get_error_category_count()
    local count = 0
    for _ in pairs(ERROR_TOKEN_BY_CATEGORY) do count = count + 1 end
    return count
end
