local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local separator = package.config:sub(1, 1)

local _, registry = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/module_registry.lua')

---Reads one repository source file as binary text.
---@param relative_path string
---@return string
local function read_source(relative_path)
    local path = repo_root .. separator .. relative_path:gsub('/', separator)
    local file = assert(io.open(path, 'rb'))
    local text = file:read('*a')
    file:close()
    return text
end

---Returns whether one repository source file exists.
---@param relative_path string
---@return boolean exists
local function source_exists(relative_path)
    local path = repo_root .. separator .. relative_path:gsub('/', separator)
    local file = io.open(path, 'rb')
    if not file then return false end
    file:close()
    return true
end

describe('DwarfUICore package contract', function()
    it('declares the DwarfUICore mod identity and root module', function()
        local info = read_source('src/info.txt')
        local root = read_source('src/scripts_modinstalled/dwarfuicore.lua')
        local rockspec = read_source('dwarfuicore.rockspec')

        assert.is_truthy(info:find('[ID:dwarfuicore]', 1, true))
        assert.is_truthy(info:find('[NUMERIC_VERSION:3]', 1, true))
        assert.is_truthy(info:find('[DISPLAYED_VERSION:0.3.0]', 1, true))
        assert.is_truthy(rockspec:find('version = "0.3.0-1"', 1, true))
        assert.is_truthy(rockspec:find('tag = "v0.3.0"', 1, true))
        assert.is_truthy(root:find('--@ module=true', 1, true))
    end)

    it('documents the complete public UserPrompt contract', function()
        local readme = read_source('README.md')
        for _, required in ipairs({
                'UserPromptServiceProvider:new(1, \'my-plugin\')',
                'prompt_map_location',
                'position_or_nil',
                'SERVICE_BUSY',
                'top center of the window border',
                'consumer-provided line inside the window',
                'left and right mouse-down events are consumed',
                'No context menu can open',
                'Ordinary tooltip state remains',
                'native map-tile indicator',
                'surface or world loss',
                'Prompt handles and APIs become stale',
            }) do
            assert.is_truthy(readme:find(required, 1, true), required)
        end
    end)

    it('owns shared infrastructure under the dwarfuicore namespace', function()
        local shared_modules = {
            'class.lua',
            'map_projection.lua',
            'pointer.lua',
            'text.lua',
            'view_root_resolver.lua',
            'widget_extensions.lua',
            'utils/function_chain.lua',
            'utils/immutable_enum.lua',
            'utils/numbers.lua',
            'service_provider/contracts.lua',
            'service_provider/namespace.lua',
            'service_provider/immutable_proxy.lua',
            'service_provider/identity.lua',
            'input_event/types.lua',
            'input_event/snapshot_factory.lua',
            'input_event/pointer_poller.lua',
            'input_event/service.lua',
            'input_event/input_hook.lua',
            'service_provider/runtime.lua',
            'service_provider/acquisition.lua',
            'service_provider/api.lua',
            'service_provider/tooltip_adapter_v1.lua',
            'service_provider/context_menu_adapter_v1.lua',
            'service_provider/user_prompt_adapter_v1.lua',
            'service_provider/input_event_adapter_v1.lua',
            'service_provider/tooltip_provider.lua',
            'service_provider/context_menu_provider.lua',
            'service_provider/user_prompt_provider.lua',
            'service_provider/input_event_provider.lua',
            'service_provider/weak_store.lua',
            'services.lua',
        }

        for _, relative_path in ipairs(shared_modules) do
            local source = read_source(
                'src/scripts_modinstalled/dwarfuicore/' .. relative_path)
            assert.is_truthy(source:find('--@ module=true', 1, true))
            assert.is_nil(source:find("reqscript('dwarfui/", 1, true))
        end
    end)

    it('owns the complete UserPrompt implementation under dwarfuicore',
            function()
        for _, relative_path in ipairs({
                'value.lua', 'indicator.lua', 'input_consumer.lua',
                'renderer.lua', 'service.lua', 'runtime.lua'}) do
            local source = read_source(
                'src/scripts_modinstalled/dwarfuicore/user_prompt/' ..
                    relative_path)
            assert.is_truthy(source:find('--@ module=true', 1, true))
        end
    end)

    it('does not retain shared infrastructure under the dwarfui namespace',
            function()
        local legacy_modules = {
            'class.lua',
            'map_projection.lua',
            'pointer_poller.lua',
            'pointer.lua',
            'text.lua',
            'view_root_resolver.lua',
            'widget_extensions.lua',
            'utils/function_chain.lua',
            'utils/immutable_enum.lua',
            'utils/numbers.lua',
        }

        for _, relative_path in ipairs(legacy_modules) do
            local path = repo_root .. separator ..
                ('src/scripts_modinstalled/dwarfui/' .. relative_path):gsub(
                    '/', separator)
            local file = io.open(path, 'rb')
            if file then file:close() end
            assert.is_nil(file)
        end
    end)

    it('owns the current tooltip implementation under dwarfuicore', function()
        local tooltip_modules = {
            'map_target.lua',
            'presenter.lua',
            'registration.lua',
            'render_hook.lua',
            'renderer.lua',
            'runtime.lua',
            'service.lua',
            'target_detector.lua',
            'target.lua',
        }

        for _, relative_path in ipairs(tooltip_modules) do
            local source = read_source(
                'src/scripts_modinstalled/dwarfuicore/tooltip/' ..
                    relative_path)
            assert.is_truthy(source:find('--@ module=true', 1, true))
            assert.is_nil(source:find("reqscript('dwarfui/tooltip/", 1, true))

            local legacy_path = repo_root .. separator ..
                ('src/scripts_modinstalled/dwarfui/tooltip/' ..
                    relative_path):gsub('/', separator)
            local legacy_file = io.open(legacy_path, 'rb')
            if legacy_file then legacy_file:close() end
            assert.is_nil(legacy_file)
        end
    end)

    it('owns the current context-menu implementation under dwarfuicore',
            function()
        local context_menu_modules = {
            'definition.lua',
            
            'input_sample.lua',
            'map_target.lua',
            'registration.lua',
            'renderer.lua',
            'root_discovery.lua',
            'screen.lua',
            'service.lua',
            'target_detector.lua',
            'target.lua',
        }

        for _, relative_path in ipairs(context_menu_modules) do
            local source = read_source(
                'src/scripts_modinstalled/dwarfuicore/context_menu/' ..
                    relative_path)
            assert.is_truthy(source:find('--@ module=true', 1, true))
            assert.is_nil(source:find(
                "reqscript('dwarfui/context_menu/", 1, true))

            local legacy_path = repo_root .. separator ..
                ('src/scripts_modinstalled/dwarfui/context_menu/' ..
                    relative_path):gsub('/', separator)
            local legacy_file = io.open(legacy_path, 'rb')
            if legacy_file then legacy_file:close() end
            assert.is_nil(legacy_file)
        end
    end)

    it('ships one authoritative native input-hook owner', function()
        local owners = {}
        for _, spec in ipairs(registry.MODULES) do
            local source = read_source(
                'src/scripts_modinstalled/' .. spec.name .. '.lua')
            if source:find('feed_viewscreen_widgets', 1, true) then
                table.insert(owners, spec.name)
            end
        end
        assert.same({'dwarfuicore/input_event/input_hook'}, owners)
        assert.is_false(source_exists(
            'src/scripts_modinstalled/dwarfuicore/user_prompt/input_hook.lua'))
    end)

    it('keeps the context-menu hook as a private compatibility export',
            function()
        local source = read_source(
            'src/scripts_modinstalled/dwarfuicore/context_menu/input_hook.lua')
        assert.is_truthy(source:find('--@ module=true', 1, true))
        assert.is_truthy(source:find(
            "reqscript('dwarfuicore/input_event/input_hook')", 1, true))
        assert.is_nil(source:find('feed_viewscreen_widgets', 1, true))
    end)

    it('does not retain direct context-menu input sampling ownership', function()
        local source = read_source(
            'src/scripts_modinstalled/dwarfuicore/context_menu/service.lua')
        assert.is_nil(source:find("context_menu/input_sample", 1, true))
        assert.is_nil(source:find('_sampler', 1, true))
    end)

    it('ships one authoritative completed-render hook owner', function()
        local owners = {}
        for _, spec in ipairs(registry.MODULES) do
            local source = read_source(
                'src/scripts_modinstalled/' .. spec.name .. '.lua')
            if source:find('render_viewscreen_widgets', 1, true) then
                table.insert(owners, spec.name)
            end
        end
        assert.same({'dwarfuicore/tooltip/render_hook'}, owners)
        assert.is_false(source_exists(
            'src/scripts_modinstalled/dwarfuicore/user_prompt/render_hook.lua'))
    end)

    it('ships every registered Core module and no DwarfUI feature module',
            function()
        assert.is_true(source_exists('src/info.txt'))
        assert.is_true(source_exists(
            'src/scripts_modinstalled/dwarfuicore.lua'))
        for _, spec in ipairs(registry.MODULES) do
            assert.is_true(source_exists(
                'src/scripts_modinstalled/' .. spec.name .. '.lua'),
                spec.name .. ' is missing from the DwarfUICore package source')
        end

        for _, feature in ipairs({
                'dwarfui-minecart-route-markers.lua',
                'dwarfui-mood-popover.lua',
                'dwarfui-ui-hotkeys.lua',
                'dwarfui-unit-card-task-details.lua',
                'dwarfui/minecart_route.lua',
                'dwarfui/mood_popover.lua',
                'dwarfui/popover.lua',
                'dwarfui/ui_hotkeys.lua'}) do
            assert.is_false(source_exists(
                'src/scripts_modinstalled/' .. feature))
        end
    end)

    it('separates the command root from the public services module', function()
        local root = read_source('src/scripts_modinstalled/dwarfuicore.lua')
        local services = read_source(
            'src/scripts_modinstalled/dwarfuicore/services.lua')
        assert.is_nil(root:find('TooltipServiceProvider', 1, true))
        assert.is_nil(root:find('ContextMenuServiceProvider', 1, true))
        assert.is_truthy(services:find('TooltipServiceProvider', 1, true))
        assert.is_truthy(services:find('ContextMenuServiceProvider', 1, true))
        assert.is_truthy(services:find('UserPromptServiceProvider', 1, true))
        assert.is_truthy(services:find('InputEventServiceProvider', 1, true))
        assert.is_nil(root:find('UserPromptServiceProvider', 1, true))
        assert.is_nil(services:find('function get(', 1, true))
        assert.is_nil(services:find('get_diagnostics', 1, true))
    end)

    it('does not ship replaced direct APIs or a compatibility namespace',
            function()
        for _, relative_path in ipairs({
                'dwarfuicore/tooltip/api.lua',
                'dwarfuicore/context_menu/api.lua',
            }) do
            assert.is_false(source_exists('src/scripts_modinstalled/' ..
                relative_path))
        end

        local readme = read_source('README.md')
        local proposal = read_source('Docs/service-provider-api-proposal.md')
        assert.is_nil(readme:find('dwarfuicore/tooltip/api', 1, true))
        assert.is_nil(readme:find('dwarfuicore/context_menu/api', 1, true))
        assert.is_truthy(proposal:find(
            'No compatibility adapter or legacy namespace is shipped.',
            1, true))
    end)
end)
