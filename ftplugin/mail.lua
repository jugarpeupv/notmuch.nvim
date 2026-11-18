-- mail: thread view (and plain mail buffers, which are left untouched).
--
-- Migrated from ftplugin/mail.vim. Behaviour is preserved: optional `:e`
-- guard that restores the snapshot and refreshes in place, folds left open,
-- message tag commands, and the existing keymaps.

if vim.b.did_ftplugin then
  return
end
vim.b.did_ftplugin = 1

-- Only thread buffers get the notmuch-specific setup. Draft/compose buffers
-- are ordinary editable mail buffers.
if not vim.startswith(vim.fs.basename(vim.api.nvim_buf_get_name(0)), "thread:") then
  return
end

local tag = require("notmuch.tag")
local completion = require("notmuch.completion")

vim.opt_local.foldmethod = "marker"
-- Create message folds but leave them open (use <Enter> to toggle one).
vim.opt_local.foldlevel = 99

-- Make :e refresh the thread view instead of emptying this scratch buffer
-- (it is not a real file). Content is restored instantly from the snapshot
-- saved at write time (BufReadPre does NOT fire for nofile buffers), then a
-- real refresh runs deferred.
vim.api.nvim_create_autocmd("BufReadCmd", {
  buffer = 0,
  callback = function()
    local afile = vim.fn.expand("<afile>")
    local current = vim.api.nvim_buf_get_name(0)
    -- Renamed buffer or :e with a file argument: allow the normal edit.
    if not vim.startswith(vim.fs.basename(current), "thread:")
        or vim.fn.fnamemodify(afile, ":p") ~= vim.fn.fnamemodify(current, ":p") then
      vim.api.nvim_clear_autocmds({ buffer = 0 })
      vim.cmd("edit " .. vim.fn.fnameescape(afile))
      return
    end

    vim.bo.modifiable = true
    local saved = vim.b.notmuch_saved_thread_lines
    if saved then
      vim.api.nvim_buf_set_lines(0, 0, -1, false, saved)
    end
    vim.bo.modifiable = false
    vim.bo.modified = false

    -- :e clears buffer-local syntax items without refiring FileType, so force
    -- a reload (runtime syntax files bail out while b:current_syntax exists).
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
        require("notmuch.refresh").refresh_thread_buffer()
      end
    end)
  end,
})

vim.api.nvim_buf_create_user_command(0, "TagAdd", function(arg)
  tag.msg_add_tag(arg.args)
end, {
  nargs = "+",
  complete = completion.comp_tags,
  force = true,
})

vim.api.nvim_buf_create_user_command(0, "TagRm", function(arg)
  tag.msg_rm_tag(arg.args)
end, {
  nargs = "+",
  complete = completion.comp_tags,
  force = true,
})

vim.api.nvim_buf_create_user_command(0, "TagToggle", function(arg)
  tag.msg_toggle_tag(arg.args)
end, {
  nargs = "+",
  complete = completion.comp_tags,
  force = true,
})

local function map(mode, lhs, rhs, opts)
  opts = vim.tbl_extend("force", { buffer = true }, opts or {})
  vim.keymap.set(mode, lhs, rhs, opts)
end

map("n", "<Tab>", function()
  require("notmuch.thread").next_message()
end, { silent = true })
map("n", "<S-Tab>", function()
  require("notmuch.thread").prev_message()
end, { silent = true })
map("n", "<Enter>", "za", { silent = true })
map("n", "a", function()
  require("notmuch.attach").get_attachments_from_cursor_msg()
end)
map("n", "r", function()
  require("notmuch.refresh").refresh_thread_buffer()
end)
map("n", "C", function()
  require("notmuch.send").compose()
end)
map("n", "R", function()
  require("notmuch.send").reply()
end)
map("n", "q", "<Cmd>bwipeout<CR>")
map("n", "+", ":TagAdd<Space>")
map("n", "-", ":TagRm<Space>")
map("n", "=", ":TagToggle<Space>")
