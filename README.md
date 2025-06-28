# GitBrowse

Open the link to *any* git repository from Neovim

- Inspired by [vim-rhubarb](https://github.com/tpope/vim-rhubarb)'s `GBrowse` command, which only works for GitHub repositories

## Installation

With lazy.nvim:
```lua
{
    "ptdewey/gitbrowse-nvim",
    config = function()
        require("gitbrowse").setup()
    end
}
```

## Usage

Create a keymap or command in your config
```lua
{
    "ptdewey/gitbrowse-nvim",
    config = function()
        require("gitbrowse").setup()

        -- Keymap
        vim.keymap.set("n", "<leader>gb", function()
            require("gitbrowse").open()
        end, { desc = "Open current Git repository in browser" })

        -- Command
        vim.api.nvim_create_user_command("GitBrowse", function()
            require("gitbrowse").open()
        end, { desc = "Open current Git repository in browser" })
    end
}
```
