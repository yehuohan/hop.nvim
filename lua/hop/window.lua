---@alias WindowRow number 1-based line row at window
---@alias WindowCol number 0-based column at window, also as string byte index
---@alias WindowColRange WindowCol[] window column range with [start-inclusive, end-exclusive)
---@alias WindowCell number 0-based displayed cell column at window; often computed via `strdisplaywidth()`
---@alias WindowChar number 0-based character index at string
-- For multi-byte character, there may be WindowCol ~= WindowCell ~= WindowChar like below showed
-- LineString:   a #### b     => '##' is a 4-bytes character takes 2-cells
-- WindowCol     0 1234 5
-- WindowCell:   0 1 2  3
-- WindowChar:   0 1    2
--
-- Infos for some neovim api:
-- * 1-based line, 0-based-column: nvim_win_get_cursor, nvim_win_set_cursor
-- * 0-based line, end-exclusive: nvim_buf_get_lines
-- * 0-based line, end-inclusive; 0-based column, end-exclusive: nvim_buf_set_extmark
-- * 1-based line: foldclosedend
-- * 0-based character index: charidx, strcharpart
-- * 0-based byte index: byteidx, strpart

---@class CursorPos
---@field row WindowRow
---@field col WindowCol

---@class LineRange
---@field top WindowRow inclusive
---@field bot WindowRow inclusive

---@class LineContext
---@field line_row WindowRow
---@field line string

---@class WindowContext
---@field win_handle number
---@field buf_handle number
---@field cursor CursorPos
---@field line_range LineRange
---@field win_width WindowCell Window cell width excluding fold, sign and number columns
---@field col_offset WindowCell First cell column displayed (also is the cell number hidden to window left)
---@field col_first WindowCell Cursor cell column relative to the first cell column displayed

local M = {}

-- Convert WindowRow to extmark line
---@param row WindowRow
function M.row2extmark(row)
  return row - 1
end

-- Convert WindowCol to extmark column
---@param col WindowCol
function M.col2extmark(col)
  return col
end

-- Convert CursorPos to extmark position
---@param pos CursorPos
function M.pos2extmark(pos)
  return pos.row - 1, pos.col
end

-- Get the character index at the window column
---@param line string
---@param cell WindowCell
---@return WindowChar
function M.cell2char(line, cell)
  if cell <= 0 then
    return 0
  end

  local line_width = vim.fn.strdisplaywidth(line)
  local line_chars = vim.fn.strchars(line)
  -- No multi-byte character
  if line_width == line_chars then
    return cell
  end
  -- Line is shorter than cell, all line should include
  if line_width <= cell then
    return line_chars
  end

  local lst
  -- Line is very long
  if line_chars >= cell then
    -- Split the line to individual characters
    lst = vim.fn.split(vim.fn.strcharpart(line, 0, cell), '\\zs')
  else
    lst = vim.fn.split(line, '\\zs')
  end
  local i, w = 0, 0
  repeat
    i = i + 1
    w = w + vim.fn.strdisplaywidth(lst[i])
  until w >= cell
  return i
end

-- Get information about the window and the cursor
---@param win_handle number
---@param buf_handle number
---@return WindowContext
local function window_context(win_handle, buf_handle)
  local win_info = vim.fn.getwininfo(win_handle)[1]
  local win_view = vim.api.nvim_win_call(win_handle, vim.fn.winsaveview)
  local cursor_pos = vim.api.nvim_win_get_cursor(win_handle)
  local cursor = { row = cursor_pos[1], col = cursor_pos[2] }
  local win_width = nil
  if not vim.wo.wrap then
    win_width = win_info.width - win_info.textoff
  end
  local cursor_line = vim.api.nvim_buf_get_lines(buf_handle, cursor.row - 1, cursor.row, false)[1]
  local col_first = vim.fn.strdisplaywidth(cursor_line:sub(1, cursor.col)) - win_view.leftcol

  return {
    win_handle = win_handle,
    buf_handle = buf_handle,
    cursor = cursor,
    line_range = { top = win_info.topline, bot = win_info.botline },
    win_width = win_width,
    col_offset = win_view.leftcol,
    col_first = col_first,
  }
end

-- Get current window context or all visible windows context in multiwindow mode
---@param opts Options
---@return WindowContext[]
function M.get_window_context(opts)
  ---@type WindowContext[]
  local contexts = {}

  -- Generate contexts of windows
  local cur_hwin = vim.api.nvim_get_current_win()
  local cur_hbuf = vim.api.nvim_win_get_buf(cur_hwin)

  contexts[1] = window_context(cur_hwin, cur_hbuf)

  if not opts.multi_windows then
    return contexts
  end

  -- Get the context for all the windows in current tab
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(w) and vim.api.nvim_win_get_config(w).relative == '' then
      local b = vim.api.nvim_win_get_buf(w)

      -- Skips current window and excluded filetypes
      if not (w == cur_hwin or vim.tbl_contains(opts.excluded_filetypes, vim.bo[b].filetype)) then
        contexts[#contexts + 1] = window_context(w, b)
      end
    end
  end

  return contexts
end

-- Collect visible and unfold lines of window context
---@param context WindowContext
---@return LineContext[]
function M.get_lines_context(context)
  ---@type LineContext[]
  local lines = {}

  local lnr = context.line_range.top
  while lnr <= context.line_range.bot do
    local fold_end = vim.api.nvim_win_call(context.win_handle, function()
      return vim.fn.foldclosedend(lnr)
    end)
    -- Skip folded lines
    if fold_end == -1 then
      lines[#lines + 1] = {
        line_row = lnr,
        line = vim.api.nvim_buf_get_lines(context.buf_handle, lnr - 1, lnr, false)[1],
      }
    else
      lnr = fold_end
    end
    lnr = lnr + 1
  end

  return lines
end

-- Clip the window context based on the direction.
---@param context WindowContext
---@param direction HintDirection
function M.clip_window_context(context, direction)
  local hint = require('hop.hint')
  if direction == hint.HintDirection.BEFORE_CURSOR then
    context.line_range.bot = context.cursor.row
  elseif direction == hint.HintDirection.AFTER_CURSOR then
    context.line_range.top = context.cursor.row
  end
end

return M
