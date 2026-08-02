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

        assert.is_truthy(info:find('[ID:dwarfuicore]', 1, true))
        assert.is_truthy(root:find('--@ module=true', 1, true))
    end)

    it('owns shared infrastructure under the dwarfuicore namespace', function()
        local shared_modules = {
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

        for _, relative_path in ipairs(shared_modules) do
            local source = read_source(
                'src/scripts_modinstalled/dwarfuicore/' .. relative_path)
            assert.is_truthy(source:find('--@ module=true', 1, true))
            assert.is_nil(source:find("reqscript('dwarfui/", 1, true))
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
            'api.lua',
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
            'api.lua',
            'definition.lua',
            'input_hook.lua',
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
end)
