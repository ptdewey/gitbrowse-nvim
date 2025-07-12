local M = {}

local o = {}

---@param filepath string
---@return string|nil
local function find_altfile(filepath)
    local altfile = nil
    if filepath:match("_test%.go$") then
        altfile = filepath:gsub("_test%.go$", ".go")
    elseif filepath:match("%.go$") then
        altfile = filepath:gsub("%.go$", "_test.go")
    else
        print("No alternate file found for '" .. filepath .. "'")
        return
    end

    return altfile
end

--- NOTE: currently this is only compatible with `.go` and `*_test.go` files
function M.open()
    local altfile = find_altfile(vim.fn.expand("%:p"))

    if altfile then
        vim.cmd("e " .. altfile)
    end
end

---@param opts table?
function M.setup(opts)
    o = vim.tbl_deep_extend("force", o, opts)
end

return M
