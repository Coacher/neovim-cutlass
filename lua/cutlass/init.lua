local M = {}

--- Default configuration for the plugin
---@class CutlassConfig
---@field cut string|nil The key to use for the cut operation
---@field exclude string[] List of mappings to exclude from being overridden
---@field registers table<string, string> Registers to use for change, delete, and select operations
local default_config = {
    cut = nil,
    exclude = {},
    registers = {
        change = '_',
        delete = '_',
        select = '_',
    },
}

--- Current configuration for the plugin
---@type CutlassConfig
local config = vim.deepcopy(default_config)


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
---@param rhs string The right-hand side of the mapping
local function create_mapping(mode, lhs, rhs)
    vim.keymap.set(mode, lhs, rhs, { silent = true, noremap = true })
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
        for _, lhs in ipairs({ 'd', 'D', 'x', 'X', '<Del>' }) do
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

    for _, lhs in ipairs({ '<CR>', '<NL>', '<Space>' }) do
        if can_map(mode, lhs) then
            create_mapping(mode, lhs, '<C-O>"' .. config.registers.select .. 'c' .. lhs)
        end
    end

    for _, lhs in ipairs({ '<BS>', '<Del>', '<C-H>' }) do
        if can_map(mode, lhs) then
            create_mapping(mode, lhs, '<C-O>"' .. config.registers.select .. 'c')
        end
    end
end

--- Override default mappings
function M.override_default_mappings()
    override_change_mappings()
    override_delete_mappings()
    override_select_mappings()
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
    if user_config then
        config = vim.tbl_deep_extend('force', default_config, user_config)
    end

    M.override_default_mappings()

    if config.cut then
        M.create_cut_mappings()
    end
end

return M
