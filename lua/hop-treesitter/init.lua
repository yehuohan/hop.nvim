local M = {}
M.opts = {}

M.hint_nodes = function(opts)
  local hop = require('hop')

  opts = setmetatable(opts or {}, { __index = M.opts })
  hop.hint_with(require('hop-treesitter.treesitter').nodes(), opts)
end

function M.register(opts)
  M.opts = opts
  vim.api.nvim_create_user_command('HopNodes', function()
    M.hint_nodes({})
  end, {})
end

return M
