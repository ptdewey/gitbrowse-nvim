# Deez

A collection of small utilities for Neovim

## Installation

With lazy.nvim:
```lua
{
    "ptdewey/deez-nvim",
    config = function()
        require("deez").setup({})
    end
}
```

---

# Utilities

## GitBrowse

Open the link to *any* git repository from Neovim

- Inspired by [vim-rhubarb](https://github.com/tpope/vim-rhubarb)'s `GBrowse` command, which only works for GitHub repositories


### Usage

```lua
{
    "ptdewey/deez-nvim",
    config = function()
        require("deez").setup({
            load_all = true,

            -- Or, loading only GitBrowse
            load_all = false,
            gitbrowse = true,
        })

        -- Keymap
        vim.keymap.set("n", "<leader>gb", function()
            require("deez.gitbrowse").open()
        end, { desc = "Open current Git repository in browser" })

        -- Command
        vim.api.nvim_create_user_command("GitBrowse", function()
            require("deez.gitbrowse").open()
        end, { desc = "Open current Git repository in browser" })
    end
}
```

---

## AltFile

Switch to "alternate" files quickly. This is primarily targeting test files for go, allowing you to quickly switch between a source file and its associated test file (i.e. `foo.go` and `foo_test.go`) with one command/keybind.

> [!NOTE]
> Currently only works for '*.go/*_test.go' files

```lua
{
    "ptdewey/deez-nvim",
    config = function()
        require("deez").setup({
            load_all = true,

            -- Or, loading only AltFile
            load_all = false,
            altfile = true,
        })

        -- Keymap
        vim.keymap.set("n", "<leader>tf", function()
            require("deez.altfile").open()
        end, { desc = "Switch to alternate file" })

        -- Command
        vim.api.nvim_create_user_command("AltFile", function()
            require("deez.altfile").open()
        end, { desc = "Switch to alternate file" })
    end
}
```

---

## GoGit

**TODO:** GoGit allows quickly opening dependency repos/godoc links in your browser, straight from the imports list
