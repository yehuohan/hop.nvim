-- Jump targets are locations in buffers where users might jump to. They are wrapped in a table and provide the
-- required information so that Hop can associate label and display the hints.
---@class Locations
---@field jump_targets JumpTarget[]
---@field indirect_jump_targets IndirectJumpTarget[]

-- A single jump target is simply a location in a given buffer.
-- So you can picture a jump target as a triple (line, column, window).
---@class JumpTarget
---@field buffer number
---@field line number
---@field column number
---@field length number
---@field window number

-- Indirect jump targets are encoded as a flat list-table of pairs (index, score). This table allows to quickly score
-- and sort jump targets. The `index` field gives the index in the `jump_targets` list. The `score` is any number. The
-- rule is that the lower the score is, the less prioritized the jump target will be.
---@class IndirectJumpTarget
---@field index number
---@field score number

---@class JumpContext
---@field buf_handle number
---@field win_handle number
---@field regex Regex
---@field x_bias number
---@field line_context LineContext
---@field col_offset number
---@field cursor_pos number[]
---@field fcol number
---@field win_width number
---@field direction HintDirection
---@field hint_position HintPosition

---@class Regex
---@field oneshot boolean
---@field match function
---@field linewise boolean determines if regex considers whole lines

---@class MatchContext Match context to Regex.match
---@field cursor_fcol number cursor cell column
---@field direction HintDirection

local hint = require('hop.hint')
local window = require('hop.window')
local mappings = require('hop.mappings')

---@class JumpTargetModule
local M = {}

-- Manhattan distance with column and row, weighted on x so that results are more packed on y.
---@param a number[]
---@param b number[]
---@param x_bias number
---@return number
local function manh_dist(a, b, x_bias)
  return (x_bias * math.abs(b[1] - a[1])) + math.abs(b[2] - a[2])
end

-- Return the character index of col position in line
---@param line string
---@param col number col index of cell with 1-based
---@return number char index with 0-based
local function str_col2char(line, col)
  if col <= 0 then
    return 0
  end

  local line_width = vim.fn.strdisplaywidth(line)
  local line_chars = vim.fn.strchars(line)
  -- No multi-byte character
  if line_width == line_chars then
    return col
  end
  -- Line is shorter than col, all line should include
  if line_width <= col then
    return line_chars
  end

  local lst
  -- Line is very long
  if line_chars >= col then
    -- split the line to individual characters
    lst = vim.fn.split(vim.fn.strcharpart(line, 0, col), '\\zs')
  else
    lst = vim.fn.split(line, '\\zs')
  end
  local i, w = 0, 0
  repeat
    i = i + 1
    w = w + vim.fn.strdisplaywidth(lst[i])
  until w >= col
  return i
end

-- Mark the current line with jump targets.
--- @param ctx JumpContext
---@return JumpTarget[]
local function mark_jump_targets_line(ctx)
  ---@type JumpTarget[]
  local jump_targets = {}

  local end_index = vim.fn.strdisplaywidth(ctx.line_context.line)
  if ctx.win_width ~= nil then
    end_index = ctx.col_offset + ctx.win_width
  end

  -- Handle shifted_line with str_col2char for multiple-bytes chars
  local left_idx = str_col2char(ctx.line_context.line, ctx.col_offset)
  local right_idx = str_col2char(ctx.line_context.line, end_index)
  local shifted_line = vim.fn.strcharpart(ctx.line_context.line, left_idx, right_idx - left_idx)
  local col_bias = vim.fn.byteidx(ctx.line_context.line, left_idx)

  -- We want to change the start offset so that we ignore everything before the cursor
  if ctx.direction == hint.HintDirection.AFTER_CURSOR then
    shifted_line = shifted_line:sub(ctx.cursor_pos[2] - col_bias + 1)
    col_bias = ctx.cursor_pos[2]
    -- We want to change the end
  elseif ctx.direction == hint.HintDirection.BEFORE_CURSOR then
    shifted_line = shifted_line:sub(1, ctx.cursor_pos[2] - col_bias + 1)
  end

  -- No possible position to place target
  if shifted_line == '' and ctx.col_offset > 0 then
    return jump_targets
  end

  ---@type MatchContext
  local match_context = {
    cursor_fcol = ctx.fcol,
    direction = ctx.direction,
  }

  local col = 1
  while true do
    local s = shifted_line:sub(col)
    local b, e = ctx.regex.match(s, match_context)

    -- match empty lines only in linewise regexes
    if b == nil or ((b == 0 and e == 0) and not ctx.regex.linewise) then
      break
    end
    -- Preview need a length to highlight the matched string. Zero means nothing to highlight.
    local matched_length = e - b
    -- As the make for jump target must be placed at a cell (but some pattern like '^' is
    -- placed between cells), we should make sure e > b
    if b == e then
      e = e + 1
    end

    local colp = col + b
    if ctx.hint_position == hint.HintPosition.MIDDLE then
      colp = col + math.floor((b + e) / 2)
    elseif ctx.hint_position == hint.HintPosition.END then
      colp = col + e - 1
    end
    jump_targets[#jump_targets + 1] = {
      line = ctx.line_context.line_nr,
      column = math.max(1, colp + col_bias),
      length = math.max(0, matched_length),
      buffer = ctx.buf_handle,
      window = ctx.win_handle,
    }

    -- do not search further if regex is oneshot or if there is nothing more to search
    if ctx.regex.oneshot or s == '' then
      break
    end
    col = col + e
    if col > #shifted_line then
      break
    end
  end

  return jump_targets
end

-- Create jump targets for a given indexed line.
-- This function creates the jump targets for the current (indexed) line and appends them to the input list of jump
-- targets `jump_targets`.
---@param ctx JumpContext
---@param locations Locations used later to sort jump targets by score and create hints.
local function create_jump_targets_for_line(ctx, locations)
  -- first, create the jump targets for the ith line
  local line_jump_targets = mark_jump_targets_line(ctx)

  -- then, append those to the input jump target list and create the indexed jump targets
  local win_bias = math.abs(vim.api.nvim_get_current_win() - ctx.win_handle) * 1000
  for _, jump_target in pairs(line_jump_targets) do
    locations.jump_targets[#locations.jump_targets + 1] = jump_target

    locations.indirect_jump_targets[#locations.indirect_jump_targets + 1] = {
      index = #locations.jump_targets,
      score = manh_dist(ctx.cursor_pos, { jump_target.line, jump_target.column }, ctx.x_bias) + win_bias,
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
    -- get the window context; this is used to know which part of the visible buffer is to hint
    local all_ctxs = window.get_window_context(opts)

    ---@type Locations
    local Locations = {
      jump_targets = {},
      indirect_jump_targets = {},
    }
    ---@type JumpContext
    local Context = {
      x_bias = opts.x_bias,
      regex = regex,
      hint_position = opts.hint_position,
    }

    -- Iterate all buffers
    for _, bctx in ipairs(all_ctxs) do
      -- Iterate all windows of a same buffer
      Context.buf_handle = bctx.buffer_handle
      for _, wctx in ipairs(bctx.contexts) do
        window.clip_window_context(wctx, opts.direction)

        Context.win_handle = wctx.hwin
        Context.col_offset = wctx.col_offset
        Context.win_width = wctx.win_width
        Context.cursor_pos = wctx.cursor_pos
        -- Get all lines' context
        local lines = window.get_lines_context(bctx.buffer_handle, wctx)
        -- in the case of a direction, we want to treat the first or last line (according to the direction) differently
        if opts.direction == hint.HintDirection.AFTER_CURSOR then
          -- the first line is to be checked first
          if not Context.regex.linewise then
            Context.direction = opts.direction
            Context.line_context = lines[1]
            create_jump_targets_for_line(Context, Locations)
          end

          Context.direction = nil
          for i = 2, #lines do
            Context.line_context = lines[i]
            create_jump_targets_for_line(Context, Locations)
          end
        elseif opts.direction == hint.HintDirection.BEFORE_CURSOR then
          -- the last line is to be checked last
          Context.direction = nil
          for i = 1, #lines - 1 do
            Context.line_context = lines[i]
            create_jump_targets_for_line(Context, Locations)
          end

          if not Context.regex.linewise then
            Context.direction = opts.direction
            Context.line_context = lines[#lines]
            create_jump_targets_for_line(Context, Locations)
          end
        else
          Context.direction = nil
          for i = 1, #lines do
            Context.line_context = lines[i]
            -- do not mark current line in active window
            if
              not (
                Context.regex.linewise
                and Context.line_context.line_nr == vim.api.nvim_win_get_cursor(Context.win_handle)[1] - 1
                and vim.api.nvim_get_current_win() == Context.win_handle
              )
            then
              create_jump_targets_for_line(Context, Locations)
            end
          end
        end
      end
    end

    M.sort_indirect_jump_targets(Locations.indirect_jump_targets, opts)

    return Locations
  end
end

-- Jump target generator for regex applied only on the cursor line.
---@param regex Regex
---@return fun(opts:Options):Locations
function M.jump_targets_for_current_line(regex)
  ---@param opts Options
  ---@return Locations
  return function(opts)
    local context = window.get_window_context(opts)[1].contexts[1]
    local line_n = context.cursor_pos[1]
    local line = vim.api.nvim_buf_get_lines(0, line_n - 1, line_n, false)
    local Locations = {
      jump_targets = {},
      indirect_jump_targets = {},
    }

    create_jump_targets_for_line({
      buf_handle = 0,
      win_handle = 0,
      regex = regex,
      x_bias = opts.x_bias,
      col_offset = context.col_offset,
      win_width = context.win_width,
      cursor_pos = context.cursor_pos,
      direction = opts.direction,
      hint_position = opts.hint_position,
      line_context = { line_nr = line_n - 1, line = line[1] },
    }, Locations)

    M.sort_indirect_jump_targets(Locations.indirect_jump_targets, opts)

    return Locations
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

-- Regex modes for the buffer-driven generator.
---@param s string
---@return boolean
local function starts_with_uppercase(s)
  if #s == 0 then
    return false
  end

  local f = s:sub(1, vim.fn.byteidx(s, 1))
  -- if it’s a space, we assume it’s not uppercase, even though Lua doesn’t agree with us; I mean, Lua is horrible, who
  -- would like to argue with that creature, right?
  if f == ' ' then
    return false
  end

  return f:upper() == f
end

-- Regex by searching a pattern.
---@param pat string
---@param plain_search? boolean
---@return Regex
local function regex_by_searching(pat, plain_search)
  if plain_search then
    pat = vim.fn.escape(pat, '\\/.$^~[]')
  end

  local regex = vim.regex(pat)

  return {
    oneshot = false,
    match = function(s)
      return regex:match_str(s)
    end,
  }
end

-- Wrapper over M.regex_by_searching to add support for case sensitivity.
---@param pat string
---@param plain_search boolean
---@param opts Options
---@return Regex
function M.regex_by_case_searching(pat, plain_search, opts)
  local pat_case = ''
  if vim.o.smartcase then
    if not starts_with_uppercase(pat) then
      pat_case = '\\c'
    end
  elseif opts.case_insensitive then
    pat_case = '\\c'
  end
  local pat_mappings = mappings.checkout(pat, opts)

  if plain_search then
    pat = vim.fn.escape(pat, '\\/.$^~[]')
  end
  if pat_mappings ~= '' then
    pat = string.format([[\(%s\)\|\(%s\)]], pat, pat_mappings)
  end
  pat = pat .. pat_case

  local regex = vim.regex(pat)

  return {
    oneshot = false,
    match = function(s)
      return regex:match_str(s)
    end,
  }
end

-- Word regex.
---@return Regex
function M.regex_by_word_start()
  return regex_by_searching('\\k\\+')
end

-- Camel case regex
---@return Regex
function M.regex_by_camel_case()
  local camel = '\\u\\l\\+'
  local acronyms = '\\u\\+\\ze\\u\\l'
  local upper = '\\u\\+'
  local lower = '\\l\\+'
  local rgb = '#\\x\\+\\>'
  local ox = '\\<0[xX]\\x\\+\\>'
  local oo = '\\<0[oO][0-7]\\+\\>'
  local ob = '\\<0[bB][01]\\+\\>'
  local num = '\\d\\+'

  local tab = { camel, acronyms, upper, lower, rgb, ox, oo, ob, num, '\\~', '!', '@', '#', '$' }
  -- regex that matches camel or acronyms or upper ... or num ...
  local patStr = '\\%(\\%(' .. table.concat(tab, '\\)\\|\\%(') .. '\\)\\)'

  local pat = vim.regex(patStr)
  return {
    oneshot = false,
    match = function(s)
      return pat:match_str(s)
    end,
  }
end

-- Line regex.
---@return Regex
function M.by_line_start()
  local c = vim.fn.winsaveview().leftcol

  return {
    oneshot = true,
    linewise = true,
    match = function(s)
      local l = vim.fn.strdisplaywidth(s)
      if c > 0 and l == 0 then
        return nil
      end

      return 0, 1
    end,
  }
end

-- Line regex at cursor position.
---@return Regex
function M.regex_by_vertical()
  return {
    oneshot = true,
    match = function(s, mctx)
      if mctx.direction == hint.HintDirection.AFTER_CURSOR then
        return 0, 1
      end
      local idx = str_col2char(s, mctx.cursor_fcol)
      local col = vim.fn.byteidx(s, idx)
      if -1 < col and col < #s then
        return col, col + 1
      else
        return #s - 1, #s
      end
    end,
  }
end

-- Line regex skipping finding the first non-whitespace character on each line.
---@return Regex
function M.regex_by_line_start_skip_whitespace()
  local regex = vim.regex('\\S')

  return {
    oneshot = true,
    linewise = true,
    match = function(s)
      return regex:match_str(s)
    end,
  }
end

-- Anywhere regex.
---@return Regex
function M.regex_by_anywhere()
  return regex_by_searching('\\v(<.|^$)|(.>|^$)|(\\l)\\zs(\\u)|(_\\zs.)|(#\\zs.)')
end

return M
