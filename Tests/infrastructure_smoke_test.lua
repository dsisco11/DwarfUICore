local luaunit = require('luaunit')
local module_loader = require('support.module_loader')
local repo_root = require('support.repo_root')
local widget_harness = require('support.widget_harness')

local tests = {}

function tests:setUp()
    self.setup_completed = true
end

function tests:test_luaunit_setup_root_and_discovery()
    luaunit.assertTrue(self.setup_completed)
    luaunit.assertNotNil(luaunit)

    local todo = assert(io.open(
        repo_root .. '/Docs/tooltip-system-port.todo', 'r'))
    todo:close()

    local files = assert(os.getenv('DFHACK_LUA_TEST_FILES'),
        'runner did not provide discovered test files')
    luaunit.assertStrContains(files, 'infrastructure_smoke_test.lua')
    luaunit.assertNotStrContains(files, 'Tests\\support\\module_loader.lua')
    luaunit.assertNotStrContains(files, 'Tests/support/module_loader.lua')
    luaunit.assertNotStrContains(files, 'Tests\\run.lua')
    luaunit.assertNotStrContains(files, 'Tests/run.lua')
end

function tests:test_module_loader_isolates_globals_and_dependencies()
    luaunit.assertNil(rawget(_G, 'GLOBAL_OFFSET'))
    luaunit.assertNil(rawget(_G, 'result'))

    local environment, returned = module_loader.load(
        repo_root,
        'Tests/fixtures/module_target.lua',
        {
            globals={GLOBAL_OFFSET=4},
            reqscript={['fixture/scripted']={value=2}},
            require_modules={['fixture.required']={value=3}},
        })

    luaunit.assertEquals(9, environment.result)
    luaunit.assertEquals(9, returned.result)
    luaunit.assertNil(rawget(_G, 'GLOBAL_OFFSET'))
    luaunit.assertNil(rawget(_G, 'result'))
end

function tests:test_module_loader_rejects_uncontrolled_reqscript()
    local ok, err = pcall(module_loader.load,
        repo_root,
        'Tests/fixtures/module_target.lua',
        {
            globals={GLOBAL_OFFSET=4},
            reqscript={},
            require_modules={['fixture.required']={value=3}},
        })

    luaunit.assertFalse(ok)
    luaunit.assertStrContains(tostring(err),
        'unexpected reqscript: fixture/scripted')
end

function tests:test_widget_harness_models_tooltip_primitives()
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

    luaunit.assertEquals('pass', panel.pointer_policy)
    luaunit.assertEquals('target', button.pointer_policy)
    luaunit.assertTrue(button.visible)
    luaunit.assertEquals('Action tooltip', button.tooltip)
    luaunit.assertIs(panel, button.parent_view)
    luaunit.assertIs(button, panel.subviews.action)
    luaunit.assertEquals({3, 2}, {button.frame_body.x1, button.frame_body.y1})
    luaunit.assertTrue(button.frame_body:inClipGlobalXY(3, 2))
    luaunit.assertFalse(button.frame_body:inClipGlobalXY(8, 2))
    luaunit.assertEquals({1, 1}, {button.frame_body:localXY(4, 3)})
    luaunit.assertEquals(10, overflow.frame_body.x2)
    luaunit.assertEquals(8, overflow.frame_body.clip_x2)
    luaunit.assertTrue(overflow.frame_body:inClipGlobalXY(8, 4))
    luaunit.assertFalse(overflow.frame_body:inClipGlobalXY(9, 4))

    root:render({})
    luaunit.assertEquals(1, root.render_count)
    luaunit.assertEquals(1, panel.render_count)
    luaunit.assertEquals(1, button.render_count)
    luaunit.assertEquals(1, overflow.render_count)
    root:invalidate()
    luaunit.assertEquals(1, root.invalidation_count)

    local Tooltip = widget_harness.defclass(nil, widgets.Widget)
    Tooltip.ATTRS{tooltip='Default tooltip'}
    function Tooltip:init()
        self:addviews{widgets.Label{view_id='text', text='Tooltip body'}}
    end
    local tooltip = Tooltip{frame={l=0, t=0, w=6, h=2}}
    luaunit.assertEquals('Default tooltip', tooltip.tooltip)
    luaunit.assertEquals('Tooltip body', tooltip.subviews.text.text)
    luaunit.assertIs(tooltip, tooltip.subviews.text.parent_view)
end

function tests:test_opt_in_failure_path()
    if os.getenv('DWARFUI_LUAUNIT_SMOKE_FORCE_FAILURE') == '1' then
        luaunit.assertEquals('actual value', 'expected value',
            'intentional LuaUnit smoke failure')
    end
end

return tests
