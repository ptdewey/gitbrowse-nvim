local M = {}

local default_opts = {
    load_all = true,
    gitbrowse = false,
    altfile = false,
}

---@param opts table?
function M.setup(opts)
    opts = vim.tbl_deep_extend("force", default_opts, opts)

    if opts.load_all or opts.gitbrowse then
        M.gitbrowse = require("deez.gitbrowse")
        M.gitbrowse.setup(opts)
    end

    if opts.load_all or opts.altfile then
        M.altfile = require("deez.altfile")
        M.altfile.setup(opts)
    end
end

return M
