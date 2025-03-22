local M = {}

function M.check()
    local health = vim.health or require('health')
    local hop = require('hop')
    local opts = hop.get_opts()

    health.start('Ensuring keys length is 1')
    local had_errors = false
    for i = 1, #opts.keys do
        local key = opts.keys:sub(i, i)
        if #key ~= 1 then
            had_errors = true
            health.ok(string.format('The length of key %s is not 1', key))
        end
    end
    if not had_errors then
        health.ok('All keys length is 1')
    end

    health.start('Ensuring keys are unique')
    had_errors = false
    local existing_keys = {}
    for i = 1, #opts.keys do
        local key = opts.keys:sub(i, i)
        if existing_keys[key] then
            had_errors = true
            health.error(string.format('key %s appears more than once in opts.keys', key))
        else
            existing_keys[key] = true
        end
    end
    if not had_errors then
        health.ok('All keys are unique')
    end
end

return M
