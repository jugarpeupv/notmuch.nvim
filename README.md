# 📨 Notmuch.nvim

A powerful and flexible mail reader interface for NeoVim. This plugin bridges
your email and text editing experiences directly within NeoVim by interfacing
with the [Notmuch mail indexer](https://notmuchmail.org).

1. [Introduction](#introduction)
2. [Feature Overview](#feature-overview)
3. [Differences from upstream](#differences-from-upstream)
4. [Requirements](#requirements)
5. [Installation](#installation)
6. [Usage](#usage)
7. [Composing and Replying](#composing-and-replying)
8. [Configuration Options](#configuration-options)
9. [License](#license)

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
- 🧾 **Aligned Thread List**: One line per thread with a fixed layout:
  status icon, local date/time, subject, participants, tags and counts.
- 🔵 **Unread Indicators**: Nerd Font envelope icons for read/unread threads,
  colored through configurable `NotmuchUnreadMail` / `NotmuchReadMail` groups.
- ⚡ **Streamed Async Search**: `notmuch search --format=json` is decoded
  incrementally in bounded batches and rendered progressively, so huge
  searches stay responsive and can be cancelled by closing the buffer.
- 🔗 **Thread Viewing**: Messages are loaded with folding, threading and
  configurable message order.
- 📎 **Attachment Management**: View, open and save received attachments
  (prefers `vim.ui.open()`), and manage outgoing draft attachments with an
  editable oil.nvim-style scratch window (add, delete, paste paths, validate
  with `:w`).
- ✉️ **Compose and Reply**: Write new emails and replies with MIME support,
  persistent drafts, signatures (plain or HTML with inline images).
- 🧠 **Reply-aware headers**: Auto-detects which of your addresses received the
  message, decodes/normalizes RFC 2047 headers, cleans Outlook-style subject
  padding, and keeps you out of your own `To`/`Cc` template.
- 🌐 **Inline HTML Rendering**: Renders HTML mail via `w3m` (with numbered link
  references) or prefers the plain-text alternative, depending on
  `render_html_body`.
- ⬇️ **Offline Mail Sync**: Supports `mbsync` for efficient sync processes, with buffer, background, and interactive terminal modes.
- 🏷️ **Tag Management**: Conveniently add, remove, or toggle email tags.
- 🩺 **Health Check**: `:checkhealth notmuch` verifies Neovim, LuaJIT/FFI,
  notmuch, libnotmuch, database access and optional tools.
- 💻 **Pure Lua**: Fully implemented in Lua for performance and maintainability.
- 🔭 (WIP) ~~**Telescope.nvim Integration**: Search interactively, extract URL's, jump
  efficiently, with the powerful file picker of choice.~~

## Differences from upstream

This repository is a fork of
[yousefakbar/notmuch.nvim](https://github.com/yousefakbar/notmuch.nvim) focused
on a few daily-driver workflows. It is not a drop-in replacement for upstream
configuration: some upstream options do not exist here, and some behaviour is
intentionally different.

### Search results

- **Fixed, aligned columns** instead of upstream's configurable column layout:
  `ICON DD/MM/YY HH:MM  Subject(40)  From(25)  (tags)  [matched/total]`.
  Dates are rendered in the user's local timezone, and widths are measured in
  display cells (emoji/CJK safe).
- **Nerd Font unread/read envelope** prefix, colored by
  `NotmuchUnreadMail` / `NotmuchReadMail` (override after colorscheme setup).
- **Participants newest-first**, cut at the field width. Upstream shows its own
  representation through `search.columns`.
- **Streaming JSON**: results are decoded with an incremental parser
  (`lua/notmuch/search/stream.lua` + `model.lua`) and appended in batches;
  closing the search buffer kills the running `notmuch search`.
- Upstream's `search.columns`, `search.separator`, `search.show_header`,
  `:NmSearchRedraw`, `K` metadata popup and dashboard saved queries are **not**
  available here.

### Thread list keymaps

- No archive mappings (`a`/`A`). `x` removes the `unread` tag in place,
  `F` toggles `flagged`, `dd` tags `del` and removes `inbox`, `D` opens the
  `tag:del` purge view, and `o` reverses the list.
- `:e` in a search or thread buffer restores the snapshot and refreshes in
  place instead of emptying the scratch buffer, and reloads buffer syntax.

### Replying

- Replies use `notmuch reply --reply-to=all` but remove your own address from
  the initial `To`/`Cc` template; if you add it back manually it is preserved.
- `From:` is chosen from the address that actually received the message
  (folder/tag aware, e.g. work vs personal), falling back to `from_cmd` and
  then `from`.
- Headers are unfolded, RFC 2047 decoded for editing and re-encoded on send;
  Outlook-style whitespace in the subject is collapsed.
- Quoted previous messages are omitted by default
  (`include_original_response = false`).

### HTML mail

- `render_html_body = false` (default): `multipart/alternative` messages show
  their `text/plain` part; HTML-only messages are still converted to text with
  `w3m` so they are never blank.
- `render_html_body = true`: the HTML alternative is rendered with `w3m`
  (plain part skipped); HTML-only messages are rendered too.
- HTML parts are fetched on demand per message, so large threads do not load
  tens of megabytes of HTML they never display.
- `w3m` output includes numbered link references.

### Attachments, drafts and maintenance

- **Outgoing attachments use an editable oil.nvim-style scratch window**
  (`lua/notmuch/attach_buffer.lua`) instead of upstream's rule-based
  `attach.incoming.*` API. Each line below the header is a file path:
  `a` adds via prompt, `dd` deletes, `p`/`P` paste (resolving oil.nvim lines to
  real paths), `gg` jumps to the file area, and `:w` validates every path and
  stores the list in `vim.b.notmuch_attachments` on the compose buffer.
  Toggle it with `keymaps.attachment_window` (default `<C-g><C-a>`; for
  example `M`). `:Attach`, `:AttachRemove` and `:AttachList` are also available.
- Received attachments are listed with `a` in the thread view (parts open with
  `v`, `o` or `s`), and can be previewed in a floating window via
  `view_handler`.
- We keep the `open_handler`/`view_handler` callback configuration. Upstream
  0.5.0 removed those callbacks in favour of `attachments.open`,
  `attachments.view`, `attachments.window`, `attachments.cache_dir` and
  `attach.incoming.*` rules, which are **not** implemented here.
- Outgoing drafts are persisted as `.eml` files and created with `0600`
  permissions; the drafts directory is `0700`.
- Attachment MIME parts are loaded with argument lists (no shell
  interpolation).
- The unused `FollowPatch`/`U` (`YTerm`) integrations, the internal
  `notmuch.float` module and the `open_cmd` option were removed.
- Upstream's `drafts.*` options, draft picker, `send.send_mode`,
  `thread_view_mode`, `thread_auto_expand` and `search.*` options are **not**
  implemented here.

If you need those upstream features, use upstream; if you want this fork's
fixed search layout, reply header handling and streaming behaviour, use this
repository.

## Requirements

- **[NeoVim](https://github.com/neovim/neovim)**: Version 0.10 or later is
  required (uses `vim.system()`, `vim.b` buffer variables, and other modern APIs).
- **[Notmuch](https://notmuchmail.org)**: Ensure Notmuch and libnotmuch library
  are installed
- **[w3m](http://w3m.sourceforge.net/)** (recommended): Used to render HTML
  mail. HTML-only messages are converted to text even when
  `render_html_body = false`; without `w3m` they show an attachment hint.
- (WIP) ~~**[Telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)**: File
  picker of choice for many use cases.~~

## Installation

You can install Notmuch.nvim using your favorite NeoVim plugin manager.

### Using `lazy.nvim`:
```lua
{
    'jugarpeupv/notmuch.nvim',
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
    'https://github.com/jugarpeupv/notmuch.nvim',
})
```

### Manual Installation:
Clone the repository and add the directory to your `runtimepath`:
```bash
git clone https://github.com/jugarpeupv/notmuch.nvim.git
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

- **`:checkhealth notmuch`**: Verifies Neovim version/APIs, LuaJIT FFI,
  `notmuch`, `libnotmuch`, database configuration/access, and optional tools
  (`msmtp`, `mbsync`, `w3m`).

### Keymaps

**Search results (`notmuch-threads`)**

| Key | Action |
| :-- | :----- |
| `<CR>` | Open thread |
| `<C-v>` / `<C-s>` / `<C-x>` | Open thread in vertical / horizontal split |
| `r` | Refresh search (`:e` also refreshes in place) |
| `q` | Close buffer |
| `%` | Sync maildir |
| `+` / `-` / `=` | `:TagAdd`, `:TagRm`, `:TagToggle` (also in visual mode) |
| `x` | Remove `unread` in place |
| `F` | Toggle `flagged` (moves down) |
| `dd` / `d` | Tag `del`, remove `inbox` (moves down in normal mode) |
| `D` | Open the `tag:del` purge view (`DD` purges files) |
| `o` | Reverse sort |
| `C` | Compose |

**Thread view (`mail`)**

| Key | Action |
| :-- | :----- |
| `<Enter>` | Toggle message fold |
| `<Tab>` / `<S-Tab>` | Next / previous message |
| `a` | Attachment listing |
| `r` | Refresh thread (`:e` also refreshes in place) |
| `R` / `C` | Reply / compose |
| `+` / `-` / `=` | Message tag commands |
| `q` | Close buffer |

**Landing page (`notmuch-hello`)**

| Key | Action |
| :-- | :----- |
| `<CR>` | Search the tag on the current line |
| `c` | Count threads for that tag |
| `r` / `%` | Refresh tag list / sync maildir |
| `C` / `q` | Compose / close |

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

Replies (`R`) use `notmuch reply --reply-to=all` and then normalize the
template:

- `From:` is taken from the address that actually received the message
  (detected from the message's recipients plus its maildir/tags), falling back
  to `from_cmd` and then `from`.
- Your own address is removed from the initial `To`/`Cc`; if you add it back
  manually it is preserved and sent.
- Folded headers are unfolded, RFC 2047 words are decoded for editing and
  re-encoded when sending, and Outlook-style subject padding is collapsed.
- Quoted previous messages are omitted by default. Set
  `include_original_response = true` to keep them inline.
- Drafts are stored as `.eml` files in `draft_dir` with `0600` permissions
  (directory `0700`) and are deleted after a successful send.

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

Press `<C-g><C-a>` (or run `:AttachList`) to open the attachment buffer. The
toggle key is configurable via `keymaps.attachment_window` (for example `M`).
This is an editable buffer (similar to oil.nvim) where each line below the
header is a file path:

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
| `from`             | `From:` for new mail and the fallback for replies                               | From `notmuch config`           |
| `from_cmd`         | Command whose output overrides `From:` (compose and replies; replies first try the address that received the message) | `nil` |
| `draft_dir`        | Persistent `.eml` drafts (compose/reply); created `0600`, directory `0700`, deleted after send | `~/.local/share/nvim/notmuch/drafts` |
| `signature_file`   | Path appended as signature to new mails. `.txt` → plain text (with `-- ` delimiter); `.html`/`.htm` → HTML signature with Outlook-style `multipart/alternative` + inline images via `cid:` | `nil`                           |
| `maildir_sync_cmd` | Bash command to run for syncing maildir                                         | `mbsync -a`                     |
| `sync.sync_mode`   | Sync display mode: `"buffer"`, `"background"`, or `"terminal"` (PTY with stdin) | `buffer`                        |
| `message_order`    | Message order in thread view: `"newest-first"` or `"oldest-first"`              | `"newest-first"`                |
| `include_original_response` | Keep the quoted original message in the reply body                  | `false`                         |
| `render_html_body` | `false`: plain text wins for `multipart/alternative`, HTML-only still rendered to text via `w3m`; `true`: render the HTML alternative with `w3m` | `false` |
| `keymaps`          | Keymap overrides: `sendmail`, `attachment_window`                               | See `config.lua`[1]             |
| `open_handler`     | Callback for opening attachments externally                                     | `vim.ui.open()`, then OS opener[2] |
| `view_handler`     | Callback converting attachments to text for the floating viewer                 | See `default_view_handler()`[2] |
| `logfile`          | Optional `msmtp --logfile` path                                                 | `nil`                           |
| `suppress_deprecation_warning` | Suppress the warning shown when using deprecated notmuch API (< 0.32) | `false`                         |

[1]: https://github.com/jugarpeupv/notmuch.nvim/blob/main/lua/notmuch/config.lua
[2]: https://github.com/jugarpeupv/notmuch.nvim/blob/main/lua/notmuch/handlers.lua

Example configuration in plugin manager (lazy.nvim):

```lua
{
    "jugarpeupv/notmuch.nvim",
    opts = {
        notmuch_db_path = "/home/xxx/Documents/Mail",
        maildir_sync_cmd = "mbsync personal",
        sync = {
            sync_mode = "buffer" -- OR "background" OR "terminal"
        },
        keymaps = {
            sendmail = "<C-g><C-g>",
        },
        message_order = "newest-first", -- OR "oldest-first"
        include_original_response = false,
        render_html_body = false, -- true renders the HTML alternative with w3m
    },
},
```

### Customizing Attachment Handlers

The plugin provides two handlers for working with attachments:

**Open Handler**: Opens attachments externally with your system's default
application. The default handler prefers `vim.ui.open()` when available and
falls back to an OS-specific command: `open` (macOS), `xdg-open` (Linux), or
`start` (Windows).

**View Handler**: Converts attachments to text for display in a floating window
within Neovim. The default handler supports HTML, PDF, images, Office documents,
Markdown, archives, and plain text files. It tries multiple CLI tools for each
format and falls back gracefully if tools aren't available. HTML previews use
`w3m` with numbered link references.

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
