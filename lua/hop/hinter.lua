--- Collect all matched jump targets
---@alias Collector fun(self, match:Matcher):JumpTarget[]

--- Select one jump target
---@alias Selector fun(self, jump_targets:JumpTarget[]):JumpTarget

---@class Hinter
--- Privates
---@field _opts Options
--- States
---@field win_ctxs WindowContext[] All required windows context
---@field buf_list integer[] All buffers displaced at win_ctxs
---@field ns_hint integer Hint namespace to highlight hint labels
---@field ns_view integer View namespace to highlight the matched string
---@field ns_area integer Area namespace to highlight unmatched buffer area
---@field ns_diag table Diagnostic namespaces
--- Methods
---@field collect Collector
---@field select Selector

--- A jump target is a location in a given buffer at a window
---@class JumpTarget
---@field window number
---@field buffer number
---@field cursor Cursor The hint for jump target will place at the Cursor.virt cell when it not nil
---@field length number Jump target column length
---@field priority number The priority of jump target close to cursor

--- Hint jump targets to select
---@class HintTarget
---@field label string A label string to hint jump target
---@field index integer The label start index (1-based)
---@field jump_target JumpTarget

local fn = vim.fn
local api = vim.api
local window = require('hop.window')

--- Hinter methods
local H = {}
H.__index = H

function H:_setup_state()
    self.win_ctxs = window.get_windows_context(self._opts)
    self.buf_list = {}
    local buf_sets = {}
    for _, wctx in ipairs(self.win_ctxs) do
        if not buf_sets[wctx.hbuf] then
            buf_sets[wctx.hbuf] = true
            self.buf_list[#self.buf_list + 1] = wctx.hbuf
        end
        -- Ensure all window contexts are cliped for hint state
        window.clip_window_context(wctx, self._opts)
    end

    self.ns_hint = api.nvim_create_namespace('Hop.NsHint')
    self.ns_view = api.nvim_create_namespace('Hop.NsView')
    self.ns_area = api.nvim_create_namespace('Hop.NsArea')

    -- Clear namespaces in case last hop operation failed before quitting
    for _, buf in ipairs(self.buf_list) do
        if api.nvim_buf_is_valid(buf) then
            api.nvim_buf_clear_namespace(buf, self.ns_hint, 0, -1)
            api.nvim_buf_clear_namespace(buf, self.ns_view, 0, -1)
            api.nvim_buf_clear_namespace(buf, self.ns_area, 0, -1)
        end
    end

    -- Backup namespaces of diagnostic
    self.ns_diag = vim.diagnostic.get_namespaces()
end

function H:_clear_state()
    for _, buf in ipairs(self.buf_list) do
        if api.nvim_buf_is_valid(buf) then
            api.nvim_buf_clear_namespace(buf, self.ns_hint, 0, -1)
            api.nvim_buf_clear_namespace(buf, self.ns_view, 0, -1)
            api.nvim_buf_clear_namespace(buf, self.ns_area, 0, -1)

            for ns in pairs(self.ns_diag) do
                vim.diagnostic.show(ns, buf)
            end
        end
    end
end

--- Render unmatched areas
function H:_render_areas()
    if not self._opts.hl_unmatched then
        return
    end
    for _, wctx in ipairs(self.win_ctxs) do
        -- Set the highlight of unmatched lines of the buffer.
        local start_line, end_line = window.line_range2extmark(wctx.line_range)
        local start_col, end_col = window.column_range2extmark(wctx.column_range)
        api.nvim_buf_set_extmark(wctx.hbuf, self.ns_area, start_line, start_col, {
            end_line = end_line,
            end_col = end_col,
            hl_group = 'HopUnmatched',
            hl_eol = true,
            priority = 65533,
        })
        -- Hide diagnostics
        for ns in pairs(self.ns_diag) do
            vim.diagnostic.show(ns, wctx.hbuf, nil, { virtual_text = false })
        end
    end
end

--- Render hint targets
---@param hint_targets HintTarget[]
function H:_render_hints(hint_targets)
    for _, buf in ipairs(self.buf_list) do
        if api.nvim_buf_is_valid(buf) then
            api.nvim_buf_clear_namespace(buf, self.ns_hint, 0, -1)
            api.nvim_buf_clear_namespace(buf, self.ns_view, 0, -1)
        end
    end

    for _, ht in pairs(hint_targets) do
        local jt = ht.jump_target
        if self._opts.hl_matched and jt.length > 1 then
            local row, col = window.pos2extmark(jt.cursor)
            api.nvim_buf_set_extmark(jt.buffer, self.ns_view, row, col, {
                end_row = row,
                end_col = col + jt.length,
                hl_group = 'HopMatched',
                priority = 65534,
            })
        end

        local len = #ht.label
        if ht.index > len then
            goto continue
        end

        local virt_text
        if ht.index == len then
            virt_text = { { ht.label:sub(#ht.label), 'HopNextKey' } }
        else
            virt_text = {
                { ht.label:sub(ht.index, ht.index), 'HopNextKey1' },
                { ht.label:sub(ht.index + 1, ht.index + 1), 'HopNextKey2' },
            }
        end

        local row, col = window.pos2extmark(ht.jump_target.cursor)
        api.nvim_buf_set_extmark(ht.jump_target.buffer, self.ns_hint, row, col, {
            virt_text = virt_text,
            virt_text_pos = 'overlay',
            virt_text_win_col = ht.jump_target.cursor.virt,
            hl_mode = 'combine',
            priority = 65535,
        })

        ::continue::
    end
end

--- Create jump targets within one line
---@param wctx WindowContext
---@param lctx LineContext
---@param match Matcher
---@return JumpTarget[]
function H:_create_jump_targets(wctx, lctx, match)
    local line_jts = {}

    -- No possible position to place target unless virtualedit is enabled
    if not wctx.virtualedit then
        if lctx.line_cliped == '' and wctx.win_offset > 0 then
            return line_jts
        end
    end

    local idx = 1 -- 1-based index for lua string
    while true do
        local s = lctx.line_cliped:sub(idx)
        local res = match.match(s, wctx, lctx)
        if res == nil then
            break
        end
        -- Preview need a length to highlight the matched string. Zero means nothing to highlight.
        local matched_length = res.e - res.b
        -- As the make for jump target must be placed at a cell (but some pattern like '^' is
        -- placed between cells), so make sure res.e > res.b
        if res.b == res.e then
            res.e = res.e + 1
        end
        -- Compute jump target column
        local col = idx + res.b + math.floor((res.e - res.b - 1) * self._opts.hint_position)
        col = col - 1 -- Convert 1-based lua string index to WindowCol
        col = math.max(0, col + lctx.col_bias) -- Apply column bias
        -- Append jump target
        local current_hwin = api.nvim_get_current_win()
        if not (wctx.hwin == current_hwin and wctx.cursor.row == lctx.row and wctx.cursor.col == col) then
            -- Skip current cursor
            ---@type JumpTarget
            local line_jt = {
                window = wctx.hwin,
                buffer = wctx.hbuf,
                cursor = { row = lctx.row, col = col, off = res.off or 0, virt = res.virt },
                length = math.max(0, matched_length),
            }
            -- Compute priority
            local win_bias = math.abs(current_hwin - wctx.hwin) * 1000
            line_jt.priority = self._opts.distance(wctx.cursor, line_jt.cursor) + win_bias
            line_jts[#line_jts + 1] = line_jt
        end

        -- Do not search further if regex is oneshot or if there is nothing more to search
        idx = idx + res.e
        if idx > #lctx.line_cliped or s == '' or match.oneshot then
            break
        end
    end

    return line_jts
end

--- Collect jump targets
---@param match Matcher
---@return JumpTarget[]
function H:collect(match)
    self:_setup_state()

    local jump_targets = {}

    -- Iterate all window then line contexts
    for _, wctx in ipairs(self.win_ctxs) do
        local line_ctxs = window.get_lines_context(wctx)
        for _, lctx in ipairs(line_ctxs) do
            window.clip_line_context(wctx, lctx, self._opts)

            local line_jts = self:_create_jump_targets(wctx, lctx, match)
            vim.list_extend(jump_targets, line_jts)
        end
    end

    -- Sort jump targets
    local comp = function(a, b)
        return a.priority < b.priority
    end
    if self._opts.hint_reverse then
        comp = function(a, b)
            return a.priority > b.priority
        end
    end
    table.sort(jump_targets, comp)

    return jump_targets
end

--- Create hint targets for jump targets
---@param jump_targets JumpTarget[]
---@return HintTarget[]
function H:_create_hint_targets(jump_targets)
    local hint_targets = {}
    local perms = self._opts.permute(self._opts.keys, #jump_targets)
    for k, jt in ipairs(jump_targets) do
        hint_targets[k] = { label = perms[k], index = 1, jump_target = jt }
    end
    return hint_targets
end

--- Select one jump target
---@param jump_targets JumpTarget[]
---@return JumpTarget|nil
function H:select(jump_targets)
    local jts_cnt = #jump_targets
    if jts_cnt == 0 then
        require('hop').echo('There’s no such thing we can see...', 'err')
        return nil
    end
    local jt_idx = nil
    if vim.v.count > 0 then
        jt_idx = vim.v.count
    elseif jts_cnt == 1 and self._opts.auto_jump_one_target then
        jt_idx = 1
    end
    if jt_idx ~= nil then
        return jump_targets[jt_idx]
    end

    -- Create hint targets
    local hint_targets = self:_create_hint_targets(jump_targets)

    return self:_on_input(hint_targets)
end

--- Refine hint targets in-place
---@param hts HintTarget[]
---@param str string
---@return HintTarget|nil,integer
function H:_refine_hints(hts, str)
    local cnt = 0
    local len = #str
    for _, ht in pairs(hts) do
        if ht.label == str then
            -- Return jump target directly when label is full matched
            return ht, cnt
        end
        if vim.startswith(ht.label, str) then
            -- Advance to next label char
            cnt = cnt + 1
            ht.index = len + 1
        else
            ht.index = #ht.label + 1
        end
    end
    return nil, cnt
end

--- Wait a selected jump target via hint targets
---@param hint_targets HintTarget[]
---@return JumpTarget|nil
function H:_on_input(hint_targets)
    self:_render_areas()

    local got = ''
    while true do
        self:_render_hints(hint_targets)
        require('hop').echo('Select:' .. got, 'sel')

        local ok, key = pcall(fn.getcharstr)
        -- Handle operation keys
        if (not ok) or (key == self._opts.key_quit) then
            self:_clear_state()
            return
        elseif key == self._opts.key_delete then
            got = got:sub(1, #got - 1)
            self:_refine_hints(hint_targets, got)
            goto continue
        end

        -- Handle target keys
        if key and self._opts.keys:find(key, 1, true) then
            got = got .. key
            local ht, cnt = self:_refine_hints(hint_targets, got)
            if ht then
                self:_clear_state()
                return ht.jump_target
            elseif cnt == 0 then
                got = got:sub(1, #got - 1)
                self:_refine_hints(hint_targets, got)
                vim.notify('No remaining sequence starts with ' .. key, vim.log.levels.ERROR)
            end
        else
            -- Pass through to nvim to be handled normally
            self:_clear_state()
            api.nvim_feedkeys(key, '', true)
            return
        end

        ::continue::
    end
end

local M = {}

--- Compute distance between cursors
---@alias Distancer fun(a:Cursor, b:Cursor):number

--- Create a new hinter
---@param opts Options
---@return Hinter
function M.new(opts)
    return setmetatable({
        _opts = opts,
    }, H)
end

-- Manhattan distance between cursors
---@param a Cursor
---@param b Cursor
---@return number
function M.manhattan(a, b)
    return (10 * math.abs(b.row - a.row)) + math.abs(b.col + b.off - a.col - a.off)
end

return M
