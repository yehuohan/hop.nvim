local M = {}
M.opts = {}

local defaults = {
  yank_register = '',
}

---@param opts Options
M.yank_char1 = function(opts)
  local hop = require('hop')
  local jump_regex = require('hop.jump_regex')
  local yank = require('hop-yank.yank')

  opts = setmetatable(opts or {}, { __index = M.opts })

  if opts.multi_windows then
    opts.multi_windows = false
    vim.notify('Cannot use yank across multiple windows', vim.log.levels.WARN)
  end

  local prompts = {
    'Yank start pattern: ',
    'Yank end pattern: ',
  }

  ---@type JumpTarget[]
  local targets = {}
  for key, prompt in pairs(prompts) do
    local c = hop.get_input_pattern(prompt, 1)
    if not c or c == '' then
      return
    end

    hop.hint_with_regex(jump_regex.regex_by_case_searching(c, true, opts), opts, function(jt)
      targets[key] = jt
    end)
  end

  if targets[1] == nil or targets[2] == nil then
    return
  end

  local text = yank.get_text(targets[1], targets[2])
  if #text == 0 or text[1] == '' then
    return
  end

  yank.yank_to(text, opts.yank_register)
end

---@param opts Options
M.paste_char1 = function(opts)
  local hop = require('hop')
  local jump_target = require('hop.jump_target')
  local jump_regex = require('hop.jump_regex')

  opts = setmetatable(opts or {}, { __index = M.opts })

  local c = hop.get_input_pattern('Paste 1 char', 1)
  if not c or c == '' then
    return
  end

  ---@param jt JumpTarget|nil
  hop.hint_with_regex(jump_regex.regex_by_case_searching(c, true, opts), opts, function(jt)
    local target = jt

    if target == nil then
      return
    end

    jump_target.move_jump_target(target, 0, opts.hint_offset)

    require('hop-yank.yank').paste_from(target, opts.yank_register)
  end)
end

function M.register(opts)
  local direction = require('hop.hint').HintDirection

  M.opts = opts
  if not M.opts.yank_register then
    M.opts.yank_register = defaults.yank_register
  end

  local user_command = vim.api.nvim_create_user_command
  local commands = {
    HopYankChar1 = M.yank_char1,
    HopPasteChar1 = M.paste_char1,
  }

  for label, hint in pairs(commands) do
    user_command(label, hint, {})

    user_command(label .. 'BC', function()
      hint({ direction = direction.BEFORE_CURSOR })
    end, {})

    user_command(label .. 'AC', function()
      hint({ direction = direction.AFTER_CURSOR })
    end, {})

    user_command(label .. 'CurrentLine', function()
      hint({ current_line_only = true })
    end, {})

    user_command(label .. 'CurrentLineBC', function()
      hint({ direction = direction.BEFORE_CURSOR, current_line_only = true })
    end, {})

    user_command(label .. 'CurrentLineAC', function()
      hint({ direction = direction.AFTER_CURSOR, current_line_only = true })
    end, {})

    user_command(label .. 'MW', function()
      hint({ multi_windows = true })
    end, {})
  end
end

return M
