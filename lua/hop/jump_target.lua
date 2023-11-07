-- Jump targets are locations in buffers where users might jump to. They are wrapped in a table and provide the
-- required information so that Hop can associate label and display the hints.
---@class Locations
---@field jump_targets JumpTarget[]
---@field indirect_jump_targets IndirectJumpTarget[]

-- A single jump target is simply a location in a given buffer at a window.
---@class JumpTarget
---@field window number
---@field buffer number
---@field cursor CursorPos
---@field length number Jump target column length

-- Indirect jump targets are encoded as a flat list-table of pairs (index, score). This table allows to quickly score
-- and sort jump targets. The `index` field gives the index in the `jump_targets` list. The `score` is any number. The
-- rule is that the lower the score is, the less prioritized the jump target will be.
---@class IndirectJumpTarget
---@field index number
---@field score number

---@class JumpContext
---@field win_ctx WindowContext
---@field line_ctx LineContext
---@field regex Regex

local hint = require('hop.hint')
local window = require('hop.window')

---@class JumpTargetModule
local M = {}

-- Manhattan distance with column and row, weighted on x so that results are more packed on y.
---@param a CursorPos
---@param b CursorPos
---@param x_bias number
---@return number
local function manh_dist(a, b, x_bias)
  return (x_bias * math.abs(b.row - a.row)) + math.abs(b.col - a.col)
end

-- Mark the current line with jump targets.
---@param jctx JumpContext
---@param opts Options
---@return JumpTarget[]
local function mark_jump_targets_line(jctx, opts)
  local wctx = jctx.win_ctx
  local lctx = jctx.line_ctx

  ---@type JumpTarget[]
  local jump_targets = {}
  window.clip_line_context(wctx, lctx, opts)

  -- No possible position to place target
  if lctx.line == '' and wctx.col_offset > 0 then
    return jump_targets
  end

  local idx = 1 -- 1-based index for lua string
  while true do
    local s = lctx.line:sub(idx)
    ---@type ColumnRange
    local b, e = jctx.regex.match(s, jctx, opts)
    if b == nil then
      break
    end
    -- Preview need a length to highlight the matched string. Zero means nothing to highlight.
    local matched_length = e - b
    -- As the make for jump target must be placed at a cell (but some pattern like '^' is
    -- placed between cells), we should make sure e > b
    if b == e then
      e = e + 1
    end

    ---@type WindowCol
    local col = idx + b
    if opts.hint_position == hint.HintPosition.MIDDLE then
      col = idx + math.floor((b + e) / 2)
    elseif opts.hint_position == hint.HintPosition.END then
      col = idx + e - 1
    end
    col = col - 1 -- Convert 1-based lua string index to WindowCol
    jump_targets[#jump_targets + 1] = {
      window = wctx.win_handle,
      buffer = wctx.buf_handle,
      cursor = {
        row = lctx.row,
        col = math.max(0, col + lctx.col_bias),
      },
      length = math.max(0, matched_length),
    }
    idx = idx + e

    -- Do not search further if regex is oneshot or if there is nothing more to search
    if idx > #lctx.line or s == '' or jctx.regex.oneshot then
      break
    end
  end

  return jump_targets
end

-- Create jump targets for a given indexed line.
-- This function creates the jump targets for the current (indexed) line and appends them to the input list of jump
-- targets `jump_targets`.
---@param jctx JumpContext
---@param locations Locations used later to sort jump targets by score and create hints.
---@param opts Options
local function create_jump_targets_for_line(jctx, locations, opts)
  -- first, create the jump targets for the ith line
  local line_jump_targets = mark_jump_targets_line(jctx, opts)

  -- then, append those to the input jump target list and create the indexed jump targets
  local win_bias = math.abs(vim.api.nvim_get_current_win() - jctx.win_ctx.win_handle) * 1000
  for _, jump_target in pairs(line_jump_targets) do
    locations.jump_targets[#locations.jump_targets + 1] = jump_target

    locations.indirect_jump_targets[#locations.indirect_jump_targets + 1] = {
      index = #locations.jump_targets,
      score = manh_dist(jctx.win_ctx.cursor, jump_target.cursor, opts.x_bias) + win_bias,
    }
  end
end

-- Create jump targets by scanning lines in the currently visible buffer.
--
-- This function takes a regex argument, which is an object containing a match function that must return the span
-- (inclusive beginning, exclusive end) of the match item, or nil when no more match is possible. This object also
-- contains the `oneshot` field, a boolean stating whether only the first match of a line should be taken into account.
--
-- This function returns the lined jump targets (an array of N lines, where N is the number of currently visible lines).
-- Lines without jump targets are assigned an empty table ({}). For lines with jump targets, a list-table contains the
-- jump targets as pair of { line, col }.
--
-- In addition the jump targets, this function returns the total number of jump targets (i.e. this is the same thing as
-- traversing the lined jump targets and summing the number of jump targets for all lines) as a courtesy, plus «
-- indirect jump targets. » Indirect jump targets are encoded as a flat list-table containing three values: i, for the
-- ith line, j, for the rank of the jump target, and dist, the score distance of the associated jump target. This list
-- is sorted according to that last dist parameter in order to know how to distribute the jump targets over the buffer.
---@param regex Regex
---@return fun(opts:Options):Locations
function M.jump_targets_by_scanning_lines(regex)
  ---@param opts Options
  ---@return Locations
  return function(opts)
    -- Get the window context; this is used to know which part of the visible buffer is to hint
    local all_ctxs = window.get_windows_context(opts)

    ---@type Locations
    local locations = {
      jump_targets = {},
      indirect_jump_targets = {},
    }

    -- Iterate all window contexts
    for _, wctx in ipairs(all_ctxs) do
      -- Get all lines' context
      window.clip_window_context(wctx, opts)
      local lines = window.get_lines_context(wctx)
      for i = 1, #lines do
        create_jump_targets_for_line({
          win_ctx = wctx,
          line_ctx = lines[i],
          regex = regex,
        }, locations, opts)
      end
    end

    M.sort_indirect_jump_targets(locations.indirect_jump_targets, opts)

    return locations
  end
end

-- Jump target generator for regex applied only on the cursor line.
---@param regex Regex
---@return fun(opts:Options):Locations
function M.jump_targets_for_current_line(regex)
  ---@param opts Options
  ---@return Locations
  return function(opts)
    local wctx = window.get_windows_context(opts)[1]
    local line_row = wctx.cursor.row
    local line = vim.api.nvim_buf_get_lines(wctx.buf_handle, line_row - 1, line_row, false)[1]
    local locations = {
      jump_targets = {},
      indirect_jump_targets = {},
    }

    create_jump_targets_for_line({
      win_ctx = wctx,
      line_ctx = { row = line_row, line = line, col_bias = 0 },
      regex = regex,
    }, locations, opts)

    M.sort_indirect_jump_targets(locations.indirect_jump_targets, opts)

    return locations
  end
end

-- Apply a score function based on the Manhattan distance to indirect jump targets.
---@param indirect_jump_targets IndirectJumpTarget[]
---@param opts Options
function M.sort_indirect_jump_targets(indirect_jump_targets, opts)
  local score_comparison = function(a, b)
    return a.score < b.score
  end
  if opts.reverse_distribution then
    score_comparison = function(a, b)
      return a.score > b.score
    end
  end

  table.sort(indirect_jump_targets, score_comparison)
end

-- Apply an offset on jump target
-- Always offset in cell first, then in line
---@param jt JumpTarget
---@param offset_cell WindowCell|nil
---@param offset_row WindowRow|nil
function M.move_jump_target(jt, offset_cell, offset_row)
  local dcell = offset_cell or 0
  local drow = offset_row or 0

  if dcell ~= 0 then
    local line = vim.api.nvim_buf_get_lines(jt.buffer, jt.cursor.row - 1, jt.cursor.row, false)[1]
    local line_cells = vim.fn.strdisplaywidth(line)
    ---@type WindowCell
    local new_cell = vim.fn.strdisplaywidth(line:sub(1, jt.cursor.col)) + dcell
    if new_cell >= line_cells then
      new_cell = line_cells
    elseif new_cell < 0 then
      new_cell = 0
    end
    jt.cursor.col = vim.fn.byteidx(line, window.cell2char(line, new_cell))
  end

  if drow ~= 0 then
    ---@type WindowRow
    local new_row = jt.cursor.row + drow
    local max_row = vim.api.nvim_buf_line_count(jt.buffer)
    if new_row > max_row then
      jt.cursor.row = max_row
    elseif new_row < 1 then
      jt.cursor.row = 1
    else
      jt.cursor.row = new_row
    end
  end
end

return M
