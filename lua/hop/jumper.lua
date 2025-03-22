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

--- Move multicursor to jump target
---@param jump_target JumpTarget
---@param opts Options
function M.move_multicursor(jump_target, opts)
    local mc = require('multicursor-nvim')
    local jt = jump_target
    local jt_cur = jt.cursor

    mc.action(function(ctx)
        local curs = ctx:getCursors()
        local main_cur = ctx:mainCursor()
        local main_pos = main_cur:getPos()
        local drow = jt_cur.row - main_pos[1]
        local dcol = jt_cur.col - main_pos[2] + 1
        local doff = jt_cur.off - main_pos[3]
        for _, cur in ipairs(curs) do
            local pos = cur:getPos()
            cur:setPos({ pos[1] + drow, pos[2] + dcol, pos[3] + doff })
        end
    end)

    M.move_cursor(jt, opts)
end

return M
