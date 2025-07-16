local M = {}

local config = {
    colors = {
        dir = vim.api.nvim_get_hl(0, { name = "Directory" }).fg, -- TODO: switch to passing fg and bg
        file = vim.api.nvim_get_hl(0, { name = "Normal" }).fg,
    },
}

local state = {
    cwd = vim.loop.cwd(),
    bufnr = nil,
    winid = nil,
    ns_id = nil,
    show_hidden = false,
}

-- TODO: replace with mini.icons
local icons = {
    folder = "",
    file = "",
    lua = "",
    md = "",
    txt = "",
    json = "",
    toml = "",
}

-- Get icon by file type
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
---@param opts table?
local function render(opts)
    if opts then
        opts = vim.tbl_deep_extend("force", {}, opts)
    else
        opts = {}
    end

    local entries = scan_dir(opts.cwd or state.cwd)
    local lines = { icons.folder .. " .." }

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

    vim.api.nvim_set_hl(0, "FilesDir", { fg = config.colors.dir })
    vim.api.nvim_set_hl(0, "FilesFile", { fg = config.colors.file })

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

-- Create a new file
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
        return
    end

    -- Create the file
    local file = io.open(filepath, "w")
    if file then
        file:close()
        vim.notify("Created file: " .. filename, vim.log.levels.INFO)
        render() -- Refresh the display
    else
        vim.notify("Failed to create file: " .. filename, vim.log.levels.ERROR)
    end

    return filename
end

-- Create a new directory
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
            return -- User cancelled (ESC)
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
            -- Do nothing, user cancelled
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

-- Open the file explorer
---@param opts table?
function M.open(opts)
    -- TODO: pass in opts.args[1] as cwd to render func

    state.bufnr = vim.api.nvim_create_buf(false, true)
    state.ns_id = vim.api.nvim_create_namespace("files")

    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = state.bufnr })
    vim.bo[state.bufnr].filetype = "files"

    -- File/directory creation keymaps (netrw style)
    vim.api.nvim_buf_set_keymap(state.bufnr, "n", "%", "", {
        callback = function()
            local filename = create_file()
            if filename then
                vim.cmd("edit " .. filename)
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

vim.api.nvim_create_user_command("ExOpen", M.open, { nargs = "?" })
vim.keymap.set("n", "<C-m>", "<cmd>ExOpen<cr>", { silent = true })

return M
