# qfedit.nvim

Edit the *entries* of a Neovim quickfix list using ordinary buffer editing, like Oil or Harpoon. Changes to this buffer **do not modify source files**.

## Installation

For a local plugin, copy `lua/qfedit/init.lua` and `plugin/qfedit.lua` into your `~/.config/nvim/` directory. Alternatively, put this directory on Neovim's `runtimepath` and invoke `require('qfedit').setup()` once.

## Configuration

```lua
require('qfedit').setup({
  hijack = true,          -- replace native quickfix windows opened by :copen
  layout = 'horizontal',  -- 'horizontal', 'vertical', or 'float'
  autosave = true,        -- sync changes when returning to Normal mode
})
```

All values shown are defaults. Setting `hijack = false` retains the original behavior: native `:copen` works normally and `:QfEdit` opens the editable buffer explicitly.

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
