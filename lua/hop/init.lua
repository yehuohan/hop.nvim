local M = {}
local fn = vim.fn
local api = vim.api
local config = require('hop.config')
local matcher = require('hop.matcher')
local hinter = require('hop.hinter')

--- Echo levels for M.echo
local echo_levels = {
    inp = 'Question',
    sel = 'Title',
    err = 'Error',
}

--- Echo message at cmdline
---@param msg string
---@param level string Level or highlight
function M.echo(msg, level)
    vim.cmd.redraw()
    api.nvim_echo({ { msg, echo_levels[level] or level } }, false, {})
end

-- Allows to overide options
---@param opts Options|nil
---@return Options
function M.get_opts(opts)
    opts = config.check_opts(opts or {})
    local mode = fn.mode()
    if mode ~= 'n' and mode ~= 'nt' then
        opts.current_window_only = true
    end
    return setmetatable(opts, { __index = config._default_opts })
end

--- Wrap hop functionalities
---@param match Matcher
---@param opts Options
function M.wrap(match, opts)
    opts = M.get_opts(opts)
    local ht = hinter.new(opts) -- Create a hinter
    local jts = ht:collect(match) -- Collect jump targets
    local jt = ht:select(jts) -- Select one jump target
    if jt then
        opts.jump(jt, opts) -- Jump to selected jump target
    end
end

function M.char(opts)
    M.echo('Hop char:', 'inp')
    local ok, c = pcall(fn.getcharstr)
    if not ok then -- Interrupted by <C-c>
        return
    end
    local mappings = opts and opts.match_mappings or config._default_opts.match_mappings
    M.wrap(matcher.chars(c, true, mappings), opts)
end

function M.word(opts)
    M.wrap(matcher.word, opts)
end

function M.anywhere(opts)
    M.wrap(matcher.anywhere, opts)
end

function M.line_start(opts)
    M.wrap(matcher.line_start, opts)
end

function M.vertical(opts)
    M.wrap(matcher.vertical, opts)
end

function M.setup(opts)
    opts = opts or {}
    config.setup(opts)

    -- stylua: ignore start
    api.nvim_create_user_command('HopChar', function() M.char({ current_line_only = false, current_window_only = false }) end, {})
    api.nvim_create_user_command('HopCharCL', function() M.char({ current_line_only = true }) end, {})
    api.nvim_create_user_command('HopCharCW', function() M.char({ current_window_only = true }) end, {})
    api.nvim_create_user_command('HopWord', function() M.word({ current_line_only = false, current_window_only = false }) end, {})
    api.nvim_create_user_command('HopWordCL', function() M.word({ current_line_only = true }) end, {})
    api.nvim_create_user_command('HopWordCW', function() M.word({ current_window_only = true }) end, {})
    api.nvim_create_user_command('HopAnywhere', function() M.anywhere({ current_line_only = false, current_window_only = false }) end, {})
    api.nvim_create_user_command('HopAnywhereCL', function() M.anywhere({ current_line_only = true }) end, {})
    api.nvim_create_user_command('HopAnywhereCW', function() M.anywhere({ current_window_only = true }) end, {})
    api.nvim_create_user_command('HopLineStart', function() M.line_start({ current_line_only = false, current_window_only = false }) end, {})
    api.nvim_create_user_command('HopLineStartCW', function() M.line_start({ current_window_only = true }) end, {})
    api.nvim_create_user_command('HopVertical', function() M.vertical({ current_line_only = false, current_window_only = false }) end, {})
    api.nvim_create_user_command('HopVerticalCW', function() M.vertical({ current_window_only = true }) end, {})
    -- stylua: ignore end
end

return M
