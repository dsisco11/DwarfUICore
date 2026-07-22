local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local function contains(text, expected)
    assert.is_truthy(text:find(expected, 1, true))
end

local function excludes(text, unexpected)
    assert.is_nil(text:find(unexpected, 1, true))
end

describe('Busted test infrastructure', function()
    local setup_completed

    before_each(function()
        setup_completed = true
    end)

    it('runs setup and sees deterministic discovery', function()
        assert.is_true(setup_completed)

        local files = assert(os.getenv('LUA_TEST_FILES'),
            'runner did not provide discovered test files')
        contains(files, 'infrastructure_smoke_test.lua')
        excludes(files, 'tests\\support\\module_loader.lua')
        excludes(files, 'tests/support/module_loader.lua')
        excludes(files, 'tests\\run.lua')
        excludes(files, 'tests/run.lua')
    end)

    it('isolates module globals and dependencies', function()
        assert.is_nil(rawget(_G, 'GLOBAL_OFFSET'))
        assert.is_nil(rawget(_G, 'result'))

        local environment, returned = module_loader.load(
            repo_root,
            'tests/fixtures/module_target.lua',
            {
                globals={GLOBAL_OFFSET=4},
                reqscript={['fixture/scripted']={value=2}},
                require_modules={['fixture.required']={value=3}},
            })

        assert.equals(9, environment.result)
        assert.equals(9, returned.result)
        assert.is_nil(rawget(_G, 'GLOBAL_OFFSET'))
        assert.is_nil(rawget(_G, 'result'))
    end)

    it('rejects an uncontrolled reqscript', function()
        local ok, err = pcall(module_loader.load,
            repo_root,
            'tests/fixtures/module_target.lua',
            {
                globals={GLOBAL_OFFSET=4},
                reqscript={},
                require_modules={['fixture.required']={value=3}},
            })

        assert.is_false(ok)
        contains(tostring(err), 'unexpected reqscript: fixture/scripted')
    end)

    it('models the tooltip widget primitives', function()
        local default_nil = widget_harness.default_nil()
        local widgets = widget_harness.widgets(nil, default_nil)
        widgets.Widget.ATTRS{visible=true, active=true, tooltip=default_nil}
        widgets.Panel.ATTRS{pointer_policy='pass'}
        widgets.TextButton.ATTRS{pointer_policy='target'}

        local button = widgets.TextButton{
            view_id='action',
            frame={l=2, t=1, w=4, h=2},
            tooltip='Action tooltip',
        }
        local overflow = widgets.Label{
            view_id='overflow',
            frame={l=6, t=3, w=4, h=1},
        }
        local panel = widgets.Panel{
            frame={l=1, t=1, w=8, h=5},
            subviews={button, overflow},
        }
        local root = widgets.Widget{frame={l=0, t=0, w=12, h=8}}
        root:addviews{panel}
        root:updateLayout(widget_harness.rect(0, 0, 12, 8))

        assert.equals('pass', panel.pointer_policy)
        assert.equals('target', button.pointer_policy)
        assert.is_true(button.visible)
        assert.equals('Action tooltip', button.tooltip)
        assert.is.equal(panel, button.parent_view)
        assert.is.equal(button, panel.subviews.action)
        assert.same({3, 2}, {button.frame_body.x1, button.frame_body.y1})
        assert.is_true(button.frame_body:inClipGlobalXY(3, 2))
        assert.is_false(button.frame_body:inClipGlobalXY(8, 2))
        assert.same({1, 1}, {button.frame_body:localXY(4, 3)})
        assert.equals(10, overflow.frame_body.x2)
        assert.equals(8, overflow.frame_body.clip_x2)
        assert.is_true(overflow.frame_body:inClipGlobalXY(8, 4))
        assert.is_false(overflow.frame_body:inClipGlobalXY(9, 4))

        root:render({})
        assert.equals(1, root.render_count)
        assert.equals(1, panel.render_count)
        assert.equals(1, button.render_count)
        assert.equals(1, overflow.render_count)
        root:invalidate()
        assert.equals(1, root.invalidation_count)

        local Tooltip = widget_harness.defclass(nil, widgets.Widget)
        Tooltip.ATTRS{tooltip='Default tooltip'}
        function Tooltip:init()
            self:addviews{widgets.Label{
                view_id='text', text='Tooltip body'}}
        end
        local tooltip = Tooltip{frame={l=0, t=0, w=6, h=2}}
        assert.equals('Default tooltip', tooltip.tooltip)
        assert.equals('Tooltip body', tooltip.subviews.text.text)
        assert.is.equal(tooltip, tooltip.subviews.text.parent_view)
    end)

    it('exposes a deliberate failure path', function()
        if os.getenv('LUA_TEST_FORCE_FAILURE') == '1' then
            assert.equals('expected value', 'actual value',
                'intentional Busted smoke failure')
        end
    end)
end)
