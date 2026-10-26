# qfedit.nvim

Edit the *entries* of a Neovim quickfix list using ordinary buffer editing, like Oil or Harpoon. Changes to this buffer **do not modify source files**.

## Installation

The repository is `donatomartin/qfedit.nvim`. No external dependencies are required.

### Native `vim.pack` (Neovim 0.12+)

```lua
vim.pack.add({
  'https://github.com/donatomartin/qfedit.nvim',
})

require('qfedit').setup()
```

### lazy.nvim

```lua
{
  'donatomartin/qfedit.nvim',
  config = function()
    require('qfedit').setup()
  end,
}
```

For a lazy.nvim plugin spec, add the table above to your plugin list or return it from a file under `lua/plugins/`.

### packer.nvim

```lua
use {
  'donatomartin/qfedit.nvim',
  config = function()
    require('qfedit').setup()
  end,
}
```

Place this inside your `require('packer').startup(function(use) ... end)` configuration, then run `:PackerSync`.

### vim-plug

In your `init.vim`:

```vim
call plug#begin()
Plug 'donatomartin/qfedit.nvim'
call plug#end()

lua require('qfedit').setup()
```

Run `:PlugInstall` after updating the plugin list.

### Manual installation

Clone the repository into a directory on Neovim's `runtimepath`, or copy `lua/qfedit/init.lua` and `plugin/qfedit.lua` to the matching paths in your Neovim configuration.

**Note:** `plugin/qfedit.lua` calls `setup()` automatically. If you provide custom options, call `require('qfedit').setup({...})` in your configuration. The setup function can be called again safely to replace options without registering duplicate commands.

## Configuration

```lua
require('qfedit').setup({
  hijack = true,          -- replace native quickfix windows opened by :copen
  layout = 'horizontal',  -- 'horizontal', 'vertical', or 'float'
  autosave = true,        -- sync changes when returning to Normal mode
  highlight = true,       -- color path, filename, position and diagnostics
})
```

All values shown are defaults. `highlight = true` uses extmarks to color directories, filenames, positions and diagnostic messages without changing buffer text. It follows your colorscheme's standard highlight groups. Override `QfEditDirectory`, `QfEditFilename`, `QfEditPosition`, `QfEditSeparator`, `QfEditMessage`, `QfEditError`, `QfEditWarning`, `QfEditInfo` and `QfEditHint` to customize the look. Setting `highlight = false` disables these decorations. Setting `hijack = false` retains the original behavior: native `:copen` works normally and `:QfEdit` opens the editable buffer explicitly.

`autosave = true` saves after Normal-mode buffer modifications and upon `InsertLeave`. `:w` remains available for manual synchronization. External quickfix modifications are protected by a changedtick conflict check.

## Usage

1. Populate quickfix (`:vimgrep`, `:make`, `:cexpr`, Telescope, etc.).
2. `:QfEdit` opens an editable split.
3. Use normal Vim motions: `dd`, `p`, `:sort`, `o`, and so on.
4. `:w` replaces the original quickfix list with your edited entries.
5. `<CR>` opens the entry under the cursor.

Lines are formatted as one of:

```
/path/to/File.java
/path/to/File.java:25:4
/path/to/File.java:25:4 | an existing error message
```

Existing identical lines preserve original quickfix metadata (type, module, user_data, etc.) even when reordered. Changed/new lines are interpreted as fresh entries. Whitespace-only lines are ignored. Relative paths are resolved by Neovim relative to the working directory when saved.

## Limitations

- Editing a line creates a new entry; additional original metadata is not preserved for that edited line.
- If other commands modify the original quickfix list between opening and writing, saving refuses to overwrite it. The edited buffer is preserved; manually copy its contents and reopen using `:QfEdit` to reconcile.
- Each row should represent a file. Unusual filenames containing the sequence ` | ` or ending in `:number` may be parsed ambiguously.
- This initial version edits the global quickfix list, not location lists. It does not automatically persist lists across Neovim restarts.
