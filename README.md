# panels.nvim

Minimal split panel manager for Neovim.

## Why

`edgy.nvim` is a great plugin if you want a full layout system for view windows. It can group, animate, pin, close, resize, and decorate views in many different ways.

That was more than I needed. I only wanted one place to configure and manage the ordinary split windows opened by different plugins: sidebars, terminals, quickfix lists, task output, and search results.

I also wanted to avoid extra UI controls, like the built-in collapse/minimize button for each view. `panels.nvim` does not try to be a view framework. It just gives plugin-owned splits a shared layout contract.

`panels.nvim` gives those splits a small shared contract:

- match a window by filetype and an optional filter
- move it to `left`, `right`, `bottom`, or `top`
- apply a configured size only on first placement or explicit equalization
- focus an existing panel instead of running its opener again

## Requirements

- Neovim 0.10+

## Installation

With `vim.pack`:

```lua
vim.pack.add({
  { src = "https://github.com/so1ve/panels.nvim" },
})
```

With `lazy.nvim`:

```lua
{
  "so1ve/panels.nvim",
  opts = {
    layers = { "bottom", "top", "left", "right" },
    positions = {
      left = 0.25,
      right = 0.25,
      bottom = 12,
      top = 10,
    },
    panels = {
      quickfix = { position = "bottom", ft = "qf", title = "Quickfix" },
    },
  },
}
```

## Usage

Configure the panels you want to manage:

```lua
require("panels").setup({
  layers = { "bottom", "top", "left", "right" },
  positions = {
    left = 0.25,
    right = 0.25,
    bottom = 12,
    top = 10,
  },
  panels = {
    quickfix = {
      title = "Quickfix",
      position = "bottom",
      ft = "qf",
    },
    terminal = {
      title = "Terminal",
      position = "bottom",
      ft = "",
      filter = function(buf, win)
        return vim.bo[buf].buftype == "terminal" and vim.api.nvim_win_get_config(win).relative == ""
      end,
    },
  },
})
```

Open or focus a panel by id:

```lua
vim.keymap.set("n", "<leader>q", function()
  require("panels").open("quickfix", "copen")
end)
```

Use `focus = false` when an opener should create or reveal a panel without stealing focus:

```lua
require("panels").open("quickfix", "copen", { focus = false })
```

Restore configured panel sizes after manual resizing:

```lua
vim.keymap.set("n", "<leader>=", function()
  require("panels").equalize()
end)
```

## Configuration

Default configuration:

```lua
require("panels").setup({
  defaults = {
    focus = true,
    wait = 3000,
  },
  layers = { "bottom", "top", "left", "right" },
  positions = {},
  panels = {},
})
```

Panel fields:

- `position`: one of `left`, `right`, `bottom`, or `top`
- `ft`: optional filetype match; use `""` to match buffers with an empty filetype
- `filter`: optional function called as `filter(buf, win)` for additional matching
- `size`: optional panel size; integers are cells, fractions are percentages of the editor size
- `title`: optional window bar title
- `wo`: optional window-local options applied to the panel window; set `winbar = false` to disable the generated title

Global `positions` provide default sizes by edge. A panel-local `size` overrides its edge default.

`layers` controls which edges cover other edges. Earlier entries are placed first; later entries stay outside them. The default keeps side panels outside top and bottom panels.

## API

### `setup(config?)`

Registers panels and starts the lightweight window arrangement autocmds.

### `open(id, opener, opts?, ...)`

Focuses an existing panel with the same id, or runs `opener` when no matching panel exists.

`opener` can be a command string or a function. Extra arguments are passed to function openers.

Options:

- `focus`: defaults to `true`; set to `false` to return to the previous window after opening
- `wait`: defaults to `3000`; milliseconds to wait for async openers that create the panel later

### `equalize()`

Runs `<C-w>=` and reapplies configured panel sizes.

Manual resizes are otherwise preserved across automatic arrangement events.

## 📝 License

[MIT](./LICENSE). Made with ❤️ by [Ray](https://github.com/so1ve)
