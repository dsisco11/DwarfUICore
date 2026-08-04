rockspec_format = "3.0"

package = "dwarfuicore"
version = "0.3.0-1"

source = {
    url = "git+https://github.com/dsisco11/DwarfUICore.git",
    tag = "v0.3.0",
}

description = {
    summary = "Reusable DFHack UI runtime infrastructure.",
    detailed = [[
DwarfUICore provides reusable process-wide tooltip, context-menu, map-location
prompt, pointer, and widget-extension infrastructure for DFHack Lua plugins.
]],
    homepage = "https://github.com/dsisco11/DwarfUICore",
    license = "MIT",
}

dependencies = {
    "lua >= 5.3",
}

test_dependencies = {
    "dwarfspec >= 0.2.0",
}

build = {
    type = "none",
}
