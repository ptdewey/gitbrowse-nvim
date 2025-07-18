local M = {}

-- TODO:
-- - Fuzzy searching (delegate to fzf-lua/any picker?)
--   - "/" search searches for files within current context (even if they are in dirs/hidden?)
-- - Sorting results (with frecency being one of the options)
--   - Possibly show active sort option somewhere?
-- - Allow setting custom icon provider
-- - Add other keymaps to keys table

local config = {
    colors = {
        dir = vim.api.nvim_get_hl(0, { name = "Directory" }),
        file = vim.api.nvim_get_hl(0, { name = "Normal" }),
    },
    keys = {
        open = { key = nil, opts = { desc = "Open Explorer", noremap = true } },
        toggle = { key = nil, opts = { desc = "Toggle Explorer", noremap = true } },
        close = { key = nil, opts = { desc = "Close Explorer", noremap = true } },
    },
    open_in_current_dir = false,
    style = {
        show_goto_parent = true,
    },
}

local state = {
    cwd = vim.loop.cwd(),
    bufnr = nil,
    winid = nil,
    ns_id = nil,
    show_hidden = false,
}

-- Get icon by filetype
---@param name string
---@param is_dir boolean
---@return string
local function get_icon(name, is_dir)
    if is_dir then
        return require("mini.icons").get("directory", name)
            or require("mini.icons").get("directory", "default")
    end
    local ext = name:match("^.+%.(.+)$")
    if ext then
        return require("mini.icons").get("extension", ext)
            or require("mini.icons").get("extension", "default")
    else
        return require("mini.icons").get("extension", "default")
    end
end

-- List directory entries
local function scan_dir(path)
    local fs = vim.loop.fs_scandir(path)
    local entries = {}

    if fs then
        while true do
            local name, type = vim.loop.fs_scandir_next(fs)
            if not name then
                break
            end

            if state.show_hidden or not name:match("^%.") then
                table.insert(entries, {
                    name = name,
                    type = type,
                })
            end
        end
    end

    table.sort(entries, function(a, b)
        if a.type == b.type then
            return a.name:lower() < b.name:lower()
        end
        return a.type == "directory"
    end)

    return entries
end

-- Render file list into buffer
local function render()
    local entries = scan_dir(state.cwd)
    local lines = {}
    if config.style.show_goto_parent then
        lines = { require("mini.icons").get("directory", "default") .. " .." }
    end

    for _, entry in ipairs(entries) do
        if entry.name and entry.type then
            local icon = get_icon(entry.name, entry.type == "directory")
            table.insert(lines, icon .. " " .. entry.name)
        end
    end

    vim.bo[state.bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
    vim.bo[state.bufnr].modifiable = false

    -- Apply highlights
    vim.api.nvim_buf_clear_namespace(state.bufnr, -1, 0, -1)

    ---@diagnostic disable-next-line: param-type-mismatch
    vim.api.nvim_set_hl(0, "FilesDir", config.colors.dir)
    ---@diagnostic disable-next-line: param-type-mismatch
    vim.api.nvim_set_hl(0, "FilesFile", config.colors.file)

    for i, line in ipairs(lines) do
        local name = line:match("^.+%s(.+)$")
        if name == ".." then
            vim.api.nvim_buf_set_extmark(state.bufnr, state.ns_id, i - 1, 0, {
                end_col = #line,
                hl_group = "FilesDir",
            })
        else
            local path = state.cwd .. "/" .. name
            local stat = vim.loop.fs_stat(path)
            if stat then
                local hl_group = (stat.type == "directory") and "filesDir"
                    or "FilesFile"
                vim.api.nvim_buf_set_extmark(
                    state.bufnr,
                    state.ns_id,
                    i - 1,
                    0,
                    {
                        end_col = #line,
                        hl_group = hl_group,
                    }
                )
            end
        end
    end
end

local function render_parent()
    state.cwd = vim.fn.fnamemodify(state.cwd, ":h")
    render()
end

-- Handle <CR>: open file or descend into dir
local function on_enter()
    local cursor = vim.api.nvim_win_get_cursor(0)[1]
    local line =
        vim.api.nvim_buf_get_lines(state.bufnr, cursor - 1, cursor, false)[1]
    local name = line:match("^.+%s(.+)$")
    if not name then
        return
    end

    if name == ".." then
        state.cwd = vim.fn.fnamemodify(state.cwd, ":h")
        render()
        return
    end

    local path = state.cwd .. "/" .. name
    local stat = vim.loop.fs_stat(path)
    if not stat then
        return
    end

    if stat.type == "directory" then
        state.cwd = path
        render()
    else
        vim.cmd("edit " .. vim.fn.fnameescape(path))
    end
end

--- Create a new file
local function create_file()
    local filename = vim.fn.input("Enter filename: ")
    if filename == "" then
        return
    end

    local filepath = state.cwd .. "/" .. filename

    -- Check if file already exists
    local stat = vim.loop.fs_stat(filepath)
    if stat then
        vim.notify("File already exists: " .. filename, vim.log.levels.WARN)
        return filepath -- Still return the path to open it
    end

    return filepath
end

--- Create a new directory
local function create_dir()
    local dirname = vim.fn.input("Enter directory name: ")
    if dirname == "" then
        return
    end

    local dirpath = state.cwd .. "/" .. dirname

    -- Check if directory already exists
    local stat = vim.loop.fs_stat(dirpath)
    if stat then
        vim.notify("Directory already exists: " .. dirname, vim.log.levels.WARN)
        return
    end

    -- Create the directory
    local success = vim.loop.fs_mkdir(dirpath, 493) -- 493 = 0755 in decimal
    if success then
        vim.notify("Created directory: " .. dirname, vim.log.levels.INFO)
        render() -- Refresh the display
    else
        vim.notify(
            "Failed to create directory: " .. dirname,
            vim.log.levels.ERROR
        )
    end
end

-- Delete file or directory
local function delete_entry()
    local cursor = vim.api.nvim_win_get_cursor(0)[1]
    local line =
        vim.api.nvim_buf_get_lines(state.bufnr, cursor - 1, cursor, false)[1]
    local name = line:match("^.+%s(.+)$")

    if not name or name == ".." then
        vim.notify(
            "Cannot delete parent directory reference",
            vim.log.levels.WARN
        )
        return
    end

    local path = state.cwd .. "/" .. name
    local stat = vim.loop.fs_stat(path)
    if not stat then
        vim.notify("File/directory not found: " .. name, vim.log.levels.ERROR)
        return
    end

    -- Confirm deletion using vim.ui.input
    local entry_type = stat.type == "directory" and "directory" or "file"
    vim.ui.input({
        prompt = "Delete " .. entry_type .. " '" .. name .. "'? ({y}es/{n}o): ",
        -- default = "n",
    }, function(input)
        if not input then
            return -- User canceled (ESC)
        end

        input = input:lower():gsub("^%s*(.-)%s*$", "%1") -- trim whitespace

        if input == "y" or input == "yes" then
            local success
            if stat.type == "directory" then
                success = vim.loop.fs_rmdir(path)
            else
                success = vim.loop.fs_unlink(path)
            end

            if success then
                vim.notify("Deleted: " .. name, vim.log.levels.INFO)
                render() -- Refresh the display
            else
                vim.notify("Failed to delete: " .. name, vim.log.levels.ERROR)
            end
        elseif input == "n" or input == "no" then
            -- Do nothing, user canceled
            return
        else
            vim.notify("Please enter y/yes or n/no", vim.log.levels.WARN)
        end
    end)
end

-- Rename file or directory
local function rename_entry()
    local cursor = vim.api.nvim_win_get_cursor(0)[1]
    local line =
        vim.api.nvim_buf_get_lines(state.bufnr, cursor - 1, cursor, false)[1]
    local name = line:match("^.+%s(.+)$")

    if not name or name == ".." then
        vim.notify(
            "Cannot rename parent directory reference",
            vim.log.levels.WARN
        )
        return
    end

    local old_path = state.cwd .. "/" .. name
    local stat = vim.loop.fs_stat(old_path)
    if not stat then
        vim.notify("File/directory not found: " .. name, vim.log.levels.ERROR)
        return
    end

    local new_name = vim.fn.input("Rename to: ", name)
    if new_name == "" or new_name == name then
        return
    end

    local new_path = state.cwd .. "/" .. new_name

    -- Check if target already exists
    local target_stat = vim.loop.fs_stat(new_path)
    if target_stat then
        vim.notify("Target already exists: " .. new_name, vim.log.levels.WARN)
        return
    end

    local success = vim.loop.fs_rename(old_path, new_path)
    if success then
        vim.notify(
            "Renamed " .. name .. " to " .. new_name,
            vim.log.levels.INFO
        )
        render() -- Refresh the display
    else
        vim.notify("Failed to rename: " .. name, vim.log.levels.ERROR)
    end
end

-- Toggle hidden files visibility
local function toggle_hidden()
    state.show_hidden = not state.show_hidden
    local status = state.show_hidden and "shown" or "hidden"
    vim.notify("Hidden files " .. status, vim.log.levels.INFO)
    render()
end

-- Refresh the directory listing
local function refresh()
    render()
    vim.notify("Refreshed directory listing", vim.log.levels.INFO)
end

-- Reset state when buffer is closed
local function reset_state()
    state.cwd = vim.loop.cwd()
    state.bufnr = nil
    state.winid = nil
    state.ns_id = nil
    state.show_hidden = false
end

-- Open the file explorer
---@param opts table?
function M.open(opts)
    if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
        -- If no args provided, do nothing (graceful exit)
        if not opts or not opts.args or opts.args == "" then
            return
        end

        -- If path provided, navigate to it
        local target_path = opts.args
        if vim.fn.isdirectory(target_path) == 1 then
            state.cwd = vim.fn.fnamemodify(target_path, ":p:h")
            render()
        else
            vim.notify(
                "Invalid directory: " .. target_path,
                vim.log.levels.ERROR
            )
        end
        return
    end

    -- Determine starting directory
    if opts and opts.args and opts.args ~= "" then
        state.cwd = opts.args
    else
        -- Check opts.open_in_current_dir first, then fall back to config
        local use_current_dir = config.open_in_current_dir
        if opts and opts.open_in_current_dir ~= nil then
            use_current_dir = opts.open_in_current_dir
        end

        if use_current_dir == nil then
            use_current_dir = config.open_in_current_dir
        end

        if use_current_dir then
            -- Open in the directory of the current file
            local current_file = vim.fn.expand("%:p")
            if current_file ~= "" then
                state.cwd = vim.fn.fnamemodify(current_file, ":h")
            else
                state.cwd = vim.loop.cwd()
            end
        else
            -- Default to current working directory
            state.cwd = vim.loop.cwd()
        end
    end

    state.bufnr = vim.api.nvim_create_buf(false, true)
    state.ns_id = vim.api.nvim_create_namespace("DeezFiles")

    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = state.bufnr })
    vim.bo[state.bufnr].filetype = "DeezFiles"

    -- Set up buffer cleanup autocmd
    vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
        buffer = state.bufnr,
        callback = reset_state,
        once = true,
    })

    vim.api.nvim_create_autocmd("BufEnter", {
        buffer = state.bufnr,
        callback = function()
            vim.opt_local.spell = false
        end
    })

    vim.api.nvim_buf_set_keymap(state.bufnr, "n", "<CR>", "", { callback = on_enter, })

    -- File/directory creation keymaps (netrw style)
    vim.api.nvim_buf_set_keymap(state.bufnr, "n", "%", "", {
        callback = function()
            local filepath = create_file()
            if filepath then
                vim.cmd("edit " .. vim.fn.fnameescape(filepath))
            end
        end,
        noremap = true,
        silent = true,
        desc = "Create new file",
    })

    vim.api.nvim_buf_set_keymap(state.bufnr, "n", "d", "", {
        callback = create_dir,
        noremap = true,
        silent = true,
        desc = "Create new directory",
    })

    -- File operations
    vim.api.nvim_buf_set_keymap(state.bufnr, "n", "D", "", {
        callback = delete_entry,
        noremap = true,
        silent = true,
        desc = "Delete file/directory",
    })

    vim.api.nvim_buf_set_keymap(state.bufnr, "n", "R", "", {
        callback = rename_entry,
        noremap = true,
        silent = true,
        desc = "Rename file/directory",
    })

    -- Refresh
    vim.api.nvim_buf_set_keymap(state.bufnr, "n", "<C-l>", "", {
        callback = refresh,
        noremap = true,
        silent = true,
        desc = "Refresh directory listing",
    })

    vim.api.nvim_buf_set_keymap(
        state.bufnr,
        "n",
        "-",
        "",
        { callback = render_parent }
    )

    vim.api.nvim_buf_set_keymap(state.bufnr, "n", "gh", "", {
        callback = toggle_hidden,
        noremap = true,
        silent = true,
        desc = "Toggle hidden files",
    })

    vim.cmd("enew") -- replace current buffer
    vim.api.nvim_win_set_buf(0, state.bufnr)

    render()
end

---@param opts table?
function M.toggle(opts)
    if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
        vim.api.nvim_buf_delete(state.bufnr, {})
    else
        M.open(opts)
    end
end

function M.close()
    if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
        vim.api.nvim_buf_delete(state.bufnr, {})
    end
end

---@param opts table?
function M.setup(opts)
    config = vim.tbl_deep_extend("force", config, opts)

    if config.keys.open.key then
        vim.keymap.set("n", config.keys.open.key, M.open, config.keys.open.opts)
    end

    if config.keys.toggle.key then
        vim.keymap.set("n", config.keys.toggle.key, M.toggle, config.keys.toggle.opts)
    end

    if config.keys.close.key then
        vim.keymap.set("n", config.keys.close.key, M.close, config.keys.close.opts)
    end

    vim.api.nvim_create_user_command("ExOpen", M.open, { nargs = "?" })
end

return M
