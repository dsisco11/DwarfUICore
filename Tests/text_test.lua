local text = require('dwarfui.text')

describe('DwarfUI text helpers', function()
    it('wraps normal text at word boundaries', function()
        assert.same({'alpha beta', 'gamma'},
            text.wrap_text('alpha beta gamma', 10))
    end)

    it('keeps words intact at narrow widths', function()
        assert.same({'a', 'long', 'b'}, text.wrap_text('a long b', 1))
    end)

    it('returns one empty line for empty input', function()
        assert.same({''}, text.wrap_text(nil, 10))
        assert.same({''}, text.wrap_text('', 10))
        assert.same({''}, text.wrap_text('   \n\t', 10))
    end)

    it('normalizes source line breaks while producing multiple lines', function()
        assert.same({'one two', 'three', 'four'},
            text.wrap_text('one two\nthree four', 7))
    end)
end)
