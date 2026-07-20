rockspec_format = "3.0"

package = "dwarfui"
version = "0.1.0-1"

source = {
    url = "git+https://github.com/dsisco11/DwarfUI.git",
    tag = "v0.1.0",
}

description = {
    summary = "Reusable DFHack user-interface infrastructure.",
    detailed = [[
DwarfUI provides reusable DFHack UI modules and user-facing interface
enhancements. DwarfSpec is declared only as a development test dependency.
]],
    homepage = "https://github.com/dsisco11/DwarfUI",
    license = "MIT",
}

dependencies = {
    "lua >= 5.3",
}

test_dependencies = {
    "dwarfspec ~> 0.1",
}

build = {
    type = "none",
}
