                                              __
                                             / /_  ____  ____
                                            / __ \/ __ \/ __ \
                                           / / / / /_/ / /_/ /
                                          /_/ /_/\____/ .___/
                                                     /_/
                                      · Neovim motions on speed! ·

A fork & rewrite of [hop.nvim](https://github.com/phaazon/hop.nvim).

# Requirements

- Neovim >= 0.9.0


# Setup

With default configs:

```lua
{
    'yehuohan/hop.nvim',
    ---@type require('hop.config').Options
    opts = {
        --- Chars to generate hint lable for jump targets
        keys = 'asdghklqwertyuiopzxcvbnmfj',

        --- The char to quit hop operation
        key_quit = '<Esc>',

        --- The char to delete one inputed char and re-select hint lable for jump targets
        key_delete = '<Bs>',

        --- Extend match capabilities (For matcher._checkout_mappings and matcher.chars)
        --- Currently supported: { "zh", "zh_sc", "zh_tc", "fa" }
        match_mappings = {},

        --- Compute distance between cursors
        --- fun(a:Cursor, b:Cursor):number
        distance = require('hop.hinter').manhattan,

        --- Generate permutations from Options.keys
        --- fun(keys:string, n:integer):string[][]
        permute = require('hop.permutation').permute,

        --- Operation on the jump target
        --- fun(jump_target:JumpTarget, opts:Options)
        jump = require('hop.jumper').move_cursor,

        --- Change hint position among the matched string, 0.0 for left and 1.0 for right
        hint_position = 0.0,

        --- Reverse hint position to make shorter hint lables placed further
        hint_reverse = false,

        --- Setup highlights for ColorScheme event
        auto_setup_hl = true,

        --- Auto jump when there's only one jump target
        auto_jump_one_target = true,

        --- Work for current line only (current_window_only will be set true forcely)
        current_line_only = false,

        --- Work for current window only
        current_window_only = false,

        --- Exclude window via function
        --- fun(hwin, hbuf):boolean
        exclude_window = nil,
    }
}
```


# Features

- Support re-selecting jump target via `opts.key_delete`

```lua
{ key_delete = '<Bs>' }
```

<div align="center">
<img alt="Delete" src="README/delete.gif"  width=80% height=80% />
</div>

- Support `virtualedit`

```lua
vim.wo[0].virtualedit = 'all'
```

<div align="center">
<img alt="Virtualedit" src="README/virtualedit.gif"  width=80% height=80% />
</div>

- Support jump to any type characters (e.g. 中文字符) via `opts.match_mappings`

```lua
{ match_mappings = { 'zh', 'zh_sc' } }
```

<div align="center">
<img alt="Match Mappings" src="README/match_mappings.gif"  width=80% height=80% />
</div>

- Create/extend hop operations very easily

*With `require('hop').wrap` for a simple operation:*

```lua
local function hop_char2()
    local hop = require('hop')
    local matcher = require('hop.matcher')

    hop.echo('Hop 2 chars:', 'inp')
    local ok1, c1 = pcall(fn.getcharstr)
    if not ok1 then
        return
    end
    local ok2, c2 = pcall(fn.getcharstr)
    if not ok2 then
        return
    end

    require('hop').wrap(
        ---@type require('hop.matcher').Matcher
        matcher.by_regex(c1 .. c2, true, false),
        ---@type require('hop.config').Options
        {
            ---@type require('hop.jumper').Jumper
            jump = function(jt, opts)
                vim.api.nvim_set_current_win(jt.window)
                vim.fn.setpos('.', { jt.buffer, jt.cursor.row, jt.cursor.col + 1, jt.cursor.off })
                vim.fn.winrestview({ curswant = vim.fn.virtcol('.') - 1 })
            end,
        }
    )
end
```

*With `require('hop.hinter')` for a more powerful operation:*

```lua
local function custom()
    local hop = require('hop')
    local matcher = require('hop.matcher')
    local hinter = require('hop.hinter')

    local opts = hop.get_opts()
    local ht = hinter.new(opts) -- Create a hinter
    ---@type hinter.JumpTarget[]
    local jts = ht:collect(matcher.word) -- Collect jump targets

    -- Perform more processing on all matched jump targets here

    ---@type hinter.JumpTarget
    local jt = ht:select(jts) -- Select one jump target
    if jt then

        -- Perform more processing on the selected jump target here

        opts.jump(jt, opts) -- Jump to selected jump target
    end
end
```


# Operations

All operations from `hop = require('hop')` accept `require('hop.config').Options` to override global options,
and support motion and operator command, e.g. `vim.keymap.set('o', 's', '<Cmd>HopChar<CR>')`.

- `:HopChar`, `hop.char(opts)`: Jump to an any character
- `:HopWord`, `hop.word(opts)`: Jump to an any word start
- `:HopAnywhere`, `hop.anywhere(opts)`: Jump to anywhere
- `:HopLineStart`, `hop.line_start(opts)`: Jump to any line start with whitespace characters skipped
- `:HopVertical`, `hop.vertical(opts)`: Jump the any line with cursor column

> `:Hop<xxx>CL` means `{ current_line_only = true }`
>
> `:Hop<xxx>CW` means `{ current_window_only = true}`


# Highlights

- `HopNextKey`: Highlight the mono-sequence keys (i.e. sequence of 1)
- `HopNextKey1`: Highlight the first key in a sequence
- `HopNextKey2`: Highlight the second and remaining keys in a sequence
- `HopUnmatched`: Highlight unmatched part of the buffer
