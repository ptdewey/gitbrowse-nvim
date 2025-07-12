local M = {}

local o = {}

---@param opts table?
function M.setup(opts)
    opts = vim.tbl_deep_extend("force", o, opts)
end

return M
