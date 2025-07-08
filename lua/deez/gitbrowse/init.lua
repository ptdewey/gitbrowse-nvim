local M = {}

local o = {}

---@param filepath string
---@return string
local function get_git_link(filepath)
    local dir = vim.fn.fnamemodify(filepath, ":p:h")
    local repo_url =
        vim.fn.system("git -C " .. dir .. " config --get remote.origin.url")
    repo_url = repo_url:gsub("\n", ""):gsub("%.git$", "")

    local branch_name = vim.fn
        .system("git -C " .. dir .. " branch --show-current")
        :gsub("\n", "")

    if branch_name ~= "" then
        -- TODO: open filepath as well (requires knowledge of the repo root)
        repo_url = repo_url .. "/blob/" .. branch_name
    end

    return repo_url
end

---@param git_link string
local function ssh_to_https(git_link)
    if git_link:match("^git@") then
        git_link = git_link:gsub(":", "/"):gsub("git@", "https://")
    end
    return git_link
end

--- Open the git repository link in the default browser.
--- REFACTOR: move to a "utils" package (with git/filepath stuff extracted and a link param)
function M.open()
    local filepath = vim.fn.expand("%:p")
    local git_link = get_git_link(filepath)

    if git_link == "" then
        print("Working directory is not a git repository")
        return
    end

    local openable_link = ssh_to_https(git_link)
    print(openable_link)

    vim.ui.open(openable_link)
end

---@param opts table?
function M.setup(opts)
    o = vim.tbl_deep_extend("force", o, opts)
end

return M
