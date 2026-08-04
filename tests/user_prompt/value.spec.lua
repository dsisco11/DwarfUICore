local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')

local _, namespace = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/service_provider/namespace.lua')
local _, value = module_loader.load(repo_root,
    'src/scripts_modinstalled/dwarfuicore/user_prompt/value.lua', {
        reqscript={
            ['dwarfuicore/service_provider/namespace']=namespace,
        },
    })

describe('UserPrompt immutable values', function()
    it('copies exact option text and accepts empty strings and newlines',
            function()
        local selected = function() end
        local cancelled = function() end
        local source = {
            title='',
            message='first\nsecond',
            on_select=selected,
            on_cancel=cancelled,
        }
        local options = value.MapLocationPromptOptions.new(source)

        source.title = 'changed'
        source.message = 'changed'
        source.on_select = function() end
        source.on_cancel = nil
        assert.equals('', options.title)
        assert.equals('first\nsecond', options.message)
        assert.equals(selected, options.on_select)
        assert.equals(cancelled, options.on_cancel)
        assert.is_true(value.MapLocationPromptOptions.is_instance(options))
        assert.has_error(function() options.title = 'changed' end,
            'DwarfUICore map-location prompt options is immutable.')
        assert.is_false(getmetatable(options))
    end)

    it('rejects every missing, extra, and mistyped option field', function()
        local callback = function() end
        for _, invalid in ipairs({
                nil,
                {},
                {title='title', message='message'},
                {title=false, message='message', on_select=callback},
                {title='title', message=false, on_select=callback},
                {title='title', message='message', on_select=false},
                {title='title', message='message', on_select=callback,
                    on_cancel=false},
                {title='title', message='message', on_select=callback,
                    namespace='spoofed'},
                {title='title', message='message', on_select=callback,
                    display_namespace='spoofed'},
                {[1]='title', title='title', message='message',
                    on_select=callback},
            }) do
            assert.has_error(function()
                value.MapLocationPromptOptions.new(invalid)
            end)
        end
    end)

    it('copies only the API-bound namespace into an immutable request',
            function()
        local selected = function() end
        local source = {title='Title', message='Message', on_select=selected}
        local options = value.MapLocationPromptOptions.new(source)
        local request = value.MapLocationPromptRequest.new('owner.plugin', options)

        source.title = 'Spoofed owner'
        assert.equals('owner.plugin', request.namespace)
        assert.equals('Title', request.title)
        assert.equals('Message', request.message)
        assert.equals(selected, request.on_select)
        assert.is_nil(request.on_cancel)
        assert.is_true(value.MapLocationPromptRequest.is_instance(request))
        assert.has_error(function() request.namespace = 'other' end,
            'DwarfUICore map-location prompt request is immutable.')

        local copied = value.MapLocationPromptRequest.copy(request)
        copied.namespace = 'mutated'
        copied.title = 'mutated'
        assert.equals('owner.plugin', request.namespace)
        assert.equals('Title', request.title)
    end)

    it('rejects invalid bound namespaces independently of prompt text',
            function()
        assert.has_error(function()
            value.MapLocationPromptRequest.new('Invalid Namespace', {
                title='Invalid Namespace',
                message='',
                on_select=function() end,
            })
        end)
    end)
end)
