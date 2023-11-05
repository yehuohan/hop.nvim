local hop = require('hop')
local hop_hint = require('hop.hint')
local api = vim.api
local eq = assert.are.same
local hop_helpers = require('hop_helpers')

local override_keyseq = hop_helpers.override_keyseq

local test_count = 0

describe('Hop movement is correct', function()
  before_each(function()
    vim.cmd.new(test_count .. 'test_file')
    test_count = test_count + 1
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxy',
    })
    hop.setup()
  end)

  it('Hop is initialized', function()
    eq(hop.initialized, true)
  end)

  it('HopChar1AC', function()
    vim.api.nvim_win_set_cursor(0, { 1, 1 })

    override_keyseq({ 'c', 's' }, function()
      hop.hint_char1({ direction = hop_hint.HintDirection.AFTER_CURSOR })
    end)
    eq(28, api.nvim_win_get_cursor(0)[2])
  end)

  it('HopChar2AC', function()
    vim.api.nvim_win_set_cursor(0, { 1, 1 })

    override_keyseq({ 'c', 'd', 's' }, function()
      hop.hint_char2({ direction = hop_hint.HintDirection.AFTER_CURSOR })
    end)

    eq(28, api.nvim_win_get_cursor(0)[2])
  end)

  it('Hop from empty line', function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxy',
      '',
      'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxy',
    })
    vim.api.nvim_win_set_cursor(0, { 2, 1 })

    override_keyseq({ 'c', 's' }, function()
      hop.hint_char1({ direction = hop_hint.HintDirection.AFTER_CURSOR })
    end)

    eq({ 3, 28 }, api.nvim_win_get_cursor(0))

    vim.api.nvim_win_set_cursor(0, { 2, 1 })

    override_keyseq({ 'c', 's' }, function()
      hop.hint_char1({ direction = hop_hint.HintDirection.BEFORE_CURSOR })
    end)

    eq({ 1, 28 }, api.nvim_win_get_cursor(0))
  end)
end)
