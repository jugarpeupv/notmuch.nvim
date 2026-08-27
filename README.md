# 📨 Notmuch.nvim

A powerful and flexible mail reader interface for NeoVim. This plugin bridges
your email and text editing experiences directly within NeoVim by interfacing
with the [Notmuch mail indexer](https://notmuchmail.org).

1. [Introduction](#introduction)
2. [Feature Overview](#feature-overview)
3. [Requirements](#requirements)
4. [Installation](#installation)
5. [Usage](#usage)
6. [Composing and Replying](#composing-and-replying)
7. [Configuration Options](#configuration-options)
8. [License](#license)

## Introduction

**Notmuch.nvim** is a NeoVim plugin that serves as a front-end for the Notmuch
mail indexer, enabling users to read, compose, and manage their emails from
within NeoVim. It facilitates a streamlined workflow for handling emails using
the familiar Vim interface and motions.

<!--
> [!IMPORTANT]
> This plugin requires NeoVim 0.5 or later to leverage its LuaJIT capabilities.
> You also need to have `telescope.nvim` for this plugin to work.
-->

## Feature Overview

- 📧 **Email Browsing**: Navigate emails with Vim-like movements.
- 🔍 **Search Your Email**: Leverage `notmuch` to search your email interactively.
- 🔗 **Thread Viewing**: Messages are loaded with folding and threading intact.
- 📎 **Attachment Management**: View, open and save attachments from received mail.
- ✉️ **Compose and Reply**: Write new emails and replies with MIME support.
- 📂 **Outgoing Attachments**: Attach files via commands, prompts, or paste from
  [oil.nvim](https://github.com/stevearc/oil.nvim) buffers.
- 🌐 **Inline HTML Rendering**: Render HTML email bodies as text via `w3m`.
- ⬇️ **Offline Mail Sync**: Supports `mbsync` for efficient sync processes, with buffer, background, and interactive terminal modes.
- 🔓 **Async Search**: Large mailboxes with thousands of email? No problem.
- 🏷️ **Tag Management**: Conveniently add, remove, or toggle email tags.
- 💻 **Pure Lua**: Fully implemented in Lua for performance and maintainability.
- 🔭 (WIP) ~~**Telescope.nvim Integration**: Search interactively, extract URL's, jump
  efficiently, with the powerful file picker of choice.~~

## Requirements

- **[NeoVim](https://github.com/neovim/neovim)**: Version 0.10 or later is
  required (uses `vim.system()`, `vim.b` buffer variables, and other modern APIs).
- **[Notmuch](https://notmuchmail.org)**: Ensure Notmuch and libnotmuch library
  are installed
- **[w3m](http://w3m.sourceforge.net/)** (optional): Required for inline HTML
  email rendering when `render_html_body = true`
- (WIP) ~~**[Telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)**: File
  picker of choice for many use cases.~~

## Installation

You can install Notmuch.nvim using your favorite NeoVim plugin manager.

### Using `lazy.nvim`:
```lua
{
    'yousefakbar/notmuch.nvim',
    config = function()
        -- Configuration goes here
        local opts = {}
        require('notmuch').setup(opts)
    end,
}
```

### Using `vim.pack`:

If you are using `nvim` v0.12, or above, you can install using the builtin
package manager:

```lua
vim.pack.add({
    'https://github.com/yousefakbar/notmuch.nvim',
})

-- Or to pin to a specific tag/version:

vim.pack.add({
  {
    src = 'https://github.com/yousefakbar/notmuch.nvim',
    version = 'v0.3.0', -- Or git commit, etc.
  },
})
```

### Manual Installation:
Clone the repository and add the directory to your `runtimepath`:
```bash
git clone https://github.com/yousefakbar/notmuch.nvim.git
```

## Usage

Here are the core commands within Notmuch.nvim:

- **`:Notmuch`**: Lists available tags in your Notmuch database in a buffer.
  Setup key bindings for easy access. Example: 

  ```lua
  -- Define a keymap to run `:Notmuch` and launch the plugin landing page
  vim.keymap.set("n", "<leader>n", "<CMD>Notmuch<CR>")
  ```

- **`:NmSearch <query>`**: Executes an asynchronous search based on provided
  Notmuch query terms.

  ```vim
  " Loads the threads in your inbox received today
  :NmSearch tag:inbox and date:today
  ```

- **`:Inbox [email]`**: Quick access to your inbox. Optionally filter by
  recipient email address (Useful for multi-account setups.)

  ```vim
  " Open all inbox messages
  :Inbox

  " Open inbox for a specific account
  :Inbox work@example.com
  ```

## Composing and Replying

### Commands

- **`:ComposeMail [to]`**: Open a compose buffer for a new email. Optionally
  provide a recipient address.
- **`C`**: Compose a new email (mapped in hello, threads, and thread view buffers).
- **`R`**: Reply to the message under the cursor (mapped in thread view).
- **`<C-g><C-g>`**: Send the email from the compose buffer (configurable via
  `keymaps.sendmail`).
- **`<C-g><C-a>`**: Toggle the attachment window (configurable via
  `keymaps.attachment_window`).

The compose buffer is a standard editable buffer with email headers (`From`,
`To`, `Cc`, `Subject`) at the top and the message body below. Sending uses
`msmtp` under the hood.

### Attachments

There are several ways to attach files to an outgoing email:

#### 1. `:Attach` command

From the compose buffer, run `:Attach <path>` with file completion:

```vim
:Attach ~/Documents/report.pdf
:Attach /tmp/screenshot.png
```

Use `:AttachRemove <path>` to remove an attachment (with completion from the
current attachment list), and `:AttachList` to open the attachment window.

#### 2. Attachment window

Press `<C-g><C-a>` (or run `:AttachList`) to open the attachment buffer. This
is an editable buffer (similar to oil.nvim) where each line below the header
is a file path:

| Key  | Action                       |
| :--- | :--------------------------- |
| `a`  | Add attachment via prompt    |
| `dd` | Delete attachment            |
| `p`  | Paste (with oil.nvim support)|
| `:w` | Save/validate attachments    |
| `q`  | Close window                 |

You can also type or paste absolute paths directly and press `:w` to validate
and save them.

#### 3. Paste from oil.nvim

If you use [oil.nvim](https://github.com/stevearc/oil.nvim), you can yank a
line from an oil buffer (`yy`) and paste it into the attachment window with
`p`. The plugin uses oil's API (`oil.get_entry_on_line()` and
`oil.get_current_dir()`) to resolve the actual file path regardless of your
oil column configuration.

This also works as a fallback when saving (`:w`) the attachment buffer -- if a
line doesn't resolve as a direct path, the plugin checks open oil buffers to
see if it matches a rendered oil line and resolves it automatically.

> **Note**: oil.nvim is entirely optional. All attachment features work without
> it. The oil integration is a convenience for users who already use oil as
> their file manager.

## Configuration Options

You can configure several global options to tailor the plugin's behavior:

| Option             | Description                                                                     | Default                         |
| :----------------- | :-----------------------------------------------------------------------------: | :------------------------------ |
| `notmuch_db_path`  | Directory containing the `.notmuch/` dir                                        | From `notmuch config`           |
| `from`             | From header used when composing new mail                                        | From `notmuch config`           |
| `from_cmd`         | Command whose output overrides `From:` on new mail compose (e.g. `pass show mail/from`) | `nil`                    |
| `draft_dir`        | Directory where unsent drafts are stored; they survive Neovim restarts and are deleted after a successful send | `~/.local/share/nvim/notmuch/drafts` |
| `signature_file`   | Path to a file whose contents are appended as signature to new mails. `.txt` → plain text (with `-- ` delimiter); `.html`/`.htm` → HTML signature with Outlook-style `multipart/alternative` + inline images via `cid:` | `nil`                           |
| `maildir_sync_cmd` | Bash command to run for syncing maildir                                         | `mbsync -a`                     |
| `sync.sync_mode`   | Sync display mode: `"buffer"`, `"background"`, or `"terminal"` (PTY with stdin) | `buffer`                        |
| `keymaps`          | Configure any (WIP) command's keymap                                            | See `config.lua`[1]             |
| `open_handler`     | Callback function for opening attachments                                       | Runs OS-aware `open`[2]         |
| `view_handler`     | Callback function for converting attachments to text to view in floating window | See `default_view_handler()`[2] |
| `render_html_body` | Render HTML email bodies inline using `w3m` (requires `w3m` installed)          | `false`                         |
| `suppress_deprecation_warning` | Suppress the warning shown when using deprecated notmuch API (< 0.32) | `false`                         |

[1]: https://github.com/yousefakbar/notmuch.nvim/blob/main/lua/notmuch/config.lua
[2]: https://github.com/yousefakbar/notmuch.nvim/blob/main/lua/notmuch/handlers.lua

Example configuration in plugin manager (lazy.nvim):

```lua
{
    "yousefakbar/notmuch.nvim",
    opts = {
        notmuch_db_path = "/home/xxx/Documents/Mail",
        maildir_sync_cmd = "mbsync personal",
        sync = {
            sync_mode = "buffer" -- OR "background" OR "terminal"
        },
        keymaps = {
            sendmail = "<C-g><C-g>",
        },
        render_html_body = true, -- Render HTML emails inline (requires w3m)
    },
},
```

### Customizing Attachment Handlers

The plugin provides two handlers for working with attachments:

**Open Handler**: Opens attachments externally with your system's default
application. The default handler automatically detects your OS and uses `open`
(macOS), `xdg-open` (Linux), or `start` (Windows).

**View Handler**: Converts attachments to text for display in a floating window
within Neovim. The default handler supports HTML, PDF, images, Office documents,
Markdown, archives, and plain text files. It tries multiple CLI tools for each
format and falls back gracefully if tools aren't available.

To customize either handler, pass a function to `setup()`:

```lua
require('notmuch').setup({
    -- Custom open handler
    open_handler = function(attachment)
        -- attachment.path contains the full file path
        vim.fn.system({ 'my-custom-opener', attachment.path })
    end,

    -- Custom view handler
    view_handler = function(attachment)
        -- Must return a string to display in the floating window
        local path = attachment.path
        if path:match('%.pdf$') then
            return vim.fn.system({ 'pdftotext', '-layout', path, '-' })
        end
        return vim.fn.system({ 'cat', path })
    end,
})
```

The default handlers are defined in `lua/notmuch/handlers.lua` and handle many
common formats out of the box. Only override them if you need specific behavior.

### Statusline Integration

When viewing a thread, the plugin exposes buffer-local variables that can be
used for statusline integration or other extensibility purposes:

| Variable | Description |
| :------- | :---------- |
| `vim.b.notmuch_thread` | Thread metadata (ID, subject, tags, authors, message count) |
| `vim.b.notmuch_messages` | Array of all messages with line positions and metadata |
| `vim.b.notmuch_current` | Cursor-tracked current message (updates on `CursorMoved`) |
| `vim.b.notmuch_status` | Pre-formatted statusline string (e.g., "2/5 John Doe 📎1") |

Example statusline integration with lualine:

```lua
require('lualine').setup({
  sections = {
    lualine_c = {
      {
        function() return vim.b.notmuch_status or '' end,
        cond = function() return vim.bo.filetype == 'mail' end,
      },
    },
  },
})
```

## License

This project is licensed under the MIT License, granting you the freedom to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell copies. The
MIT License's full text can be found in the `LICENSE` section of the project's
documentation.

For more details on usage and advanced configuration options, please refer to
the in-depth plugin help within NeoVim: `:help notmuch`.
