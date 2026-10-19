local M = {}

--- Configuration for the plugin
---@class CutlassConfig
---@field cut string|nil The key to use for the cut operation
---@field exclude string[] List of mappings to exclude from being overridden
---@field registers table<string, string> Registers to use for change, delete, select, and put operations
local config = {
    cut = nil,
    exclude = {},
    registers = {
        change = '_',
        delete = '_',
        select = '_',
        put = '_',
    },
}

local put_register_names = vim.list_extend({ '"', '-' }, vim.tbl_map(tostring, vim.fn.range(10)))

local put_registers = {}
local put_changedtick = 0
local put_pending = false
local put_replaced = nil


--- Check if a mapping can be created
---@param mode string The mode for the mapping
---@param lhs string The left-hand side of the mapping
---@return boolean
local function can_map(mode, lhs)
    for _, excluded in ipairs(config.exclude) do
        if excluded == mode .. lhs then
            return false
        end
    end
    return vim.fn.maparg(lhs, mode) == ''
end

--- Create a mapping
---@param mode string The mode for the mapping
---@param lhs string The left-hand side of the mapping
---@param rhs string|function The right-hand side of the mapping
---@param opts table|nil Additional mapping options
local function create_mapping(mode, lhs, rhs, opts)
    vim.keymap.set(mode, lhs, rhs, vim.tbl_extend('force', { silent = true, noremap = true }, opts or {}))
end

--- Redirect a mapping to a register
---@param mode string The mode for the mapping
---@param lhs string The left-hand side of the mapping
---@param reg string The register to redirect to
local function redirect_to_register(mode, lhs, reg)
    create_mapping(mode, lhs, '"' .. reg .. lhs)
end


--- Override change mappings
local function override_change_mappings()
    for _, mode in ipairs({ 'n', 'x' }) do
        for _, lhs in ipairs({ 'c', 'C', 's', 'S' }) do
            if can_map(mode, lhs) then
                redirect_to_register(mode, lhs, config.registers.change)
            end
        end
    end

    for _, lhs in ipairs({ 'cc' }) do
        if can_map('n', lhs) then
            redirect_to_register('n', lhs, config.registers.change)
        end
    end
end

--- Override delete mappings
local function override_delete_mappings()
    for _, mode in ipairs({ 'n', 'x' }) do
        for _, lhs in ipairs({ 'd', 'D', 'x', 'X', '<Del>', '<kDel>' }) do
            if can_map(mode, lhs) then
                redirect_to_register(mode, lhs, config.registers.delete)
            end
        end
    end

    for _, lhs in ipairs({ 'dd' }) do
        if can_map('n', lhs) then
            redirect_to_register('n', lhs, config.registers.delete)
        end
    end
end

--- Override select mappings
local function override_select_mappings()
    local mode = 's'

    for code = 33, 126 do
        local lhs = vim.fn.nr2char(code)
        if can_map(mode, lhs) then
            create_mapping(mode, lhs, '<C-O>"' .. config.registers.select .. 'c' .. lhs)
        end
    end

    for _, lhs in ipairs({ '<CR>', '<NL>', '<kEnter>', '<Space>' }) do
        if can_map(mode, lhs) then
            create_mapping(mode, lhs, '<C-O>"' .. config.registers.select .. 'c' .. lhs)
        end
    end

    for _, lhs in ipairs({ '<BS>', '<Del>', '<kDel>', '<C-H>' }) do
        if can_map(mode, lhs) then
            create_mapping(mode, lhs, '<C-O>"' .. config.registers.select .. 'd')
        end
    end
end

--- Save registers that Visual put may change
---@param lhs string The left-hand side of the mapping
---@return string
local function save_put_registers(lhs)
    local names = vim.list_extend({}, put_register_names)
    local clipboard = vim.opt.clipboard:get()
    if vim.tbl_contains(clipboard, 'unnamed') and vim.fn.has('clipboard') == 1 then
        table.insert(names, '*')
    end
    if vim.tbl_contains(clipboard, 'unnamedplus') and vim.fn.has('clipboard') == 1 then
        table.insert(names, '+')
    end
    put_registers = {}
    for _, name in ipairs(names) do
        put_registers[name] = vim.fn.getreginfo(name)
    end
    put_changedtick = vim.api.nvim_buf_get_changedtick(0)
    put_pending = (config.registers.put ~= '_')
    put_replaced = nil
    return lhs .. '<Cmd>lua require("cutlass")._restore_put_registers()<CR>'
end

--- Capture the text replaced by Visual put
local function capture_put_replaced()
    -- Visual put yanks the replaced text before the put, other TextYankPost
    -- handlers may change the registers, but v:event keeps the yanked text
    if put_pending then
        put_pending = false
        put_replaced = { regcontents = vim.v.event.regcontents, regtype = vim.v.event.regtype }
    end
end

--- Restore registers changed by Visual put
--- Internal, called by the Visual put mappings
function M._restore_put_registers()
    put_pending = false
    -- Registers are unchanged if the put fails, e.g. in a nomodifiable buffer
    if vim.api.nvim_buf_get_changedtick(0) == put_changedtick then
        return
    end
    for name, info in pairs(put_registers) do
        if not vim.deep_equal(vim.fn.getreginfo(name), info) then
            vim.fn.setreg(name, info)
        end
    end
    vim.fn.setreg('"', { points_to = put_registers['"'].points_to })
    if put_replaced then
        vim.fn.setreg(config.registers.put, put_replaced)
    end
end

--- Redirect a Visual put mapping to the put register
---@param mode string The mode for the mapping
---@param lhs string The left-hand side of the mapping
local function redirect_put_to_register(mode, lhs)
    create_mapping(mode, lhs, function() return save_put_registers(lhs) end, { expr = true })
end

--- Override put mappings
local function override_put_mappings()
    for _, lhs in ipairs({ 'p', 'gp', 'gP', ']p', '[p', ']P', '[P' }) do
        if can_map('x', lhs) then
            redirect_put_to_register('x', lhs)
        end
    end

    if config.registers.put ~= '_' then
        vim.api.nvim_create_autocmd('TextYankPost', {
            group = vim.api.nvim_create_augroup('cutlass_put', { clear = true }),
            callback = capture_put_replaced,
        })
    end
end

--- Override default mappings
function M.override_default_mappings()
    override_change_mappings()
    override_delete_mappings()
    override_select_mappings()
    override_put_mappings()
end

--- Create cut mappings
function M.create_cut_mappings()
    create_mapping('n', config.cut, 'd')
    create_mapping('x', config.cut, 'd')
    create_mapping('n', config.cut .. config.cut, 'dd')
    create_mapping('n', string.upper(config.cut), 'D')
end


--- Setup the plugin with user configuration
---@param user_config CutlassConfig|nil User configuration
function M.setup(user_config)
    config = vim.tbl_deep_extend('force', config, user_config or {})

    M.override_default_mappings()

    if config.cut then
        M.create_cut_mappings()
    end
end

return M
