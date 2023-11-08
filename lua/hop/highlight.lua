-- This module contains everything for highlighting Hop.
local M = {}

-- Insert the highlights that Hop uses.
function M.insert_highlights()
  local set = vim.api.nvim_set_hl

  -- Highlight used for the mono-sequence keys (i.e. sequence of 1).
  set(0, 'HopNextKey', { fg = '#ff007c', bold = true, ctermfg = 198, cterm = { bold = true }, default = true })

  -- Highlight used for the first key in a sequence.
  set(0, 'HopNextKey1', { fg = '#00dfff', bold = true, ctermfg = 45, cterm = { bold = true }, default = true })

  -- Highlight used for the second and remaining keys in a sequence.
  set(0, 'HopNextKey2', { fg = '#2b8db3', ctermfg = 33, default = true })

  -- Highlight used for the unmatched part of the buffer.
  set(0, 'HopUnmatched', { fg = '#666666', sp = '#666666', ctermfg = 242, default = true })

  -- Highlight used for the fake cursor visible when hopping.
  set(0, 'HopCursor', { link = 'Cursor', default = true })

  -- Highlight used for preview pattern
  set(0, 'HopPreview', { link = 'IncSearch', default = true })
end

function M.create_autocmd()
  vim.api.nvim_create_autocmd('ColorScheme', {

    group = vim.api.nvim_create_augroup('HopInitHighlight', {
      clear = true,
    }),

    callback = function()
      require('hop.highlight').insert_highlights()
    end,
  })
end

return M
