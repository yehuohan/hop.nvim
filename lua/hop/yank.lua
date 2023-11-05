local M = {}

--- yanks the text to specified register
---@param text string[]
---@param register string
M.yank_to = function(text, register)
  vim.fn.setreg(register, text)
end

--- yanks the text to specified register
---@param register string
---@param target JumpTarget
M.paste_from = function(target, register)
  local text = vim.fn.getreg(register)
  if text == '' then
    return
  end

  local replacement = vim.split(text, '\n', { trimempty = true })
  vim.api.nvim_buf_set_text(
    target.buffer,
    target.cursor.row - 1,
    target.cursor.col + 1,
    target.cursor.row - 1,
    target.cursor.col + 1,
    replacement
  )
end

--- checks the range bounds and when end is before the start swaps theme
---@param start_range JumpTarget
---@param end_range JumpTarget
---@return JumpTarget,JumpTarget
local function check_bounds(start_range, end_range)
  if start_range.cursor.row < end_range.cursor.row then
    return start_range, end_range
  elseif start_range.cursor.row == end_range.cursor.row and start_range.cursor.col <= end_range.cursor.col then
    return start_range, end_range
  end
  return end_range, start_range
end

--- returns the text in the range for current buffer
---@param start_range JumpTarget
---@param end_range JumpTarget
---@return string[]
M.get_text = function(start_range, end_range)
  start_range, end_range = check_bounds(start_range, end_range)
  return vim.api.nvim_buf_get_text(
    0,
    start_range.cursor.row - 1,
    start_range.cursor.col,
    end_range.cursor.row - 1,
    end_range.cursor.col + 1,
    {}
  )
end

return M
