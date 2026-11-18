-- notmuch-threads: search results buffer (one thread per line).
--
-- Migrated from ftplugin/notmuch-threads.vim. Behaviour is preserved:
-- optional `:e` guard that restores the snapshot and refreshes in place,
-- buffer-local tag commands, and the existing keymaps.

if vim.b.did_ftplugin then
  return
end
vim.b.did_ftplugin = 1

vim.opt_local.wrap = false
vim.opt_local.conceallevel = 3
vim.opt_local.concealcursor = ""
vim.opt_local.signcolumn = "no"

-- Make :e behave like r (refresh) in this scratch buffer (not a real file).
-- Content is restored instantly from b:notmuch_saved_lines (taken at write
-- time, because BufReadPre does NOT fire for nofile buffers), then a real
-- refresh runs deferred.
vim.api.nvim_create_autocmd("BufReadCmd", {
  buffer = 0,
  callback = function()
    local afile = vim.fn.expand("<afile>")
    local current = vim.api.nvim_buf_get_name(0)
    -- :e with a file argument: allow the normal edit, drop our guard.
    if vim.fn.fnamemodify(afile, ":p") ~= vim.fn.fnamemodify(current, ":p") then
      vim.api.nvim_clear_autocmds({ buffer = 0 })
      vim.cmd("edit " .. vim.fn.fnameescape(afile))
      return
    end

    vim.bo.modifiable = true
    local saved = vim.b.notmuch_saved_lines
    if saved then
      vim.api.nvim_buf_set_lines(0, 0, -1, false, saved)
      if vim.b.notmuch_saved_ids then
        vim.b.notmuch_thread_ids = vim.b.notmuch_saved_ids
      end
      if vim.b.notmuch_saved_lnum then
        vim.api.nvim_win_set_cursor(0, { vim.b.notmuch_saved_lnum, 0 })
      end
    end
    vim.bo.modifiable = false
    vim.bo.modified = false

    -- :e clears buffer-local syntax items without refiring FileType, so force
    -- a reload (syntax files with a b:current_syntax guard need it removed).
    local syn = vim.bo.syntax
    if syn ~= "" then
      vim.b.current_syntax = nil
      vim.bo.syntax = ""
      vim.bo.syntax = syn
    end

    -- Only refresh if the user is still in this buffer; otherwise a
    -- scheduled refresh could act on whatever buffer is current by then.
    local target = vim.api.nvim_get_current_buf()
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(target)
          and vim.api.nvim_get_current_buf() == target
      then
        require("notmuch.refresh").refresh_search_buffer()
      end
    end)
  end,
})

local nm = require("notmuch")
local r = require("notmuch.refresh")
local s = require("notmuch.sync")
local tag = require("notmuch.tag")
local completion = require("notmuch.completion")

vim.api.nvim_buf_create_user_command(0, "TagAdd", function(arg)
  tag.thread_add_tag(arg.args, arg.line1, arg.line2)
end, {
  range = true,
  nargs = "+",
  complete = completion.comp_tags,
  force = true,
})

vim.api.nvim_buf_create_user_command(0, "TagRm", function(arg)
  tag.thread_rm_tag(arg.args, arg.line1, arg.line2)
end, {
  range = true,
  nargs = "+",
  complete = completion.comp_tags,
  force = true,
})

vim.api.nvim_buf_create_user_command(0, "TagToggle", function(arg)
  tag.thread_toggle_tag(arg.args, arg.line1, arg.line2)
end, {
  range = true,
  nargs = "+",
  complete = completion.comp_tags,
  force = true,
})

vim.api.nvim_buf_create_user_command(0, "DelThread", function(arg)
  tag.thread_add_tag("del", arg.line1, arg.line2)
  tag.thread_rm_tag("inbox", arg.line1, arg.line2)
end, {
  range = true,
  force = true,
})

local function map(mode, lhs, rhs, opts)
  opts = vim.tbl_extend("force", { buffer = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

map("n", "<CR>", function()
  nm.show_thread()
end)
map("n", "<C-v>", function()
  nm.show_thread_vsplit()
end)
map("n", "<C-s>", function()
  nm.show_thread_split()
end)
map("n", "<C-x>", function()
  nm.show_thread_split()
end)
map("n", "r", r.refresh_search_buffer)
map("n", "q", "<Cmd>bwipeout<CR>")
map("n", "%", s.sync_maildir)
map("n", "+", ":TagAdd<Space>")
map("x", "+", ":TagAdd<Space>")
map("n", "-", ":TagRm<Space>")
map("x", "-", ":TagRm<Space>")
map("n", "=", ":TagToggle<Space>")
map("x", "=", ":TagToggle<Space>")
-- Mark read: remove unread without moving the cursor.
map("n", "x", "<Cmd>TagRm unread<CR>")
map("x", "x", ":TagRm unread<CR>")
map("n", "F", "<Cmd>TagToggle flagged<CR>j")
map("x", "F", ":TagToggle flagged<CR>")
map("n", "C", function()
  require("notmuch.send").compose()
end)
map("n", "dd", "<Cmd>DelThread<CR>j")
map("x", "d", ":DelThread<CR>")
map("n", "D", function()
  require("notmuch.delete").purge_del()
end)
map("n", "o", function()
  nm.reverse_sort_threads()
end)
