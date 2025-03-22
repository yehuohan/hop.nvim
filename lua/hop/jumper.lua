---@alias Jumper fun(jump_target:JumpTarget, opts:Options) Operation on the jump target

local M = {}
local fn = vim.fn
local api = vim.api

--- Move cursor to jump target
---@param jump_target JumpTarget
---@param opts Options
function M.move_cursor(jump_target, opts)
    local jt = jump_target

    -- If it is pending for operator shift cursor.col to the right by 1
    if api.nvim_get_mode().mode == 'no' then
        jt.cursor.col = jt.cursor.col + 1
    end

    -- Update the jump list
    -- There is bug with set extmark neovim/neovim#17861
    api.nvim_set_current_win(jt.window)
    --local cursor = api.nvim_win_get_cursor(0)
    --api.nvim_buf_set_mark(jt.buffer, "'", cursor[1], cursor[2], {})
    vim.cmd("normal! m'")

    -- Note that nvim_win_set_cursor() only supports virtualedit=all
    -- Must set cursor with setpos() that supports virtualedit=insert/block
    --api.nvim_win_set_cursor(jt.window, { jt.cursor.row, jt.cursor.col + jt.cursor.off })
    fn.setpos('.', { jt.buffer, jt.cursor.row, jt.cursor.col + 1, jt.cursor.off })
    fn.winrestview({ curswant = fn.virtcol('.') - 1 })
end

return M
